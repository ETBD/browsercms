require 'test_helper'

# Phase 4, stage H -- work item 4.7 / Tier B B7.
# Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# WHY THIS FILE EXISTS
#
# `publish!` (publishing.rb:118) is the one place in the engine that writes content
# state with hand-built SQL rather than through ActiveRecord. Two consequences:
#
#   1. Nothing about it is checked by Rails' own tests, and a Rails change to
#      quoting, `update_column`, or `unscoped` lands here silently.
#   2. `publish` (publishing.rb:101) wraps it in `rescue Exception => e; false`, so
#      when it breaks it does not raise -- it returns false and logs.
#
# Point 2 is not hypothetical. Stage B.4 found `publish!` calling
# `self.class.quote_value(id)` with one argument against 4.2's two-parameter
# `quote_value`. It raised ArgumentError on every call, `publish` swallowed it, and
# publishing a non-versioned record **silently did nothing for years**. The test that
# should have caught it had been edited to agree with the bug
# (publishable_test.rb#test_publish_on_save, now inverted back).
#
# So B7 asks for the one thing that would have caught it: assert what is **in the
# database** after publishing, read back through a fresh query rather than from the
# in-memory object. That distinction is the whole point here -- `publish!` sets
# `self.published = true` in memory at publishing.rb:169 **whatever the SQL did**, so
# an assertion on the object under test passes against a completely broken write.
#
# WHAT IS DELIBERATELY NOT ASSERTED
#
# The API shape. publishing.rb:161 still calls `connection.quote(value, column)`,
# whose two-argument form is deprecated at 5.0 and removed at 5.1 (Tier B, B7). These
# tests assert the row that comes out, not the call that produced it, so they survive
# that removal and will fail if -- and only if -- the fix for it is wrong.

# The engine has no publishable-but-not-versioned model, which is exactly why the
# branch at publishing.rb:142-166 went unexercised long enough for B.4 to hide in it.
# Downstream projects do define them. This is the only way to reach that branch.
#
# Defined at top level rather than under `Cms`, deliberately: namespaces_test.rb
# enumerates every constant in that namespace at load time and would adopt a test-only
# model as engine surface.
ActiveRecord::Base.connection.instance_eval do
  drop_table(:nonversioned_publishables) if table_exists?(:nonversioned_publishables)
  create_table(:nonversioned_publishables) do |t|
    t.string :name
    t.boolean :published, :default => false
  end
end

class NonversionedPublishable < ActiveRecord::Base
  self.table_name = 'nonversioned_publishables'
  is_publishable
end

class PublishingSqlTest < ActiveSupport::TestCase

  # Deliberately not `reload`, and deliberately not the model. This reads the column
  # straight out of the table, so no scope, no attribute cache and no in-memory
  # assignment can stand in for the write actually having happened.
  def column_in_db(klass, id, column)
    klass.connection.select_value(
      "SELECT #{column} FROM #{klass.quoted_table_name} WHERE id = #{id}"
    )
  end

  def published_in_db?(klass, id)
    value = column_in_db(klass, id, 'published')
    # 4.2's PG adapter hands back "t"/"f"; 5.0's hands back true/false. Both bundles
    # run this file, so normalise rather than assert on the adapter's typecasting.
    [true, 't', 'true', 1, '1'].include?(value)
  end

  # ---------------------------------------------------------------------------
  # The versioned branch (publishing.rb:125-141) -- every content type in the engine
  # ---------------------------------------------------------------------------

  test "publish! promotes the draft's values onto the live row in the database" do
    block = Cms::HtmlBlock.create!(name: "v1", content: "first", publish_on_save: true)

    draft = Cms::HtmlBlock.find(block.id)
    draft.name = "v2"
    draft.save_draft
    assert_equal "v1", column_in_db(Cms::HtmlBlock, block.id, 'name'),
                 "precondition: a draft must not have touched the live row"

    Cms::HtmlBlock.find(block.id).publish!

    assert_equal "v2", column_in_db(Cms::HtmlBlock, block.id, 'name'),
                 "publish! copies each versioned column from the draft onto the main " +
                 "record with update_column (publishing.rb:135-137). If this fails the " +
                 "draft was marked published without its content going live."
    assert published_in_db?(Cms::HtmlBlock, block.id)
  end

  test "publish! marks the draft version row published, not just the live row" do
    block = Cms::HtmlBlock.create!(name: "v1", content: "first", publish_on_save: false)
    refute published_in_db?(Cms::HtmlBlock, block.id), "precondition"

    Cms::HtmlBlock.find(block.id).publish!

    draft_row = Cms::HtmlBlock::Version.where(original_record_id: block.id)
                                       .order(:version).last
    assert draft_row.published?,
           "both halves are written -- the version row via `d.update` and the live " +
           "row via update_column. A fix that only does one leaves the two disagreeing."
  end

  # publishing.rb:97-98 documents this: "This will not create a new version, and will
  # not persist changes made to a record." Nothing asserted it.
  test "publish! creates no new version row" do
    block = Cms::HtmlBlock.create!(name: "v1", content: "first", publish_on_save: false)
    before = Cms::HtmlBlock::Version.where(original_record_id: block.id).count

    Cms::HtmlBlock.find(block.id).publish!

    assert_equal before, Cms::HtmlBlock::Version.where(original_record_id: block.id).count,
                 "publishing is a state change, not an edit. A new version row here " +
                 "means every publish inflates the history."
  end

  test "publish! returns false and writes nothing when there is nothing to publish" do
    block = Cms::HtmlBlock.create!(name: "v1", content: "first", publish_on_save: true)
    assert published_in_db?(Cms::HtmlBlock, block.id), "precondition: already live"
    before = column_in_db(Cms::HtmlBlock, block.id, 'updated_at')

    assert_equal false, Cms::HtmlBlock.find(block.id).publish!,
                 "the guard at publishing.rb:130 short-circuits an already-live record"
    assert_equal before, column_in_db(Cms::HtmlBlock, block.id, 'updated_at'),
                 "a no-op publish must not touch the row"
  end

  # ---------------------------------------------------------------------------
  # The non-versioned branch (publishing.rb:142-166) -- the hand-built UPDATE, and
  # the branch B.4's defect lived in
  # ---------------------------------------------------------------------------

  test "publish! flips published in the database for a non-versioned record" do
    record = NonversionedPublishable.create!(name: "A", publish_on_save: false)
    refute published_in_db?(NonversionedPublishable, record.id), "precondition"

    assert_equal true, NonversionedPublishable.find(record.id).publish!

    assert published_in_db?(NonversionedPublishable, record.id),
           "the hand-built UPDATE at publishing.rb:159-164 did not land. Check whether " +
           "`publish`'s `rescue Exception` is hiding an error from it -- that is " +
           "exactly how B.4 stayed hidden."
  end

  # The WHERE clause of that UPDATE is assembled by string interpolation. A record
  # published one row at a time is the normal case; a record that publishes the whole
  # table is the failure mode, and it would look identical from the published record.
  test "publish! on a non-versioned record touches only that row" do
    target = NonversionedPublishable.create!(name: "Target", publish_on_save: false)
    bystander = NonversionedPublishable.create!(name: "Bystander", publish_on_save: false)

    NonversionedPublishable.find(target.id).publish!

    assert published_in_db?(NonversionedPublishable, target.id)
    refute published_in_db?(NonversionedPublishable, bystander.id),
           "the interpolated WHERE published more than it was asked to"
  end

  # ---------------------------------------------------------------------------
  # CHARACTERIZATION: `publish` swallows everything, including programming errors.
  #
  # publishing.rb:101-106:
  #
  #     def publish
  #       publish!
  #     rescue Exception => e
  #       logger.warn(...)
  #       false
  #     end
  #
  # `rescue Exception` catches NoMethodError, ArgumentError, TypeError -- every bug
  # class as well as every legitimate failure. That is the mechanism, not a
  # contributing factor, by which B.4's ArgumentError survived years of green builds:
  # the call site is `publish_if_needed` -> `publish`, so nothing ever raised.
  #
  # NOT FIXED. Narrowing this to StandardError, or letting it raise, changes what
  # happens on every save of every content type in the engine, on 4.2 as much as 5.0.
  # That is a product decision about failure handling, not an upgrade one -- the same
  # line D6 drew.
  #
  # This pins the current behaviour so the next person who finds a swallowed bug can
  # see that the swallowing is known and deliberate rather than rediscovering it.
  # When it is narrowed, this test fails: that is the signal to rewrite it, not to
  # widen the rescue again.
  # ---------------------------------------------------------------------------
  test "CHARACTERIZATION: publish returns false instead of raising a programming error" do
    block = Cms::HtmlBlock.create!(name: "v1", content: "first", publish_on_save: false)
    block.stubs(:publish!).raises(NoMethodError, "undefined method `quote_value'")

    assert_equal false, block.publish,
                 "publish swallowed a NoMethodError and reported a normal failure. " +
                 "This is the shape of every bug this method has ever hidden."
    refute published_in_db?(Cms::HtmlBlock, block.id),
           "and nothing was published, with no error reaching the caller"
  end

  test "publish! on a new record warns and publishes nothing" do
    record = NonversionedPublishable.new(name: "Never Saved")

    assert_equal false, record.publish!
    refute record.persisted?,
           "publishing.rb:121's deprecation says this no longer saves the record"
  end
end
