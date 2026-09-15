require 'test_helper'

# Phase 4, stage F -- work item 4.4 / Tier B B9, criterion 7.
# Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# The two remaining B9 sites, and the two that matter most: both are AUTHORIZATION
# logic implemented by mutating a params sub-hash.
#
#   pages_controller.rb:124-128   strips :hidden, :archived and :visibility unless the
#                                 user can publish_content
#   sections_controller.rb:42     strips 'group_ids' unless the user can administrate
#
# `.delete` still exists on ActionController::Parameters in Rails 5; what changed is
# that Parameters is no longer a Hash, so surrounding code that assumed Hash semantics
# can behave differently. A regression here fails OPEN -- a user who should not be able
# to set these fields silently gets to set them -- which is the worst available failure
# mode and produces no error to notice.
#
# Both directions are asserted in every case. A test that only checks the restricted
# user would still pass if the strip ran unconditionally and broke the feature for
# everyone; a test that only checks the privileged user would pass if the strip never
# ran at all. Neither half is worth anything alone.
module Cms
  class VisibilityParamsAuthorizationTest < ActionController::TestCase
    tests Cms::PagesController
    include Cms::ControllerTestHelper

    def setup
      given_a_site_exists
      @editor = create(:user)
      @group = create(:group, name: "Editors",
                      group_type: create(:group_type, name: "CMS User", cms_access: true))
      @group.permissions << create_or_find_permission_named("edit_content")
      @group.sections << root_section
      @editor.groups << @group

      @page = create(:page, section: root_section, name: "Target Page")
    end

    def grant_publishing!
      @group.permissions << create_or_find_permission_named("publish_content")
    end

    def update_page_hidden
      put :update, params: {id: @page.to_param, page: {name: "Target Page", hidden: true}}
    end

    test "a user without publish_content cannot set hidden through params" do
      login_as(@editor)
      refute @editor.able_to?(:publish_content), "precondition: editor cannot publish"

      update_page_hidden

      refute @page.reload.hidden?,
             "strip_visibility_params must remove :hidden for a non-publisher. If this " +
             "fails, an authorization control has failed OPEN."
    end

    test "a user with publish_content can set hidden through params" do
      grant_publishing!
      login_as(@editor)
      assert @editor.reload.able_to?(:publish_content), "precondition: editor can publish"

      update_page_hidden

      assert @page.reload.hidden?,
             "the strip must not run for a publisher, or the feature is broken for " +
             "everyone and the test above would pass for the wrong reason"
    end

    test "the stripped keys are absent from params, not merely ignored downstream" do
      login_as(@editor)
      update_page_hidden

      page_params = @controller.params[:page]
      %w[hidden archived visibility].each do |key|
        refute page_params.key?(key),
               "#{key} should have been deleted from params[:page] by the before_action"
        refute page_params.key?(key.to_sym)
      end
    end
  end

  class GroupIdsAuthorizationTest < ActionController::TestCase
    tests Cms::SectionsController
    include Cms::ControllerTestHelper

    def setup
      # Ordering mirrors the working test at sections_controller_test.rb:23 --
      # login_as_cms_admin BEFORE given_there_is_a_sitemap. Built the other way round
      # the admin ends up outside root_section's groups and every update answers 403.
      given_a_site_exists
      @admin = login_as_cms_admin
      given_there_is_a_sitemap
      @restricted_group = create(:group, name: "Should Not Be Assignable",
                                 group_type: create(:group_type, name: "Other", cms_access: true))
      # `groups: root_section.groups` is required for anyone to be able to edit this
      # section at all -- without it the controller answers 403 before reaching the
      # params, and both tests below would pass for entirely the wrong reason.
      @section = create(:section, parent: root_section, name: "Target Section",
                        groups: root_section.groups)
    end

    def update_section_groups(user)
      login_as(user)
      put :update, params: {
        id: @section.to_param,
        section: {name: "Target Section", group_ids: [@restricted_group.id.to_s]}
      }
    end

    test "a non-administrator cannot assign group_ids through params" do
      editor = create(:user)
      group = create(:group, name: "Editors",
                     group_type: create(:group_type, name: "CMS User", cms_access: true))
      group.permissions << create_or_find_permission_named("edit_content")
      group.sections << root_section
      editor.groups << group
      @section.groups << group          # so the editor can edit it at all
      refute editor.able_to?(:administrate), "precondition: editor cannot administrate"

      update_section_groups(editor)
      assert_response :redirect, "precondition: the update must actually run, not 403"

      refute @section.reload.groups.include?(@restricted_group),
             "group_ids must be stripped for a non-administrator. If this fails, an " +
             "authorization control has failed OPEN."
    end

    test "an administrator can assign group_ids through params" do
      login_as(@admin)
      assert @admin.able_to?(:administrate), "precondition: admin can administrate"

      put :update, params: {
        id: @section.to_param,
        section: {name: "Target Section", group_ids: [@restricted_group.id.to_s]}
      }
      assert_response :redirect, "precondition: the update must actually run, not 403"

      assert @section.reload.groups.include?(@restricted_group),
             "the strip must not run for an administrator, or assigning groups is " +
             "broken for everyone and the test above would pass for the wrong reason"
    end
  end
end
