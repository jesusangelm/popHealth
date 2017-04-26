MONGO_DB = Mongoid.default_client

if $mongo_client.nil?
  host = MONGO_DB.cluster.addresses[0].host #Mongoid::Clients.default.cluster.addresses[0].host
  port = MONGO_DB.cluster.addresses[0].port #Mongoid::Clients.default.cluster.addresses[0].port
  database=MONGO_DB.options[:database] #Mongoid::Clients.default.options[:database]
  options={}
  options={:auth_source => MONGO_DB.options[:auth_source], :user => MONGO_DB.options[:user], :password=>MONGO_DB.options[:password]} if (MONGO_DB.options[:user].present?)
  $mongo_client = Mongo::Client.new("mongodb://#{host}:#{port}/#{database}",options)

end
# js_collection = MONGO_DB['system.js']

# unless js_collection.find_one('_id' => 'contains')
#   js_collection.save('_id' => 'contains', 
#                      'value' => BSON::Code.new("function( obj, target ) { return obj.indexOf(target) != -1; };"))
# end

# # create a unique index for patient cache, this prevents a race condition where the same patient can be entered multiple times for a patient
# MONGO_DB.collection('patient_cache').ensure_index([['value.measure_id', Mongo::ASCENDING], ['value.sub_id', Mongo::ASCENDING], ['value.effective_date', Mongo::ASCENDING], ['value.patient_id', Mongo::ASCENDING]], {'unique'=> true})

# base_fields = [['value.measure_id', Mongo::ASCENDING], ['value.sub_id', Mongo::ASCENDING], ['value.effective_date', Mongo::ASCENDING], ['value.test_id', Mongo::ASCENDING],  ['value.manual_exclusion', Mongo::ASCENDING]]

# %w(population denominator numerator antinumerator exclusions).each do |group|
#   MONGO_DB.collection('patient_cache').ensure_index(base_fields.clone.concat([["value.#{group}", Mongo::ASCENDING]]), {name: "#{group}_index"})
# end

module QME
  module DatabaseAccess
    # Monkey patch in the connection for the application
    def get_db
      MONGO_DB
    end
  end
end

# TODO Set indexes
