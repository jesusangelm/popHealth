require 'cypress/patient_filter.rb'
require 'cypress/expected_results_calculator.rb'
require 'c4_helper.rb'
require 'js_ecqm_calc.rb'

module Api
  class QueriesController < ApplicationController
    resource_description do
      short 'Queries'
      formats ['json']
      description <<-QCDESC
        This resource is responsible for managing clinical quality measure calculations. Creating a new query will kick
        off a new CQM calculation (if it hasn't already been calculated). You can determine the status of ongoing
        calculations, force recalculations and see results through this resource.
      QCDESC
    end
    include PaginationHelper
    include LogsHelper
    skip_authorization_check
    before_filter :authenticate_user!
    before_filter :set_pagination_params, :only => [:patient_results, :patients]
    # HACK alert: should probably move these class methods to a helper.
    def self.get_svs_value(key, cval)
      id = cval[:id]
      code=cval[:code]
      return code if !code.nil?
      val = $mongo_client.database.collection('health_data_standards_svs_value_sets')
                .find({"concepts._id": BSON::ObjectId("#{id}")}).projection({"concepts.$": 1}).first
      if !val.nil?
        val['concepts'][0]['code']
      elsif !cval[:code].nil?
        val = $mongo_client.database.collection('health_data_standards_svs_value_sets')
                  .find({"concepts.code": cval[:code]}).projection({"concepts.$": 1}).first
        val['concepts'][0]['code'] unless val.nil?
      else
        puts "id or code not found"
      end
    end


    @@filter_mapping = {
        'ethnicities' => method(:get_svs_value),
        'races' => method(:get_svs_value),
        'payers' => method(:get_svs_value),
        'problems' => Proc.new { |key, cval|
          id=cval[:id]
          val = $mongo_client.database.collection('health_data_standards_svs_value_sets').find("_id" => BSON::ObjectId("#{id}")).first
          val['oid'] if not val.nil?
        },
        'providerTypes' => method(:get_svs_value),
        'asOf' => Proc.new { |key, txt|
          # the filter needs a Time object, not a Date object (Ah, Ruby)
          Date.strptime(txt, '%m/%d/%Y').to_time
        },
        'age' => Proc.new { |key, txt|
          res={}
          m = /(>=?)\s*(\d+)/.match(txt)
          m = /(<=?)\s*(\d+)/.match(txt) if m.nil?
          unless m.nil?
            n=m[2].to_i # to_i?
            case m[1]
              when '<'
                res['max'] = n-1
              when '<='
                res['max'] = n
              when '>'
                res['min'] = n+1
              when '>='
                res['min'] = n
            end
            # ruby is SOOO baroque
            next res
          end
          # OR
          m= /^\s*(\d+)\s*-+\s*(\d+)/.match(txt)
          unless m.nil?
            res['min'] = m[1].to_i
            res['max'] = m[2].to_i
            next res
          end
          # else
          m=/(\d+)/.match(txt)
          if m.present?
            res['min'] = res['max'] = m[1].to_i
            next res
          end
          puts "ERROR: Bad input to age:#{txt}"
        }
    }


    def index
      filter = {}
      filter["hqmf_id"] = {"$in" => params["measure_ids"]} if params["measure_ids"]
      providers = collect_provider_id
      filter["filters.providers"] = {"$in" => providers} if providers
      log_api_call LogAction::VIEW, "View all queries"
      render json: QME::QualityReport.where(filter)
    end

    api :GET, '/queries/:id', "Retrieve clinical quality measure calculation"
    param :id, String, :desc => 'The id of the quality measure calculation', :required => true
    example '{"DENEX":0,"DENEXCEP":0,"DENOM":5,"IPP":5,"MSRPOPL":0,"NUMER":0,  "status":{"state":"completed", ...}, ...}'
    description "Gets a clinical quality measure calculation. If calculation is completed, the response will include the results."

    def show
      @qr = QME::QualityReport.find(params[:id])
      if current_user.preferences.show_aggregate_result && !@qr.aggregate_result && !APP_CONFIG['use_opml_structure']
        cv = @qr.measure.continuous_variable
        #aqr = QME::QualityReport.where(measure_id: @qr.measure_id, sub_id: @qr.sub_id, 'filters.providers' => [Provider.root._id.to_s], effective_date: @qr.effective_date).first
        aqr = QME::QualityReport.where(measure_id: @qr.measure_id, sub_id: @qr.sub_id, 'filters.providers' => [get_parent_provider_qsi(@qr[:filters][:providers][0])], effective_date: @qr.effective_date).first
        if aqr.result
          if cv
            @qr.aggregate_result = aqr.result.OBSERV
          else
            @qr.aggregate_result = (aqr.result.DENOM > 0) ? (100*((aqr.result.NUMER).to_f / (aqr.result.DENOM - aqr.result.DENEXCEP - aqr.result.DENEX).to_f)).round : 0
          end
          @qr.save!
        end
      end

      log_api_call LogAction::VIEW, "View quality measure calculation"
      authorize! :read, @qr
      render json: @qr
    end

    api :POST, '/queries', "Start a clinical quality measure calculation"
    param :measure_id, String, :desc => 'The HQMF id for the CQM to calculate', :required => true
    param :sub_id, String, :desc => 'The sub id for the CQM to calculate. This is popHealth specific.', :required => false, :allow_nil => true
    param :effective_date, ->(effective_date) { effective_date.present? }, :desc => 'Time in seconds since the epoch for the end date of the reporting period', :required => true
    param :effective_start_date, ->(effective_start_date) { effective_start_date.present? }, :desc => 'Time in seconds since the epoch for the start date of the reporting period'
    param :providers, Array, :desc => 'An array of provider IDs to filter the query by', :allow_nil => true
    example '{"_id":"52fe409bb99cc8f818000001", "status":{"state":"queued", ...}, ...}'
    description <<-CDESC
      This action will create a clinical quality measure calculation. If the measure has already been calculated,
      it will return the results. If not, it will return the status of the calculation, which can be checked in
      the status property of the returned JSON. If it is calculating, then the results may be obtained by the
      GET action with the id.
    CDESC

    def create
      options = {}
      prefilter = {}
      @pids=[]
      @mids=[]
      @patients=[]
      @msrs = []
      @measures = {}
      sub_ids ={}
     if params[:providers]
      options[:filters] = build_filter
      authorize_providers
      end_date = params[:effective_date]
      start_date = params[:effective_start_date]
      end_date = Time.at(end_date.to_i) if end_date.is_a?(String)
      start_date = Time.at(start_date.to_i) if start_date.is_a?(String)
      start_date = end_date.years_ago(1) if start_date.nil?
      
      @msr = HealthDataStandards::CQM::Measure.where(hqmf_id: params[:measure_id], sub_id: params[:sub_id]).first
       @mids << @msr._id
       @msrs << @msr

      rp = ReportingPeriod.where(start_date: start_date, end_date: end_date).first_or_create
      rp.save!

      options[:start_date] = start_date
      options[:effective_date] = end_date
      options[:test_id] = rp._id
      begin
        #, "filters.providers" => {'$in': params[:providers]}
        qc = QME::QualityReport.where('measure_id' => params[:measure_id], 'effective_date' => options[:effective_date],'start_date' => options[:start_date], 'sub_id' => params[:sub_id]).first
        if qc
          puts "calculation is already available in cache"
          render json: qc
        else
          providers = params[:providers]
          QDM::Patient.all.each do |p|
            pdata = JSON.parse(p.extendedData["provider_performances"]).select{|pid| pid["provider_id"] == providers.first}
            if pdata.present?
                @pids << p._id.to_s
                @patients << p
            end
          end
          #providers.each do |prov|
            #QDM::Patient.all.each do |p|
              #if(prov == JSON.parse(p.extendedData['provider_performances']).first['provider_id'].to_s)
                #@pids << p._id.to_s
                #@patients << p
              #end
            #end
          #end
          calc_job = Cypress::JsEcqmCalc.new('correlation_id': options[:test_id],'effective_date': Time.at(options[:effective_date]).in_time_zone.to_formatted_s(:number), 'measure_period_start': Time.at(options[:start_date]).in_time_zone.to_formatted_s(:number)) 
          response = calc_job.sync_job(@pids, @mids)
          if response['status'] == 'success'
            calc_job.stop
            sleep(2)
            @msrs.each do |msr|
              QME::ManualExclusion.apply_manual_exclusions(msr._id,msr.sub_id)
            end
            erc = Cypress::ExpectedResultsCalculator.new(@patients,options[:test_id],options[:effective_date],options[:start_date],options[:filters])
            @results = erc.aggregate_results_for_measures(@msrs)
          end
            log_api_call LogAction::ADD, "Create a clinical quality calculation"
            render json: @results
        end
        rescue Exception => e
          puts e.message
          puts e.backtrace.inspect
        end
      else
        return false
      end
    end

    api :DELETE, '/queries/:id', "Remove clinical quality measure calculation"
    param :id, String, :desc => 'The id of the quality measure calculation', :required => true

    def destroy
      qr = QME::QualityReport.find(params[:id])
      authorize! :delete, qr
      qr.destroy
      log_api_call LogAction::DELETE, "Remove clinical quality calculation"
      render :status => 204, :text => ""
    end

    api :PUT, '/queries/:id/recalculate', "Force a clinical quality measure to recalculate"
    param :id, String, :desc => 'The id of the quality measure calculation', :required => true

    def recalculate
      prefilter = {}
      qr = QME::QualityReport.find(params[:id])
      authorize! :recalculate, qr
      #prefilter = build_mr_prefilter_qsi(qr.filters['providers']) if APP_CONFIG['use_map_reduce_prefilter']
      #qr.calculate({"oid_dictionary" => OidHelper.generate_oid_dictionary(qr.measure_id),
      #              'recalculate' => true,
      #              "prefilter" => prefilter}, true)
      log_api_call LogAction::UPDATE, "Force a clinical quality calculation"
      render json: qr
    end

    api :POST, '/queries/:id/filter', "Apply a filter to an existing measure calculation"
    param :id, String, :desc => 'The id of the quality measure calculation', :required => true

    def filter
      namekey=[]
      filters={}
      bundle = HealthDataStandards::CQM::Bundle.all.sort(:version => :desc).first
      pcache = QDM::IndividualResult.first
      effective_date = pcache ? pcache['extendedData']['effective_date'].to_time.to_i : bundle.effective_date
      pcache = nil
      filter_options= {:effective_date => effective_date, :bundle_id => bundle._id}
      #authorize! :recalculate, qc
      # add filters here
      params.each_pair do |key, val|
        if not /^(controller|action|id|default_provider_id)/i === key
          (0...val.length).each do |i|
            value =val[i] || val[i.to_s]
            namekey.push(key) unless key=='asOf'
            if /npis|tins|addresses/i === key
              key='provider_ids'
              value=value[:id]
            end
            filters[key] = [] if filters[key].nil? unless key == 'problems'
            if @@filter_mapping[key]
              res=@@filter_mapping[key].call(key, value)
              # and why does the array come through sometimes with ['0'] instead of [0]
              if key == 'problems'
                if filters[key].nil?
                  filters[key]={:oid => []}
                end
                filters[key][:oid].push(res)
              elsif key== 'asOf'
                filter_options[:as_of] = res;
              else
                filters[key].push(res)
              end
              next # wish TF we had continue
            end


            if value.is_a?(Array)
              filters[key].concat(value)
            else
              filters[key].push(value)
            end
          end
        end
      end
      #now do something with filters
      # todo: Date.new should be replaced by meaningful
      # todo: :bundle_id in options Is there only ever one bundle
      mrns = []
      records = Cypress::PatientFilter.filter(QDM::Patient, filters, filter_options)
      numrecs = records.count rescue nil
      unless numrecs.nil?
        reset_patient_cache
        records.each do |r|
          if QDM::IndividualResult.where("extendedData.medical_record_number" => r['extendedData.medical_record_number']).exists?
            mrns.push(r['extendedData.medical_record_number'])
          end
        end
        # At this point the mrns tell us what cat1's to keep and what cat3's to generate
        # was: PatientCache.not_in("value.medical_record_id" => mrns).destroy_all
        # FileUtils.mkdir('results') if !File.exist?('results')
        # filepath='results/'+QME::QualityMeasure.where(:id => params[:id]).first['cms_id']+'_'+namekey.join('_')
        current_user.preferences['c4filters']=namekey
        current_user.save
        #zipfilepath=filepath+'.zip'
        #QueriesController.generate_qrda1_zip(zipfilepath, mrns, current_user)
        QDM::IndividualResult.not_in("extendedData.medical_record_number" => mrns).each { |pc|
          val = pc['extendedData']
          ManualExclusion.find_or_create_by(:measure_id => pc['measure_id'], :sub_id => val['sub_id'],
                                            :medical_record_id => val['medical_record_number'],
                                            :rationale => namekey, :user => current_user['_id'])
        }
        # new let page recalc
        QDM::IndividualResult.delete_all
        #convert_measure_id = HealthDataStandards::CQM::Measure.where("_id" => params[:id]).first
        # force recalculate has no effect if the patients are cached !!!!!!!!!!!!!!
        QME::QualityReport.where({measure_id: params[:id]}).each do |qc|
          # updating nested attributes in Mongoid appears lame
          qc.delete #update_attribute(:status, {:state => nil, :log => ''})
        end

      end
      #send_file(zipfilepath, {:disposition => 'attachment'})
      #provs=$mongo_client.database.collection('query_cache').find({'measure_id' => {'$in':current_user.preferences['selected_measure_ids']}}).collect{|q| q['filters']['providers'][0]}.uniq
      redirect_to '/#providers/'+params[:default_provider_id]
    end

    api :POST, '/queries/:id/clearfilters', "Clear all filters and recalculate"
    param :id, String, :desc => 'The id of the quality measure calculation', :required => true

    def clearfilters
      begin
      reset_patient_cache
      delete_patient_cache
      current_user.preferences['c4filters']=nil
      current_user.save
      rescue Exception => e
          puts e.message
          puts e.backtrace.inspect
      end 
      redirect_to '/#providers/'+params[:default_provider_id]
    end

    def reset_patient_cache
      mrns=[]
      measures=[]
      subs=[]
      pcoll=$mongo_client.database.collection('qdm_individual_results')
      pcoll.update_many({}, {'$set': {'extendedData.manual_exclusion': nil}})
      pcoll.find().each do |pc|
        val=pc['extendedData']
        mrns.push(val['medical_record_number'])
        measures.push(pc['measure_id'].to_s) unless measures.include?(pc['measure_id'])
        subs.push(pc['sub_id']) unless subs.include?(pc['sub_id'])
      end
      if !subs.empty? && subs.length == 0
      $mongo_client.database.collection('manual_exclusions').delete_many(
          {'measure_id': {'$in': measures}, 'sub_id': {'$in': subs}, 'medical_record_id': {'$in': mrns}})
      else
        $mongo_client.database.collection('manual_exclusions').delete_many(
          {'measure_id': {'$in': measures}, 'medical_record_id': {'$in': mrns}})
      end
    end

    def delete_patient_cache
      log_admin_controller_call LogAction::DELETE, "Remove caches"
      HealthDataStandards::CQM::QueryCache.delete_all
      QDM::IndividualResult.delete_all
      Mongoid.default_client["rollup_buffer"].drop()
    end

    api :GET, '/queries/:id/patient_results[?population=true|false]',
        "Retrieve patients relevant to a clinical quality measure calculation"
    param :id, String, :desc => 'The id of the quality measure calculation', :required => true
    param :ipp, /true|false/, :desc => 'Ensure patients meet the initial patient population for the measure', :required => false
    param :denom, /true|false/, :desc => 'Ensure patients meet the denominator for the measure', :required => false
    param :numer, /true|false/, :desc => 'Ensure patients meet the numerator for the measure', :required => false
    param :denex, /true|false/, :desc => 'Ensure patients meet the denominator exclusions for the measure', :required => false
    param :denexcep, /true|false/, :desc => 'Ensure patients meet the denominator exceptions for the measure', :required => false
    param :msrpopl, /true|false/, :desc => 'Ensure patients meet the measure population for the measure', :required => false
    param :antinumerator, /true|false/, :desc => 'Ensure patients are not in the numerator but are in the denominator for the measure', :required => false
    param_group :pagination, Api::PatientsController
    example '[{"_id":"52fe409ef78ba5bfd2c4127f","value":{"DENEX":0,"DENEXCEP":0,"DENOM":1,"IPP":1,"NUMER":1,"antinumerator":0,"birthdate":1276869600.0,"effective_date":1356998340.0,,"first":"Steve","gender":"M","last":"E","measure_id":"40280381-3D61-56A7-013E-6224E2AC25F3","medical_record_id":"ce83c561f62e245ad4e0ca648e9de0dd","nqf_id":"0038","patient_id":"52fbbf34b99cc8a728000068"}},...]'
    description <<-PRDESC
      This action returns an array of patients that have results calculated for this clinical quality measure. The list can be restricted
      to specific populations, such as only patients that have made it into the numerator by passing in a query parameter for a particular
      population. Results are paginated.
    PRDESC

    def patient_results
      qr = QME::QualityReport.find(params[:id])
      authorize! :read, qr
      # this returns a criteria object so we can filter it additionally as needed
      results = qr.patient_results
      #.only('_id', 'extendedData.medical_record_number', 'extendedData.first', 'extendedData.last', 'extendedData.DOB', 'extendedData.gender', 'patient_id')
      log_api_call LogAction::VIEW, "Get patient results for measure calculation", true
      render json: paginate(patient_results_api_query_url(qr), results.where(build_patient_filter))
    end

    def patients
      qr = QME::QualityReport.find(params[:id])
      authorize! :read, qr
      # this returns a criteria object so we can filter it additionally as needed
      results = qr.patient_results
      ids = paginate(patients_api_query_url(qr), results.where(build_patient_filter).order_by([:last.asc, :first.asc])).collect { |r| r["extendedData.medical_record_number"] }
      log_api_call LogAction::VIEW, "Get patients for measure calculation", true
      render :json => QDM::Patient.where({:'extendedData.medical_record_number'.in => ids})
    end


    private
    def build_filter
      @filter = params.select { |k, v| %w(providers).include? k }.to_options
    end

    def authorize_providers
      providers = @filter[:providers] || []
      if !providers.empty?
        providers.each do |p|
          provider = Provider.find(p)
          authorize! :read, provider
        end
      else
        #this is hacky and ugly but cancan will allow just the
        # class Provider to pass for a simple user so providing
        #an empty Provider with no NPI number gets around this
        authorize! :read, Provider.new
      end
    end

    def build_mr_prefilter
      measure = HealthDataStandards::CQM::Measure.where({"hqmf_id" => params[:measure_id], "sub_id" => params[:sub_id]}).first
      measure.prefilter_query!(params[:effective_date].to_i)
      measure.prefilter_query!(params[:effective_start_date].to_i)
    end

    def build_mr_prefilter_qsi(providers)
      map_reduce_query = nil
      unless providers.blank?
        providers_bson = providers.map { |pv| BSON::ObjectId.from_string(pv) }
        map_reduce_query = {"provider_performances.provider_id" => {'$in' => providers_bson}}
      end
      prefilter = map_reduce_query
      prefilter
    end

    def get_parent_provider_qsi(provider)
      provider=Provider.find(provider)
      parent_provider= provider._id
      parent_provider=provider.parent_id if !provider.parent_id.nil?
      parent_provider.to_s
    end

    def build_patient_filter
      patient_filter = {}
      patient_filter["IPP"]= {"$gt" => 0} if params[:ipp] == "true"
      patient_filter["DENOM"]= {"$gt" => 0} if params[:denom] == "true"
      patient_filter["NUMER"]= {"$gt" => 0} if params[:numer] == "true"
      patient_filter["DENEX"]= {"$gt" => 0} if params[:denex] == "true"
      patient_filter["DENEXCEP"]= {"$gt" => 0} if params[:denexcep] == "true"
      patient_filter["MSRPOPL"]= {"$gt" => 0} if params[:msrpopl] == "true"
      # jb addition
      #patient_filter["value.manual_exclusion"] = {"$exists" => 0}
      #patient_filter["value.antinumerator"]= {"$gt" => 0} if params[:antinumerator] == "true"
      #patient_filter["value.provider_performances.provider_id"]= BSON::ObjectId.from_string(params[:provider_id]) if params[:provider_id]
      patient_filter
    end

    def collect_provider_id
      params[:providers] || Provider.where({:npi.in => params[:npis] || []}).to_a
    end

    def get_patients(provider)
    end

  end
end
