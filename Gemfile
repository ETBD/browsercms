source 'http://rubygems.org'

ruby '2.7.8'

# Load this project as a gem.
gemspec
# gem 'query_reviewer' # Enable for performance tuning

gem 'puma', '~> 4'
gem 'railties', '~> 4.2'
# Uncomment to confirm that older versions work (for compaitiblity with Spree 2.2.4/bcms_spree)
# gem 'paperclip', '~> 3.4.1'
# For testing behavior in production
group :production do
  gem 'uglifier'
end

group :development do
  gem 'rake'
  # gem 'debugger'
  # gem 'quiet_assets'
end
group :test, :development do
  gem 'minitest'
  gem 'minitest-rails'
  gem 'minitest-reporters'
  gem 'yard'
  gem 'bluecloth'
  gem 'pry'
  # Not auto-required: requiring it monkeypatches Array#grep with an
  # implementation that does `"str" =~ SomeClass`, which floods Ruby 2.7 with
  # "deprecated Object#=~ is called on Class" warnings from every
  # ActiveRecord where(hash) call. Run `require 'awesome_print'` in a console
  # when you actually want `ap`.
  gem 'awesome_print', require: false
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
  gem 'cucumber-rails', require: false
  gem 'database_cleaner'
  gem 'launchy'

  # ruby-prof needs this config for installation on modern macos
  # bundle config --global build.ruby-prof --with-cflags="-Wno-incompatible-pointer-types"
  gem 'ruby-prof'
  gem 'aruba', '= 0.14.14'
  gem 'loofah', '= 2.19.1'
  gem 'delayed_job'
end
