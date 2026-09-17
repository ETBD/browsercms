require 'test_helper'

# Phase 4, stage F -- work item 4.4 / Tier B B9, criterion 7.
# Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# Cms::FormsController was at 0% coverage: no functional test file existed, so nothing
# ever instantiated it. Two of its three before_action callbacks manipulate params as
# though they were a plain Hash, and both are on the create/update path:
#
#   forms_controller.rb:26  params[:form][:field_ids] = params[:field_ids].split(" ")
#   forms_controller.rb:33  params[:form].delete(:new_entry)
#
# :33 is one of the ten B9 sites. `.delete` still exists on
# ActionController::Parameters in Rails 5; what changed is that Parameters is no longer
# a Hash, so surrounding code assuming Hash semantics -- assignment into it, `.each`
# yielding pairs, implicit to_hash coercion, permitted-state propagation -- can behave
# differently. :26 is the assignment case and travels with it.
#
# `new_entry` is described in the source as "a garbage parameter that exists to make
# displaying forms work". It is not in Cms::Form's column list, so if the strip ever
# stopped working the failure would be an UnknownAttributeError on a real submission --
# loud, but only in production, because nothing here exercised it until now.
module Cms
  class FormsControllerTest < ActionController::TestCase
    include Cms::ControllerTestHelper

    def setup
      given_a_site_exists
      login_as_cms_admin
    end

    def create_form(form_attrs = {}, extra = {})
      post :create, params: {
        field_ids: '',
        form: {name: 'Contact Us'}.merge(form_attrs)
      }.merge(extra)
    end

    test "create strips the new_entry garbage parameter before assignment" do
      assert_difference 'Cms::Form.count', 1 do
        create_form(new_entry: 'garbage that is not a column')
      end

      refute @controller.params[:form].key?(:new_entry),
             "strip_new_entry_params must remove :new_entry from params[:form] -- it is " +
             "not a column on cms_forms, so anything that mass-assigns it raises"
      refute @controller.params[:form].key?('new_entry')
    end

    test "create persists a form when new_entry is present" do
      create_form(new_entry: 'garbage')

      form = Cms::Form.order(:id).last
      assert_equal 'Contact Us', form.name,
                   "the form should save normally; :new_entry is discarded, not fatal"
    end

    # The sibling callback, and the reason it is tested alongside the delete: it ASSIGNS
    # into params[:form], which is the other Hash-shaped assumption on this path.
    test "create splits the space separated field_ids into an array on the form params" do
      # Built directly: there is no :form_field factory, which is itself a symptom of
      # this subsystem never having been tested.
      field_ids = 3.times.map do |n|
        Cms::FormField.create!(label: "Field #{n}", field_type: 'text_field').id
      end

      create_form({}, field_ids: field_ids.join(' '))

      assert_equal field_ids.map(&:to_s), @controller.params[:form][:field_ids],
                   "associate_form_fields must write an Array back into params[:form]"
    end

    test "new builds and saves a form with default confirmation text" do
      assert_difference 'Cms::Form.count', 1 do
        get :new
      end

      assert_equal "Thanks for filling out this form.",
                   assigns(:block).confirmation_text,
                   "the controller's own work should happen even though the view " +
                   "cannot render -- see the characterization test below"
    end

    # -------------------------------------------------------------------------
    # CHARACTERIZATION: the Forms admin UI cannot render. This is a live defect,
    # found in Phase 4 stage F by instantiating a controller that had sat at 0%
    # coverage, and it is NOT caused by the Rails upgrade -- it fails identically on
    # both bundles.
    #
    #   app/views/cms/forms/_form.html.erb:7   f.input :slug, as: :path
    #   app/inputs/path_input.rb:14            Cms::Section.with_path(object.class.path)
    #
    # but Cms::Form has no `path`, no `base_path` and no `slug` column, because
    # `is_addressable path: '/forms'` is commented out at form.rb:5. So rendering the
    # form partial raises NoMethodError and #new and #edit return 500.
    #
    # The same abandoned migration explains the :form factory, which set a `slug` that
    # does not exist and had never been called by anything.
    #
    # NOT FIXED HERE. The repair is either restoring is_addressable (which needs a
    # slug column, i.e. a migration) or removing the slug input -- a product decision
    # about whether Forms are addressable, not an upgrade one. Out of scope for a
    # characterization phase.
    #
    # This test pins the CURRENT behaviour. When someone fixes the UI it will fail --
    # that failure is the signal to delete this test, not to work around it.
    # -------------------------------------------------------------------------
    test "CHARACTERIZATION: the new/edit views cannot render, on both bundles" do
      refute Cms::Form.respond_to?(:path),
             "Cms::Form gained a .path -- is_addressable was probably restored. If so " +
             "the views below may now work; re-check and delete this test."

      get :new
      assert_response :internal_server_error,
                      "expected the known PathInput failure. If this now succeeds, the " +
                      "Forms UI has been repaired -- delete this test and restore the " +
                      "assert_response :success above."
    end
  end
end
