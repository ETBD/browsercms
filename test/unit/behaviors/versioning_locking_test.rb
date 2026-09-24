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

  # ===========================================================================
  # CMS-435 -- the defect Phase 4 left open, now closed.
  #
  # This section replaces the characterization test that used to sit here, which
  # pinned the *defect*: two people edit one page, the second save wins, the first
  # person's edit is gone, nothing raised and nothing logged. That test's own
  # failure message said its failure was the signal to survey every caller of a
  # versioned #save and decide what the user sees. That survey is in
  # docs/rails-upgrade/cms-435-optimistic-locking.md; this is the outcome.
  #
  # Three things had to be true at once, and none of them was:
  #
  #  1. THE CHECK NEVER RAN. ActiveRecord checks the locking column in
  #     `_update_record`, by adding it to the WHERE of an UPDATE against the
  #     content row. `create_or_update` (versioning.rb) does not issue one -- an
  #     update INSERTs a row into the _versions table instead. So the content
  #     row's lock_version was never in any WHERE clause, and two editors' writes
  #     could not collide. `check_for_stale_lock_version!` is the check, run
  #     before the version row is built.
  #
  #  2. THERE WAS NOTHING TO CHECK AGAINST. Both edit screens load their record
  #     through `build_object_from_version` (`load_draft_page`,
  #     `load_block_draft`), and the _versions table has no lock_version column
  #     for it to copy -- schema_statements_test.rb:141 asserts that. So the
  #     object carried the column default, 0, whatever the content row said, and
  #     the form's hidden field posted back a value that identified nothing.
  #     Measured before the fix: content row at 4, form rendered value="0".
  #
  #  3. A RAISE WOULD HAVE BROKEN INTERNAL CALLERS. `PageComponent#save` -- the
  #     Mercury inline editor -- loads a page, updates each block on it, then
  #     saves the page. Each block update copies the page's connectors forward and
  #     bumps the page, so the page is *always* behind by the time it is saved.
  #     Measured: in-memory 3, database 4, with no second editor involved. An
  #     unconditional check makes every inline edit a false conflict.
  #
  # (3) is why the check is gated on the caller having supplied a lock_version,
  # which is what a form round-trip does and what internal code never does.
  # ===========================================================================

  # The inverse of the deleted characterization test, asserting the fix rather
  # than the defect. If this ever goes back to passing silently, the data loss is
  # back.
  test "a stale save raises rather than silently overwriting a concurrent edit" do
    editor_a = Cms::Page.find(@page.id).as_of_draft_version
    editor_b = Cms::Page.find(@page.id).as_of_draft_version

    editor_b.name = "Saved By Someone Else"
    editor_b.lock_version = editor_b.lock_version # what the form posts back
    editor_b.save!

    editor_a.name = "Saved By Us, Second, While Stale"
    editor_a.lock_version = editor_a.lock_version # a value that is now stale

    assert_raises(ActiveRecord::StaleObjectError) { editor_a.save! }
  end

  test "the first editor's content survives the conflicting second save" do
    editor_a = Cms::Page.find(@page.id).as_of_draft_version
    editor_b = Cms::Page.find(@page.id).as_of_draft_version

    editor_b.name = "Saved By Someone Else"
    editor_b.lock_version = editor_b.lock_version
    editor_b.save!

    editor_a.name = "Saved By Us, Second, While Stale"
    editor_a.lock_version = editor_a.lock_version
    assert_raises(ActiveRecord::StaleObjectError) { editor_a.save! }

    assert_equal "Saved By Someone Else", Cms::Page.find(@page.id).draft.name,
                 "the losing save must not have overwritten the winner"
  end

  # A conflict must leave nothing behind. The check runs before the version row is
  # built, so a rejected save must not add to the _versions table.
  test "a rejected save writes no version row" do
    editor_a = Cms::Page.find(@page.id).as_of_draft_version
    before = Cms::Page::Version.where(original_record_id: @page.id).count

    other = Cms::Page.find(@page.id).as_of_draft_version
    other.name = "Theirs"
    other.lock_version = other.lock_version
    other.save!

    after_their_save = Cms::Page::Version.where(original_record_id: @page.id).count
    assert_equal before + 1, after_their_save, "precondition: their save added one version"

    editor_a.name = "Ours"
    editor_a.lock_version = editor_a.lock_version
    assert_raises(ActiveRecord::StaleObjectError) { editor_a.save! }

    assert_equal after_their_save,
                 Cms::Page::Version.where(original_record_id: @page.id).count,
                 "the rejected save must not have inserted a version row"
  end

  # -- (2): the value the form carries -----------------------------------------

  # The single change that makes any of this reachable. Without it the hidden
  # field is 0 on every screen and there is nothing to compare.
  test "an object built from a version carries the content row's lock_version" do
    @page.name = "Moved Along"
    @page.save!
    expected = db_lock_version(@page)
    assert_operator expected, :>, 0, "precondition: the content row has moved off the default"

    draft = Cms::Page.find(@page.id).as_of_draft_version

    assert_equal expected, draft.lock_version,
                 "as_of_draft_version must carry the real lock_version, not the column default"
  end

  # Building a draft must not itself count as the caller supplying a lock_version,
  # or every internal save of a draft-loaded object would be checked.
  test "building a draft does not arm the conflict check" do
    draft = Cms::Page.find(@page.id).as_of_draft_version
    bump_lock_version_behind_its_back(@page)

    draft.name = "Changed Without Touching lock_version"

    assert_nothing_raised { draft.save! }
  end

  # -- (3): the gate -----------------------------------------------------------

  # The PageComponent/Mercury shape, reduced to its essentials: a caller holding a
  # record whose lock_version moved underneath it, which never mentions
  # lock_version. This is the case that must keep working.
  test "a stale save that never supplied a lock_version still proceeds" do
    bump_lock_version_behind_its_back(@page)

    @page.name = "Internal Cascade"

    # An internal caller that never assigns lock_version must not be subject to the
    # conflict check -- PageComponent#save is behind the page every time it runs, with
    # no second editor involved. (The message is a comment rather than an argument to
    # assert_nothing_raised, which is deprecated on 5.0 and removed in 5.1.)
    assert_nothing_raised { @page.save! }
    assert_equal "Internal Cascade", Cms::Page.find(@page.id).draft.name
  end

  # The other half of the gate, and the one that makes the test above mean
  # something: supplying the value is what turns the check on.
  test "supplying a lock_version arms the check on the very same record" do
    bump_lock_version_behind_its_back(@page)
    stale = @page.lock_version

    @page.name = "Internal Cascade, But Declared"
    @page.lock_version = stale

    assert_raises(ActiveRecord::StaleObjectError) { @page.save! }
  end

  # Supplying a lock_version that is still current must not raise. Otherwise every
  # ordinary single-editor save through a form would conflict with itself.
  test "supplying a current lock_version saves normally" do
    draft = Cms::Page.find(@page.id).as_of_draft_version

    draft.name = "Ordinary Edit"
    draft.lock_version = draft.lock_version

    assert_nothing_raised { draft.save! }
    assert_equal "Ordinary Edit", Cms::Page.find(@page.id).draft.name
  end

  # The flag must not outlive the save that used it, or a second save on the same
  # instance would be checked against a value the caller never supplied for it.
  test "the check does not carry over to a later save of the same record" do
    draft = Cms::Page.find(@page.id).as_of_draft_version
    draft.name = "First"
    draft.lock_version = draft.lock_version
    draft.save!

    bump_lock_version_behind_its_back(@page)
    draft.name = "Second"

    assert_nothing_raised { draft.save! }
  end

  # A new record has no row to conflict with, and the create path does not run the
  # check at all. Guards against the check firing on Page creation.
  test "creating a record with a lock_version does not raise" do
    fresh = build(:page, name: "Brand New")
    fresh.lock_version = 0

    assert_nothing_raised { fresh.save! }
  end

  # Content blocks go through the same behavior and the same controller shape, and
  # have their own conflict UI. The fix is in the behavior, so it must hold there
  # too -- otherwise this is a Page fix wearing a behavior's clothes.
  test "the conflict check applies to content blocks, not just pages" do
    block = create(:html_block, name: "Contested Block", content: "v1")
    block.content = "v2"
    block.save!

    editor_a = Cms::HtmlBlock.find(block.id).as_of_draft_version
    editor_b = Cms::HtmlBlock.find(block.id).as_of_draft_version

    editor_b.content = "theirs"
    editor_b.lock_version = editor_b.lock_version
    editor_b.save!

    editor_a.content = "ours"
    editor_a.lock_version = editor_a.lock_version

    assert_raises(ActiveRecord::StaleObjectError) { editor_a.save! }
    assert_equal "theirs", Cms::HtmlBlock.find(block.id).draft.content
  end

  # The real internal caller, not a reduction of it. PageComponent#save is the
  # measured worst case and the reason the gate exists; if this raises, Mercury
  # inline editing is broken.
  test "the PageComponent inline-edit flow does not raise a false conflict" do
    page = create(:page, name: "Inline Host")
    block = create(:html_block, name: "Inline Block", content: "v1")
    page.add_content(block, "main")
    page.save!

    held_page = Cms::Page.find(page.id)
    Cms::HtmlBlock.find(block.id).update(content: "v2")

    assert_operator db_lock_version(held_page), :>, held_page.lock_version,
                    "precondition: the block update must have left the page behind"

    held_page.title = "Retitled Inline"

    assert_nothing_raised { held_page.save! }
  end
end
