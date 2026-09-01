ENV["RAILS_ENV"] = "test"
require 'simplecov'

require File.expand_path("../../test/dummy/config/environment.rb", __FILE__)
require "rails/test_help"
require "minitest/spec"
# mocha 1.x's minitest adapter assigns ::MiniTest::Assertion
# (mocha/integration/mini_test/adapter.rb:26). That camelCase alias is defined
# in exactly one place -- the deprecated legacy shim file this phase stopped
# requiring -- and
# which also drags in the deprecated Minitest::Unit::TestCase shim. Alias the
# one constant mocha needs instead of requiring the whole deprecated file.
# Delete this when mocha goes to 2.x, which dropped the legacy reference.
MiniTest = Minitest unless defined?(MiniTest)
require 'mocha/minitest'

Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }
require File.expand_path("../../test/factories/factories", __FILE__)
require File.expand_path("../../test/factories/attachable_factories", __FILE__)

require 'minitest/reporters'
Minitest::Reporters.use!

require 'database_cleaner'
DatabaseCleaner.strategy = :truncation

class Minitest::Spec
  after :each do
    DatabaseCleaner.clean
  end
  include FactoryBot::Syntax::Methods
  include FactoryHelpers
end
