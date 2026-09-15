require 'test_helper'

ActiveRecord::Base.connection.instance_eval do
  drop_table(:publishables) if table_exists?(:publishables)
  create_table(:publishables) do |t|
    t.string :name
    t.boolean :published, :default => false
  end
  drop_table(:unpublishables) if table_exists?(:unpublishables)
  create_table(:unpublishables) do |t|
    t.string :name
  end

  drop_table(:publishable_blocks) if table_exists?(:publishable_blocks)
  drop_table(:publishable_block_versions) if table_exists?(:publishable_block_versions)
  create_content_table(:publishable_blocks) do |t|
    t.string :name
  end
end

class Publishable < ActiveRecord::Base
  is_publishable
 #attr_accessible :name
end

class Unpublishable < ActiveRecord::Base
 #attr_accessible :name

end

class PublishableBlock < ActiveRecord::Base
  acts_as_content_block
 #attr_accessible :name
end

class PublishableBlockTestCase < ActiveSupport::TestCase

  def setup
    @object = PublishableBlock.create!(:name=>"v1", :publish_on_save=>true)
  end

  test "#live?" do
    assert @object.live?
  end

  test "#live? if there are draft versions" do
    @object.name = "New Name"
    @object.save_draft

    assert_equal false, @object.live?
    assert_equal :draft, @object.status
  end
end

class PublishableTestCase < ActiveSupport::TestCase

  def setup
    @object = Publishable.new(:name => "New Record")
  end

  def test_publishable
    assert @object.publishable?
  end

  def test_save
    assert @object.save
    assert !@object.published?
  end

  # This assertion was inverted in Phase 4, stage B.4. Read this before changing it
  # back.
  #
  # It used to read `assert !@object.reload.published?`, added in c6994b96 (2017,
  # "All tests working"). That was not the behaviour anyone intended -- it was the
  # observable result of a swallowed programming error:
  #
  #   publishing.rb:146 called `self.class.quote_value(id)` with one argument.
  #   On 4.2 quote_value is `quote_value(value, column)`, so it raised
  #   ArgumentError. `publish` (publishing.rb:101) rescues Exception, logs, and
  #   returns false -- so publishing a non-versioned record silently did nothing,
  #   and the test was changed to agree with it.
  #
  # Rails 5.0 dropped quote_value's second parameter, the call started working, the
  # record started publishing, and this test began failing on Gemfile.next. The call
  # site is fixed; both bundles now publish, and the assertion matches.
  #
  # Publishable is deliberately non-versioned -- that is the branch under test. No
  # model in the engine itself is publishable-but-not-versioned, so this test is the
  # only coverage that branch has.
  def test_publish_on_save
    @object.publish_on_save = true
    assert @object.save!
    assert @object.reload.published?,
           "publish_on_save should publish a non-versioned record. If this is false " +
           "again, check whether publishing.rb's `rescue Exception` is hiding a new " +
           "ArgumentError from the hand-built SQL in publish!."
  end

  def test_unpublishable
    @object = Unpublishable.new(:name => "New Record")
    assert !@object.publishable?
    assert @object.save!
    assert !@object.publishable?
  end

  def test_not_publishable_if_connect_to_page_id_is_blank
    assert Cms::HtmlBlock.new(:connect_to_page_id => "").publishable?
  end

end
