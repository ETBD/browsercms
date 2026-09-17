require File.dirname(__FILE__) + "/lib/cms/version.rb"

# Dual-boot support for the Rails upgrade (docs/rails-upgrade/).
#
# The Gemfile's `next?` helper is not in scope here: Bundler evaluates this file
# in a Gem::Specification context that has never heard of it. So key off
# BUNDLE_GEMFILE, which Bundler sets to .../Gemfile.next for the next bundle.
#
# This deliberately defaults to the 4.2 branch, so `gem build browsercms.gemspec`
# with no bundler environment produces exactly what it produced before the
# upgrade started. Once Rails 5.0 is actually supported (Phase 5), replace this
# with a plain version range and delete the conditional.
NEXT_BOOT = ENV["BUNDLE_GEMFILE"].to_s.end_with?("Gemfile.next")

Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = "browsercms"
  s.version = Cms::VERSION

  s.authors = ["BrowserMedia"]
  s.homepage = "http://www.browsercms.org"
  s.summary = %q{Web Content Management in Rails}
  s.description = %q{BrowserCMS is a general purpose, open source Web Content Management System (CMS) that supports Ruby on Rails v4.0. It can be used as a standalone CMS, added to existing Rails projects or extended using Rails Engines.}
  s.email = %q{github@browsermedia.com}
  s.extra_rdoc_files = %w{
      LICENSE.txt
      COPYRIGHT.txt
      GPL.txt
      README.markdown
  }
  s.required_ruby_version = '>= 2.3.0'

  s.files = Dir["{app,bin,db,doc,lib,vendor}/**/*"]
  s.files += Dir[".yardopts"]
  s.files += Dir["config/routes.rb"]
  s.files -= Dir["lib/tasks/**/*"]
  s.files += Dir["lib/tasks/cms.rake"]

  # Test files are not used and throwing 'Gem::Package::TooLongFileName' errors during packaging, so we are going to skip for now.
  #s.test_files = Dir["test/**/*"]
  #s.files -= Dir["test/dummy/*"]

  s.executables = ["bcms", "browsercms"]

  s.add_dependency("rails", NEXT_BOOT ? "~> 5.0.0" : "~> 4.2.0")
  s.add_dependency("devise", "~> 4.0")
  s.add_dependency("sass-rails")
  s.add_dependency("bootstrap-sass")
  s.add_dependency("compass-rails")
  s.add_dependency("ancestry", "~> 3.0.0")
  # 4.3.4 dispatches its Railtie on `case ::Rails.version` and has no Rails 5 branch, so
  # under 5.0 the gem defines no Rails::Engine at all, its lib/assets never joins the
  # asset load path, and `//= require ckeditor-jquery` (bcms/ckeditor.js:5) cannot
  # resolve -- which takes down every page rendering the CMS layout. Measured: 131 of 131
  # cucumber failures and 28 of 30 functional errors on Gemfile.next.
  #
  # 4.5.10 is the first release whose `when` clause reads /^[45]/ (verified against 4.4.8,
  # 4.5.1, 4.5.2 and 4.5.3, all of which still read /^4/), and it is the last before 4.16
  # replaces the default `moono` skin with `moono-lisa`. This gem's version IS CKEditor's
  # version, so this is an editor upgrade wearing a dependency bump's clothes -- and with
  # zero @javascript scenarios, no test here can see a WYSIWYG regression. The smallest
  # jump that loads is therefore the right one; widening both bundles to a modern editor
  # belongs with the 5.0 bump, not here. See docs/rails-upgrade/phase-3-implementation-plan.md D6.
  s.add_dependency("ckeditor_rails", NEXT_BOOT ? "~> 4.5.10" : "~> 4.3.0")
  s.add_dependency("underscore-rails", "~> 1.4")
  # jquery-rails 3.x caps railties < 5.0.
  s.add_dependency("jquery-rails", NEXT_BOOT ? "~> 4.0" : "~> 3.1")
  s.add_dependency("jquery-ui-rails", "~> 4.1")
  s.add_dependency("paperclip", "~> 5.0")
  s.add_dependency("panoramic")
  s.add_dependency("will_paginate", "3.3.1")
  s.add_dependency("actionpack-page_caching", "~>1.0")
  # simple_form 3.1 caps actionpack/activemodel ~> 4.0. The custom inputs under
  # app/inputs/ ride on its API, so expect real work here in Phase 2.
  s.add_dependency("simple_form", NEXT_BOOT ? "~> 3.5" : "~> 3.1.0")
  # Currently reaching us transitively through devise. Six sites depend on it directly --
  # respond_with at content_controller.rb:79 and page_components_controller.rb:14/:16, and
  # class-level respond_to at content_controller.rb:3, inline_content_controller.rb:3 and
  # page_components_controller.rb:4 -- and they should not depend on another gem's
  # dependency graph. Deliberately unconstrained: the two locks resolve 2.4.1 (4.2) and
  # 3.0.1 (5.0), responders 3.0 requires railties >= 5.0, so any constraint tight enough
  # to be useful would exclude one bundle.
  s.add_dependency("responders")
  s.add_dependency("bigdecimal")
  # Required only for bcms-upgrade
  s.add_dependency "term-ansicolor"
end
