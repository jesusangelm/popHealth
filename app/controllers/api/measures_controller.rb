require 'measures/loader.rb'
#require 'hds/measure.rb'
module Api
  
  class LightMeasureSerializer
    include ActiveModel::Serialization    
        attr_accessor :_id, :title, :category, :hqmf_id, :type, :cms_id, :nqf_id, :hqmf_set_id, :hqmf_version_number, :sub_id, :subtitle, :description
    
  end
  
  class MeasuresController < ApplicationController
    resource_description do
      short 'Measures'
      formats ['json']
      description "This resource allows for the management of clinical quality measures in the popHealth application."
    end
    include PaginationHelper
    include LogsHelper
    before_action :authenticate_user!
    before_action :validate_authorization!
    before_action :set_pagination_params, :only=> :index
    before_action :create_filter , :only => :index
    before_action :update_metadata_params, :only => :update_metadata
    
    
    #api :GET, "/measureslight", "Get a list of measures light"
    param_group :pagination, Api::PatientsController
    def measureslight
      log_api_call LogAction::VIEW, "View list of measures"
      
      measures = Measure.where(@filter)
 
      measLight = Array.new

      measures.each do |item|
        p = LightMeasureSerializer.new
        p._id = item._id
        #p.name = item.title
        p.category = item.category 
        p.hqmf_id = item.hqmf_id
        p.type = item.type
        p.cms_id = item.cms_id
        p.nqf_id = item.nqf_id
        p.hqmf_set_id = item.hqmf_set_id
        p.hqmf_version_number = item.hqmf_version_number
        p.sub_id = item.sub_id
        p.subtitle = item.subtitle
        p.description = item.description

        measLight << p
      end
     
       render json: measLight
    end

    api :GET, "/measures", "Get a list of measures"
    param_group :pagination, Api::PatientsController
    def index
      log_api_call LogAction::VIEW, "View list of measures"
      measures = Measure.where(@filter)
      #m = Measure.first
      #Delayed::Worker.logger.info("************** what is M **************")
      #Delayed::Worker.logger.info(m)
      render json: measures
      #paginate(api_measures_url, measures), each_serializer: HealthDataStandards::CQM::MeasureSerializer
    end

    api :GET, "/measures/:id", "Get an individual clinical quality measure"
    param :id, String, :desc => 'The HQMF id for the CQM to calculate', :required => true
    param :sub_id, String, :desc => 'The sub id for the CQM to calculate. This is popHealth specific.', :required => false
    def show
      log_api_call LogAction::VIEW, "View measure"
      measure = Measure.where({"hqmf_id" => params[:id], "sub_id"=>params[:sub_id]}).first

      render :json=> measure
    end

    api :POST, "/measures", "Load a measure into popHealth"
    description "The uploaded measure must be in the popHealth JSON measure format. This will not accept HQMF definitions of measures."
    def create
      authorize! :create, CQM::Measure
      measure_details = {
        'type'=>params[:measure_type],
        'episode_of_care'=>params[:calculation_type] == 'episode',
        'category'=> params[:category].empty? ?  "miscellaneous" : params[:category],
        'lower_is_better'=> params[:lower_is_better]
      }
      ret_value = {}
      hqmf_document = Measures::Loader.parse_model(params[:measure_file].tempfile.path)
      if measure_details["episode_of_care"]
        Measures::Loader.save_for_finalization(hqmf_document)
        ret_value= {episode_ids: hqmf_document.specific_occurrence_source_data_criteria().collect{|dc| {id: dc.id, description: dc.description}},
                    hqmf_id: hqmf_document.hqmf_id,
                    vsac_username: params[:vsac_username],
                    vsac_password: params[:vsac_password],
                    category: measure_details["category"],
                    lower_is_better: measure_details[:lower_is_better],
                    hqmf_document: hqmf_document
                  }
      else
        Measures::Loader.generate_measures(hqmf_document,params[:vsac_username],params[:vsac_password],measure_details)
      end
      log_api_call LogAction::UPDATE, "Loaded measure"
      render json: ret_value
      rescue => e
        log_api_call LogAction::UPDATE, "Failed to load measure, with error #{e.to_s}"
        render text: e.to_s, status: 500
    end

    api :DELETE, '/measures/:id', "Remove a clinical quality measure from popHealth"
    param :id, String, :desc => 'The HQMF id for the CQM to calculate', :required => true
    description "Removes the measure from popHealth. It also removes any calculations for that measure."
    def destroy
      authorize! :delete, CQM::Measure
      measure = CQM::Measure.where({"hqmf_id" => params[:id]})
      #delete all of the pateint and query cache entries for the measure
      #HealthDataStandards::CQM::PatientCache.where({"value.measure_id" => params[:id]}).destroy
      #HealthDataStandards::CQM::QueryCache.where({"measure_id" => params[:id]}).destroy
      measure.destroy
      log_api_call LogAction::DELETE, "Remove measure"
      render :status=>204, :text=>""
    end


    def update_metadata
      authorize! :update, CQM::Measure
      measures = CQM::Measure.where({ hqmf_id: params[:hqmf_id]})
      measures.each do |m|
        m.update_attributes(params[:measure])
        m.save
      end
      log_api_call LogAction::UPDATE, "Update measure metadata"
      render json:  measures,  each_serializer: HealthDataStandards::CQM::MeasureSerializer
      rescue => e
        log_api_call LogAction::UPDATE, "Failed to update measure, with error #{e.to_s}"
        render text: e.to_s, status: 500
    end


    def finalize
      measure_details = {
          'episode_ids'=>params[:episode_ids],
          'category' => params[:category],
          'measure_type' => params[:measure_type],
          'lower_is_better' => params[:lower_is_better]

       }
      Measures::Loader.finalize_measure(params[:hqmf_id],params[:vsac_username],params[:vsac_password],measure_details)
      measure = CQM::Measure.where({hqmf_id: params[:hqmf_id]}).first
      log_api_call LogAction::UPDATE, "Finalize measure"
      render json: measure, serializer: HealthDataStandards::CQM::MeasureSerializer
      rescue => e
        log_api_call LogAction::UPDATE, "Failed to finalize measure, with error #{e.to_s}"
        render text: e.to_s, status: 500
    end

  private

    def validate_authorization!
      authorize! :read, CQM::Measure
    end

    def create_filter
      measure_ids = params[:measure_ids]
      @filter = measure_ids.nil? || measure_ids.empty? ? {} : {:hqmf_id.in => measure_ids}
    end

    def update_metadata_params
      params[:measure][:lower_is_better] = nil if params[:measure][:lower_is_better].blank?
    end

  end
end
