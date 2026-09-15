require 'test_helper'

class Cms::TasksControllerTest < ActionController::TestCase
  include Cms::ControllerTestHelper

  def setup
    @admin = login_as_cms_admin

    @task = create(:task, :assigned_to=>@admin)
  end

  def test_complete_task
    task = Cms::Task.find_by_id_and_assigned_to_id(@task.id, @admin.id)
    assert_instance_of Cms::Task, task, "This test depends on there being a task to complete"
    assert !task.completed?

    put :complete, params: {:id => @task.id}
    assert_response :redirect
    assert_redirected_to task.page.path
    assert_equal "Task was marked as complete", flash[:notice]

    task.reload
    assert task.completed?
  end


  def test_complete_multiple_tasks
    @task2 = create(:task, :assigned_to=>@admin)
    ids = [@task.id, @task2.id]
    tasks = Cms::Task.where(["assigned_to_id = ?", @admin.id]).to_a
    assert_equal 2, tasks.length, "This test depends on there being 2 tasks to complete"
    assert !tasks.detect {|t| t.completed?}

    # should update all tasks in the ids list
    put :complete, params: {:task_ids => ids}
    assert_response :redirect
    assert_redirected_to dashboard_path
    assert_equal "Tasks marked as complete", flash[:notice]

    tasks.each do |t|
      t.reload
      assert t.completed?
    end

    # if empty list is passed, should gracefully claim to have completed them all
    put :complete, params: {:task_ids => []}
    assert_response :redirect
    assert_redirected_to dashboard_path
    assert_equal "Tasks marked as complete", flash[:notice]
  end

  def test_complete_no_tasks
    put :complete, params: {:task_ids => nil}
    assert_response :redirect
    assert_redirected_to dashboard_path
    assert_equal "No tasks were marked for completion", flash[:error]
  end

  # Phase 4, stage B.3. The test above passed on 4.2 and failed on 5.0, which read
  # like a Rails 5 incompatibility. It was not:
  #
  #   4.2  `params: {task_ids => nil}` arrives as nil   -- falsy, else branch taken
  #   5.0  the same line arrives as ""                  -- truthy, if branch taken,
  #                                                        "" handed to Postgres as
  #                                                        an integer, 500
  #
  # That is a difference in how the *test harness* serializes nil, not in the
  # application. A real request with `?task_ids=` sends "" on BOTH versions, and
  # before the fix both raised PG::InvalidTextRepresentation -- verified by running
  # this exact test with "" on each bundle. So `if params[:task_ids]` was a live
  # 500 on the shipping 4.2 bundle, and 5.0's harness happened to exercise it.
  #
  # This test sends the blank explicitly, so it does not depend on harness
  # behaviour and means the same thing on both bundles. The guard is now
  # `.present?` -- blank is treated as absent, which is what the controller's own
  # else branch already assumed.
  def test_complete_with_blank_task_ids
    put :complete, params: {:task_ids => ""}
    assert_response :redirect
    assert_redirected_to dashboard_path
    assert_equal "No tasks were marked for completion", flash[:error]
  end

  private
  # Rails engine paths still don't seem to want to load.
  def dashboard_path
    "/cms/dashboard"
  end
end