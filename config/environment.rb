# Load the rails application
require File.expand_path('../application', __FILE__)

# Initialize the rails application
PopHealth::Application.initialize!

require_relative '../lib/oid_helper'
#require_relative '../lib/hds/record.rb'
#require_relative '../lib/hds/provider.rb'
#require_relative '../lib/hds/query_cache.rb'
#require_relative '../lib/hds/provider_performance.rb'
# in c4_filter but removed in June in master; currently mentioned in patch.rb
# require_relative '../lib/qme_ext/quality_report.rb' # was ../lib/qme/quality_report.rb
require_relative '../lib/import_archive_job.rb'
require_relative '../lib/cql_ext/value_set.rb'
require_relative '../lib/cql_ext/measure.rb'
require_relative '../lib/cql_ext/patient.rb'
require_relative '../lib/cql_ext/provider.rb'
require_relative '../lib/cql_ext/data_element.rb'
#require_relative '../lib/provider_tree_importer.rb'
#require_relative '../lib/hds/bulk_record_importer.rb'
#require_relative '../lib/hds/value_set.rb'
