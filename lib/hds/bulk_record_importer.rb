#require 'cqm/converter'

require 'fileutils'
require_relative '../cql_ext/provider_importer.rb'

class BulkRecordImporter
  def initialize
    super
  end 
  
  def self.import_archive(file, failed_dir=nil, practice=nil)
    begin
      failed_dir ||= File.join(File.dirname(file), "failed")
      #@hds_record_converter = CQM::Converter::HDSRecord.new
      patient_id_list = nil
      Zip::ZipFile.open(file.path) do |zipfile|
        zipfile.entries.each do |entry|
          if entry.name
            if entry.name.split("/").last == "patient_manifest.txt"
              patient_id_list = zipfile.read(entry.name)
              next
            end
          end
          next if entry.directory?
          data = zipfile.read(entry.name)
          self.import_file(entry.name,data,failed_dir,nil,practice)
        end
      end
      missing_patients = []

      #if there was a patient manifest, theres a patient id list we need to load
      #if patient_id_list
        #patient_id_list.split("\n").each do |id|
          #patient = Record.where(:medical_record_number => id).first
          #if patient == nil
            #missing_patients << id
          #end
        #end
      #end
      missing_patients
    rescue => ex
      FileUtils.mkdir_p(failed_dir)
      FileUtils.cp(file, File.join(failed_dir, File.basename(file)))
      File.open(File.join(failed_dir,"#{File.basename(file)}.error"), "w") do |f|
        f.puts($!.message)
        f.puts($!.backtrace)
      end
      raise $!
    end
  end

  def self.import_file(name,data,failed_dir,provider_map={}, practice=nil)
    begin
      ext = File.extname(name)
      if ext == ".json"
        self.import_json(data)
      else
        self.import(data, {}, practice)
      end
    rescue Exception => e
      Delayed::Worker.logger.info(e.message)
      Delayed::Worker.logger.info(e.backtrace.inspect)

      FileUtils.mkdir_p(File.dirname(File.join(failed_dir,name)))
      File.open(File.join(failed_dir,name),"w") do |f|
        f.puts(data)
      end
      File.open(File.join(failed_dir,"#{name}.error"),"w") do |f|
        f.puts($!.message)
        f.puts($!.backtrace)
      end
    end
  end

  def self.import(xml_data, provider_map = {}, practice_id=nil)
    doc = Nokogiri::XML(xml_data)
    prov_perf = []
    #@hds_record_converter = CQM::Converter::HDSRecord.new

    providers = []
    
    root_element_name = doc.root.name
    if root_element_name == 'ClinicalDocument'
      doc.root.add_namespace_definition('cda', 'urn:hl7-org:v3')
      doc.root.add_namespace_definition('sdtc', 'urn:hl7-org:sdtc')
      #if doc.at_xpath("/cda:ClinicalDocument/cda:templateId[@root='2.16.840.1.113883.3.88.11.32.1']")
        #patient_data = HealthDataStandards::Import::C32::PatientImporter.instance.parse_c32(doc)
      #elsif doc.at_xpath("/cda:ClinicalDocument/cda:templateId[@root='2.16.840.1.113883.10.20.22.1.2']")
        #patient_data = HealthDataStandards::Import::CCDA::PatientImporter.instance.parse_ccda(doc)
      #elsif doc.at_xpath("/cda:ClinicalDocument/cda:templateId[@root='2.16.840.1.113883.10.20.24.1.2']")
        begin

          patient_data = QRDA::Cat1::PatientImporter.instance.parse_cat1(doc)
          #Delayed::Worker.logger.info(patient_data.qdmPatient.dataElements)
          patient_data = self.update_address(patient_data, doc)
          patient_data.bundleId = Bundle.all.first.id
          bundle = Bundle.all.first
          CqlData::QRDAPostProcessor.replace_negated_codes(patient_data, bundle)
        rescue Exception => e
          puts "UNABLE TO IMPORT PATIENT RECORD"
          puts e.message
          Delayed::Worker.logger.info("UNABLE TO IMPORT PATIENT RECORD")
          Delayed::Worker.logger.info(e.message)
        end 
      begin
        providers = PROV::ProviderImporter.instance.extract_providers(doc, patient_data)
      rescue Exception => e
        STDERR.puts "error extracting providers"
        puts e.message
      end
    else
      return {status: 'error', message: 'Unknown XML Format', status_code: 400}
    end
    ignore_provider_performance_dates = APP_CONFIG['ignore_provider_performance_dates']
    if practice_id
      practice = Practice.find(practice_id)
      practice_provider = practice.provider
      npi_providers = providers.map {|perf| perf}
      name = practice.name + " Unassigned"
      cda_identifier = CDAIdentifier.new({root: APP_CONFIG['orphan_provider']['root'], extension: name})
      begin
      providers.each do |perf|
        prov = perf.provider
        if ignore_provider_performance_dates
          p_start = nil 
          p_end = nil
        else
          p_start = perf.start_date
          p_end = perf.end_date
        end
        if prov.cda_identifiers.first.extension == 'Orphans'          
          orphan_provider = Provider.where("cda_identifiers.extension" => name).first
          if orphan_provider   
            new_prov = orphan_provider
          else     
            new_prov = Provider.create(cda_identifiers: [cda_identifier], given_name: name)
            new_prov.parent = practice_provider
            new_prov.save!
          end
          npi_providers.delete(perf)
          npi_providers << ProviderPerformance.new(start_date: p_start, end_date: p_end, provider: new_prov)  
        else
          if prov.parent == nil
            prov.parent = practice_provider
            prov.save!
          elsif prov.parent.id == practice_provider.id
                next
          else
            prov_check = Provider.where({'cda_identifiers.extension' => prov.cda_identifiers.first.extension, parent_id: practice_provider.id}).first
            if prov_check
              npi_providers.delete(perf)
              npi_providers << ProviderPerformance.new(start_date: p_start, end_date: p_end, provider: prov_check)
            else            
              new_prov = prov.clone
              new_prov.parent = practice_provider
              new_prov.save
              npi_providers.delete(perf)
              npi_providers << ProviderPerformance.new(start_date: p_start, end_date: p_end, provider: new_prov)
            end
          end
        end
      end
    rescue Exception => e
        STDERR.puts "error in creating provider provider_performances"
        puts e.message
    end 
      
      # if no providers assigned, then assign to orphan
      if npi_providers.empty?
        orphan_provider = Provider.where("cda_identifiers.extension" => name).first
        if orphan_provider
          new_prov = orphan_provider
        else
          new_prov = Provider.new(cda_identifiers: [cda_identifier], givenNames: [name])
          new_prov.parent = practice_provider
          new_prov.save!
        end
        npi_providers << ProviderPerformance.new(provider: new_prov)
      end
      prov_perf << npi_providers.to_json
      orphan_prov = Provider.where("cda_identifiers.extension" => "Orphans").first
      if orphan_prov
        prov = orphan_prov
        prov.parent = nil
        prov.parent_ids = nil
        prov.save!
      end
      providers = npi_providers
    else # if no practice, use regular assignment
      prov_perf << providers.to_json
    end

    providers.each do |prov|
      prov.provider.ancestors.each do |ancestor|
        if ignore_provider_performance_dates
          p_start = nil 
          p_end = nil
        else
          p_start = prov.start_date
          p_end = prov.end_date
        end
        prov_perform = [ProviderPerformance.new(start_date: p_start, end_date: p_end, provider: ancestor)].to_json

        prov_perf << prov_perform
      end
    end
    begin
    patient_data.qdmPatient.extendedData = {:provider_performances => prov_perf}
    cqm_patient = self.checkdedup(patient_data, practice_id)
    cqm_patient.save(validate: false)
    #patient_data.save(validate: false)
    rescue Exception => e
      puts e.message
      Delayed::Worker.logger.info(e.message)
      Delayed::Worker.logger.info(e.backtrace)
    end
  end

  def self.update_address(patient_data, doc)
    patient_role_element = doc.at_xpath('/cda:ClinicalDocument/cda:recordTarget/cda:patientRole')
    patient_data[:addresses] = patient_role_element.xpath("./cda:addr").map { |addr| self.import_address(addr) }
    patient_data[:telecoms] = patient_role_element.xpath("./cda:telecom").map { |tele| self.import_telecom(tele) }
    patient_data
  end

  def self.import_address(address_element)
    address = CQM::Address.new
    address.use = address_element['use']
    address.street = address_element.xpath("./cda:streetAddressLine").map {|street| street.text}
    address.city = address_element.at_xpath("./cda:city").try(:text)
    address.state = address_element.at_xpath("./cda:state").try(:text)
    address.zip = address_element.at_xpath("./cda:postalCode").try(:text)
    address.country = address_element.at_xpath("./cda:country").try(:text)
    address
  end

  def self.import_telecom(telecom_element) 
     tele = CQM::Telecom.new
     tele.value = telecom_element['value']
     tele.use = telecom_element['use']
     tele
  end
  def self.checkdedup(patient_data, practice_id=nil)
    db = Mongoid.default_client
    #mrn = qdm_patient.extendedData['medical_record_number']
    first = patient_data.givenNames[0]
    last = patient_data.familyName
    street = patient_data.addresses.first.street.first
    city =  patient_data.addresses.first.city
    state = patient_data.addresses.first.state
    zip = patient_data.addresses.first.zip
    dob = patient_data.qdmPatient.birthDatetime
    
    demochange_pipeline = []
    demochange_pipeline << {'$match' => { '$or' => [
      {givenNames: first, familyName: last, 'addresses.street': street, 'addresses.city': city, 'addresses.state': state, 'addresses.zip': zip, 'qdmPatient.birthDatetime': dob},
      {givenNames: first, 'addresses.street': street, 'addresses.city': city, 'addresses.state': state, 'addresses.zip': zip, 'qdmPatient.birthDatetime': dob},
      {familyName: last, 'addresses.street': street, 'addresses.city': city, 'addresses.state': state, 'addresses.zip': zip, 'qdmPatient.birthDatetime': dob}  
    ]}}
    result =  db['cqm_patients'].aggregate(demochange_pipeline)

    if result.first
      existing_patient = CQM::Patient.where("_id": result.first._id).first
      existing_patient.update_attributes(patient_data.attributes.except("_id", "qdmPatient"))
      #existing.update_attributes!(qdm_patient.attributes.except("_id", "extendedData", "practice_id", "dataElements"))
      #existing.extendedData.update(qdm_patient.extendedData.except("medical_record_number"))
      existing_patient = self.update_dataelements(existing_patient, patient_data)
      existing_patient
    else
      patient_data
    end
  end

  def self.update_dataelements(existing, incoming)
    incoming.qdmPatient.dataElements.each do |de|
      Delayed::Worker.logger.info("Working on " +de["_type"]+ " Data Element")
      if de["hqmfOid"] == "2.16.840.1.113883.10.20.28.4.59" || de["hqmfOid"] == "2.16.840.1.113883.10.20.28.4.55" || de["hqmfOid"] == "2.16.840.1.113883.10.20.28.4.56"
        existing.qdmPatient.dataElements.map do |dataelement|
          if dataelement["hqmfOid"] == "2.16.840.1.113883.10.20.28.4.59"  || dataelement["hqmfOid"] == "2.16.840.1.113883.10.20.28.4.55" || dataelement["hqmfOid"] == "2.16.840.1.113883.10.20.28.4.56"
            Delayed::Worker.logger.info("Replacing data element in case of Gender, Race & Ethnicity")
            dataelement = de
          end
        end
      else
        Delayed::Worker.logger.info("* Working on " +de["_type"]+ " Data Element *")
        query={}
        section = "qdmPatient.dataElements"
        query = {'_id': existing._id,section => {'$elemMatch' => {}}}

        if de["_type"]
          query[section]['$elemMatch']["_type"] = de["_type"]
        end
        if de["result"]
          query[section]['$elemMatch']["result"] = de["result"]
        end

        if de["authorDatetime"]
          query[section]['$elemMatch']["authorDatetime"] = de["authorDatetime"]
        end
      
        if de["relevantPeriod"]
          query[section]['$elemMatch']["relevantPeriod.low"] = de["relevantPeriod"][:low] if de["relevantPeriod"][:low]
          query[section]['$elemMatch']["relevantPeriod.high"] = de["relevantPeriod"][:high] if de["relevantPeriod"][:high]
        end
      
        if de["dataElementCodes"]
          query[section]['$elemMatch']['dataElementCodes'] = de['dataElementCodes']
        end

        is_available = CQM::Patient.where(query).first
        if is_available == nil
          existing.qdmPatient.dataElements.push(de)
        end 
      end   
    end
    existing
  end
end

=begin
  def self.checkdedup(qdm_patient, practice_id=nil)
    mrn = qdm_patient.extendedData['medical_record_number']
    existing = CQM::Patient.where(:"extendedData.medical_record_number" => mrn).first
    if existing
      existing.update_attributes!(qdm_patient.attributes.except("_id", "extendedData", "practice_id", "dataElements"))
      existing.extendedData.update(qdm_patient.extendedData.except("medical_record_number"))
      existing = self.update_dataelements(existing, qdm_patient, mrn)
      existing
    else
      qdm_patient
    end
  end

  def self.update_dataelements(existing, incoming, mrn)

    incoming.dataElements.each do |de|
      query={}
      section = "dataElements"
      query = {'extendedData.medical_record_number': mrn, section => {'$elemMatch' => {}}}

      if de["_type"]
        query[section]['$elemMatch']["_type"] = de["_type"]
      end

      if de["relevantPeriod"]
        query[section]['$elemMatch']["relevantPeriod.low"] = de["relevantPeriod"][:low] if de["relevantPeriod"][:low]
        query[section]['$elemMatch']["relevantPeriod.high"] = de["relevantPeriod"][:high] if de["relevantPeriod"][:high]
      end
      
      if de["dataElementCodes"]
        query[section]['$elemMatch']['dataElementCodes'] = de['dataElementCodes']
      end

      is_available = CQM::Patient.where(query).first
      if is_available == nil
        existing.dataElements.push(de)
      end    
    end
    existing
  end
=end
#end
