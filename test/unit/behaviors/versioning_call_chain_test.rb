require 'test_helper'

# Phase 4, stage G -- work item 4.6 / Tier B B6.
# Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# THE AUDIT, AND ITS ANSWERS
#
# B6 asks three questions about test/unit/behaviors/versioning_test.rb. Criterion 10
# asks for them answered yes or no in a committed note or in test comments. Here they
# are, answered by grep against that file and then by the tests below:
#
#   1. Does a failed validation produce no new version row?   NO ASSERTION EXISTED
#      (nothing in the file mentions `valid` or `invalid`)
#   2. Does version_comment reflect *this* save's changes?    NO ASSERTION EXISTED
#      (`version_comment` appears in no assertion)
#   3. Does a rolled-back transaction leave no orphan row?    NO ASSERTION EXISTED
#      (neither `transaction` nor `rollback` appears)
#
# All three were unasserted while versioning.rb sat at 96.91% line coverage. That gap
# between "almost every line ran" and "nothing checked what the lines did" is the
# thesis of this whole phase, stated in one file.
#
# WHY THESE THREE AND NOT OTHERS
#
# versioning.rb does not override one method; it replaces the save call chain.
# `create_or_update` (versioning.rb:294) intercepts every update and saves a *version
# row* instead of the record, and `save!` (versioning.rb:341) forwards to `save`. Both
# signatures were changed during Phase 1 and Phase 2 to accept `(*args, &block)` --
# see phase-1-gem-report.md P1-2. A behaviour that depends on where a hook sits
# relative to that chain can move without any test noticing.
#
# Each question pins one such relationship:
#
#   Q1  before_validation :initialize_version runs before validation;
#       before_save :build_new_version runs after it. Swap the two, or promote
#       build_new_version to before_validation, and invalid records start
#       accumulating version rows.
#   Q2  default_version_comment reads `changes`, so it depends on the dirty state
#       surviving intact from the caller down to the before_save.
#   Q3  the version INSERT and the parent's raw-SQL latest_version UPDATE must both
#       sit inside the caller's transaction.
#
# WHAT THE ANSWERS TURN OUT TO BE
#
# Q1 and Q3 behave correctly, and now say so. Q2 is correct for a record loaded the
# ordinary way and WRONG for one loaded the way the CMS UI loads it -- see the
# characterization block below, which locates the cause on a single line.
#
# These pin 4.2. They pass on the Gemfile bundle unchanged.
module Cms
  class VersioningCallChainTest < ActiveSupport::TestCase

    def version_rows(record)
      record.class.version_class.where(original_record_id: record.id)
    end

    # Read the persisted comment back through a fresh query. The in-memory
    # `version_comment` accessor returns @version_comment, which
    # build_new_version_and_add_to_versions_list_for_saving sets to nil on the way
    # past -- so asking the object would not tell us what was written.
    def persisted_version_comment(record)
      record.class.find(record.id).draft.version_comment
    end

    # -------------------------------------------------------------------------
    # Q1 -- A failed validation produces no new version row
    # -------------------------------------------------------------------------

    test "Q1: a failed validation on update leaves no new version row" do
      block = Cms::HtmlBlock.create!(name: "Valid", content: "original")
      assert_equal 1, version_rows(block).count, "precondition: one version from the create"

      block.name = ""
      assert_equal false, block.save, "precondition: the record must actually be invalid"
      assert block.errors[:name].any?, "precondition: name is the validation that failed"

      assert_equal 1, version_rows(block).count,
                   "an invalid save must not write a version row. build_new_version is a " +
                   "before_save, which runs only after validation passes -- if it is ever " +
                   "moved to before_validation this fails."
    end

    test "Q1: a failed validation on update does not advance the draft" do
      block = Cms::HtmlBlock.create!(name: "Valid", content: "original")
      block.name = ""
      block.save

      fresh = Cms::HtmlBlock.find(block.id)
      assert_equal 1, fresh.draft.version
      assert_equal "Valid", fresh.name, "the invalid value must not have reached the table"
    end

    test "Q1: a failed validation on create writes no version row at all" do
      before = Cms::HtmlBlock.version_class.count

      block = Cms::HtmlBlock.new(name: "")
      assert_equal false, block.save
      refute block.persisted?

      assert_equal before, Cms::HtmlBlock.version_class.count,
                   "a record that never existed must not leave a version row behind"
    end

    # Cms::Page carries a denormalized `latest_version` column that
    # update_latest_version maintains with raw SQL (versioning.rb:161). Raw SQL does
    # not run validations or callbacks, so it is worth checking separately that the
    # column does not drift when a save is rejected.
    test "Q1: a failed validation does not advance Page#latest_version" do
      page = create(:page, name: "Valid Page")
      assert_equal 1, page.latest_version, "precondition"

      page.name = ""
      assert_equal false, page.save

      assert_equal 1, Cms::Page.find(page.id).latest_version,
                   "latest_version is maintained by raw SQL -- if it ever runs outside " +
                   "the after_save it will drift past the newest real version row"
    end

    # -------------------------------------------------------------------------
    # Q2 -- version_comment reflects the changes from *this* save
    # -------------------------------------------------------------------------

    test "Q2: a new record's version is commented Created" do
      block = Cms::HtmlBlock.create!(name: "First", content: "aaa")
      assert_equal "Created", persisted_version_comment(block)
    end

    test "Q2: an update names only the attribute this save changed" do
      block = Cms::HtmlBlock.create!(name: "First", content: "aaa")

      fresh = Cms::HtmlBlock.find(block.id)
      fresh.name = "Second"
      fresh.save!

      assert_equal "Changed name", persisted_version_comment(block),
                   "content did not change in this save and must not be listed"
    end

    test "Q2: consecutive saves of one object each name only their own change" do
      block = Cms::HtmlBlock.create!(name: "First", content: "aaa")
      fresh = Cms::HtmlBlock.find(block.id)

      fresh.name = "Second"
      fresh.save!
      assert_equal "Changed name", persisted_version_comment(block)

      fresh.content = "bbb"
      fresh.save!
      assert_equal "Changed content", persisted_version_comment(block),
                   "the second save must not still be reporting the first save's change. " +
                   "This is the assertion that catches dirty state leaking between saves."
    end

    test "Q2: an explicit version_comment wins, and is consumed by one save" do
      block = Cms::HtmlBlock.create!(name: "First", content: "aaa")

      fresh = Cms::HtmlBlock.find(block.id)
      fresh.version_comment = "Fixed a typo"
      fresh.name = "Second"
      fresh.save!
      assert_equal "Fixed a typo", persisted_version_comment(block)

      # @version_comment is nil'd in build_new_version_and_add_to_versions_list_for_saving
      # (versioning.rb:239), so the next save falls back to the generated comment rather
      # than repeating the caller's.
      fresh.content = "bbb"
      fresh.save!
      assert_equal "Changed content", persisted_version_comment(block),
                   "an explicit comment must apply to one save only"
    end

    # -------------------------------------------------------------------------
    # CHARACTERIZATION: Q2's answer is "no" on the path the CMS UI actually takes.
    #
    # versioning.rb:258-259 carries a comment written by the original author:
    #
    #     # This doesn't always seem to properly be applied, or is applying for
    #     # ALL fields, not just the changed ones.
    #
    # It is right, and the cause is one line. build_object_from_version
    # (versioning.rb:21-42) copies every versioned column onto a fresh object and then
    # ends with:
    #
    #     # Last but not least, clear the changed attributes
    #     clear_changes_information          # <- versioning.rb:39
    #
    # That is an implicit `self.`, and `self` there is the **Version record**, not the
    # `obj` being built and returned. The object that needed its dirty state cleared
    # never gets it, so everything as_of_version and as_of_draft_version return has
    # every non-nil versioned column marked as changed -- plus `id`, `created_at` and
    # `updated_at`, which are not versioned columns at all.
    #
    # This is not an obscure path. It is the admin edit path:
    #
    #     pages_controller.rb:137-140  load_draft_page -> @page.as_of_draft_version
    #     pages_controller.rb:46       @page.update(page_params)
    #
    # so every page edited through the CMS records a version comment listing the whole
    # record. The version history is technically intact and practically useless, which
    # is why nobody has reported it.
    #
    # There is a second consequence, pinned below: different_from_last_draft?
    # (versioning.rb:432) short-circuits on `self.changed?`, so it is unconditionally
    # true for these objects and the "unchanged record, skip the save" optimization at
    # versioning.rb:297 never fires on the UI path.
    #
    # NOT FIXED HERE. `obj.clear_changes_information` is a one-word fix to the comment
    # text, but it also switches that skip-save branch on for the engine's busiest
    # write path, where it has never run in any released version. That is a behaviour
    # change to 4.2, which is the same line D6 drew for optimistic locking and is drawn
    # in the same place for the same reason.
    #
    # Fails on both bundles identically -- NOT caused by the Rails upgrade. When it is
    # fixed these two tests fail, which is the signal to rewrite them against the
    # repaired behaviour rather than to work around them.
    # -------------------------------------------------------------------------

    test "CHARACTERIZATION: a draft object is dirty in every column before anything is edited" do
      block = Cms::HtmlBlock.create!(name: "First", content: "aaa")

      draft_object = Cms::HtmlBlock.find(block.id).as_of_draft_version

      assert draft_object.changed?,
             "as_of_draft_version returned a clean object -- versioning.rb:39 may have " +
             "been fixed to clear obj's changes rather than the version record's."
      %w[name content id created_at updated_at].each do |attribute|
        assert_includes draft_object.changed, attribute,
                        "#{attribute} should be spuriously dirty on an untouched draft object"
      end
    end

    test "CHARACTERIZATION: saving a draft object comments every field, not the changed one" do
      block = Cms::HtmlBlock.create!(name: "First", content: "aaa")

      draft_object = Cms::HtmlBlock.find(block.id).as_of_draft_version
      draft_object.name = "Second"
      draft_object.save!

      comment = persisted_version_comment(block)
      assert_equal "Changed content, created_at, id, name, published, updated_at", comment,
                   "this is the CMS edit path's version comment. Only `name` changed."
      assert_includes comment, "id",
                      "`id` is not even a versioned column -- it is listed because " +
                      "build_object_from_version assigns it and never clears the flag"
    end

    test "CHARACTERIZATION: an unedited draft object still saves a new version" do
      block = Cms::HtmlBlock.create!(name: "First", content: "aaa")

      draft_object = Cms::HtmlBlock.find(block.id).as_of_draft_version
      assert draft_object.different_from_last_draft?,
             "the spurious dirty state makes this true for an object nothing has touched"

      assert_difference -> { version_rows(block).count }, 1 do
        draft_object.save!
      end
    end

    # -------------------------------------------------------------------------
    # Q3 -- A rolled-back transaction leaves no orphan version row
    # -------------------------------------------------------------------------

    test "Q3: ActiveRecord::Rollback leaves no orphan version row" do
      block = Cms::HtmlBlock.create!(name: "Original", content: "aaa")
      assert_equal 1, version_rows(block).count, "precondition"

      Cms::HtmlBlock.transaction do
        block.name = "Rolled back"
        block.save!
        assert_equal 2, version_rows(block).count,
                     "precondition: the version row must exist inside the transaction, " +
                     "or the rollback below proves nothing"
        raise ActiveRecord::Rollback
      end

      assert_equal 1, version_rows(block).count,
                   "the version INSERT must participate in the caller's transaction"
      assert_equal "Original", Cms::HtmlBlock.find(block.id).name
    end

    test "Q3: a raised exception leaves no orphan version row" do
      block = Cms::HtmlBlock.create!(name: "Original", content: "aaa")

      assert_raises(RuntimeError) do
        Cms::HtmlBlock.transaction do
          block.name = "Doomed"
          block.save!
          raise "something downstream failed"
        end
      end

      assert_equal 1, version_rows(block).count
      assert_equal "Original", Cms::HtmlBlock.find(block.id).name
    end

    # The one piece of this behaviour that is not ordinary ActiveRecord.
    # update_latest_version issues `self.class.connection.execute sql` (versioning.rb:162)
    # rather than an AR write. Raw execute still runs on the transaction's connection,
    # so it rolls back -- but it does so by accident of sharing a connection, not
    # because anything in the code says so. Worth pinning: a connection-pool or
    # multi-database change at a later hop is exactly what would break it, and the
    # failure would be a silent pointer to a version row that does not exist.
    test "Q3: a rollback also unwinds the raw-SQL latest_version update" do
      page = create(:page, name: "Original Page")
      assert_equal 1, page.latest_version, "precondition"

      Cms::Page.transaction do
        page.name = "Rolled back"
        page.save!
        assert_equal 2, Cms::Page.find(page.id).latest_version, "precondition"
        raise ActiveRecord::Rollback
      end

      assert_equal 1, Cms::Page.find(page.id).latest_version,
                   "latest_version would now point at a version row that does not exist"
      assert_equal 1, version_rows(page).count
    end
  end
end
