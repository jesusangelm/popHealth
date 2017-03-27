class OidHelper
  def self.generate_oid_dictionary(measure)
    valuesets = HealthDataStandards::SVS::ValueSet.in(oid: measure['oids'])
    js = {}
    valuesets.each do |vs|
      js[vs['oid']] ||= {}
      if vs.nil?
         puts "WARNING: nil valueset"
      elsif vs['concepts'].nil?
         puts "WARNING: no concepts for valueset: #{vs.oid} for measure #{measure.id}"
      else
        vs['concepts'].each do |con|
          name = con['code_system_name']
          js[vs['oid']][name] ||= []
          js[vs['oid']][name] << con['code'].downcase  unless js[vs['oid']][name].index(con['code'].downcase)
        end
      end
    end

    js.to_json
  end
end