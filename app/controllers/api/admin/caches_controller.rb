module Api
  module Admin
    class CachesController < ApplicationController
      resource_description do
        resource_id 'Admin::Caches'
        short 'Caches Admin'
        formats ['json']
        description "This resource allows for administrative tasks to be performed on the cache via the API."
      end
      include LogsHelper
      protect_from_forgery except: [:destroy]

      before_action :authenticate_user!
      before_action :validate_authorization!

      api :GET, "/admin/caches/count", "Return count of caches in the database."
      example '{"query_cache_count":56, "patient_cache_count":100}'
      def count
        log_admin_api_call LogAction::VIEW, "Count of caches"
        json = {}
        json['query_cache_count'] = CQM::QualityReport.count
        json['patient_cache_count'] = CQM::IndividualResult.count
        render :json => json
      end

      #api :GET, "/admin/caches/spinner", "Return spinner status"
      def spinner
        json = {}
        json['spinner_stat'] = Delayed::Job.where(queue: "patient_import").count
        render :json => json
      end

      #api :GET, "/admin/caches/staticmeasures", "Return static measure"
      def static_measure
        measure_definition = nil
        cql_element = nil
        smeasure = StaticMeasure.where({"measure_id" => params[:id]}).first
        cql_measure = Measure.where({"hqmf_id" => params[:id]}).first
        if (cql_measure)
          cql_element = cql_measure["cql"][0]
          measure_definition = cql_element[cql_element.index("define") .. cql_element.length].gsub! "define",""
          measure_definition = measure_definition.insert(0,"<tr><td><b>").gsub! "\r\n\r\n", "</td></tr>\r\n\r\n<tr><td><b>"
          measure_definition.gsub!("\":\r\n\t", "\"</b>:\r\n\t")
          measure_definition.gsub!("\):\r\n\t", "\)</b>:\r\n\t")
          measure_definition << "</td></tr>"
        end
        smeasure.definition = measure_definition
        render :json => smeasure
      end

      api :DELETE, "/admin/caches", "Empty all caches in the database."
      def destroy
        log_admin_api_call LogAction::DELETE, "Empty all caches"
        CQM::QualityReport.delete_all
        CQM::IndividualResult.delete_all
        render status: 200, plain: 'Server caches have been emptied.'
      end

      private 

      def validate_authorization!
        authorize! :admin, :users
      end
    end
  end
end
