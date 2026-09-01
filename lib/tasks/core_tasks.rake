    # Tasks for working with BrowserCMS that should not be packaged into the Gem
namespace :db do

  # This copy of the core CMS task is necessary because Engines push all existing Rails tasks under app:db:install
  desc 'Creates and populates the initial BrowserCMS database for a new project.'
  task :install => %w{ db:create db:migrate db:seed }

  desc 'Truncates database tables (without dropping like db:reset)'
  task :clean => :environment do
    require 'database_cleaner'
    DatabaseCleaner.clean_with(:truncation)
  end

  desc '[TEST] Creates sample products'
  task :many_products => :environment do
    (1..100).each do |i|
      Dummy::Product.create(name: "Product #{i}")
    end
  end

  namespace :yard do
    desc "Clean up the YARD api docs"
    task :clean do
      FileUtils.rm_rf "doc/api"
    end
  end
end

namespace :coverage do

  # Not SimpleCov's own `minimum_coverage`: that is enforced in *every* test
  # process's at_exit, so the units suite alone would fail the build for not
  # meeting a threshold set for the whole chain. coverage/.last_run.json is
  # written unconditionally, and the last suite to finish writes the fully
  # merged figure, so one check after the chain is both correct and enough.
  desc 'Fail if merged coverage fell below the recorded Phase 0 baseline'
  task :check do
    require 'json'
    # 78.35, not the 75.82 Phase 0 recorded: the simplecov 0.12 -> 0.22 bump
    # changed the instrument, not the tests. Measured across that bump on
    # identical code, the covered-line count was identical at 4901 and only the
    # denominator moved, 6460 -> 6255, because 0.18+ narrowed what counts as a
    # relevant line. See docs/rails-upgrade/phase-2-harness-report.md.
    threshold = Float(ENV.fetch('COVERAGE_MINIMUM', '78.35'))
    path = 'coverage/.last_run.json'
    abort "#{path} is missing -- did the suite run?" unless File.exist?(path)

    result = JSON.parse(File.read(path)).fetch('result')

    # simplecov < 0.18 wrote {"result": {"covered_percent": 75.82}}. From 0.18 that
    # key is gone and the shape is {"result": {"line": 75.82}}, plus "branch" once
    # enable_coverage :branch is on. Accept either, so the gate keeps working across
    # the bump -- and abort on neither, rather than comparing nil to a Float.
    actual = result['line'] || result['covered_percent']
    abort "#{path} has no line-coverage key (got #{result.keys.inspect})" if actual.nil?

    # Reported, not gated: there is no committed branch baseline, and inventing a
    # floor in the same commit that first measures the number would be gating on
    # something nobody has looked at. Phase 3 sets the floor.
    puts format('Branch coverage %.2f%%', result['branch']) if result['branch']
    if actual < threshold
      abort format('Coverage %.2f%% is below the %.2f%% baseline.', actual, threshold)
    end
    puts format('Coverage %.2f%% (baseline %.2f%%)', actual, threshold)
  end
end

# These are tasks for the core browsercms project, and shouldn't be bundled into the distributable gem
namespace :project do

  # Could be improved somewhat to get rid of unneeded warnings.
  #desc "run tests against sqlite database"
  #task :sqlite3 do
  #  cp(File.join('config', 'database.sqlite3.yml'), File.join('config', 'database.yml'), :verbose => true)
  #  Rake::Task['db:drop'].invoke
  #  Rake::Task['db:create'].invoke
  #  system "rake db:migrate test"
  #end
  #
  ## Could be improved somewhat to get rid of unneeded warnings.
  #desc "run tests against mysql database"
  #task :mysql do
  #  cp(File.join('config', 'database.mysql.yml'), File.join('config', 'database.yml'), :verbose => true)
  #  Rake::Task['db:drop'].invoke
  #  Rake::Task['db:create'].invoke
  #  system "rake db:migrate test"
  #end

  task :ensure_db_exists do
    unless File.exist?("test/dummy/config/database.yml")
      fail("Need to create a database.yml file before running tests. Run:\n $ rake project:setup[database] to create a sample database.yml for the project.")
    end
  end


  desc 'Copy database.yml files for running tests'
  task :setup, :database do |t, args|
    # drivers = %w(jdbcmysql mysql postgres sqlite3)
    # unless drivers.include?(args[:database])
      # fail("'#{args[:database]}' is not an available database. Choose from one of the following #{drivers.inspect}. i.e\n\t$ rake project:setup[mysql]")
    # end
#
    # source = File.join('test/dummy/config', "database.#{args[:database]}.yml")
    # destination = File.join('test/dummy/config', "database.yml")
    # cp(source, destination, :verbose => true)
  end

  namespace :setup do
    task :mysql do
      Rake::Task['project:setup'].invoke('mysql')
    end
  end
end
