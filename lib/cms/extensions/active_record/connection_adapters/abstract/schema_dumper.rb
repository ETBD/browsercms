require 'active_record'

# Rails 4.2 builds each column's schema spec by mutating the option strings in
# place with String#insert. Ruby 2.7 returns a *frozen* string from
# true.inspect/false.inspect, and a boolean column's default is rendered with
# exactly that call, so any table with a boolean default (every content table
# has published/deleted/archived) blew up with
# "can't modify frozen String: \"false\"" and was skipped by the dumper,
# leaving db/schema.rb missing half its tables.
#
# Build a new string instead of mutating the existing one.
#
# ---------------------------------------------------------------------------
# WHY THIS IS GUARDED (Phase 4, stage A -- docs/rails-upgrade/)
#
# The guard is on the *framework's implementation*, not on which bundle
# booted. Those happen to coincide today; they are different questions, so
# this deliberately does not use NextRails.
#
# Rails 5.0 fixed the underlying bug -- its column_spec already builds a new
# string -- and changed the signature while doing it:
#
#     4.2   def column_spec(column, types)   # arity 2
#     5.0   def column_spec(column)          # arity 1
#
# ColumnDumper was NOT removed at 5.0 (it is still included by
# abstract_adapter.rb:71), so applying this override there does not evaporate
# harmlessly -- it *wins*, replacing a 1-arity method with a 2-arity one.
# SchemaDumper then calls it with one argument, and because SchemaDumper#table
# rescues per-table exceptions into a comment, the dump SUCCEEDS while
# emitting nothing:
#
#     # Could not dump table "catalogs" because of following ArgumentError
#     #   wrong number of arguments (given 1, expected 2)
#
# Measured on this repo: 0 of 74 tables dumped on 5.0, 73 on 4.2, and the
# process exits 0 either way. A silently-empty db/schema.rb is the worst
# available outcome -- it corrupts every developer's database and every
# downstream CI run, and the commit looks clean in review.
#
# There is no `super` available as an alternative: reopening a module and
# redefining a method replaces the original outright, so a signature-tolerant
# version would have to carry a copy of Rails' own body and re-sync it every
# hop. Not applying the patch is the only option that cannot silently rot.
#
# When 4.2 support is dropped, delete this file rather than widening the
# guard. test/unit/schema_dumper_test.rb is what will tell you if you are
# wrong about any of the above.
# ---------------------------------------------------------------------------
if ActiveRecord::VERSION::MAJOR < 5
  module ActiveRecord
    module ConnectionAdapters
      module ColumnDumper

        def column_spec(column, types)
          spec = prepare_column_options(column, types)
          (spec.keys - [:name, :type]).each { |k| spec[k] = "#{k}: #{spec[k]}" }
          spec
        end

      end
    end
  end
end
