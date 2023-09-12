source 'http://rubygems.org'

ruby '2.7.8'

# Load this project as a gem.
gemspec
# gem 'query_reviewer' # Enable for performance tuning


gem 'puma', '~> 4'
gem 'railties', '~> 4.2'

gem 'sass-rails', '~>5.0.0'
gem 'sprockets-rails', '~>2.3.1'

# Uncomment to confirm that older versions work (for compaitiblity with Spree 2.2.4/bcms_spree)
# gem 'paperclip', '~> 3.4.1'
# For testing behavior in production
group :production do
  gem 'uglifier'
end

group :development do
  gem 'rake'
  # gem 'debugger'
  gem 'better_errors'
  gem 'binding_of_caller'
end
group :test, :development do
  gem 'minitest'
  gem "test-unit", "~> 3.0"
  gem 'minitest-rails'
  gem 'minitest-reporters'
  gem 'yard'
  gem 'bluecloth'
  gem 'pry'
  gem 'awesome_print'
  gem 'rails-controller-testing'
end

group :test do
  gem 'pg'
  gem 'sass-rails'
  gem 'simplecov', require: false

  gem 'poltergeist'
  gem 'm'

  gem 'single_test'
  gem 'factory_girl_rails'
  gem 'mocha', require: false

  # Cucumber and dependencies
  gem 'capybara'
  gem 'database_cleaner'
  gem 'cucumber-rails', '~> 1.4.1', :require=> false
  gem 'cucumber'
  gem 'launchy'
  gem 'ruby-prof'
  gem 'aruba', '= 0.14.14'
  gem 'loofah', '= 2.19.1'
  gem 'delayed_job'
end
