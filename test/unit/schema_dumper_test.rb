require 'test_helper'
require 'stringio'

# Phase 4, stage A -- the net under lib/cms/extensions/.../abstract/schema_dumper.rb.
#
# WHAT WENT WRONG, AND WHY NOTHING CAUGHT IT
#
# That file patches ActiveRecord::ConnectionAdapters::ColumnDumper#column_spec to
# work around a Ruby 2.7 frozen-string crash in Rails 4.2. The analysis behind it
# (RAILS_UPGRADE_TEST_PRIORITY.md B1) predicted the patch would silently *evaporate*
# at some later Rails, on the theory that ColumnDumper had been folded into
# SchemaDumper and the `module` keyword would define a fresh empty module.
#
# That is not what happens. ColumnDumper still exists at 5.0 and is still included
# by abstract_adapter.rb, so the override lands -- and 5.0 changed the signature:
#
#     4.2   def column_spec(column, types)   # arity 2
#     5.0   def column_spec(column)          # arity 1
#
# So on 5.0 the patch replaced a 1-arity method with a 2-arity one, and
# SchemaDumper called it with one argument. The damage is invisible from the
# outside because SchemaDumper#table wraps each table in a rescue and writes the
# exception into the stream AS A COMMENT:
#
#     # Could not dump table "catalogs" because of following ArgumentError
#     #   wrong number of arguments (given 1, expected 2)
#
# Measured before the fix: 0 of 74 tables dumped on 5.0, 73 on 4.2, exit 0 on both.
#
# WHY THESE TESTS ARE SHAPED THE WAY THEY ARE
#
# Three test shapes that look sufficient and are not, all of which PASS against the
# broken dumper:
#
#   * "the dump does not raise"     -- it doesn't. The rescue swallows it.
#   * "the output is not empty"     -- it isn't. 234 lines of header and comments.
#   * "ColumnDumper is defined"     -- it is. That was never the failure mode.
#
# The assertions therefore have to be on dumped CONTENT. Everything below runs on
# both bundles and describes the contract rather than either version's internals.
class SchemaDumperTest < ActiveSupport::TestCase

  # Rails ignores its own bookkeeping tables, and which ones exist differs by
  # version (ar_internal_metadata arrives at 5.0), so this is not asserted as an
  # exact count against connection.tables.
  IGNORED_BY_THE_DUMPER = %w[schema_migrations ar_internal_metadata].freeze

  # A content table with all three boolean flags. Every acts_as_content_block
  # table has these; this one is core and is not created dynamically by a test.
  CONTENT_TABLE = 'cms_html_blocks'.freeze

  def dump
    @dump ||= begin
      io = StringIO.new
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, io)
      io.string
    end
  end

  def dumped_tables
    dump.scan(/create_table "([^"]+)"/).flatten
  end

  # --- A.3: the dump is complete ------------------------------------------

  test "every table in the database appears in the dump" do
    expected = ActiveRecord::Base.connection.tables - IGNORED_BY_THE_DUMPER
    missing = expected - dumped_tables

    assert missing.empty?,
           "#{missing.size} of #{expected.size} tables are missing from the dump. " +
           "A dump that silently drops tables is the B1 failure mode -- check " +
           "whether the column_spec override is being applied to a Rails that " +
           "does not want it. Missing: #{missing.first(10).join(', ')}"
  end

  test "no table is reported as undumpable" do
    failures = dump.scan(/# Could not dump table "([^"]+)" because of following (\w+)/)

    assert failures.empty?,
           "SchemaDumper rescued #{failures.size} per-table errors and wrote them " +
           "into the schema as comments, so the dump 'succeeded' while losing " +
           "those tables: " +
           failures.first(3).map { |t, e| "#{t} (#{e})" }.join(', ')
  end

  # The original bug: boolean defaults were rendered with true/false.inspect,
  # which Ruby 2.7 froze, and the 4.2 dumper mutated in place. Tables carrying
  # them were the ones that vanished, so they are the specific thing to assert.
  test "boolean columns keep their defaults through the dump" do
    block = dump[/create_table "#{CONTENT_TABLE}".*?\n  end/m]
    assert block, "#{CONTENT_TABLE} was not dumped at all"

    %w[published deleted archived].each do |flag|
      assert_match(/t\.boolean\s+"#{flag}",\s+default: false/, block,
                   "#{CONTENT_TABLE}.#{flag} lost its `default: false` in the dump")
    end
  end

  test "the dump is loadable Ruby, not a file of comments" do
    # Guards the shape of the failure rather than its cause: the broken dump was
    # syntactically valid and would have been committed without complaint.
    assert dumped_tables.size > 50,
           "only #{dumped_tables.size} create_table statements in a #{dump.lines.size}-line " +
           "dump -- that ratio is what a rescued-into-comments failure looks like"
  end

  # --- A.4: the guard ------------------------------------------------------

  # This is the assertion that would have caught the original defect, and the one
  # that will catch it again at 5.1, 6.0 or wherever column_spec next moves.
  #
  # The contract is: the method SchemaDumper will call must accept the number of
  # arguments SchemaDumper passes. Asserting the constant exists does not express
  # that -- ColumnDumper existed throughout.
  test "column_spec accepts the arity the running Rails calls it with" do
    expected = ActiveRecord::VERSION::MAJOR < 5 ? 2 : 1
    actual = ActiveRecord::Base.connection.method(:column_spec).arity

    assert_equal expected, actual,
                 "SchemaDumper on Rails #{ActiveRecord::VERSION::STRING} calls " +
                 "column_spec with #{expected} argument(s), but the method resolves " +
                 "to arity #{actual}. Every table will fail to dump, and the dump " +
                 "will still exit successfully."
  end

  test "the column_spec override applies on 4.2 and only on 4.2" do
    source = ActiveRecord::Base.connection.method(:column_spec).source_location.first
    patched = source.include?('cms/extensions')

    if ActiveRecord::VERSION::MAJOR < 5
      assert patched,
             "the 4.2 frozen-string workaround is not in effect (column_spec came " +
             "from #{source}). Boolean-default tables will be dropped from db/schema.rb."
    else
      refute patched,
             "the 4.2 workaround is being applied to Rails " +
             "#{ActiveRecord::VERSION::STRING}, which fixed the underlying bug and " +
             "changed column_spec's signature. Narrow the guard in " +
             "lib/cms/extensions/active_record/connection_adapters/abstract/schema_dumper.rb."
    end
  end
end
