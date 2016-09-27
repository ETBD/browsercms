source 'http://rubygems.org'

ruby '2.2.4'

# Load this project as a gem.
gemspec
# gem 'query_reviewer' # Enable for performance tuning

gem 'puma'

# Uncomment to confirm that older versions work (for compaitiblity with Spree 2.2.4/bcms_spree)
# gem 'paperclip', '~> 3.4.1'
# For testing behavior in production
group :production do
  gem 'uglifier'
end

group :development do
  gem 'rake'
  # gem 'debugger'
  gem 'quiet_assets'
end
group :test, :development do
  gem 'minitest'
  gem 'minitest-rails'
  gem 'minitest-reporters'
  gem 'yard'
  gem 'bluecloth'
  gem 'pry'
  gem 'awesome_print'
end

group :test do
  gem 'pg'
  gem 'sass-rails'

  gem 'poltergeist'
  gem 'm', '~> 1.2'

  gem 'single_test'
  gem 'factory_girl_rails'
  gem "mocha", require: false

  # Cucumber and dependencies
  gem 'capybara'
  gem 'cucumber-rails', require: false
  gem 'database_cleaner'
  gem 'launchy'
  gem 'ruby-prof'
  gem 'aruba'
end
