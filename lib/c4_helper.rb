module C4Helper
  class Cat1Exporter
    attr_accessor :measures
    attr_accessor :start_time
    attr_accessor :end_time
    # note bad redundancy: have to declare version on init
    # (don't know if call on export matters at all -- should be one or the other)
    CAT1EXPORTER = HealthDataStandards::Export::Cat1.new('r3_1')

    def initialize
      # define @measures, @start_time @end_time from query_cache  use pushnew? with measures
      measids=[]
      QME::QualityReport.all.each { |qr|
        @start_time=qr['start_time']
        @end_time=qr['effective_time']
        measids.push(qr['measure_id']) if !measids.include?(qr['measure_id'])
      }
      @measures = QME::QualityMeasure.in(:_id => measids).to_a
    end

    def export(patient)
      # don't know about this one; try both ways
      cms_compatible = true # if patient.product_test && patient.product_test.product.c3_test
      # qrda version is hard coded right now!!!
      CAT1EXPORTER.export(patient, @measures, @start_time, @end_time, nil, 'r3_1', #patient.bundle.qrda_version,
                          cms_compatible)
    end

    def zip(file, patients)
      patients = apply_sort_to patients

      Zip::ZipOutputStream.open(file.path) do |z|
        patients.each_with_index do |patient, i|
          # safe_first_name = patient.first.delete("'")
          # safe_last_name = patient.last.delete("'")
          # next_entry_path = "#{i}_#{safe_first_name}_#{safe_last_name}"
          z.put_next_entry("#{next_entry_path(patient, i)}.qrda")
          z << export(patient)
        end
      end
    end

    def apply_sort_to(patients)
      if patients.is_a? Array
        patients.sort_by { |p| p.first + '_' + p.last }
      else
        patients.order_by(:first.asc, :last.asc)
      end
    end

    def next_entry_path(patient, index)
      safe_first_name = patient.first.delete("'")
      safe_last_name = patient.last.delete("'")
      "#{index}_#{safe_first_name}_#{safe_last_name}"
    end

  end

  # Problem: you have to be running on the same machine you loaded the original file from
  class Cat1ZipFilter
    attr_accessor :measures
    attr_accessor :start_date
    attr_accessor :end_date
    attr_accessor :exporter

    def initialize(measures_in, start_date_in, end_date_in)
      @exporter = HealthDataStandards::Export::Cat1.new 'r3_1'
      @measures=measures_in
      @start_date=start_date_in
      @end_date=end_date_in
    end

    def make_name(p)
      "#{p['first']}_#{p['last']}"
    end

    def pluck(outfilepath, patients)
      #, Zip::File::CREATE
      if patients && patients.length > 0
        Zip::OutputStream.open(outfilepath) do |zout|
            patients.each do |patient_hash|
              patient=patient_hash[:record]
              pmeas=@measures.select { |m| patient_hash[:sub_id].include?(m[:sub_id]) }
              zout.put_next_entry(make_name(patient)+'.xml')
              zout.puts(@exporter.export(patient, pmeas, @start_date, @end_date, nil, 'r3_1'))
            end
            zout.close
        end
      else
        # clumsy alternative; add a bogus file to the zip and then delete it. UGH!
        File.open(outfilepath,'w') do |zout|
          zout.print("\x50\x4b\x05\x06\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
        end
      end
    end
  end


  class Cat3Helper
    attr_accessor :measids
    attr_accessor :start_time
    attr_accessor :end_time

    def initialize
      # define @measures, @start_time @end_time from query_cache  use pushnew? with measures
      @measids=[]
      QME::QualityReport.all.each { |qr|
        @start_time=qr['start_time']
        @end_time=qr['effective_time']
        @measids.push(qr['measure_id']) if !measids.include?(qr['measure_id'])
      }
      #@measures = QME::QualityMeasure.in(:_id => measids).to_a
    end

    def cat3(provider_ids, providers, filepath)
      #log_api_call LogAction::EXPORT, "QRDA Category 3 report"
      # measure_ids = params[:measure_ids] ||current_user.preferences["selected_measure_ids"]
      filter = @measids=="all" ? {} : {:hqmf_id.in => @measids}
      exporter = HealthDataStandards::Export::Cat3.new
      effective_date = @end_time
      effective_start_date = @start_time
      end_date = Time.at(effective_date.to_i)
      bndl = (b = HealthDataStandards::CQM::Bundle.all.sort(:version => :desc).first) ? b.version : 'n/a'
      # todo: generalize to 2016 and beyond
      use_r11 = /2016/ =~ bndl
      provider_filter = nil
      if !provider_ids.nil?
        provider_filter={'filters.providers' => provider_ids}
      end
      # workaround not being rails controller
      cat3xml = exporter.export(HealthDataStandards::CQM::Measure.top_level.where(filter),
                                generate_header(providers),
                                effective_date.to_i,
                                Time.at(effective_start_date.to_i),
                                end_date,
                                use_r11.nil? ? nil : 'r1_1',
                                provider_filter)
      File.open(filepath+'-qrda-cat3.xml', 'w') { |f| f.write(cat3xml) }
      cat3xml
    end

    def generate_header(provider)
      header = Qrda::Header.new(APP_CONFIG["cda_header"])

      header.identifier.root = UUID.generate
      header.authors.each { |a| a.time = Time.now }
      header.legal_authenticator.time = Time.now
      header.performers << provider

      header
    end

  end
end
