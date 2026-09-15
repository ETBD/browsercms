require 'test_helper'

# Phase 4, stage C -- work item 4.2 / Tier B B10.
# Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# One hour of work, and the cheapest defence available against the largest single
# item in the whole upgrade: Zeitwerk at Rails 6.0.
#
# WHY THIS EXISTS
#
# lib/cms/engine.rb:112-116 pushes nine paths onto
# ActiveSupport::Dependencies.autoload_paths -- an API Zeitwerk does not have at
# all. Zeitwerk replaces "search these directories for a missing constant" with a
# strict, eager mapping: a file at <root>/a/b_c.rb MUST define A::BC, or the
# application does not boot. Nothing in this repo checks that mapping today, so the
# 6.0 hop would discover every violation at once, at boot, with no inventory.
#
# These tests are that inventory.
#
# WHAT THE TEST ENVIRONMENT REQUIRES
#
# test/dummy/config/environments/test.rb sets `config.eager_load = false`, so
# eager loading has to be asked for explicitly. Flipping the config instead would
# slow every test in the suite and change what other tests exercise.
class EagerLoadTest < ActiveSupport::TestCase

  # ---------------------------------------------------------------------------
  # This test runs in the default suite. It did not always -- it was written in stage C
  # and held out until stage F, because `Rails.application.eager_load!` loads files no
  # suite otherwise touches and that changes what the coverage report measures:
  #
  #     branch numerator    unchanged     (nothing became less tested)
  #     branch denominator  +28 branches  (in 6 files nothing loads)
  #
  # The branch baseline was re-measured rather than worked around. The reasoning is in
  # lib/tasks/core_tasks.rake next to COVERAGE_MINIMUM_BRANCH, and in stage F of
  # docs/rails-upgrade/phase-4-implementation-plan.md.
  # ---------------------------------------------------------------------------

  # Files whose constant name does not match the path Zeitwerk will derive from it.
  # EVERY ENTRY HERE IS A 6.0 BOOT FAILURE. The list is the work item, not an
  # excuse for it -- it exists so that *new* violations fail immediately while the
  # known ones wait for the hop that owns them.
  #
  # Do not add to this list to make a test pass. Adding an entry means committing a
  # file that will stop the application booting on Rails 6.
  KNOWN_ZEITWERK_MISMATCHES = {
    # Root is app/portlets, so the path implies Helpers::Cms::ListPortletHelper.
    # The file actually defines a bare top-level `ListPortletHelper` -- it is
    # missing BOTH the Helpers:: segment and the Cms:: segment, and
    # `Cms::ListPortletHelper` does not resolve either.
    #
    # It works today because portlet helpers are resolved by Rails' helper lookup
    # at render time rather than by constant autoloading. Zeitwerk does not care
    # how it is reached; it validates the mapping at boot.
    #
    # Fix at 6.0 by one of: moving the file to app/helpers/cms/, renaming the
    # constant to match the path, or registering app/portlets/helpers as its own
    # autoload root the way engine.rb:116 already does for the host application.
    'Helpers::Cms::ListPortletHelper' => 'app/portlets/helpers/cms/list_portlet_helper.rb',
  }.freeze

  # Guards the guard. If eager_load_paths ever stops including the engine's own
  # app directories, the sweep below would check almost nothing and still pass.
  MINIMUM_FILES_SWEPT = 100

  def engine_roots
    Cms::Engine.instance.config.eager_load_paths
               .map(&:to_s)
               .reject { |p| p.end_with?('assets') }
  end

  def zeitwerk_expected_constant(root, file)
    file.sub("#{root}/", '').sub(/\.rb\z/, '').camelize
  end

  test "the application eager loads without raising" do
    assert_nothing_raised do
      Rails.application.eager_load!
    end
  end

  test "the engine contributes its app directories to eager loading" do
    roots = engine_roots
    %w[app/controllers app/models app/portlets app/helpers].each do |expected|
      assert roots.any? { |r| r.end_with?(expected) },
             "#{expected} is not in the engine's eager_load_paths, so nothing in it " +
             "is loaded at boot and the sweep below cannot see it. Roots: #{roots.inspect}"
    end
  end

  # The Zeitwerk contract, checked against the classic autoloader. This is the
  # whole point of the file: it catches a naming violation on the day it is
  # committed instead of at the 6.0 boot.
  test "every file in the engine's eager-load roots defines the constant its path implies" do
    Rails.application.eager_load!

    swept = 0
    mismatches = {}

    engine_roots.each do |root|
      Dir.glob(File.join(root, '**', '*.rb')).sort.each do |file|
        swept += 1
        expected = zeitwerk_expected_constant(root, file)
        begin
          expected.constantize
        rescue NameError, LoadError
          mismatches[expected] = file.sub("#{Rails.root}/../../", '')
        end
      end
    end

    assert swept >= MINIMUM_FILES_SWEPT,
           "only #{swept} files swept, expected at least #{MINIMUM_FILES_SWEPT} -- " +
           "the engine's eager_load_paths have changed and this test is no longer " +
           "checking what it claims to"

    unexpected = mismatches.keys - KNOWN_ZEITWERK_MISMATCHES.keys
    assert unexpected.empty?,
           "#{unexpected.size} file(s) define a constant that does not match their path. " +
           "Each one is a Rails 6.0 boot failure under Zeitwerk. Fix the name or the " +
           "location -- do not add it to KNOWN_ZEITWERK_MISMATCHES:\n  " +
           unexpected.map { |c| "#{c} <- #{mismatches[c]}" }.join("\n  ")

    fixed = KNOWN_ZEITWERK_MISMATCHES.keys - mismatches.keys
    assert fixed.empty?,
           "these are recorded as known Zeitwerk mismatches but now resolve correctly. " +
           "Remove them from KNOWN_ZEITWERK_MISMATCHES so the list stays honest about " +
           "how much 6.0 work is left: #{fixed.join(', ')}"
  end

  # The `Cms::` namespace is the engine's public surface. A constant that stops
  # resolving here breaks consuming applications, not just this suite.
  test "the engine's core Cms constants resolve after eager loading" do
    Rails.application.eager_load!

    %w[
      Cms::Page Cms::Section Cms::HtmlBlock Cms::Portlet Cms::User Cms::Group
      Cms::Attachment Cms::Category Cms::Connector Cms::SectionNode Cms::Task
      Cms::PageRoute Cms::ContentType Cms::Engine
    ].each do |name|
      assert_nothing_raised("#{name} should resolve after eager loading") do
        name.constantize
      end
    end
  end
end
