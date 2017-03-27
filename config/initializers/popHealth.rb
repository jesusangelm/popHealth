require 'hqmf-parser'
require 'csv'

APP_CONFIG = YAML.load_file(Rails.root.join('config', 'popHealth.yml'))[Rails.env]

# insert races and ethnicities
(
  MONGO_DB['races'].drop() if MONGO_DB['races']
  MONGO_DB['ethnicities'].drop() if MONGO_DB['ethnicities']
  JSON.parse(File.read(File.join(Rails.root, 'test', 'fixtures', 'code_sets', 'races.json'))).each do |document|
    MONGO_DB['races'].insert_one(document)
  end
  JSON.parse(File.read(File.join(Rails.root, 'test', 'fixtures', 'code_sets', 'ethnicities.json'))).each do |document|
    MONGO_DB['ethnicities'].insert_one(document)
  end
) if MONGO_DB['races'].find.count == 0 || MONGO_DB['ethnicities'].find.count == 0

# insert languages
(
  JSON.parse(File.read(File.join(Rails.root, 'test', 'fixtures', 'code_sets', 'languages.json'))).each do |document|
    MONGO_DB['languages'].insert_one(document)
  end
) if MONGO_DB['languages'].find({}).count == 0

def format_nucc_code(nucc_row)
  display_name = nucc_row['Grouping']
  display_name += " \\ " + nucc_row['Classification'] if nucc_row['Classification']
  display_name += " \\ " + nucc_row['Specialization'] if nucc_row['Specialization']
  display_name
end

# Insert provider specialty taxonomy
(
  provider_value_set = {"display_name" => "NUCC Provider Taxonomy", "oid" => "2.16.840.1.113762.1.4.1026.23", "version" => "16.1", "concepts" => []}
  csv = CSV.parse(File.read(File.join(Rails.root, 'test', 'fixtures', 'code_sets', 'nucc_provider_taxonomy_16_1.csv')).encode('UTF-8', :invalid => :replace), :headers => true)
  csv.each do |row|
    provider_value_set["concepts"].push({
      "black_list" => false,
      "code" => row['Code'],
      "code_system" => "2.16.840.1.113883.11.19465",
      "code_system_name" => "NUCCPT",
      "code_system_version" => "16.1",
      "display_name" => format_nucc_code(row),
      "white_list" => false
      })
  end
  vs = HealthDataStandards::SVS::ValueSet.new(provider_value_set)
  MONGO_DB['health_data_standards_svs_value_sets'].insert_one(vs.as_document)
) if MONGO_DB['health_data_standards_svs_value_sets'].find({'oid' => '2.16.840.1.113762.1.4.1026.23'}).count == 0
