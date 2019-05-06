require 'bundler/inline'

gemfile do	
gem 'cqm-converter', git: 'https://github.com/OSEHRA/cqm-converter.git', branch: 'master'
gem 'health-data-standards', git: 'https://github.com/OSEHRA/health-data-standards.git', branch: 'r5'
gem 'cql_qdm_patientapi',git: 'https://github.com/projecttacoma/cql_qdm_patientapi.git', tag: 'v1.2.0'
gem 'cqm-models', '~> 0.8.4'
gem 'cqm-parsers', '~> 0.2.1'
gem 'cqm-validators', '~> 0.1.0'
gem 'json', '~> 2.1.0'
gem 'mongoid', '~> 5.0.2'
end


Mongoid.load!('./mongoid.yml', :production)
Mongoid.logger.level = Logger::FATAL
Mongo::Logger.logger.level = Logger::FATAL
@hds_record_converter = CQM::Converter::HDSRecord.new
puts "Begining Patient Data Migration"
begin
Record.all.each do |record|
	puts "BEGIN: Import patient file for #{record.first} #{record.last}"	
	qdm_patient = @hds_record_converter.to_qdm(record)
	qdm_patient.save!
	puts "COMPLETED: Import patient file for #{record.first} #{record.last}"
end
puts "Patient Data Migration is Complete"
Record.delete_all
rescue => err
	puts err.backtrace
	puts "Error in importing patients.Contact popHealth support team"
end
