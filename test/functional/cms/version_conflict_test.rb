require 'test_helper'

# Phase 4, stage G -- item B.2, carried from stage B.
# Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# THE BUG
#
# app/views/cms/pages/_main_form.html.erb rendered two partials that do not exist:
#
#     line  2   'cms/shared/version_conflict_error'
#     line 23   "cms/shared/version_conflict_diff"
#
# app/views/cms/shared/ holds access_denied, error and error.xml -- nothing about
# version conflicts. Both real partials live in app/views/cms/application/. So the
# entire edit-conflict screen for Pages raised ActionView::MissingTemplate, on 4.2 and
# on 5.0 alike. NOT an upgrade regression: it has been broken for as long as the paths
# have said `shared`.
#
# Stage B found the first of the two while diagnosing ten Rails 5 failures, two of
# which were reported as `Missing partial cms/shared/_version_conflict_error`. Those
# two failures were a *symptom*: 5.0's touch was raising StaleObjectError where 4.2
# did not, which drove pages_controller.rb into the conflict branch, which then hit
# the missing partial. Fixing the locking (B.1) removed the StaleObjectError and with
# it the only path that reached this code -- so the fix went green and the bug stayed.
# That ordering is why B.2 was held back to its own stage rather than folded in.
#
# WHY IT COULD NEVER BE CAUGHT BY ACCIDENT
#
# pages_controller.rb:52 enters this branch only on ActiveRecord::StaleObjectError, and
# no ordinary save raises one. The versioning behavior's create_or_update
# (versioning.rb:294) does not issue an UPDATE against the page row at all -- it saves
# a version row instead -- so the parent's lock_version is never checked on the write
# path. The one place that did check it was the after_save touch, on 5.0 only, and
# sync_locking_column_before_touch now keeps that from firing.
#
# So the branch is genuinely unreachable through ordinary use, and the failure it
# produces is only visible to whoever hits a real conflict in production. The trigger
# below is therefore stubbed: `save` is made to raise the error the controller declares
# it rescues. Everything after that point is real -- the rescue, the second load of the
# record, the full render of edit.html.erb through _form to _main_form and both
# partials. It is the render that was broken, and it is the render being tested.
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
      # reason that has nothing to do with the partial path.
      @page.update_column(:updated_by_id, @admin.id)
    end

    def update_with_stale_lock_version
      # The error the controller declares it rescues, raised where it would really be
      # raised from. Nothing downstream of this is stubbed.
      Cms::Page.any_instance.stubs(:save).raises(
        ActiveRecord::StaleObjectError.new(@page, "update")
      )
      put :update, params: {id: @page.id, page: {name: "My Edit", lock_version: 0}}
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
      assert_select "table#diff td", /Contested Page|Version Two/
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
  end
end
