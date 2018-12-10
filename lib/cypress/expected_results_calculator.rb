module Cypress
  class ExpectedResultsCalculator
    def initialize(patients, test_id, effective_date, filters)
      @patients = patients
      @test_id = test_id
      @effective_date = effective_date
      @patient_sup_map = {}
      @measure_result_hash = {}
      @filters = filters
      @patients.each do |patient|
        add_patient_to_sup_map(@patient_sup_map, patient)
      end
    end

    def add_patient_to_sup_map(ps_map, patient)
      patient_id = patient.id.to_s
      ps_map[patient_id] = {}
      ps_map[patient_id]['SEX'] = patient.get_by_hqmf_oid('2.16.840.1.113883.10.20.28.3.55')[0].dataElementCodes[0]['code']
      ps_map[patient_id]['RACE'] = patient.get_by_hqmf_oid('2.16.840.1.113883.10.20.28.3.59')[0].dataElementCodes[0]['code']
      ps_map[patient_id]['ETHNICITY'] = patient.get_by_hqmf_oid('2.16.840.1.113883.10.20.28.3.56')[0].dataElementCodes[0]['code']
      ps_map[patient_id]['PAYER'] = JSON.parse(patient.extendedData['insurance_providers']).first['codes']['SOP'].first
    end

    def aggregate_results_for_measures(measures)
        measures.each do |measure|
          @measure_result_hash['result']= {}
          @measure_result_hash['status']={}
          aggregate_results_for_measure(measure)
        end
        @measure_result_hash
    end

    # rubocop:disable Metrics/AbcSize
    def aggregate_results_for_measure(measure)
        individual_results = QDM::IndividualResult.where('measure_id' => measure._id, 'extendedData.correlation_id' => @test_id.to_s, "extendedData.manual_exclusion" => {'$in' => [nil, false]})
        measure_populations = %w[DENOM NUMER DENEX DENEXCEP IPP MSRPOPL MSRPOPLEX]
        @measure_result_hash['result']['supplemental_data'] = {}
        measure_populations.each do |pop|
          @measure_result_hash['result'][pop] = 0
        end
        observ_values = []
        individual_results.each do |ir|
          measure_populations.each do |pop|
            next if ir[pop].nil? || ir[pop].zero?
            @measure_result_hash['result'][pop] += ir[pop]
            increment_sup_info(@patient_sup_map[ir.patient_id.to_s], pop, @measure_result_hash['result'])
          end

          observ_values.concat get_observ_values(ir['episode_results']) if ir['episode_results']
        end
        @measure_result_hash['result']['OBSERV'] = median(observ_values.reject(&:nil?))
        @measure_result_hash['measure_id'] = measure.hqmf_id
        @measure_result_hash['population_ids'] = measure.population_ids
        create_query_cache_object(@measure_result_hash, measure)
      #end
    end
    # rubocop:enable Metrics/AbcSize

    def get_observ_values(episode_results)
      episode_results.collect_concat do |_id, episode_result|
        next unless episode_result['MSRPOPL']&.positive? && !episode_result['MSRPOPLEX']&.positive?
        episode_result['values']
      end
    end

    def increment_sup_info(patient_sup, pop, single_measure_result_hash)
      unless single_measure_result_hash['supplemental_data'][pop]
        single_measure_result_hash['supplemental_data'][pop] = { 'RACE' => {}, 'ETHNICITY' => {}, 'SEX' => {}, 'PAYER' => {} }
      end
      patient_sup.keys.each do |sup_type|
        add_or_increment_code(pop, sup_type, patient_sup[sup_type], single_measure_result_hash)
      end
    end

    def add_or_increment_code(pop, sup_type, code, single_measure_result_hash)
      if single_measure_result_hash['supplemental_data'][pop][sup_type][code]
        single_measure_result_hash['supplemental_data'][pop][sup_type][code] += 1
      else
        single_measure_result_hash['supplemental_data'][pop][sup_type][code] = 1
      end
    end

    def create_query_cache_object(result, measure)
      measure_populations = %w[DENOM NUMER DENEX DENEXCEP IPP MSRPOPL MSRPOPLEX OBSERV]
      qco = result
      measure_populations.each do |pop|
        qco[pop] = qco['result'][pop]
      end
      qco['test_id'] = @test_id
      qco['effective_date'] = @effective_date
      qco['sub_id'] = measure.sub_id if measure.sub_id
      qco['status']['state'] = "completed"
      qco['supplemental_data'] = qco['result']['supplemental_data']
      qco['filters'] = @filters
      Mongoid.default_client['query_cache'].insert_one(qco)
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
