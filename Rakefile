#!/usr/bin/env rake
begin
  require 'bundler/setup'
rescue LoadError
  puts 'You must `gem install bundler` and `bundle install` to run rake tasks'
end
begin
  require 'rdoc/task'
rescue LoadError
  require 'rdoc/rdoc'
  require 'rake/rdoctask'
  RDoc::Task = Rake::RDocTask
end

APP_RAKEFILE = File.expand_path("../test/dummy/Rakefile", __FILE__)
load 'rails/tasks/engine.rake'


Bundler::GemHelper.install_tasks

require 'rake/testtask'
require 'single_test/tasks'

# Each suite runs in its own process and merges into coverage/.resultset.json
# under a name SimpleCov otherwise *guesses*. Two suites that guess alike
# overwrite each other, so name them explicitly. Returns a task name suitable
# for use as a prerequisite; the test subprocess inherits the environment.
def coverage_suite(name)
  suite_task = "coverage:suite:#{name.downcase.tr(' ', '_')}"
  task(suite_task) { ENV['COVERAGE_SUITE'] = name }
  suite_task
end

Rake::TestTask.new('units' => coverage_suite('Unit Tests')) do |t|
  t.libs << 'lib'
  t.libs << 'test'
  t.pattern = 'test/unit/**/*_test.rb'
  t.verbose = false
  t.warning = false
end

Rake::TestTask.new('spec' => coverage_suite('RSpec')) do |t|
  t.libs << 'lib'
  t.libs << 'spec'
  t.pattern = 'spec/**/*_spec.rb'
  t.warning = false
end

Rake::TestTask.new('test:functionals' => ['project:ensure_db_exists', 'app:test:prepare', coverage_suite('Functional Tests')]) do |t|
  t.libs << 'lib'
  t.libs << 'test'
  t.pattern = 'test/functional/**/*_test.rb'
  t.verbose = false
  t.warning = false
end

# test/*_test.rb, test/helpers/** and the dummy app's own tests under
# test/dummy/test/** are matched by none of the patterns above, so until this
# task existed they were in the repo but never run. `rake app:test` looks like
# the answer and is not -- it exits 0 having run nothing, because Rails 4.2
# hands it the literal top-level task name ("app:test") and matches no sub-task.
Rake::TestTask.new('test:orphans' => ['project:ensure_db_exists', 'app:test:prepare', coverage_suite('Orphan Tests')]) do |t|
  t.libs << 'lib'
  t.libs << 'test' # so the dummy app's `require "test_helper"` finds the engine's
  t.test_files = FileList[
      'test/*_test.rb',
      'test/helpers/**/*_test.rb',
      'test/dummy/test/**/*_test.rb'
  ]
  t.verbose = false
  t.warning = false
end

require 'cucumber'
require 'cucumber/rake/task'

Cucumber::Rake::Task.new({:features => coverage_suite('Cucumber Features')}, "Run all (fast) scenarios without known bugs or missing features") do |t|
  t.cucumber_opts = "launch_on_failure=false features --format progress --tags ~@cli -t ~@missing-feature -t ~@known-bug"
end

Cucumber::Rake::Task.new({'features:all' => coverage_suite('Cucumber Features (all)')}, 'Runs all scenarios (including slow/missing/etc') do |t|
  t.cucumber_opts = "launch_on_failure=false features --format progress"
end

# @cli scenarios shell out through aruba, so their coverage is collected in a
# child process SimpleCov cannot see. Named anyway, so the entry is distinct
# rather than overwriting the in-process cucumber result with an empty one.
Cucumber::Rake::Task.new('features:cli' => ['project:ensure_db_exists', 'app:test:prepare', coverage_suite('Cucumber CLI Features')]) do |t|
  t.cucumber_opts = "features --format progress --tags @cli"
end

Cucumber::Rake::Task.new('features:wip', 'Run all (fast) scenarios without known bugs/features.') do |t|
  t.cucumber_opts = "features --format progress --tags ~@cli -t ~@known-bug -t ~@missing-feature"
end

Cucumber::Rake::Task.new('features:wip:all', 'Run all scenarios (including slow) without known bugs/missing features.') do |t|
  t.cucumber_opts = "features --format progress -t ~@known-bug -t ~@missing-feature"
end

Cucumber::Rake::Task.new('features:known-bugs', 'Run all scenarios with known bugs.') do |t|
  t.cucumber_opts = "features --format progress -t @known-bug"
end

#Rake::Task['features:wip'].enhance ['project:ensure_db_exists', 'app:test:prepare']

desc "Run everything but the command line (slow) tests"
task 'test:fast' => %w{app:test:prepare test:units test:functionals features}

desc "Runs all unit level tests"
task 'test:units' => ['app:test:prepare'] do
  run_tests ["units", "spec"]
end

desc 'Runs all the tests, specs and scenarios.'
task :test => ['project:ensure_db_exists', 'app:test:prepare'] do
  tests_to_run =  %w(test:units spec test:functionals test:orphans features)
  run_tests(tests_to_run)
end

def run_tests(tests_to_run)
  errors = tests_to_run.collect do |task|
    begin
      Rake::Task[task].invoke
      nil
    rescue => e
      {:task => task, :exception => e}
    end
  end.compact

  if errors.any?
    errors.each { |e| $stderr.puts "FAILED: #{e[:task]} -- #{e[:exception].message}" }
    raise "Test failures in: #{errors.collect { |e| e[:task] }.join(', ')}"
  end
end

# Build and run against Postgres.
task 'ci:test' => ['db:drop', 'db:create:all', 'db:install', 'test']

# Checked once, after the chain, rather than through SimpleCov's own
# minimum_coverage -- that is enforced in every test process's at_exit, so the
# first suite would fail the build for not meeting the whole chain's threshold
# on its own. `test` raises on failure, so a red suite short-circuits this,
# which is the right order: coverage from a failing run means nothing.
Rake::Task['ci:test'].enhance { Rake::Task['coverage:check'].invoke }

task :default => 'ci:test'

require 'yard'
YARD::Rake::YardocTask.new do |t|
  t.options = ['--output-dir', 'doc/api/']
end

# Load all tasks files
#Dir.glob('lib/tasks/*.rake').each { |r| import r }

# Load just this one task file instead (the previous rake files can probably be simplified)
import 'lib/tasks/core_tasks.rake'

begin
  require 'cucumber/rake/task'
  namespace :cucumber do
    Cucumber::Rake::Task.new({:launch => 'db:test:prepare'}, 'Run features opening failures in the browser') do |t|
      t.fork = true # You may get faster startup if you set this to false
      t.profile = 'default'
      t.cucumber_opts = ["-f", "Debug::Formatter"]
    end
  end
end
