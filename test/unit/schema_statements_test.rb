require 'test_helper'

class SchemaStatementsTest < ActiveSupport::TestCase
  # Clean up tables prior to each test. Someday, we'll get DatabaseCleaner
  # going in here.
  def setup
    %w(fake_contents explicit_column_blocks non_versioned_blocks possibly_versioned_blocks non_existant_blocks).each do |t|
      connection.drop_content_table(t)
    end

  end

  test "Removed ability to explicitly set :version_foreign_key in bcms 3.4. Should silently do nothing" do
    class ::Cms::ExplictColumnBlock < ActiveRecord::Base
      acts_as_content_block :versioned=>{:version_foreign_key => :something_id }
    end
    connection.create_content_table :explicit_column_blocks do |t| ; end

    assert_column_exists :explicit_column_block_versions, :original_record_id
    assert_column_does_not_exist :explicit_column_block_versions, :something_id
  end

  test "Nonversioned blocks shouldn't create versions table" do

    class ::Cms::NonVersionedBlock < ActiveRecord::Base
      acts_as_content_block :versioned=>false
    end
    connection.create_content_table :non_versioned_blocks, :versioned=>false do |t| ; end

    assert_equal false, ActiveRecord::Base.connection.table_exists?(:non_versioned_block_versions)
  end


  test "Create default versioned column, even if the record isn't marked versions (handles subclasses)" do
    class ::Cms::PossiblyVersionedBlock < ActiveRecord::Base
    end
    connection.create_content_table :possibly_versioned_blocks do |t| ; end

    assert_column_exists :possibly_versioned_block_versions, :original_record_id
  end

  test "non-existant models should create default versions table." do
    connection.create_content_table :non_existant_blocks do |t| ; end

    assert_column_exists :non_existant_block_versions, :original_record_id
  end

  test "create_content_table should make two tables" do
    connection.create_content_table :fake_contents do |t|
      t.string :name
    end

    expected_columns = %w(archived created_at created_by_id deleted id lock_version name published updated_at updated_by_id version)
    expected_columns_v = %w(archived created_at created_by_id deleted id name original_record_id published updated_at updated_by_id version version_comment)
    assert_equal expected_columns, connection.columns(:fake_contents).map { |c| c.name }.sort
    assert_equal expected_columns_v, connection.columns(:fake_content_versions).map { |c| c.name }.sort
  end

  test "add_content_column should add columns to both primary and versions table" do
    connection.create_content_table :fake_contents do |t|; end
    connection.add_content_column :fake_contents, :foo, :string

    found_c = connection.columns(:fake_contents).map { |c| c.name }
    assert found_c.include?("foo")

    found_c = connection.columns(:fake_content_versions).map { |c| c.name }
    assert found_c.include?("foo")
  end

  # ---------------------------------------------------------------------------
  # Phase 4, stage E -- work item 4.3 / Tier B B3, criterion 6.
  # Docs: docs/rails-upgrade/phase-4-implementation-plan.md
  #
  # `create_content_table` is the migration DSL every BrowserCMS project depends on,
  # and it is the largest blast radius in the codebase: every migration in this
  # engine and in every downstream project runs through it. Internally it calls
  # create_table, change_table and column_exists?, all of which have shifted
  # signatures and keyword-argument requirements across six majors.
  #
  # Unlike most Tier B items this one fails LOUDLY -- but it fails at *migration*
  # time, which in practice means in someone's deploy rather than in CI. These
  # tests move that failure to here.
  #
  # The DSL takes exactly two options, both defaulting to true, so the matrix is
  # 2x2 and is enumerated in full below. Each case asserts the COMPLETE column set
  # on both tables rather than the presence of one column, because the failure mode
  # worth catching is a column quietly appearing or disappearing.
  # ---------------------------------------------------------------------------

  # Always present on a content table, whatever the options.
  BASE_COLUMNS = %w(archived created_at created_by_id deleted id published updated_at updated_by_id).freeze
  # Added to the content table only when versioned.
  VERSIONING_COLUMNS = %w(lock_version version).freeze
  # Always present on a _versions table.
  VERSION_TABLE_COLUMNS = (BASE_COLUMNS + %w(original_record_id version version_comment)).freeze

  def columns_for(table)
    connection.columns(table).map(&:name).sort
  end

  test "matrix: versioned and named (the default)" do
    connection.create_content_table :possibly_versioned_blocks

    assert_equal (BASE_COLUMNS + VERSIONING_COLUMNS + %w(name)).sort,
                 columns_for(:possibly_versioned_blocks)
    assert_equal (VERSION_TABLE_COLUMNS + %w(name)).sort,
                 columns_for(:possibly_versioned_block_versions)
  end

  test "matrix: versioned and unnamed" do
    connection.create_content_table :possibly_versioned_blocks, name: false

    assert_equal (BASE_COLUMNS + VERSIONING_COLUMNS).sort,
                 columns_for(:possibly_versioned_blocks)
    assert_equal VERSION_TABLE_COLUMNS.sort,
                 columns_for(:possibly_versioned_block_versions)
  end

  test "matrix: non-versioned and named" do
    connection.create_content_table :non_versioned_blocks, versioned: false

    assert_equal (BASE_COLUMNS + %w(name)).sort, columns_for(:non_versioned_blocks)
    refute connection.table_exists?(:non_versioned_block_versions),
           "versioned: false must not create a _versions table"
  end

  test "matrix: non-versioned and unnamed" do
    connection.create_content_table :non_versioned_blocks, versioned: false, name: false

    assert_equal BASE_COLUMNS.sort, columns_for(:non_versioned_blocks)
    refute connection.table_exists?(:non_versioned_block_versions),
           "versioned: false must not create a _versions table"
  end

  # Two asymmetries between the pair of tables that are easy to break and easy to
  # miss, because both tables carry most of the same columns.
  test "lock_version is on the content table only, version_comment on the versions table only" do
    connection.create_content_table :possibly_versioned_blocks

    assert_column_exists :possibly_versioned_blocks, :lock_version
    assert_column_does_not_exist :possibly_versioned_block_versions, :lock_version

    assert_column_exists :possibly_versioned_block_versions, :version_comment
    assert_column_does_not_exist :possibly_versioned_blocks, :version_comment
  end

  # The block is applied to BOTH tables -- a versioned content type has to carry its
  # own columns in its history as well as its current row, or version_comparisons
  # and reverts silently lose data.
  test "the caller's block is applied to the content table and the versions table" do
    connection.create_content_table :possibly_versioned_blocks do |t|
      t.string :headline
      t.text :body
    end

    %w(headline body).each do |column|
      assert_column_exists :possibly_versioned_blocks, column
      assert_column_exists :possibly_versioned_block_versions, column
    end
  end

  # Anything not consumed as :versioned or :name is forwarded to create_table. This
  # is the line B3 flags -- `create_table table_name, options` is positional today
  # and becomes an ArgumentError if options ever turn into keyword arguments. The
  # assertion is on the resulting table rather than on the call, so it survives
  # whichever way Rails spells it.
  test "unrecognised options are forwarded to create_table" do
    connection.create_content_table :non_versioned_blocks, versioned: false, id: false do |t|
      t.integer :owner_id
    end

    assert_column_does_not_exist :non_versioned_blocks, :id
    assert_column_exists :non_versioned_blocks, :owner_id
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  def assert_table_was_created(table_name)
    result = connection.execute("show tables like '#{table_name}'")
    assert_equal 1, result.count, "Ensure the table was crated. (Might fail when running unit tests with drivers other than mysql2)"
  end
end
