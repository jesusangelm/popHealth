require 'patient_ext/patient.rb'
require 'cypress/criteria_picker.rb'
module Cypress
  class PatientFilter
    def self.filter(records, filters, options)
      filtered_patients = []
      @effective_date = nil
      records.each do |patient|
        filtered_patients << patient unless patient_missing_filter(patient, filters, options)
      end
      filtered_patients
    end

    def self.patient_missing_filter(patient, filters, params)
      # byebug
      if filters.key? ("asOf")
        if params[:as_of].present?
          @effective_date = Time.at(params[:as_of])
          filters.delete("asOf")
        else
          @effective_date = Time.at(params[:effective_date])
          filters.delete("asOf")
        end
      end
      filters.each do |k, v|
          # return true if patient is missing any filter item
          # TODO: filter for age and problem (purposefully no prng)
          if k == 'age'
            v.each do |f|
              # {}"age"=>{"min"=>70}}
              # TODO: compare integers?? or dates?
              return true if check_age(f, patient, params)
            end
          elsif k == 'payers'
            # missing payer if value doesn't match any payer name (of multiple providers)
            return true unless match_payers(v, patient)
          elsif k == 'problems'
            return patient_missing_problems(patient, v)
          elsif k == 'providers'
            provider = patient.lookup_provider(include_address: true)
            v.each { |key, val| return true if val != provider[key] }
          elsif k == "provider_ids"
            provider_id = v
            if get_provider_info(provider_id, patient)
              return true
            else
              return false
            end  
          elsif v.length > 1
              # multiple filtes of races, ethnicities, genders, providers
              val = Cypress::CriteriaPicker.send(k, patient, params)
            if v.include? val[0]
              return false
            else
              return true
            end
          elsif v != Cypress::CriteriaPicker.send(k, patient, params)
            # races, ethnicities, genders, providers
            return true
          end
      end
      false
    end

    def self.match_payers(v, patient)
      JSON.parse(patient.extendedData['insurance_providers']).map{|ip| ip['codes']['SOP']}[0].include?(v.first)
    end

    def self.check_age(v, patient, params)
      if @effective_date
        effective_date = @effective_date
      else
        effective_date = Time.at(params[:effective_date])
      end
      return true if v.key?('min') && patient.age_at(effective_date) < v['min']
      return true if v.key?('max') && patient.age_at(effective_date) > v['max']
      false
    end

    def self.patient_missing_problems(patient, problem)
      # TODO: first... different versions of value set... which version do we want?
      # 2.16.840.1.113883.3.666.5.748
      value_set = HealthDataStandards::SVS::ValueSet.where(oid: problem[:oid].first).first
      !Cypress::CriteriaPicker.find_problem_in_records([patient], value_set)
    end
    def self.get_provider_info(id, patient)
      provider = Provider.find(JSON.parse(patient.extendedData['provider_performances']).first['provider_id'])
        if provider["_id"].to_s != id[0]
          return true
        else
          return false
        end
    end
  end
end
