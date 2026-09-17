# Loads the Gemfile from the root of the project itself, rather than a typical rails app.

require 'rubygems'

# Dual-boot: honour an explicitly-provided BUNDLE_GEMFILE (Gemfile.next) and
# only fall back to the engine's Gemfile when nothing was set.
#
# This used to assign ENV['BUNDLE_GEMFILE'] unconditionally, which quietly broke
# dual-booting the *test suite*. Rake::TestTask and cucumber each spawn a fresh
# Ruby process, and in a fresh process this file runs before Bundler is set up --
# so the hardcoded path won and every suite ran on 4.2 no matter what
# BUNDLE_GEMFILE said on the command line. It only looked like it worked from
# `bundle exec ruby -e ...`, where Bundler is already loaded by the time we get
# here. A Gemfile.next CI job on top of that would have reported a false green.
default_gemfile = File.expand_path('../../../../Gemfile', __FILE__)
gemfile = ENV['BUNDLE_GEMFILE'] ? File.expand_path(ENV['BUNDLE_GEMFILE']) : default_gemfile

if File.exist?(gemfile)
  ENV['BUNDLE_GEMFILE'] = gemfile
  require 'bundler'
  Bundler.setup
end

$:.unshift File.expand_path('../../../../lib', __FILE__)

# Rails 4.2's active_support/core_ext/object/duplicable.rb calls the removed
# BigDecimal.new at load time, before Bundler.require (and thus browsercms's
# own extensions) ever runs. Load the patch explicitly, ahead of `require
# 'rails/all'` in application.rb.
require 'cms/extensions/big_decimal'