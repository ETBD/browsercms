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

  private

  def connection
    ActiveRecord::Base.connection
  end

  def assert_table_was_created(table_name)
    result = connection.execute("show tables like '#{table_name}'")
    assert_equal 1, result.count, "Ensure the table was crated. (Might fail when running unit tests with drivers other than mysql2)"
  end
end
