module Api
  class ValueSetsController < ApplicationController
    respond_to :json
    #before_filter :authenticate_user!
    skip_authorization_check

    api :GET, '/value_sets/:oid?search=:search'
    param :oid, String, :desc => "Value set OID", :required => true
    param :search, String, :desc => "Value set term search string", :required => false
    def show
      s=params[:search]
      rx=Regexp.new("${s}")
      # assume user typed in a start of a word so sort
      sortfun=lambda { |x| rx=~x['display_name'] }
      if /^[0-9]+[.]/ =~ params[:oid]
        value_set = HealthDataStandards::SVS::ValueSet.where({oid: params[:oid]}).first
        render json: value_set.concepts.all({display_name: /#{s}/i }).sort_by!(&sortfun)
      else
        value_set = HealthDataStandards::SVS::ValueSet.where({display_name: /#{s}/i}).all.to_a
        value_set.sort_by!(&sortfun)
        render json: value_set
      end
    end
  end
end