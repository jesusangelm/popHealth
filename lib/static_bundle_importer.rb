module StaticBundle
  class StaticBundleImporter
  	def self.import(zip)
  		puts "In static bundle importer import "
  		Zip::ZipFile.open(zip.path) do |zip_file|
  			unpack_and_store(zip_file)
  		end
  	end
  	def self.unpack_and_store(zip)
  		puts "In unpack_and_store"
  		entries = zip.glob(File.join('Json', '**','*.json'))
  		entries.each do |entry|
  			source_measure = unpack_json(entry)
  			measure = source_measure.clone
  			Mongoid.default_client['static_measures'].insert_one(measure)
  		end
  	end
  	def self.unpack_json(entry)
  		puts "In unpack_json"
  		JSON.parse(entry.get_input_stream.read, max_nesting: false)
  	end
  end
end