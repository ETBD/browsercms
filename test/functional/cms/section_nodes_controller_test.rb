require 'test_helper'

# Phase 4, stage I -- work item 4.7, final bullet ("Tier C fixes with a behavioural
# choice"). Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# `move_to_position` is the sitemap's drag-and-drop endpoint and had **zero** coverage:
# no unit test, no functional test, no feature. It is also where Phase 3 left the only
# `TODO(Phase 4)` marker in the repository, against the dedupe in
# `nodes_to_update_on_success`.
#
# THE DEDUPE, AND WHY IT IS FIXED HERE RATHER THAN CHARACTERIZED
#
# The method returns the siblings the front end must reposition. Before this stage:
#
#     (previous_parent.children.not_of_type(HIDDEN) +
#      target_parent.children.not_of_type(HIDDEN).distinct).map { ... }
#
# `.distinct` binds to the *second relation only*, so it became `SELECT DISTINCT`
# within one query -- where the rows were already distinct -- and did nothing about
# duplicates *between* the two halves. Those are the only duplicates this method can
# produce, and it produces them on **every move within a single folder**, because the
# two queries are then the same query.
#
# Phase 3 spotted it and declined to act mid-rename. Worth being precise about what
# Phase 3 did and did not do: `Relation#uniq` on 4.2 is an **alias for `distinct`**,
# not `Array#uniq`, and `.children` returns a Relation -- so the `uniq` -> `.distinct`
# rename bound exactly the same way and changed nothing. **The defect is older than the
# upgrade and is not a Phase 3 regression.**
#
# Phase 4 fixes rather than characterizes it (D8) because the consumer was read first.
# `Sitemap.prototype.updateValuesOnSuccess` (app/assets/javascripts/cms/sitemap.js:188)
# is pure assignment -- `$row.data('position', position)`, `.html(position)`,
# `dataset.position = position` -- so a repeated triple writes the same values twice
# and the duplicate is cosmetic. That makes the fix free, and leaves nothing to decide:
# nobody would argue for the duplicate, and the intent is already written into the code
# because the dedupe call was there and was meant to work. Characterizing it would have
# meant asserting that a misplaced parenthesis is correct.
module Cms
  class SectionNodesControllerTest < ActionController::TestCase
    tests Cms::SectionNodesController
    include Cms::ControllerTestHelper

    def setup
      given_there_is_a_cmsadmin
      login_as_cms_admin
      given_there_is_a_sitemap

      @folder = create(:section, parent: root_section, name: "Folder",
                       groups: root_section.groups)
      @other_folder = create(:section, parent: root_section, name: "Other Folder",
                             groups: root_section.groups)

      @first = create(:page, section: @folder, name: "First")
      @second = create(:page, section: @folder, name: "Second")
      @third = create(:page, section: @folder, name: "Third")
    end

    def node_for(record)
      record.section_node
    end

    def move(node, target_parent, position = nil)
      params = {id: node.id, target_node_id: node_for(target_parent).id}
      params[:position] = position unless position.nil?
      put :move_to_position, params: params
    end

    def updated_ids
      JSON.parse(response.body).fetch('updated_values').map(&:first)
    end

    # --- the endpoint works at all --------------------------------------------

    test "move_to_position moves a node to the requested position" do
      move(node_for(@third), @folder, 0)

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal true, body['success'], body.inspect
      assert_equal 0, node_for(@third).reload.position
    end

    test "move_to_position with no position moves the node to the end" do
      move(node_for(@first), @other_folder)

      assert_response :success
      assert_equal true, JSON.parse(response.body)['success']
      assert_equal node_for(@other_folder).id, node_for(@first).reload.parent_id,
                   "the node should now live under the target folder"
    end

    test "move_to_position reports the siblings that need repositioning" do
      move(node_for(@third), @folder, 0)

      # The payload drives Sitemap.prototype.updateValuesOnSuccess, which looks each
      # row up by id -- so the ids have to be the ones the sitemap is displaying.
      assert_includes updated_ids, node_for(@first).id
      assert_includes updated_ids, node_for(@second).id
      assert_includes updated_ids, node_for(@third).id
    end

    # -------------------------------------------------------------------------
    # CHARACTERIZATION: the `rescue StandardError` cannot report the two failures
    # most likely to reach it.
    #
    # section_nodes_controller.rb:52-59 builds its failure message by interpolating
    # `node_to_move.node.name` and `target_parent.node.name` -- but both of those are
    # assigned by `SectionNode.find` calls *inside* the begin block:
    #
    #     node_to_move   = SectionNode.find(params[:id])            # :28
    #     target_parent  = SectionNode.find(params[:target_node_id]) # :35
    #
    # So whenever a find is what raised, the corresponding local is nil when the
    # handler runs, and the handler raises NoMethodError on nil. Nothing catches that,
    # so an unknown id produces an unhandled exception instead of the JSON error
    # response the action was written to return.
    #
    # Measured: the JSON error branch renders only if **both** finds succeed and
    # something later raises. No such case was found -- even moving a folder into its
    # own descendant returns 200.
    #
    # Identical on both bundles. NOT caused by the upgrade.
    #
    # NOT FIXED. The repair means composing a message without the objects that failed
    # to load, which is a decision about what the error should say -- and unlike the
    # dedupe below, there is no existing intent in the code to read off. The three
    # branches this stage owns are named in work item 4.7; this is a fourth, found by
    # instrumenting them, and it is recorded rather than absorbed.
    #
    # Both directions asserted, so a fix that handles one id and not the other is
    # still caught.
    # -------------------------------------------------------------------------
    test "CHARACTERIZATION: an unknown target_node_id escapes the rescue" do
      assert_raises(NoMethodError) do
        put :move_to_position, params: {id: node_for(@first).id, target_node_id: -1}
      end
    end

    test "CHARACTERIZATION: an unknown id escapes the rescue the same way" do
      assert_raises(NoMethodError) do
        put :move_to_position, params: {id: -1, target_node_id: node_for(@folder).id}
      end
    end

    # --- the dedupe -----------------------------------------------------------

    # THE REGRESSION TEST for the TODO(Phase 4) marker. A move within one folder makes
    # `previous_parent` and `target_parent` the same record, so both halves of
    # `nodes_to_update_on_success` run the same query and every sibling came back twice.
    #
    # Before the fix this failed with each id appearing exactly twice.
    test "a move within one folder reports each sibling once" do
      move(node_for(@third), @folder, 0)

      ids = updated_ids
      duplicates = ids.select { |id| ids.count(id) > 1 }.uniq
      assert_empty duplicates,
                   "each node must appear once. Duplicates mean the dedupe in " +
                   "nodes_to_update_on_success is back inside the parentheses, where " +
                   "it cannot see across the two halves: #{ids.inspect}"
    end

    # Guards the guard. If the two halves ever stop being combined at all, the test
    # above would pass against a payload that simply lost the previous parent's
    # siblings -- which is the failure the dedupe fix could plausibly cause.
    test "a move between folders reports siblings from both the old and new parent" do
      move(node_for(@first), @other_folder, 0)

      ids = updated_ids
      assert_includes ids, node_for(@second).id,
                      "a sibling left behind in the previous parent still needs its " +
                      "position updated"
      assert_includes ids, node_for(@first).id,
                      "and so does the node that moved"

      duplicates = ids.select { |id| ids.count(id) > 1 }.uniq
      assert_empty duplicates, "still no duplicates across the two parents"
    end
  end
end
