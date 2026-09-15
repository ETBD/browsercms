require 'test_helper'

# Phase 4, stage F.
# Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# Three controllers that no suite loaded, revealed by the eager-load test in stage C.
# Each is small, and each has at least one branch worth pinning on its own merits --
# one of them is a security control.
#
# Scope note: these were written to close a coverage gate, which
# phase-4-characterization-tests.md otherwise rules out. They are characterization
# tests of untested code; the gate was the prompt, not the design. Where a controller
# turned out to be broken it is characterized rather than fixed.
module Cms
  # CHARACTERIZATION: Cms::ToolbarController is vestigial. GET /toolbar is routed and
  # the action runs, but it can never render a response:
  #
  #   * there is no app/views/cms/toolbar/index template
  #   * the layout it declares, "cms/toolbar", does not exist either
  #
  # All that survives in app/views/cms/toolbar/ is _new_pages_menu.html.erb, rendered
  # as a partial from layouts/cms/_main_menu.html.erb:56. So the directory is still
  # used; the controller is not.
  #
  # Worth stating plainly: toolbar_controller.rb:14 is one of the nine truthiness
  # guards corrected in stage B.3, and this makes it a fix to unreachable code. It was
  # correct to change it -- it is the same defect as the others and the file is still
  # shipped -- but it does not sit on a live path, and the stage B write-up should not
  # be read as implying otherwise.
  #
  # These tests exercise the action body, which runs before rendering, and stop at the
  # render. Not fixed: deleting a routed controller is a decision for whoever owns the
  # admin UI, not for a characterization phase.
  class ToolbarControllerTest < ActionController::TestCase
    tests Cms::ToolbarController

    include Cms::ControllerTestHelper

    def setup
      given_a_site_exists
      login_as_cms_admin
      @page = create(:page, section: root_section, name: "Toolbar Page")
    end

    # The action's work happens before the render, so the branches are still covered.
    #
    # Both exception classes are listed because Rails changed which one a missing
    # template produces: 4.2 raises ActionView::MissingTemplate, 5.0 raises
    # ActionController::UnknownFormat ("is missing a template for this request format
    # and variant"). A small 4.2-to-5.0 difference, and one this file only noticed
    # because it deliberately depends on the failure.
    MISSING_TEMPLATE_ERRORS = [ActionView::MissingTemplate, ActionController::UnknownFormat].freeze

    def get_index(params = {})
      get :index, params: params
      flunk "GET /toolbar rendered successfully -- the controller may have been revived"
    rescue *MISSING_TEMPLATE_ERRORS
      # expected: see the comment above
    end

    test "index enables the page toolbar by default" do
      get_index
      assert assigns(:page_toolbar_enabled),
             "the toolbar should be enabled unless page_toolbar is explicitly '0'"
    end

    test "index disables the page toolbar when asked" do
      get_index(page_toolbar: "0")
      refute assigns(:page_toolbar_enabled),
             "page_toolbar=0 is the one value that turns the toolbar off"
    end

    test "index loads the requested version of the page" do
      get_index(page_id: @page.id, page_version: @page.draft.version)
      assert_equal @page.id, assigns(:page).id
    end

    # The stage B.3 fix. Before it, `if params[:page_id]` was true for a blank string
    # -- which 5.0's harness produces from nil -- and Page.find("") raised. A real
    # `?page_id=` request did the same on both versions.
    test "index tolerates a blank page_id rather than raising" do
      get_index(page_id: "")
      assert_nil assigns(:page),
                 "a blank page_id must be treated as absent, not passed to Page.find"
    end
  end

  # execute_handler lets a request name a method to call on a portlet. The branch
  # below is the guard that stops that being any method at all -- inherited, private
  # or protected methods are refused. It is an authorization control, and it was at
  # 0% coverage.
  class PortletControllerTest < ActionController::TestCase
    tests Cms::PortletController

    include Cms::ControllerTestHelper

    def setup
      given_a_site_exists
      login_as_cms_admin
      @portlet = DynamicPortlet.create!(name: "Handler Portlet")
    end

    # Cms::Errors::AccessDenied is rescued by the controller stack and rendered as a
    # 403, so these assert on the response rather than on a raised exception.
    test "execute_handler refuses a method inherited from the portlet superclass" do
      # ActiveRecord::Base#destroy reaches DynamicPortlet through Cms::Portlet, so a
      # request naming it must be refused. This is why the guard exists: without it,
      # POST /portlet/:id/destroy would delete the portlet.
      assert Cms::Portlet.method_defined?('destroy'), "precondition"

      post :execute_handler, params: {id: @portlet.id, handler: 'destroy'}

      assert_response :forbidden
      assert Cms::Portlet.exists?(@portlet.id), "the portlet must still be there"
    end

    test "execute_handler refuses a private method" do
      # Kernel#puts is private on every object, so it stands in for the whole class of
      # private methods a request must not be able to name.
      assert DynamicPortlet.private_method_defined?('puts'), "precondition"

      post :execute_handler, params: {id: @portlet.id, handler: 'puts'}

      assert_response :forbidden
    end
  end

  # PageComponent is the object behind the inline page editor, and the class whose
  # save path produced the stale-lock_version cluster in stage B.1.
  class PageComponentsControllerTest < ActionController::TestCase
    tests Cms::PageComponentsController

    include Cms::ControllerTestHelper

    def setup
      given_a_site_exists
      login_as_cms_admin
      @page = create(:page, section: root_section, name: "Original Title")
    end

    test "update saves the component and responds successfully" do
      put :update, params: {
        id: @page.id,
        content: {"page_title" => {"type" => "simple", "data" => {}, "value" => "New Title"}},
        format: :json
      }

      assert_response :success
      assert_equal "New Title", Cms::Page.find(@page.id).draft.title
    end

    test "new exposes the content types the editor can add" do
      get :new

      assert_response :success
      assert assigns(:content_types), "the add-content menu needs the connectable types"
      assert assigns(:default_type)
    end
  end
end
