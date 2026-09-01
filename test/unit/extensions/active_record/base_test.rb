require 'minitest_helper'

class ActiveRecord::BaseTest < ActiveSupport::TestCase
  def test_updated_on_string
    base = Cms::HtmlBlock.new
    assert_nil base.updated_on_string
    base.updated_at = Time.zone.parse("1978-07-06")
    assert_equal "Jul 6, 1978", base.updated_on_string
  end
end

# Must use vanilla TestCase to avoid ActiveRecord setup conflicts.
#
# This said `MiniTest::Unit`, which is not a TestCase at all -- it is the
# deprecated compatibility shim class from minitest's legacy unit file, so
# minitest never
# collected these two tests and they have not run in years. The 4.x name the
# author wanted, MiniTest::Unit::TestCase, is Minitest::Test on minitest 5.
# Naming it correctly is what makes them run. See phase-2-harness-report.md.
class TestExtensions < Minitest::Test

  #"If a connection throws an error when established, then we consider the database to not exist."
  def test_throws_error
    ActiveRecord::Base.expects(:connection).raises(StandardError)
    assert_equal false, ActiveRecord::Base.database_exists?
  end

  # "If we can establish a connection, the database exists"
  def test_exists
    assert_equal true, ActiveRecord::Base.database_exists?
  end
end
