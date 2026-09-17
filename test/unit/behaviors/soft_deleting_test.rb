require 'test_helper'

# Phase 4, stage H -- work item 4.7 / Tier B B8.
# Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# WHAT IS ALREADY COVERED, AND WHY THIS FILE IS NOT THAT
#
# soft_deleting.rb is not untested. test/unit/lib/content_block_test.rb already asserts
# that destroy marks rather than removes, that `find` raises for a deleted record, that
# dynamic finders skip it, that `count` excludes it and `with_deleted` includes it.
# Repeating those here would add lines and no defence.
#
# What none of them touch is the part of this behavior that is *not* ordinary
# ActiveRecord:
#
#   1. The default scope is installed inside a `begin/rescue StandardError` at
#      soft_deleting.rb:30-35. If that rescue ever fires, the scope is simply absent
#      and every deleted row becomes visible everywhere, with a debug-level log line
#      as the only evidence. Nothing asserts the scope is actually there.
#   2. `delete_all` is **overridden to not delete** (soft_deleting.rb:52), and the real
#      one is preserved as `delete_all!` by an alias taken three lines earlier. The
#      alias and the `extend ClassMethods` that shadows it are order-dependent.
#   3. `exists?` is overridden (soft_deleting.rb:56) with a **required** argument,
#      narrowing a Rails method whose argument is optional.
#   4. Scope composition. Every existing assertion is against a bare `Model.count` or
#      `Model.find`. A default scope that survives `.count` but is dropped by a
#      `where` chain would pass all of them.
#
# THE FAILURE MODE
#
# All four fail **open**: deleted content becomes visible, or a hard delete silently
# does not happen. Neither raises. Both are the kind of thing found by a customer.
#
# These pin 4.2 and pass on the Gemfile bundle unchanged.
module Cms
  class SoftDeletingTest < ActiveSupport::TestCase

    def setup
      @kept = Cms::HtmlBlock.create!(name: "Kept", content: "a")
      @dropped = Cms::HtmlBlock.create!(name: "Dropped", content: "b")
      @dropped.destroy
    end

    def scoped_ids(relation)
      relation.where(id: [@kept.id, @dropped.id]).pluck(:id).sort
    end

    def row_count(id)
      Cms::HtmlBlock.connection.select_value(
        "SELECT count(*) FROM #{Cms::HtmlBlock.quoted_table_name} WHERE id = #{id}"
      ).to_i
    end

    # -------------------------------------------------------------------------
    # 1. The default scope exists at all
    # -------------------------------------------------------------------------

    # soft_deleting.rb:30-35 swallows any StandardError raised while installing the
    # default scope, because it can run before the table exists. The cost is that a
    # failure for any *other* reason is indistinguishable from success. This is the
    # assertion that tells them apart, and it is the half of B8 that stage C's
    # eager-load test cannot reach.
    test "the default scope survived the startup rescue" do
      assert Cms::HtmlBlock.uses_soft_delete?, "precondition"
      refute_empty Cms::HtmlBlock.default_scopes,
                   "no default scope is installed. soft_deleting.rb:33 rescued a " +
                   "StandardError while setting it and logged at debug level, so the " +
                   "only symptom is deleted content appearing everywhere."
      assert_match(/deleted/, Cms::HtmlBlock.all.to_sql,
                   "the scope is registered but is not filtering on `deleted`")
    end

    # -------------------------------------------------------------------------
    # 2. Composition -- the gap the existing tests leave
    # -------------------------------------------------------------------------

    test "the default scope excludes deleted rows and unscoped brings them back" do
      assert_equal [@kept.id], scoped_ids(Cms::HtmlBlock)
      assert_equal [@kept.id, @dropped.id].sort, scoped_ids(Cms::HtmlBlock.unscoped)
      assert_equal [@kept.id, @dropped.id].sort, scoped_ids(Cms::HtmlBlock.with_deleted),
                   "with_deleted is just `unscoped` (soft_deleting.rb:49); if they ever " +
                   "diverge, one of the two call sites in the engine is wrong"
    end

    test "the default scope composes with a where chain in both directions" do
      both = [@kept.id, @dropped.id]

      assert_equal [@kept.id],
                   Cms::HtmlBlock.where(id: both).where(content: %w[a b]).pluck(:id),
                   "a chained where dropped the default scope"
      assert_equal [@kept.id],
                   Cms::HtmlBlock.where(content: %w[a b]).where(id: both).pluck(:id),
                   "order of chaining must not matter"
      assert_equal [@kept.id],
                   Cms::HtmlBlock.where(id: both).order(:id).limit(10).pluck(:id),
                   "order/limit must not drop it either"
    end

    test "not_deleted agrees with the default scope" do
      assert_equal [@kept.id], scoped_ids(Cms::HtmlBlock.not_deleted)
      assert_equal [@kept.id], scoped_ids(Cms::HtmlBlock.unscoped.not_deleted),
                   "not_deleted must stand on its own -- it is the only filter left " +
                   "once someone has called unscoped"
    end

    test "unscoped in block form reaches a deleted record" do
      found = Cms::HtmlBlock.unscoped { Cms::HtmlBlock.find(@dropped.id) }
      assert_equal @dropped.id, found.id
      assert found.deleted?
    end

    # -------------------------------------------------------------------------
    # 3. Destroy writes a flag, and the row is still there
    # -------------------------------------------------------------------------

    # Every existing assertion about this goes through ActiveRecord, which is the same
    # layer that would be wrong. This one asks the table directly.
    test "destroy leaves the row in the table with deleted set" do
      assert_equal 1, row_count(@dropped.id),
                   "the row is gone -- destroy hard-deleted instead of marking"
      assert Cms::HtmlBlock.unscoped.find(@dropped.id).deleted?
    end

    # -------------------------------------------------------------------------
    # 4. delete_all does not delete -- and delete_all! does
    # -------------------------------------------------------------------------

    # `Model.delete_all` is ordinary Rails API that here means the opposite of what it
    # says. content_block_test.rb#test_delete_all asserts the record stops being
    # findable; it does not assert the row survives, which is the surprising half.
    test "delete_all soft-deletes and leaves every row in place" do
      target = Cms::HtmlBlock.create!(name: "DeleteAllTarget", content: "c")

      Cms::HtmlBlock.delete_all(["id = ?", target.id])

      assert_equal 1, row_count(target.id),
                   "delete_all is overridden to UPDATE deleted = true " +
                   "(soft_deleting.rb:52-54). If the row is gone, the override has been " +
                   "lost and every caller expecting a soft delete is now destroying data."
      assert Cms::HtmlBlock.unscoped.find(target.id).deleted?
    end

    # The alias at soft_deleting.rb:22 is taken BEFORE `extend ClassMethods` on line 25,
    # so it captures ActiveRecord's real delete_all. Swap those two lines and
    # `delete_all!` silently becomes the soft version -- a hard delete that quietly
    # stops happening, with no error anywhere. This test is that ordering.
    test "delete_all! really deletes the row" do
      target = Cms::HtmlBlock.create!(name: "HardDeleteTarget", content: "d")
      assert_equal 1, row_count(target.id), "precondition"

      Cms::HtmlBlock.delete_all!("id = #{target.id}")

      assert_equal 0, row_count(target.id),
                   "delete_all! must reach ActiveRecord's delete_all. If this fails, " +
                   "check the alias/extend order at soft_deleting.rb:21-25."
    end

    # -------------------------------------------------------------------------
    # 5. exists?
    # -------------------------------------------------------------------------

    test "exists? respects the default scope" do
      assert_equal true, Cms::HtmlBlock.exists?(@kept.id)
      assert_equal false, Cms::HtmlBlock.exists?(@dropped.id),
                   "a soft-deleted record must not report as existing"
      assert_equal true, Cms::HtmlBlock.exists?(name: "Kept")
      assert_equal false, Cms::HtmlBlock.exists?(name: "Dropped")
    end

    # -------------------------------------------------------------------------
    # CHARACTERIZATION: the exists? override narrows a Rails signature.
    #
    # ActiveRecord declares `exists?(conditions = :none)` -- the argument is optional,
    # and `Model.exists?` meaning "are there any rows at all" is ordinary usage.
    # soft_deleting.rb:56 redefines it as `exists?(id_or_conditions)` with the argument
    # **required**, so on every soft-deleting model in the engine -- Cms::Page,
    # Cms::Portlet, Cms::Attachment, Cms::DynamicView and every content block --
    # `Model.exists?` raises ArgumentError.
    #
    # Identical on 4.2 and 5.0. NOT caused by the upgrade.
    #
    # Not currently reachable from engine code: `grep -rn "exists?" app/ lib/` finds no
    # no-argument call. The relation form (`Model.where(...).exists?`) is unaffected --
    # it reaches ActiveRecord's own method, not this one -- which is why `.any?` and
    # `.present?` still work and why nothing has tripped over it.
    #
    # NOT FIXED. Giving the parameter a default is a one-word change, but the override
    # also returns `query.count > 0` rather than ActiveRecord's LIMIT 1 EXISTS query,
    # so "fixing" the signature quietly commits the engine to a full count on a call
    # that Rails callers expect to be cheap. Deciding what `exists?` should do here is
    # a design question, not an upgrade one.
    #
    # This pins the current behaviour. When it is fixed this test fails -- rewrite it
    # against the repaired signature rather than restoring the required argument.
    # -------------------------------------------------------------------------
    test "CHARACTERIZATION: exists? with no arguments raises instead of answering" do
      assert_raises(ArgumentError) { Cms::HtmlBlock.exists? }

      assert_equal true, Cms::HtmlBlock.where(id: @kept.id).exists?,
                   "the relation form is untouched by the override, which is why this " +
                   "has never been noticed"
      assert_equal true, Cms::HtmlBlock.where(id: @kept.id).any?
    end
  end
end
