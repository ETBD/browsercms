require 'test_helper'

module Cms
  class InlineContentControllerTest < ActionController::TestCase

    test "filter html from page_title" do
      assert_equal "Remove", Rails::Html::FullSanitizer.new.sanitize("<p>Remove</p>")
    end
  end
end
