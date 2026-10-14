require 'test_helper'

# The edit-conflict screen, reached the way a user reaches it.
#
# HISTORY -- why this file changed shape twice
#
# Phase 4, stage G (item B.2) created this file to cover a render bug:
# app/views/cms/pages/_main_form.html.erb rendered two partials that do not exist --
# 'cms/shared/version_conflict_error' (line 2) and 'cms/shared/version_conflict_diff'
# (line 23), when both live in app/views/cms/application/. The whole conflict screen
# for Pages raised ActionView::MissingTemplate, on 4.2 and 5.0 alike. Both paths were
# fixed there; fixing only the first would have moved the failure eighteen lines down
# and looked like a repair, which is why the two partials are still asserted
# separately below.
#
# At that point the branch was unreachable through ordinary use, so the trigger was
# stubbed: Cms::Page.any_instance.stubs(:save) was made to raise the StaleObjectError
# the controller declares it rescues. The file said so, and said why -- no ordinary
# save could raise one, because versioning's create_or_update never issued an UPDATE
# against the page row and so never checked the locking column.
#
# CMS-435 made it reachable. A stale save now raises on its own, so the stub is gone
# and every test below drives the real thing: two editors, a genuine conflict, and the
# screen the loser is shown. Nothing here is stubbed any more.
#
# The engine-side survey and the reasoning behind the gate are in
# docs/rails-upgrade/cms-435-optimistic-locking.md. The behaviour-level tests are in
# test/unit/behaviors/versioning_locking_test.rb.
module Cms
  class VersionConflictTest < ActionController::TestCase
    tests Cms::PagesController
    include Cms::ControllerTestHelper

    def setup
      given_there_is_a_cmsadmin
      given_there_is_a_sitemap
      login_as_cms_admin
      @admin = Cms::User.find_by_login('cmsadmin')

      @page = create(:page, section: root_section, name: "Contested Page")
      @page.name = "Version Two"
      @page.save!
      # _version_conflict_error.html.erb:4 renders other_version.updated_by.full_name.
      # The factory does not stamp one, and a nil here would fail the render for a
      # reason that has nothing to do with the conflict.
      @page.update_column(:updated_by_id, @admin.id)
    end

    # What editor A's browser is holding: the lock_version the edit screen actually
    # rendered into the form. Before CMS-435 this was always 0 regardless of the row.
    def lock_version_from_the_edit_form
      get :edit, params: {id: @page.id}
      assigns(:page).lock_version
    end

    # Editor B, who gets there first and wins.
    def another_editor_saves(name = "Their Edit")
      other = Cms::Page.find(@page.id).as_of_draft_version
      other.name = name
      other.lock_version = other.lock_version
      other.save!
      Cms::Page.where(id: @page.id).update_all(updated_by_id: @admin.id)
    end

    # Editor A submits the form they were given, after B has already saved. No stub:
    # the StaleObjectError this produces is raised by the save itself.
    def update_with_stale_lock_version
      stale = lock_version_from_the_edit_form
      another_editor_saves
      put :update, params: {id: @page.id, page: {name: "My Edit", lock_version: stale}}
    end

    test "the edit-conflict screen renders" do
      update_with_stale_lock_version

      assert_response :success,
                      "the conflict screen must render. Before B.2 this raised " +
                      "ActionView::MissingTemplate for cms/shared/_version_conflict_error."
      assert_template "cms/pages/edit"
    end

    test "the conflict screen shows the other version's error partial" do
      update_with_stale_lock_version

      assert_select "#version-conflict.error", 1,
                    "_version_conflict_error.html.erb did not render"
      assert_select "#version-conflict", /Version Conflict/
      assert_select "#version-conflict", /#{@admin.full_name}/,
                    "the partial names the user who committed the other version"
    end

    test "the conflict screen shows the diff partial" do
      update_with_stale_lock_version

      assert_select "table#diff", 1,
                    "_version_conflict_diff.html.erb did not render. It was broken the " +
                    "same way and in the same file, and fixing only the error partial " +
                    "would have left this screen raising on the very next line."
      assert_select "table#diff td", /Their Edit/
    end

    # The point of showing the conflict rather than just erroring: the form comes back
    # carrying the *other* version's lock_version, so resubmitting it wins the next
    # round instead of conflicting again forever. _main_form.html.erb:3.
    test "the conflict form carries the other version's lock_version forward" do
      update_with_stale_lock_version

      other_version = Cms::Page.find(@page.id)
      assert_select "input#page_lock_version[value=?]", other_version.lock_version.to_s
    end

    # Guards the guard. If the controller stops setting @other_version -- or the
    # `if @other_version` wrapper in _main_form is removed -- the three tests above
    # would still pass against a form that simply never shows a conflict.
    test "the ordinary edit screen renders neither conflict partial" do
      get :edit, params: {id: @page.id}

      assert_response :success
      assert_nil assigns(:other_version)
      assert_select "#version-conflict", false,
                    "the conflict partial must render only in the conflict branch"
      assert_select "table#diff", false
    end

    # ------------------------------------------------------------------------
    # CMS-435. The three below are about whether the conflict is real, not about
    # whether the screen renders. Without them the four above would pass against a
    # controller that showed the conflict screen to everybody.
    # ------------------------------------------------------------------------

    # The defect in one assertion. This is the data loss the ticket describes: the
    # second save winning and the first editor's work disappearing.
    test "the losing edit does not overwrite the winning one" do
      update_with_stale_lock_version

      assert_equal "Their Edit", Cms::Page.find(@page.id).draft.name,
                   "the conflicting save must not have landed"
    end

    # An ordinary edit by one person must still just work. If the check were too
    # eager -- firing whenever lock_version is present rather than when it is stale --
    # every single page save would show a conflict screen, and every test above would
    # still pass.
    test "an ordinary edit with a current lock_version succeeds" do
      current = lock_version_from_the_edit_form

      put :update, params: {id: @page.id, page: {name: "Just Me", lock_version: current}}

      assert_redirected_to @page
      assert_equal "Just Me", Cms::Page.find(@page.id).draft.name
      assert_nil assigns(:other_version)
    end

    # The form must carry a real lock_version for any of this to work. Before
    # CMS-435 build_object_from_version left it at the column default, so the edit
    # screen rendered value="0" for a row sitting at 4 and the posted value
    # identified nothing.
    test "the edit form carries the content row's real lock_version" do
      db = Cms::Page.connection.select_value(
        "SELECT lock_version FROM cms_pages WHERE id = #{@page.id}").to_i
      assert_operator db, :>, 0, "precondition: the row has moved off the default"

      get :edit, params: {id: @page.id}

      # The message goes in the options hash, not as a bare third argument: the `?`
      # already consumed db.to_s, so a trailing String would be read as the element's
      # expected *text* and this would fail against a form that was perfectly correct.
      assert_select "input#page_lock_version[value=?]", db.to_s,
                    count: 1,
                    message: "the edit form must post back the row's real lock_version"
    end
  end
end
