# Just a spot check that a rails project was generated successfully.
# The exact files being check could be tuned better.
Then /^a rails application named "([^"]*)" should exist$/ do |app_name|
  self.project_name = app_name
  check_directory_presence [project_name], true
  expect_project_directories %w{ app config db }
  expect_project_files %w{bin/rails Gemfile }
end

Given /^a rails application named "([^"]*)" exists$/ do |name|
  create_rails_project(name)
  append_to_file "#{name}/db/seeds.rb", "# Some sample seed data here"
end

When /^I create a new BrowserCMS project named "([^"]*)"$/ do |name|
  self.project_name = name
  cmd = "bcms new #{project_name} --skip-bundle"
  run_simple(unescape(cmd), false)
end

When /^I create a module named "([^"]*)"$/ do |name|
  self.project_name = name
  cmd = "bcms module #{project_name} --skip-bundle"
  run_simple(unescape(cmd), false)
end

Then /^a rails engine named "([^"]*)" should exist$/ do |engine_name|
  check_directory_presence [engine_name], true
  expect_project_directories %w{ app config lib }
  expect_project_files ["bin/rails", "Gemfile", "#{engine_name}.gemspec"]
end

When /^BrowserCMS should be added the \.gemspec file$/ do
  expect_file_to_contain("#{project_name}/#{project_name}.gemspec", "s.add_dependency \"browsercms\", \"~> #{Cms::VERSION}\"")
end

Then /^BrowserCMS should be installed in the project$/ do
  assert_matching_output("BrowserCMS has been installed", all_output)
  # This is a not a really complete check but it at least verifies the generator completes.
  expect_file_to_contain('config/routes.rb', 'mount_browsercms')
  verify_seed_data_requires_browsercms_seeds
end

Then /^a demo project named "([^"]*)" should be created$/ do |project|
  check_directory_presence [project], true
  cd project
  expected_files = %W{
      public/themes/blue_steel/images/logo.jpg
      public/themes/blue_steel/images/splash.jpg
      public/themes/blue_steel/stylesheets/style.css
      lib/tasks/demo_site.rake
      db/demo_site_seeds.rb
  }
  check_file_presence expected_files, true
end

# Generating a project is the single most expensive thing these features do, so
# it happens once per run and every scenario gets a copy.
#
# This used to swap @dirs to point aruba at the scratch directory and generate
# there directly. Aruba 0.14 has no @dirs -- the swap did nothing, the scratch
# directory stayed empty, and the copy below then failed on a source that was
# never created. Generate into aruba's working directory (the only place aruba
# will run a command) and copy *out* to the cache instead; aruba wipes the
# working directory between scenarios, so the cached copy is what survives.
Given /^a BrowserCMS project named "([^"]*)" exists$/ do |project_name|
  cached = File.absolute_path(File.join(ARUBA_SCRATCH_DIR, project_name))

  unless File.exist?(cached)
    create_bcms_project(project_name)
    FileUtils.mkdir_p(File.dirname(cached))
    FileUtils.cp_r(expand_path(project_name), cached)
  end

  FileUtils.mkdir_p(expand_path('.'))
  FileUtils.cp_r(cached, expand_path(project_name))

  self.project_name = project_name
end

When /^I run `([^`]*)` in the project$/ do |cmd|
  cd(project_name)
  run_simple(unescape(cmd), false)
  cd("..")
end

Then /^a project file named "([^"]*)" should contain "([^"]*)"$/ do |file, partial_content|
  expect_file_to_contain(prefix_project_name_to(file), partial_content)
end

Then /^a project file named "([^"]*)" should not contain "([^"]*)"$/ do |file, partial_content|
  expect_file_not_to_contain(prefix_project_name_to(file), partial_content)
end

When /^I cd into the project "([^"]*)"$/ do |project|
  cd project
  self.project_name = project
end

When /^a migration named "([^"]*)" (#{SHOULD_OR_NOT}) contain:$/ do |file, should_or_not, partial_content|
  migration = find_migration_with_name(file)
  if should_or_not
    expect_file_to_contain(migration, partial_content)
  else
    expect_file_not_to_contain(migration, partial_content)
  end
end

# A table of string values to check
When /^a migration named "([^"]*)" should contain the following:$/ do |file, table|
  migration = find_migration_with_name(file)
  table.rows.each do |row|
    expect_file_to_contain(migration, row.first)
  end
end

Then /^it should seed the BrowserCMS database$/ do
  assert_matching_output "YOUR CMS username/password is: cmsadmin/cmsadmin", all_output
end

When /^it should seed the demo data$/ do
  assert_partial_output "Cms::PagePartial(:_header)", all_output
  # This output is ugly, but it verifies that seed data completely runs
end

Then /^the file "([^"]*)" should contain the following content:$/ do |file, table|
  table.rows.each do |row|
    expect_file_to_contain(file, row[0])
  end
end

# The negated form used to be missing from aruba, so it was defined here. Aruba
# 0.14 provides it -- `(?:a|the) file(?: named)? "..." should (not )?contain:` --
# and keeping this one made every use of it a Cucumber::Ambiguous abort, which
# took down the whole @cli run before a single result was reported.

When /^the correct version of Rails should be added to the Gemfile$/ do
  # Not a literal: `rails new` writes `gem 'rails', '4.2.11.3'` on 4.2 but
  # `gem 'rails', '~> 5.0.7', '>= 5.0.7.2'` on 5.0 -- app_base.rb's
  # #rails_version_specifier splits a four-segment version into a pair of
  # constraints. What the step means is "a rails entry naming the version this
  # bcms is running under", which is the same claim on both.
  expect_file_to_match(
    "#{project_name}/Gemfile",
    /^gem 'rails',.*#{Regexp.escape(Rails::VERSION::STRING)}/
  )
end

When /^BrowserCMS should be added the Gemfile$/ do
  # Single quotes: this line is written by Rails::Generators::Actions#gem, which
  # has emitted single-quoted names since Rails 4.
  expect_file_to_contain("#{project_name}/Gemfile", "gem 'browsercms'")
end

Then /^Gemfile should have the correct version of BrowserCMS$/ do
  expect_file_to_contain("Gemfile", %!gem "browsercms", "#{Cms::VERSION}"!)
end

When /^the production environment should be configured with reasonable defaults$/ do
  production_rb = "#{project_name}/config/environments/production.rb"
  expect_file_to_contain production_rb, "config.assets.compile = true"
  expect_file_to_contain production_rb, %!# config.cms.site_domain = "www.example.com"!
end

When /^it should comment out Rails in the Gemfile$/ do
  expect_file_to_contain("Gemfile", "# gem 'rails', '#{Rails::VERSION::STRING}'")
end

When /^it should run bundle install$/ do
  assert_partial_output "Your bundle is", all_output
end

When /^it should copy all the migrations into the project$/ do
  expected_outputs = [
      "rake  cms:install:migrations",
      "Copied migration",
      "browsercms300.cms.rb from cms",
      "browsercms400.cms.rb from cms",
  ]
  expected_outputs.each do |expect|
    assert_matching_output expect, all_output
  end
end

When /^it should add the seed data to the project$/ do
  check_file_presence ["db/browsercms.seeds.rb"], true
  verify_seed_data_requires_browsercms_seeds
end

When /^it should display instructions to the user$/ do
  expected = [
      "Next Steps:",
   ]
  expected.each do |expect|
    assert_partial_output expect, all_output
  end
end

Given /^the project has a "([^"]*)" block(| which hasn't ever been migrated)$/ do |block_name, been_migrated|
  # Generate a 3.3.x block and migration (Done here so as to EXACTLY preserve how block datastructure existed in this version)
  block_content = <<RUBY
  class #{block_name.capitalize} < ActiveRecord::Base
    acts_as_content_block
  end
RUBY
  write_file "app/models/#{block_name}.rb", block_content


  been_migrated_line = (been_migrated == "" ? "rename_column :#{block_name}_versions, :original_record_id, :#{block_name}_id" : "")
  content = <<RUBY
  class Create#{block_name.capitalize}s < ActiveRecord::Migration
    def change
      create_content_table :#{block_name}s do |t|
        t.timestamps
      end
      #{been_migrated_line}
    end
  end
RUBY
  write_file "db/migrate/001_create_#{block_name}s.rb", content
end

When /^the project has a "([^"]*)" model$/ do |model_name|
  run "rails g model #{model_name}"
end

Then /^the migration (#{SHOULD_OR_NOT}) update the version table for "([^"]*)" block$/ do |should, block|
  did_migration = %!rename_column("#{block}_versions", "#{block}_id", :original_record_id)!

  assert_partial_output "UpdateVersionIdColumns: migrated", all_output
  if should
    assert_partial_output did_migration, all_output
  else
    assert_no_partial_output did_migration, all_output
  end
end

Then /^it should display the current version of BrowserCMS$/ do
  assert_partial_output "BrowserCMS #{Cms::VERSION}", all_output
end

When /^rails script be configured to work with engines$/ do
  expect_file_to_contain "script/rails", "ENGINE_PATH = "
end

# Note: We skip running `rake rails:update` as part of these tests since it requires an interactive
# command as part a separate process to overwrite files, so its very hard to wait for the exact timing.
When /^I run the bcms update script$/ do
  run_simple('bcms upgrade --skip-rails --skip-bundle', false)
end

# This will be slower since bundler needs to run.
When /^I run the bcms update script with bundler$/ do
  run_simple('bcms upgrade --skip-rails', false)
end