# Dual-boot (next_rails). Gemfile.next is a *symlink* to this file, so both
# bundles evaluate the same Gemfile and this is the only thing that tells them
# apart. Note that browsercms.gemspec cannot call this -- Bundler evaluates the
# gemspec in a Gem::Specification context, so it keys off BUNDLE_GEMFILE instead.
def next?
  File.basename(__FILE__) == "Gemfile.next"
end

source 'http://rubygems.org'

ruby '2.7.8'

# Load this project as a gem.
gemspec
# gem 'query_reviewer' # Enable for performance tuning

gem 'puma', '~> 4'
gem 'railties', next? ? '~> 5.0.0' : '~> 4.2'
# Uncomment to confirm that older versions work (for compaitiblity with Spree 2.2.4/bcms_spree)
# gem 'paperclip', '~> 3.4.1'
# For testing behavior in production
group :production do
  gem 'uglifier'
end

group :development do
  gem 'rake'
  # Dual-boot tooling for the Rails upgrade: supplies `next_rails --init`
  # (Gemfile.next) and `bundle_report compatibility`. A maintainer tool, so it
  # belongs here and not in browsercms.gemspec.
  gem 'next_rails'
  # gem 'debugger'
  # gem 'quiet_assets'
end
group :test, :development do
  # Rails 5.0's Rails::TestUnitReporter (railties/lib/rails/test_unit/reporter.rb)
  # calls result.method, which predates Minitest::Result -- introduced in minitest
  # 5.11. On a newer minitest the reporter raises NameError while formatting the
  # *first* failure and takes the whole run down, so nothing is reportable.
  # Pinned for the next bundle only; revisit when the hop passes 5.1.
  if next?
    gem 'minitest', '~> 5.10.3'
  else
    gem 'minitest'
  end
  # minitest-rails removed: it capped railties ~> 4.1 and nothing used it --
  # every reference in test/minitest_helper.rb was already commented out. The
  # cheapest of the six Rails 5 blockers. (minitest_helper.rb itself stays; 19
  # test files require it.)
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
  gem 'simplecov', '~> 0.22.0', require: false

  gem 'm'

  gem 'single_test'
  # 4.2 has assert_template and assigns built in; 5.0 extracted them. The gem
  # cannot resolve on 4.2 (it needs actionpack >= 5.0.1.rc1), so this is one of
  # the few places a next? branch is not a smell -- it is the only expressible
  # form. Criterion 12 is about test *code*, not the Gemfile.
  gem 'rails-controller-testing' if next?
  gem 'factory_bot_rails', '~> 5.2'
  # 1.x, not 2.x: `mocha/minitest` exists from 1.5.0, so 1.x satisfies the Rails 5
  # requirement in full. Mocha 2.0 removes the legacy entry points *and* changes
  # any_instance and configuration behaviour across 109 call sites -- a
  # modernisation with no Rails deadline. See phase-2-implementation-plan.md D4.
  gem 'mocha', '~> 1.16', require: false

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
