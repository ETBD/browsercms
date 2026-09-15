require 'test_helper'

# Phase 4, stage B.1 -- characterization of the after_save touch under optimistic
# locking. Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# THE SETUP
#
# `create_content_table` gives every versioned content table a `lock_version`
# column (schema_statements.rb:33), so optimistic locking is enabled on all of
# them, Cms::Page included. The versioning behavior registers
# `after_save :touch_self_and_ancestors` (versioning.rb:83), which touches the
# record after every save.
#
# Callers legitimately hold a parent loaded *before* a child update bumped that
# parent's lock_version in the database -- page_component.rb:31 and page.rb:256
# both do. So the after_save touch routinely runs against a record whose
# in-memory lock_version is behind.
#
# WHAT EACH RAILS DOES WITH THAT
#
#   4.2  touch scopes the UPDATE by id alone and increments from whatever value
#        it is holding. The write lands. No error. (persistence.rb:495-505)
#   5.0  touch adds the locking column to the WHERE and raises StaleObjectError
#        when it matches no rows. (persistence.rb:513-526)
#
# These tests pin the **4.2** behaviour -- they pass on the Gemfile bundle
# unchanged -- and are what makes the fix in `sync_locking_column_before_touch`
# checkable rather than asserted.
class VersioningLockingTest < ActiveSupport::TestCase

  def setup
    @page = create(:page, name: "Locking Test Page")
  end

  def db_lock_version(page)
    Cms::Page.connection
             .select_value("SELECT lock_version FROM cms_pages WHERE id = #{page.id}")
             .to_i
  end

  # Simulate what a child update does to the parent: bump the parent's
  # lock_version in the database without the in-memory object hearing about it.
  def bump_lock_version_behind_its_back(page)
    Cms::Page.connection.update(
      "UPDATE cms_pages SET lock_version = lock_version + 1 WHERE id = #{page.id}"
    )
  end

  test "optimistic locking is actually enabled on versioned content" do
    # If this ever goes false the rest of this file is asserting nothing, and the
    # 5.0 failure it characterizes could not have happened.
    assert @page.locking_enabled?,
           "Cms::Page has no lock_version, so the after_save touch cannot go stale"
  end

  test "saving a record whose lock_version moved underneath it does not raise" do
    before = db_lock_version(@page)
    bump_lock_version_behind_its_back(@page)
    assert_equal before, @page.lock_version,
                 "precondition: the in-memory object should still be holding the old value"
    assert_equal before + 1, db_lock_version(@page),
                 "precondition: the database should have moved on"

    @page.name = "Renamed While Stale"

    assert_nothing_raised do
      @page.save!
    end
  end

  test "the save still persists when the lock_version moved underneath it" do
    bump_lock_version_behind_its_back(@page)

    @page.name = "Renamed While Stale"
    @page.save!

    assert_equal "Renamed While Stale", Cms::Page.find(@page.id).draft.name
  end

  test "the in-memory lock_version is resynced rather than left behind" do
    bump_lock_version_behind_its_back(@page)
    stale = @page.lock_version

    @page.name = "Renamed While Stale"
    @page.save!

    refute_equal stale, @page.lock_version,
                 "the touch should have re-read the locking column before writing"
    assert_equal db_lock_version(@page), @page.lock_version,
                 "in-memory and database lock_version should agree after the save"
  end

  # The sync has to be a no-op for a model without a locking column -- the
  # behavior is mixed into content types generally, and only `create_content_table`
  # with `versioned` adds lock_version. Without the guard this would ask the
  # database for a column that is not there.
  test "the lock sync does nothing when the model has no locking column" do
    @page.stubs(:locking_enabled?).returns(false)

    assert_nothing_raised do
      @page.send(:sync_locking_column_before_touch)
    end
  end

  # The row can legitimately be gone by the time the after_save touch runs -- a
  # destroy in another connection, or a test tearing down around it. The sync must
  # leave the in-memory value alone rather than writing nil into it, and let the
  # touch that follows deal with the missing row.
  test "the lock sync leaves the attribute alone when the row has disappeared" do
    before = @page.lock_version
    Cms::Page.connection.execute("DELETE FROM cms_pages WHERE id = #{@page.id}")

    assert_nothing_raised do
      @page.send(:sync_locking_column_before_touch)
    end
    assert_equal before, @page.lock_version,
                 "a missing row should not overwrite the in-memory lock_version"
  end

  # ---------------------------------------------------------------------------
  # The defect this phase deliberately did NOT fix.
  #
  # A save against a genuinely stale record still wins silently -- a concurrent
  # editor's change is overwritten with no conflict raised. That has been true on
  # 4.2 since optimistic locking was added to these tables, and Rails 5 exposed it
  # rather than caused it.
  #
  # This test pins the CURRENT behaviour, not the desired one. If someone later
  # makes conflicts raise, this test is supposed to fail -- and its failure is the
  # signal to check every caller of a versioned #save, not to delete the test.
  # See D6 in the implementation plan.
  # ---------------------------------------------------------------------------
  test "CHARACTERIZATION: a stale save silently overwrites a concurrent edit" do
    other = Cms::Page.find(@page.id)
    other.name = "Saved By Someone Else"
    other.save!

    @page.name = "Saved By Us, Second, While Stale"

    assert_nothing_raised(
      "If this now raises, optimistic locking has started working. That is an " +
      "improvement, but it changes behaviour every caller of a versioned #save " +
      "depends on -- see D6 in docs/rails-upgrade/phase-4-implementation-plan.md " +
      "before updating this test."
    ) { @page.save! }

    assert_equal "Saved By Us, Second, While Stale",
                 Cms::Page.find(@page.id).draft.name,
                 "the second writer wins and the first edit is lost, silently"
  end
end
