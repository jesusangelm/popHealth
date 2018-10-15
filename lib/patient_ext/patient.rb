# The Patient model is an extension of app/models/qdm/patient.rb as defined by CQM-Models.
Patient = QDM::Patient

module QDM
 class Patient
 	def age_at(date)
  	  dob = Time.at(birthDatetime).in_time_zone
      date.year - dob.year - (date.month > dob.month || (date.month == dob.month && date.day >= dob.day) ? 0 : 1)
	end
	def gender
      gender_chars = get_data_elements('patient_characteristic', 'gender')
      if gender_chars&.any? && gender_chars.first.dataElementCodes &&
         gender_chars.first.dataElementCodes.any?
        gender_chars.first.dataElementCodes.first['code']
      else
        raise 'Cannot find gender element'
      end
    end

    def race
      race_element = get_data_elements('patient_characteristic', 'race')
      if race_element&.any? && race_element.first.dataElementCodes &&
         race_element.first.dataElementCodes.any?
        race_element.first.dataElementCodes.first['code']
      else
        raise 'Cannot find race element'
      end
    end

    def ethnicity
      ethnicity_element = get_data_elements('patient_characteristic', 'ethnicity')
      if ethnicity_element&.any? && ethnicity_element.first.dataElementCodes &&
         ethnicity_element.first.dataElementCodes.any?
        ethnicity_element.first.dataElementCodes.first['code']
      else
        raise 'Cannot find ethnicity element'
      end
	end
	def lookup_provider(include_address = nil)
      # find with provider id hash i.e. "$oid"->value
      provider = Provider.find(JSON.parse(extendedData['provider_performances']).first['provider_id'])
      addresses = []
      provider.addresses.each do |address|
        addresses << { 'street' => address.street, 'city' => address.city, 'state' => address.state, 'zip' => address.zip,
                       'country' => address.country }
      end

      return { 'npis' => [provider.npi], 'tins' => [provider.tin], 'addresses' => addresses } if include_address
      { 'npis' => [provider.npi], 'tins' => [provider.tin] }
	end
 end
end