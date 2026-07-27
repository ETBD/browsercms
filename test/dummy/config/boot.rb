# Loads the Gemfile from the root of the project itself, rather than a typical rails app.

require 'rubygems'
gemfile = File.expand_path('../../../../Gemfile', __FILE__)

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