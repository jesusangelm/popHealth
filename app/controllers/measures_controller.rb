class MeasuresController < ApplicationController
  include MeasuresHelper

  before_filter :authenticate_user!
  before_filter :validate_authorization!
  before_filter :build_filters
  before_filter :set_up_environment
  before_filter :generate_report, :only => [:patients, :measure_patients]
  after_filter :hash_document, :only => :report
  
  def index
    @categories = Measure.non_core_measures
    @core_measures = Measure.core_measures
    @core_alt_measures = Measure.core_alternate_measures
    @all_measures = Measure.all_by_measure
  end
  
  def show
    respond_to do |wants|
      wants.html {}
      wants.json do
        SelectedMeasure.add_measure(current_user.username, params[:id])
        measures = params[:sub_id] ? Measure.get(params[:id], params[:sub_id]) : Measure.sub_measures(params[:id])
        render_measure_response(measures, params[:jobs]) do |sub|
          QME::QualityReport.new(sub['id'], sub['sub_id'], 'effective_date' => @effective_date, 'filters' => @filters)
        end
      end
    end
  end
  
  def providers
    respond_to do |wants|
      wants.html do
        @providers = Provider.alphabetical
        @races = Race.ordered
        @providers_by_team = @providers.group_by { |pv| pv.team.try(:name) || "Other" }
      end
      
      wants.json do
        
        providerIds = params[:provider].empty? ?  Provider.all.map { |pv| pv.id.to_s } : @filters.delete('providers')

        render_measure_response(providerIds, params[:jobs]) do |pvId|
          QME::QualityReport.new(params[:id], params[:sub_id], 'effective_date' => @effective_date, 'filters' => @filters.merge('providers' => [pvId]))
        end
      end
    end
  end
  
  def remove
    SelectedMeasure.remove_measure(current_user.username, params[:id])
    render :text => 'Removed'
  end
  
  def patients
  end

  def measure_patients
    type = if params[:type]
      "value.#{params[:type]}"
    else
       "value.denominator"
     end
    @limit = (params[:limit] || 20).to_i
    @skip = ((params[:page] || 1).to_i - 1 ) * @limit
    sort = params[:sort] || "_id"
    sort_order = params[:sort_order] || :asc
    measure_id = params[:id] 
    sub_id = params[:sub_id]
    @records = mongo['patient_cache'].find({'value.measure_id' => measure_id, 'value.sub_id' => sub_id,
                                       'value.effective_date' => @effective_date, type => true},
                                      {:sort => [sort, sort_order], :skip => @skip, :limit => @limit}).to_a
    @total =  mongo['patient_cache'].find({'value.measure_id' => measure_id, 'value.sub_id' => sub_id,
                                      'value.effective_date' => @effective_date, type => true}).count
    @page_results = WillPaginate::Collection.create((params[:page] || 1), @limit, @total) do |pager|
       pager.replace(@records)
    end
    # log the patient_id of each of the patients that this user has viewed
    @page_results.each do |patient_container|
      Log.create(:username =>   current_user.username,
                 :event =>      'patient record viewed',
                 :patient_id => (patient_container['value'])['medical_record_id'])
    end
  end

  def patient_list
    measure_id = params[:id] 
    sub_id = params[:sub_id]
    @records = mongo['patient_cache'].find({'value.measure_id' => measure_id, 'value.sub_id' => sub_id,
                                            'value.effective_date' => @effective_date}).to_a
    # log the patient_id of each of the patients that this user has viewed
    @records.each do |patient_container|
      Log.create(:username =>   current_user.username,
                 :event =>      'patient record viewed',
                 :patient_id => (patient_container['value'])['medical_record_id'])
    end
    respond_to do |format|
      format.xml do
        headers['Content-Disposition'] = 'attachment; filename="excel-export.xls"'
        headers['Cache-Control'] = ''
        render :content_type => "application/vnd.ms-excel"
      end
    end
  end

  def report
    Atna.log(current_user.username, :query)
    selected_measures = mongo['selected_measures'].find({:username => current_user.username}).to_a
    @report = {}
    @report[:start] = Time.at(@effective_date - 3 * 30 * 24 * 60 * 60) # roughly 3 months
    @report[:end] = Time.at(@effective_date)
    @report[:registry_name] = current_user.registry_name
    @report[:registry_id] = current_user.registry_id
    # @report[:npi] = current_user.npi
    # @report[:tin] = current_user.tin
    @report[:results] = []
    selected_measures.each do |measure|
      subs_iterator(measure['subs']) do |sub_id|
        @report[:results] << extract_result(measure['id'], sub_id, @effective_date)
      end
    end
    respond_to do |format|
      format.xml do
        response.headers['Content-Disposition']='attachment;filename=quality.xml';
        render :content_type=>'application/pqri+xml'
      end
    end
  end

  private
  
  def set_up_environment
    @patient_count = mongo['records'].count
    if params[:id]
      measure = QME::QualityMeasure.new(params[:id], params[:sub_id])
      render(:file => "#{RAILS_ROOT}/public/404.html", :layout => false, :status => 404) unless measure
      @definition = measure.definition
    end
  end
  
  def generate_report
    @quality_report = QME::QualityReport.new(@definition['id'], @definition['sub_id'], 'effective_date' => @effective_date, 'filters' => @filters)
    if @quality_report.calculated?
      @result = @quality_report.result
    else
      @quality_report.calculate
    end
  end
  
  def render_measure_response(collection, uuids)
    result = collection.inject({jobs: {}, result: []}) do |memo, var|
      report = yield(var)
      if report.calculated?
        memo[:result] << report.result
      else
        key = "#{report.instance_variable_get(:@measure_id)}#{report.instance_variable_get(:@sub_id)}"
        memo[:jobs][key] = report.calculate if uuids.nil? || uuids[key].nil?
      end
      
      memo
    end

    render :json => result.merge(:complete => result[:jobs].empty?)
  end
  
  def build_filters
    providers = params[:provider] || []
    racesEthnicities = params[:races] ? Race.selected(params[:races]).all : []
    races = racesEthnicities.map {|value| value.flatten(:race)}.flatten, 
    ethnicities = racesEthnicities.map {|value| value.flatten(:ethnicity)}.flatten
    
    @filters = {'providers' => providers, 'races' => races, 'ethnicities' => ethnicities}
  end

  def extract_result(id, sub_id, effective_date)
    qr = QME::QualityReport.new(id, sub_id, 'effective_date' => effective_date)
    result = qr.result
    {
      :id=>id,
      :sub_id=>sub_id,
      :population=>result['population'],
      :denominator=>result['denominator'],
      :numerator=>result['numerator'],
      :exclusions=>result['exclusions']
    }
  end

  def validate_authorization!
    authorize! :read, Measure
  end
  
end