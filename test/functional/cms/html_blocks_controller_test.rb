require 'test_helper'

module Cms
  class HtmlBlocksControllerTest < ActionController::TestCase
    include Cms::ControllerTestHelper

    def setup
      given_a_site_exists
      login_as_cms_admin
      @block = create(:html_block, :name => "Test", :content => "I worked.", :publish_on_save => true)
    end

    def test_new
      get :new
      assert_response :success
    end

    def test_add_to_page
      @page = create(:page, :path => "/test", :section => root_section)
      get :new, :html_block => {:connect_to_page_id => @page.id, :connect_to_container => "test"}
      assert_response :success
      assert_select "input[name=?][value=?]", "html_block[connect_to_page_id]", @page.id.to_s
      assert_select "input[name=?][value=?]", "html_block[connect_to_container]", "test"
    end

    def test_creating_a_block_that_should_be_connected_to_a_page
      @page = create(:page, :path => "/test", :section => root_section)
      html_block_count = HtmlBlock.count

      post :create, :html_block => FactoryGirl.attributes_for(:html_block).merge(
          :connect_to_page_id => @page.id, :connect_to_container => "test")

      assert_incremented html_block_count, HtmlBlock.count
      assert_equal "test", @page.reload.connectors.first.container
      assert_redirected_to @page.path
    end

    def test_search
      skip("deeper dive needed on why these indexes are not rendering")
      get :index, :search => {:term => 'test'}
      assert_response :success
      assert_select "td", "Test"

      get :index, :search => {:term => 'worked', :include_body => true}
      assert_response :success
      assert_select "td", "Test"
    end

    def test_edit
      get :edit, :id => @block.id
      assert_response :success
      assert_select "input[id=?][value=?]", "html_block_name", "Test"
    end


    def test_update
      html_block_count = HtmlBlock.count
      html_block_version_count = HtmlBlock::Version.count

      put :update, :id => @block.id, :html_block => {:name => "Test V2"}
      reset(:block)

      assert_redirected_to @block
      assert_equal html_block_count, HtmlBlock.count
      assert_incremented html_block_version_count, HtmlBlock::Version.count
      assert_equal "Test V2", @block.draft.name
      assert_equal "Html Block 'Test V2' was updated", flash[:notice]
    end

    def test_versions
      get :versions, :id => @block.id
      assert_response :success
      assert_equal @block, assigns(:block)
    end

    def test_revert_to
      @block.update_attributes(:name => "Test V2", :publish_on_save => false)
      reset(:block)

      put :revert_to, :id => @block.id, :version => "1"
      reset(:block)

      assert_equal 3, @block.draft.version
      assert_equal "Test", @block.reload.name
      assert_equal "Html Block 'Test' was reverted to version 1", flash[:notice]
      assert_redirected_to @block
    end

    def test_revert_to_with_invalid_version_parameter
      @block.update_attributes(:name => "Test V2", :publish_on_save => true)
      reset(:block)

      html_block_version_count = HtmlBlock::Version.count

      put :revert_to, :id => @block.id, :version => 99
      reset(:block)

      assert_equal html_block_version_count, HtmlBlock::Version.count
      assert_equal "Html Block 'Test V2' could not be reverted to version 99", flash[:error]
      assert_redirected_to @block
    end

  end
end
