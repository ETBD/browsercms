require 'active_record'

module ActiveRecord
  module ConnectionAdapters
    module ColumnDumper

      # Rails 4.2 builds each column's schema spec by mutating the option
      # strings in place with String#insert. Ruby 2.7 returns a *frozen* string
      # from true.inspect/false.inspect, and a boolean column's default is
      # rendered with exactly that call, so any table with a boolean default
      # (every content table has published/deleted/archived) blew up with
      # "can't modify frozen String: \"false\"" and was skipped by the dumper,
      # leaving db/schema.rb missing half its tables.
      #
      # Build a new string instead of mutating the existing one.
      def column_spec(column, types)
        spec = prepare_column_options(column, types)
        (spec.keys - [:name, :type]).each { |k| spec[k] = "#{k}: #{spec[k]}" }
        spec
      end

    end
  end
end
