module Cypress
  class ExpectedResultsCalculator
    # The ExpectedResultsCalculator aggregates Individual Results to calculated the expected results for a
    # Measure Test or Task

    # @param [Array] patients the list of patients that are included in the aggregate results
    # @param [String] correlation_id the id used to associate a group of patients
    # @param [String] effective_date used when generating the query_cache_object for HDS QRDA Cat III export
    # @param [Hash] options :individual_results are the raw results from JsEcqmCalc
    def initialize(patients, correlation_id, effective_date, start_date, sub_id = nil, filters = nil, callingfor = false)
      @correlation_id = correlation_id
      # Hash of patient_id and their supplemental information
      @patient_sup_map = {}
      @measure_result_hash = {}
      @effective_date = effective_date
      @start_date = start_date
      @sub_id = sub_id
      @filters = filters
      patients.each do |patient|
        # iterate through each patient and store their supplemental information
        add_patient_to_sup_map(@patient_sup_map, patient)
      end
      @callingfor = callingfor
    end

    def add_patient_to_sup_map(ps_map, patient)
      patient_id = patient.id.to_s
      ps_map[patient_id] = {}
      ps_map[patient_id]['SEX'] = patient.qdmPatient.get_data_elements('patient_characteristic', 'gender')[0].dataElementCodes[0].code
      ps_map[patient_id]['RACE'] = patient.qdmPatient.get_data_elements('patient_characteristic', 'race')[0].dataElementCodes[0].code
      ps_map[patient_id]['ETHNICITY'] = patient.qdmPatient.get_data_elements('patient_characteristic', 'ethnicity')[0].dataElementCodes[0].code
      ps_map[patient_id]['PAYER'] = patient.qdmPatient.get_data_elements('patient_characteristic', 'payer')[0].dataElementCodes[0].code
    end

    def prepopulate_measure_result_hash(measure)
      @measure_result_hash[measure.hqmf_id] = {}
      population_set_keys = measure.population_sets_and_stratifications_for_measure.map { |ps| measure.key_for_population_set(ps) }
      population_set_keys.each do |psk|
        @measure_result_hash[measure.hqmf_id][psk] = {}
        measure.population_keys.each do |pop_key|
          @measure_result_hash[measure.hqmf_id][psk][pop_key] = 0
        end
        @measure_result_hash[measure.hqmf_id][psk]['supplemental_data'] = {}
      end
    end

    def aggregate_results_for_measures(measures, individual_results = nil)
      measures.each do |measure|
        prepopulate_measure_result_hash(measure)
        measure_individual_results = nil
        # If individual_results are provided, use the results for the measure being aggregated
        measure_individual_results = individual_results.select { |res| res['measure_id'] == measure.id.to_s } if individual_results
        # If individual_results are provided, use them.  Otherwise, look them up in the database by measure id and correlation_id
        measure_individual_results ||= CQM::IndividualResult.where('measure_id' => measure._id, correlation_id: @correlation_id, 'extendedData.manual_exclusion': {'$in': [nil, false]})

        aggregate_results_for_measure(measure, measure_individual_results)
      end
      @measure_result_hash
    end

    # rubocop:disable Metrics/AbcSize
    def aggregate_results_for_measure(measure, individual_results = nil)
      # If individual_results are provided, use them.  Otherwise, look them up in the database by measure id and correlation_id
      begin
      individual_results ||= CQM::IndividualResult.where('measure_id': measure._id, correlation_id: @correlation_id, 'extendedData.manual_exclusion': {'$in': [nil, false]})
      rescue Exception => e
           Delayed::Worker.logger.info(e.message)
           Delayed::Worker.logger.info(e.backtrace.inspect)
      end
      observ_values = {}
      # Increment counts for each measure_populations in each individual_result
      individual_results.each do |individual_result|
        key = individual_result['population_set_key']
        observ_values[key] = [] unless observ_values[key]
        measure.population_keys.each do |pop|
          next if individual_result[pop].nil? || individual_result[pop].zero?

          @measure_result_hash[measure.hqmf_id][key][pop] += individual_result[pop]
          # For each population, increment supplemental information counts
          increment_sup_info(@patient_sup_map[individual_result.patient_id.to_s], pop, @measure_result_hash[measure.hqmf_id][key])
        end
        # extract the observed value from an individual results.  Observed values are in the 'episode result'.
        # Each episode will have its own observation
        observ_values[key].concat get_observ_values(individual_result['episode_results']) if individual_result['episode_results']
      end
      # TODO: Observations may not always be the median
      @measure_result_hash[measure.hqmf_id].keys.each do |key|
        @measure_result_hash[measure.hqmf_id][key]['OBSERV'] = observ_values[key] ? median(observ_values[key].reject(&:nil?)) : 0.0
        @measure_result_hash[measure.hqmf_id][key]['measure_id'] = measure.hqmf_id
        @measure_result_hash[measure.hqmf_id][key]['pop_set_hash'] = measure.population_set_hash_for_key(key)
        if @callingfor
         begin
          qc = CQM::QualityReport.where('measure_id' => measure.id, 'effective_date' => @effective_date,'start_date' => @start_date, "filters" => @filters, "status.state" => {'$in': ["pending", "completed"]}).first
          if !qc
            Delayed::Worker.logger.info("creating query cache object")
            create_query_cache_object(@measure_result_hash, measure)
          else
            Delayed::Worker.logger.info(" Delete temporary query cache object with pending status")
            CQM::QualityReport.delete_all({'measure_id' => measure.id, 'effective_date' => @effective_date,'start_date' => @start_date, "filters" => @filters})
            Delayed::Worker.logger.info("creating new query cache object")
            create_query_cache_object(@measure_result_hash, measure)
          end
          rescue Exception => e
           Delayed::Worker.logger.info(e.message)
           Delayed::Worker.logger.info(e.backtrace.inspect)
          end
        end
      end
    end
    # rubocop:enable Metrics/AbcSize

    def get_observ_values(episode_results)
      episode_results.collect_concat do |_id, episode_result|
        # Only use observed values when a patient is in the MSRPOPL and not in the MSRPOPLEX
        next unless episode_result['MSRPOPL']&.positive? && !episode_result['MSRPOPLEX']&.positive?

        episode_result['observation_values']
      end
    end

    def increment_sup_info(patient_sup, pop, single_measure_result_hash)
      # If supplemental_data for a population does not already exist, create a new hash
      unless single_measure_result_hash['supplemental_data'][pop]
        single_measure_result_hash['supplemental_data'][pop] = { 'RACE' => {}, 'ETHNICITY' => {}, 'SEX' => {}, 'PAYER' => {} }
      end
       if (patient_sup.keys != nil)
        patient_sup.keys.each do |sup_type|
          # For each type of supplemental data (e.g., RACE, SEX), increment code values
          add_or_increment_code(pop, sup_type, patient_sup[sup_type], single_measure_result_hash)
        end
      end
    end

    def add_or_increment_code(pop, sup_type, code, single_measure_result_hash)
      # If the code already exists for the meausure_population, increment.  Otherwise create a hash for the code, start at 1
      if single_measure_result_hash['supplemental_data'][pop][sup_type][code]
        single_measure_result_hash['supplemental_data'][pop][sup_type][code] += 1
      else
        single_measure_result_hash['supplemental_data'][pop][sup_type][code] = 1
      end
    end

    def create_query_cache_object(result, measure)
      measure_populations = %w[DENOM NUMER DENEX DENEXCEP IPP MSRPOPL MSRPOPLEX OBSERV]
      #When we have multiple population sets in a measure
      if measure.population_sets.length > 1
      measure.population_sets.each do |population_set|
        # With in population sets if we have multiple stratifications
        if population_set.stratifications.length > 0
          population_set.stratifications.each do |stratification|
            sub_id = stratification.stratification_id
            qco = result[measure.hqmf_id]
            qco_saved = nil
            qco['result'] = {}
            if qco[sub_id].present?
              measure_populations.each do |pop|
                qco[pop] = qco[sub_id][pop]
                qco['result'][pop] = qco[sub_id][pop]
              end
                qco['measure_id'] = measure._id.to_s
                qco['test_id'] = @correlation_id.to_s
                qco['effective_date'] = @effective_date
                qco['start_date'] = @start_date
                qco['sub_id'] = sub_id
                qco['status'] = {}
                qco['status']['state'] = "completed"
                qco['supplemental_data'] = qco[sub_id]['supplemental_data']
                qco['filters'] = @filters
              Mongoid.default_client['query_cache'].insert_one(qco)
          end
        end
        result
        # if there are only multiple populations but not stratifications
        else 
        sub_id = population_set.population_set_id
        qco = result[measure.hqmf_id]
        qco_saved = nil
        qco['result'] = {}
          if qco[sub_id].present?
            measure_populations.each do |pop|
              qco[pop] = qco[sub_id][pop]
              qco['result'][pop] = qco[sub_id][pop]
            end
              qco['measure_id'] = measure._id.to_s
              qco['test_id'] = @correlation_id.to_s
              qco['effective_date'] = @effective_date
              qco['start_date'] = @start_date
              qco['sub_id'] = sub_id
              qco['status'] = {}
              qco['status']['state'] = "completed"
              qco['supplemental_data'] = qco[sub_id]['supplemental_data']
              qco['filters'] = @filters
              Mongoid.default_client['query_cache'].insert_one(qco)
          end
        end
        end
        result
        # Single population with multiple stratifications
      elsif measure.population_sets.length == 1 && measure.population_sets[0].stratifications.length > 0
        measure.population_sets[0].stratifications.each do |stratification|
        sub_id = stratification.stratification_id
        qco = result[measure.hqmf_id]
        qco_saved = nil
        qco['result'] = {}
          if qco[sub_id].present?
            measure_populations.each do |pop|
              qco[pop] = qco[sub_id][pop]
              qco['result'][pop] = qco[sub_id][pop]
            end
              qco['measure_id'] = measure._id.to_s
              qco['test_id'] = @correlation_id.to_s
              qco['effective_date'] = @effective_date
              qco['start_date'] = @start_date
              qco['sub_id'] = sub_id
              qco['status'] = {}
              qco['status']['state'] = "completed"
              qco['supplemental_data'] = qco[sub_id]['supplemental_data']
              qco['filters'] = @filters
              Mongoid.default_client['query_cache'].insert_one(qco)
          end
        end
        result
        #single measure with single population and no stratification
      else
        qco = result
       qco['result'] = {}
       measure_populations.each do |pop|
         qco[pop] = qco[measure.hqmf_id].first[1][pop]
         qco['result'][pop] =  qco[measure.hqmf_id].first[1][pop]
       end
       qco['measure_id'] = measure._id.to_s
       qco['test_id'] = @correlation_id.to_s
       qco['effective_date'] = @effective_date
       qco['start_date'] = @start_date
      #qco['sub_id'] = measure.sub_id if measure.sub_id
       qco['status'] = {}
       qco['status']['state'] = "completed"
       qco['supplemental_data'] = qco[measure.hqmf_id].first[1]['supplemental_data']
       qco['filters'] = @filters
       qc = Mongoid.default_client['query_cache'].insert_one(qco)
       qc
      end
  end

    private

    def mean(array)
      return 0.0 if array.empty?

      array.inject(0.0) { |sum, elem| sum + elem } / array.size
    end

    def median(array, already_sorted = false)
      return 0.0 if array.empty?

      array = array.sort unless already_sorted
      m_pos = array.size / 2
      array.size.odd? ? array[m_pos] : mean(array[m_pos - 1..m_pos])
    end
  end
end
