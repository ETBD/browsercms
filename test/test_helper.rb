ENV["RAILS_ENV"] = "test"
require 'simplecov'

require File.expand_path("../dummy/config/environment.rb", __FILE__)
require "rails/test_help"

Rails.backtrace_cleaner.remove_silencers!

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

# mocha 1.x's minitest adapter assigns ::MiniTest::Assertion
# (mocha/integration/mini_test/adapter.rb:26). That camelCase alias is defined
# in exactly one place -- the deprecated legacy shim file this phase stopped
# requiring -- and
# which also drags in the deprecated Minitest::Unit::TestCase shim. Alias the
# one constant mocha needs instead of requiring the whole deprecated file.
# Delete this when mocha goes to 2.x, which dropped the legacy reference.
MiniTest = Minitest unless defined?(MiniTest)
require 'mocha/minitest'
require 'action_view/test_case'

# Allows Generators to be unit tested
require "rails/generators/test_case"

require 'mock_file'
require 'support/factory_helpers'
require 'support/database_helpers'

# I'm not sure why ANY of these FactoryBot requires are necessary at all.
require 'factory_bot'
require 'factories/factories'
require 'factories/attachable_factories'

# A global warning suppression used to sit here, to quiet HTML-parsing noise in
# the functional tests. It also silenced every Ruby deprecation warning in the
# suite -- and those are the roadmap for the Rails upgrade, so they are worth
# the noise. Do not reinstate a blanket suppression: silence a specific warning
# at a specific call site, with a comment saying why.

require 'support/engine_controller_hacks'

# The suite runs two cleaning strategies side by side: ActiveSupport::TestCase
# rolls each test back in a transaction, while Minitest::Spec truncates via
# DatabaseCleaner after every example. db:install seeds a Home page and a
# /system section, and the first truncation permanently removes them -- so a
# transactional test saw seeded data or an empty table depending purely on
# where the random test order happened to put the first spec. Tests that assert
# the exact contents of the root section (Section#master_section_list,
# #sitemap, #visible_child_nodes) passed or failed on that coin flip.
#
# Start every run from the same empty database. The helpers in
# support/factory_helpers.rb all find_or_create what they need.
require 'database_cleaner'
DatabaseCleaner.clean_with(:truncation)

class ActiveSupport::TestCase

  include FactoryBot::Syntax::Methods
  include FactoryHelpers

  # Add more helper methods to be used by all tests here...
  require File.dirname(__FILE__) + '/test_logging'
  include TestLogging
  require File.dirname(__FILE__) + '/custom_assertions'
  include CustomAssertions

  #----- Test Macros -----------------------------------------------------------
  class << self
    def should_validate_presence_of(options)
      factory_name = options.keys.first
      fields = options[factory_name]
      fields.each do |f|
        define_method("test_validates_presence_of_#{f}") do
          model = FactoryBot.build(factory_name, f => nil)
          assert !model.valid?
          assert_has_error_on model, f, "can't be blank"
        end
      end
    end

    def should_validate_uniqueness_of(options)
      class_name = options.keys.first
      fields = options[class_name]
      fields.each do |f|
        define_method("test_validates_uniqueness_of_#{f}") do
          existing_model = FactoryBot.create(class_name)
          model = FactoryBot.build(class_name, f => existing_model.send(f))
          assert !model.valid?
          assert_has_error_on model, f, "has already been taken"
        end
      end
    end
  end


   # Read the actual file contents and return them as a string.
  def file_contents(path_to_file)
    open(path_to_file) {|f| f.read }
  end

  def self.subclasses_from_module(module_name)
    subclasses = []
    mod = module_name.constantize
    if mod.class == Module
      mod.constants.each do |module_const_name|
        begin
          klass_name = "#{module_name}::#{module_const_name}"
          klass = klass_name.constantize
          if klass.class == Class
            subclasses << klass
            subclasses += klass.send(:descendants).collect { |x| x.respond_to?(:constantize) ? x.constantize : x }
          else
            subclasses += subclasses_from_module(klass_name)
          end
        rescue NameError
          raise $!
          puts $!.inspect
        end
      end
    end
    return subclasses
  end

  #----- Fixture/Data related helpers ------------------------------------------

  def admin_user
    cms_users(:user_1)
  end

  def login_as(user)
    sign_in user
    #@request.session[:user_id] = user ? user.id : nil
  end

  def login_as_cms_admin
    given_there_is_a_cmsadmin if Cms::User.count == 0
    admin = Cms::User.first
    login_as(admin)
    admin
  end


  # Takes a list of the names of instance variables to "reset"
  # Each instance variable will be set to a new instance
  # That is found by looking that object by id
  def reset(*args)
    args.each do |v|
      val = instance_variable_get("@#{v}")
      instance_variable_set("@#{v}", val.class.find(val.id))
    end
  end

  # @3.4.x-merge Remove me once Cucumber coverage is added

  # Fixtures add incorrect Section/Section node data. We don't want to replace fixtures AGAIN (this is handled in CMS 3.3)
  # so we can just clean it out using this method where needed to avoid test breakage.
  def remove_all_sitemap_fixtures_to_avoid_bugs
    #Section.delete_all
    #SectionNode.delete_all
    #Page.delete_all
  end

  # @3.4.x-merge Remove me once Cucumber coverage is added

  # Create a 'faux' sitemap which will work for tests (avoids need for fixtures)
  def given_a_site_exists
    Cms::Page.delete_all
    @root = root_section
    @homepage = create(:public_page, :name => "Home", :section => @root, :path => "/")
    @system_section = create(:public_section, :name => "System", :parent => @root, :path => "/system")
    @not_found_page = create(:public_page, :name => "Not Found", :section => @system_section, :path => Cms::ErrorPages::NOT_FOUND_PATH)
    @access_denied_page = create(:public_page, :name => "Access Denied", :section => @system_section, :path => Cms::ErrorPages::FORBIDDEN_PATH)
    @error_page = create(:public_page, :name => "Server Error", :section => @system_section, :path => Cms::ErrorPages::SERVER_ERROR_PATH)
  end
end

ActionDispatch::IntegrationTest.fixture_path = ActiveSupport::TestCase.fixture_path

module Cms::ControllerTestHelper
  def self.included(test_case)
    test_case.send(:include, Cms::PathHelper)
  end

  def request
    @request
  end

  def streaming_file_contents
    #The body of a streaming response is a proc
    streamer = @response.body

    #Create a dummy object for the proc to write to
    output = Object.new

    def output.write(contents)
      (@contents ||= "") << contents
    end

    #run the proc
    streamer.call(@response, output)

    #return what it wrote to the dummy object
    output.instance_variable_get("@contents")
  end
end

class ActionController::TestCase
  include Devise::Test::ControllerHelpers
end

# Defined here and included nowhere -- and login_as asserts 403 immediately
# after a successful login, so it could not have passed in years. Converted
# rather than deleted: this phase is a port, and "no tests were lost" is easier
# to defend if nothing was removed. Flagged for Phase 3's dead-code item.
#
# Note this call is NOT covered by the KeywordControllerArgs shim above: that
# prepends to ActionController::TestCase, and integration tests go through
# ActionDispatch::IntegrationTest#process, which has a different signature
# entirely. If this module is ever revived it will break on the 4.2 bundle.
module Cms::IntegrationTestHelper
  def login_as(user, password = "password")
    get login_url
    assert_response :success
    post login_url, params: {:login => user.login, :password => password}
    assert_response 403
    assert_equal "", @response.body, "Checking post login"
    assert flash[:notice]
  end

  def login_as_cms_admin
    login_as(Cms::User.first, "cmsadmin")
  end
end

def create_testing_table(name)
  ActiveRecord::Base.connection.instance_eval do
    drop_table(name) if table_exists?(name)
    create_table(name)
  end
end

# Monkey patch to fix ThreadError: already initialized in Rails 4.2 and Ruby 2.6
# https://github.com/rails/rails/issues/34790
if Gem::Version.new(RUBY_VERSION)>=Gem::Version.new('2.6.0')
  if Gem::Version.new(Rails.version) < Gem::Version.new('5.0.0')
    puts 'Patching ActionController::TestResponse to avoid MonitorMixin double-initialize error'
    class ActionController::TestResponse < ActionDispatch::TestResponse
      def recycle!
        # hack to avoid MonitorMixin double-initialize error:
        if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7.0')
          @mon_data = nil
          @mon_data_owner_object_id = nil
        else
          @mon_mutex = nil
          @mon_mutex_owner_object_id = nil
        end
        initialize
      end
    end
  else
    puts "Monkeypatch for ActionController::TestResponse no longer needed"
  end
end

# Rails 4.2's ActionController::TestCase#process has three positional slots and
# no keyword handling: `def process(action, http_method = 'GET', *args)` then
# `parameters, session, flash = args` (actionpack-4.2.11.3 test_case.rb:595).
# So `get :show, params: {id: 5}` arrives as params[:params][:id] and the
# controller never sees :id -- a silently wrong answer, not an error. Rails 5.0
# accepts both forms; 5.1 accepts only the keyword form. No single form works on
# both, so the call sites are written the 5.x way and translated back here, once,
# for the 4.2 bundle only. Delete this whole block in Phase 5.
if Gem::Version.new(Rails.version) < Gem::Version.new('5.0.0')
  module KeywordControllerArgs
    TRANSLATABLE = [:params, :session, :flash].freeze

    # 4.2 has no positional slot for any of these. Zero call sites use one today
    # (no xhr / xml_http_request / as: / format: anywhere in test/functional).
    # Raise rather than drop: a dropped keyword is a test that passes for the
    # wrong reason, which is the one failure mode this shim must not have.
    UNTRANSLATABLE = [:xhr, :as, :format, :body, :env, :headers].freeze

    def process(action, http_method = 'GET', *args)
      kwargs = args.first
      keyword_form = args.length == 1 && kwargs.is_a?(Hash) && kwargs.any? &&
        kwargs.keys.all? { |k| TRANSLATABLE.include?(k) || UNTRANSLATABLE.include?(k) }
      return super unless keyword_form

      unsupported = kwargs.keys & UNTRANSLATABLE
      unless unsupported.empty?
        raise ArgumentError, "Rails 4.2 cannot express #{unsupported.inspect} in a " \
                             "controller test. Rewrite the call, or extend the shim " \
                             "in test/test_helper.rb -- do not drop the keyword."
      end

      super(action, http_method, kwargs[:params], kwargs[:session], kwargs[:flash])
    end
  end

  ActionController::TestCase.prepend(KeywordControllerArgs)
  puts 'Translating keyword controller-test args back to Rails 4.2 positional form'
end

# Disable url encoding for Paperclip, it erroneously encodes the '?'
# between the path and the query string.
Paperclip::Attachment.default_options[:escape_url] = false
Paperclip::Attachment.default_options[:validate_media_type] = false
