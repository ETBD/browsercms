require 'test_helper'

# Phase 4, stage I -- work item 4.7, final bullet ("Tier C fixes with a behavioural
# choice"). Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# Two error branches that no suite has ever executed, and that both had `render text:`
# until Phase 3 converted them to `render plain:` in 70b22bdf.
#
# WHY THIS MATTERS MORE THAN THE BRANCHES THEMSELVES SUGGEST
#
# `render text:` is deprecated at Rails 5.0 and **removed at 5.1**. Phase 3 made the
# conversion correctly, but nothing executed either branch afterwards, so the
# conversion was unverified -- and the two forms are not interchangeable:
#
#     render text:  "Fail"   ->  Content-Type: text/html
#     render plain: "Fail"   ->  Content-Type: text/plain
#
# That is why each test below asserts the **body and the content type**, not just the
# status. A status-only assertion passes against either form and would have told us
# nothing about the thing we actually need to know at 5.1.
#
# These pin 4.2 and pass on the Gemfile bundle unchanged.
module Cms
  # content_block_controller.rb:138. `versions` answers 501 for a content type that is
  # not versioned. Measured: Cms::Category, Cms::Tag, Cms::CategoryType and
  # Cms::Portlet all report `versioned? == false`, all have a registered ContentType,
  # and all have a ContentBlockController subclass -- so the branch is reachable
  # through four routed controllers and had never been taken by a test.
  class NotVersionedVersionsBranchTest < ActionController::TestCase
    tests Cms::CategoriesController
    include Cms::ControllerTestHelper

    def setup
      given_a_site_exists
      login_as_cms_admin
      @category_type = create(:category_type, name: "Colours")
      @category = create(:category, category_type: @category_type, name: "Blue")
    end

    test "versions answers Not Implemented for a content type that is not versioned" do
      refute Cms::Category.versioned?, "precondition: this is the branch under test"

      get :versions, params: {id: @category.id}

      assert_response :not_implemented
      assert_equal "Not Implemented", response.body
      assert_equal "text/plain", response.content_type,
                   "`render text:` would answer text/html here. That form is removed " +
                   "at Rails 5.1, and this assertion is what proves the conversion " +
                   "Phase 3 made actually took."
    end

    # Guards the guard. If `model_class.versioned?` ever answered true for everything,
    # the test above would be asserting a branch nothing reaches, and a versioned type
    # would silently start returning 501 instead of its version list.
    test "versions loads normally for a content type that is versioned" do
      assert Cms::HtmlBlock.versioned?, "precondition"

      block = Cms::HtmlBlock.create!(name: "Versioned", content: "x")
      @controller = Cms::HtmlBlocksController.new
      get :versions, params: {id: block.id}

      assert_response :success
      refute_equal "Not Implemented", response.body
    end
  end

  # form_fields_controller.rb:43. The failure half of `update`. Stage F covered
  # `create` and `new` on this controller; `update` had no test at all, so neither
  # half of its branch had ever run.
  class FormFieldUpdateFailureBranchTest < ActionController::TestCase
    tests Cms::FormFieldsController
    include Cms::ControllerTestHelper

    def setup
      given_a_site_exists
      login_as_cms_admin
      @form = create(:form, name: "Contact Us")
      @taken = Cms::FormField.create!(label: "Email", field_type: "text_field")
      @form.fields << @taken
      @field = Cms::FormField.create!(label: "Phone", field_type: "text_field")
      @form.fields << @field
      @form.save!
    end

    test "update renders the field as json on success" do
      put :update, params: {id: @field.id, form_field: {label: "Mobile"}}

      assert_response :success
      assert_equal "Mobile", JSON.parse(response.body)['label']
    end

    # -------------------------------------------------------------------------
    # CHARACTERIZATION: this branch cannot be reached through the controller.
    #
    # Three independent facts, each verifiable on its own, close every route to it:
    #
    #   1. `:name` is the ONLY validated attribute -- uniqueness scoped to :form_id
    #      (form_field.rb:18). Nothing else on the model can fail.
    #   2. `:name` is assigned by `before_validation(on: :create)` (form_field.rb:14),
    #      so an update never recomputes it from the label. Posting a colliding label
    #      changes the label and leaves the name alone, and validation passes.
    #   3. `:name` is explicitly removed from the permitted list --
    #      `FormField.permitted_params` is `super - [:name]` (form_field.rb:67-69) --
    #      so a request cannot set it directly either.
    #
    # So `field.update form_field_params` always succeeds, and
    # form_fields_controller.rb:43 is dead code.
    #
    # Both of this test's first two drafts were wrong in instructive ways, which is why
    # all three facts are asserted rather than described: a colliding **label** returned
    # 200 (fact 2), and then a colliding **name** also returned 200 (fact 3).
    #
    # NOT FIXED -- and not obviously a defect. Re-deriving :name on update would break
    # existing form entries, which the model says in its own comment at
    # form_field.rb:10-12. The branch may simply be vestigial.
    # -------------------------------------------------------------------------
    test "CHARACTERIZATION: update cannot fail, so the Fail branch is unreachable" do
      assert_equal 1, Cms::FormField.validators.size,
                   "fact 1: :name uniqueness is the only validator"
      refute_includes Cms::FormField.permitted_params, :name,
                      "fact 3: :name cannot be set through a request"

      # fact 2: a colliding label is accepted, because :name does not follow it
      put :update, params: {id: @field.id, form_field: {label: @taken.label}}

      assert_response :success
      assert_equal "Email", @field.reload.label, "the label did change"
      assert_equal "phone", @field.name.to_s, "and the name did not, so nothing collided"
    end

    # The branch is unreachable, but `render plain:` still has to be right, because
    # `render text:` is removed at Rails 5.1 and this is one of the two sites Phase 3
    # converted. Reaching it means making `update` return false, which only a stub can
    # do -- everything after that point is the real render. Same shape as stage G's
    # version-conflict test, and for the same reason.
    test "the Fail branch renders plain text when it is reached" do
      Cms::FormField.any_instance.stubs(:update).returns(false)

      put :update, params: {id: @field.id, form_field: {label: "Anything"}}

      assert_response :internal_server_error
      assert_equal "Fail", response.body
      assert_equal "text/plain", response.content_type,
                   "`render text:` would answer text/html. This assertion is what " +
                   "proves the Phase 3 conversion took, and it is the only thing that " +
                   "will notice if it is reverted."
    end
  end
end
