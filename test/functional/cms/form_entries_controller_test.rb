require 'test_helper'

# Phase 4, stage F.
# Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# Cms::FormEntriesController was at 0% coverage across 108 lines -- the largest
# untested controller in the engine, and the one that handles PUBLIC form submission.
# `allow_guests_to [:submit]` means the submit action is reachable without
# authentication, so it is also the largest untested attack surface.
#
# It is named in Phase 5's manual-verification list for exactly that reason. These
# tests replace part of that manual pass with something that runs every build.
#
# Scope note: this file was written during stage F to close a coverage gate, which
# phase-4-characterization-tests.md otherwise rules out ("writing tests to raise a
# percentage is the wrong objective"). The tests are characterization tests of a
# controller that had none -- the gate was the prompt, not the design.
module Cms
  class FormEntriesControllerTest < ActionController::TestCase
    tests Cms::FormEntriesController
    include Cms::ControllerTestHelper

    def setup
      given_a_site_exists
      @form = build_form
    end

    # Cms::Form is a versioned content block, so `update!` on an existing form creates
    # a DRAFT -- and the controller reads the published record, which still has the old
    # values. Every attribute a test depends on has to be set at creation time.
    def build_form(attrs = {})
      form = create(:form, {name: "Contact Us", confirmation_behavior: 'redirect',
                            confirmation_redirect: '/thanks'}.merge(attrs))
      form.fields << Cms::FormField.create!(label: "Email", field_type: "text_field")
      form.save!
      form
    end

    def submit_entry(attrs = {email: "visitor@example.com"})
      post :submit, params: {form_id: @form.id, form_entry: attrs}
    end

    # --- the public path -----------------------------------------------------

    test "a guest can submit a form entry without logging in" do
      assert_difference 'Cms::FormEntry.count', 1 do
        submit_entry
      end

      entry = Cms::FormEntry.order(:id).last
      assert_equal @form, entry.form
    end

    # -------------------------------------------------------------------------
    # CHARACTERIZATION: public form submission is broken for every form configured to
    # show confirmation text, which is the default behaviour offered in the UI.
    #
    #   form_entries_controller.rb:17   render layout: Cms::Form.layout   (success)
    #   form_entries_controller.rb:31   render 'error', layout: Cms::Form.layout
    #
    # `Cms::Form.layout` does not exist -- no model or behavior in the engine defines
    # `self.layout`, and Cms::Form.respond_to?(:layout) is false. Both call sites raise
    # NoMethodError, so a visitor submitting such a form gets a 500 and the entry's
    # confirmation is never shown. The entry IS saved first, so data is not lost.
    #
    # Fails identically on both bundles -- NOT caused by the Rails upgrade. Found in
    # Phase 4 stage F by instantiating a controller that had sat at 0% coverage across
    # 108 lines. It is the second defect of this shape in the Forms subsystem; the
    # first is Cms::Form.path, characterized in forms_controller_test.rb.
    #
    # NOT FIXED HERE: the repair is a product decision about which layout a form
    # confirmation should render in, not an upgrade one.
    #
    # This pins the CURRENT behaviour. When it is fixed this test fails -- that is the
    # signal to delete it and assert the real confirmation, not to work around it.
    # -------------------------------------------------------------------------
    test "CHARACTERIZATION: submit 500s when the form shows confirmation text" do
      @form = build_form(confirmation_behavior: 'show_text',
                         confirmation_text: "Thanks, we got it.")
      refute Cms::Form.respond_to?(:layout),
             "Cms::Form gained a .layout -- the defect below may be fixed; re-check."

      assert_difference 'Cms::FormEntry.count', 1 do
        submit_entry
      end
      assert_response :internal_server_error,
                      "expected the known Cms::Form.layout failure. If this now " +
                      "succeeds, the Forms confirmation path has been repaired."
    end

    test "submit redirects when the form is configured to redirect" do
      submit_entry
      assert_redirected_to '/thanks'
    end

    # The notification branch is `unless @form.notification_email.blank?`, so both
    # sides need exercising or the blank guard could invert unnoticed and the CMS
    # would start mailing on every submission -- or stop mailing entirely.
    test "submit sends a notification email when the form has a notification address" do
      @form = build_form(notification_email: 'owner@example.com')

      assert_difference 'Cms::EmailMessage.count', 1 do
        submit_entry
      end

      message = Cms::EmailMessage.order(:id).last
      assert_equal 'owner@example.com', message.recipients
      assert_match(/Contact Us/, message.body)
    end

    test "submit sends no notification email when no address is configured" do
      assert_no_difference 'Cms::EmailMessage.count' do
        submit_entry
      end
    end

    # --- the admin paths -----------------------------------------------------

    test "update saves a valid change to an existing entry" do
      submit_entry
      entry = Cms::FormEntry.order(:id).last
      login_as_cms_admin

      put :update, params: {id: entry.id, form_entry: {email: "changed@example.com"}}

      assert_redirected_to Cms::Engine.routes.url_helpers.form_entry_path(entry)
      assert_equal "changed@example.com", entry.reload.email
    end

    test "bulk_update deletes the selected entries" do
      submit_entry
      submit_entry(email: "second@example.com")
      login_as_cms_admin
      ids = Cms::FormEntry.order(:id).last(2).map(&:id)

      assert_difference 'Cms::FormEntry.count', -2 do
        put :bulk_update, params: {content_id: ids.map(&:to_s), commit: 'Delete', form_id: @form.id}
      end
      assert_equal "Deleted 2 records.", flash[:notice]
    end

    # The `params[:content_id] || []` guard. Without it this raises NoMethodError on
    # nil rather than doing nothing, and the action is reachable from the admin UI's
    # bulk toolbar with nothing selected.
    test "bulk_update with nothing selected deletes nothing and does not raise" do
      submit_entry
      login_as_cms_admin

      assert_no_difference 'Cms::FormEntry.count' do
        put :bulk_update, params: {commit: 'Delete', form_id: @form.id}
      end
    end

    test "bulk_update ignores a commit value other than Delete" do
      submit_entry
      login_as_cms_admin
      ids = [Cms::FormEntry.order(:id).last.id.to_s]

      assert_no_difference 'Cms::FormEntry.count' do
        put :bulk_update, params: {content_id: ids, commit: 'Something Else', form_id: @form.id}
      end
    end

    test "show and edit load the requested entry" do
      submit_entry
      entry = Cms::FormEntry.order(:id).last
      login_as_cms_admin

      get :show, params: {id: entry.id}
      assert_equal entry, assigns(:entry)

      get :edit, params: {id: entry.id}
      assert_equal entry, assigns(:entry)
    end
  end
end
