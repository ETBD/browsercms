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

end
