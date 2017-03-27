module ReportsHelper
  def generate_cat3(provider, effective_date, measure_ids)
    exporter = HealthDataStandards::Export::Cat3.new
    effective_date ||= Time.gm(2015,12,31)
    end_date = DateTime.new(effective_date.to_i, 12, 31)
    bndl = (b = HealthDataStandards::CQM::Bundle.all.sort(:version => :desc).first) ? b.version : 'n/a'
    use_r11 = /2016/ =~ bndl
    provider_filter = {}
    provider_filter['filters.providers'] = provider.id.to_s
    filter = measure_ids==["all"] ? {} : {:cms_id.in => measure_ids}
    return exporter.export(HealthDataStandards::CQM::Measure.top_level.where(filter),
                            generate_header(provider),
                            effective_date.to_i,
                            end_date.years_ago(1),
                           end_date,
                           use_r11.nil? ? nil : 'r1_1',
                           provider_filter)
  end

  def generate_header(provider)
    header = Qrda::Header.new(APP_CONFIG["cda_header"])

    header.identifier.root = UUID.generate
    header.authors.each {|a| a.time = Time.now}
    header.legal_authenticator.time = Time.now
    header.performers << provider

    header
  end
end
