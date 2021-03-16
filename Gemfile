source 'https://rubygems.org'
ruby '2.6.3'

gem 'rails', '~> 5.2.2'

# Use MongoDB just like in Cypress v2!
gem 'delayed_job_mongoid', git: 'https://github.com/collectiveidea/delayed_job_mongoid', tag: 'v2.3.0'
gem 'mongoid', '~> 6.4.2'
gem 'mongoid-tree'
gem 'mongo'
# gem 'mongoid', '~> 4.0.2'
gem 'bson_ext'
gem 'mustache'
gem 'os'

gem 'cqm-models', '~> 3.0.1'
gem 'cqm-parsers', '~> 3.1.1.0'
gem 'cqm-reports', '~> 3.1.3'
gem 'cqm-validators', '~> 3.0.1'

#gem 'quality-measure-engine', git: 'https://github.com/OSEHRA/quality-measure-engine.git', branch: 'bump_mongoid_v6'

#gem "hqmf2js", :git=> "https://github.com/OSEHRA/hqmf2js.git"
gem 'nokogiri', '~> 1.10'
gem 'rubyzip','~> 1.2'
gem 'net-ssh'
gem 'hquery-patient-api', '1.0.4'
gem 'spreadsheet', '1.0.3'
gem 'sshkit'
# Should be removed in the future. This is only used for the
# admin log page. When the admin pages are switched to
# client side pagination, this can go away.
gem 'will_paginate'
gem 'bunny'
gem "active_model_serializers"

gem 'rest-client', '~>2.0.2'

gem 'json', :platforms => :jruby


gem 'highline', '~> 1.7.8'

gem 'devise'

gem 'git'

#gem 'protected_attributes', '~> 1.1.3'

gem 'foreman'
gem "thin" , '1.7.0'
gem 'formtastic'
gem 'cancancan'
gem 'factory_girl'
gem 'apipie-rails'


gem 'sass-rails', '~> 5.0.4'
# Dependencies for CMS Assets Framework
gem 'bootstrap-sass', '~> 3.4.1'
gem 'jquery-rails', '~> 4.3.3'
gem 'jquery-ui-rails', '~> 6.0.1'

# Gems used for assets
#gem 'bootstrap-sass', '~> 3.3.5'
#gem 'sass-rails'
gem 'coffee-rails'
#gem 'jquery-rails' # necessary for jquery_ujs w/data-method="delete" etc
gem 'bootstrap-datepicker-rails', '1.3.0.2'
gem 'uglifier', '~> 1.3.0'
gem 'non-stupid-digest-assets' # support vendored non-digest assets
gem 'jquery-datatables-rails', '3.4.0'
gem 'select2-rails'

group :test, :develop, :ci do
  gem 'pry'
  gem 'pry-rails'
  gem 'pry-rescue'
  gem 'jasmine', '2.0.1'
  gem 'turn', :require => false
  gem 'simplecov', :require => false
  gem 'simplecov-cobertura', :require => false
  gem 'mocha', :require => false
  gem "unicorn", :platforms => [:ruby, :jruby]
  gem 'minitest', "~> 5.3"
end

group :test, :develop do
  gem 'pry-byebug'
end

group :production do
  gem 'libv8', '~> 3.16.14.3'
  gem 'therubyracer', '~> 0.12.0', :platforms => [:ruby, :jruby] # 10.8 mountain lion compatibility
end

# gem 'handlebars_assets', '0.17.1'
gem 'handlebars_assets', '0.23.1'
