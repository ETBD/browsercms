require 'test_helper'

# Phase 4, stage F -- work item 4.4 / Tier B B9, criterion 7.
# Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# Cms::FormFieldsController was at 0% coverage: no functional test file existed, so
# nothing ever instantiated it. That matters here because form_fields_controller.rb:16
# is one of the ten sites that treat an ActionController::Parameters sub-hash as a
# Hash:
#
#   form = Cms::Form.find(params[:form_field].delete(:form_id))
#
# `.delete` does two things at once -- it returns the value AND removes the key -- and
# the code depends on both halves: the returned id finds the Form, and the removal is
# what keeps :form_id out of form_field_params on the next line.
#
# `.delete` still exists on Parameters in Rails 5. What changed is that Parameters is
# no longer a Hash, so surrounding code that assumed Hash semantics can behave
# differently. These tests assert the two halves separately, so a regression in either
# is attributable.
module Cms
  class FormFieldsControllerTest < ActionController::TestCase
    include Cms::ControllerTestHelper

    def setup
      given_a_site_exists
      login_as_cms_admin
      @form = create(:form, name: "Contact Us")
    end

    def create_field(overrides = {})
      post :create, params: {
        form_field: {
          form_id: @form.id,
          label: 'Email Address',
          field_type: 'text_field'
        }.merge(overrides)
      }
    end

    test "create associates the field with the form named by the deleted form_id" do
      assert_difference 'Cms::FormField.count', 1 do
        create_field
      end

      assert_response :success
      field = Cms::FormField.order(:id).last
      assert_equal @form, field.form,
                   "form_id is pulled out of the params with .delete and used to find " +
                   "the Form; if that stops working the field is orphaned"
    end

    # The other half of the same line. If `.delete` stopped removing the key, :form_id
    # would fall through into form_field_params and be mass-assigned -- which happens
    # to reach the same result here, so asserting only the association above would not
    # notice. This asserts the removal itself.
    test "create removes form_id from the params it mass-assigns" do
      create_field
      assert_response :success

      refute @controller.params[:form_field].key?(:form_id),
             "form_field_params is built from params[:form_field] after the delete, so " +
             ":form_id must no longer be present"
      refute @controller.params[:form_field].key?('form_id')
    end

    test "create renders the field as json on success" do
      create_field
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal 'Email Address', body['label']
      assert body.key?('edit_path'), "as_json should include the edit path"
      assert body.key?('delete_path'), "as_json should include the delete path"
    end

    # The error branch of the same action. Uses the uniqueness validation because it is
    # the only one FormField actually has -- there is no presence validation on :label,
    # so a blank label is accepted and simply produces a field named :"" (the
    # before_validation at form_field.rb:14 does `label.parameterize.underscore.to_sym`).
    # Noted rather than fixed: tightening that is a product decision, not an upgrade one.
    test "create reports validation errors as json rather than raising" do
      create_field
      assert_response :success

      assert_no_difference 'Cms::FormField.count' do
        create_field   # same label, same form -> fails the uniqueness scope
      end
      assert_response :unprocessable_entity

      body = JSON.parse(response.body)
      assert body['errors'].any?, "expected validation errors in the json body"
    end

    test "new builds an unsaved field for the requested form and type" do
      get :new, params: {form_id: @form.id, field_type: 'text_field'}

      assert_response :success
      field = assigns(:field)
      assert field.new_record?, "new should not persist the field"
      assert_equal @form.id, field.form_id
      assert_equal 'text_field', field.field_type
    end
  end
end
