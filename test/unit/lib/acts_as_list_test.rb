require 'test_helper'

# CMS-434 fallout -- the Symbol form of `acts_as_list :scope`.
#
# WHY THIS FILE EXISTS
#
# Nothing in the suite has ever targeted lib/acts_as_list.rb. Every branch it had was
# reached incidentally, by the three models that declare it doing other things, and
# that was enough to cover the macro's two spellings of :scope:
#
#   Cms::Connector     (connector.rb:10)    String scope -- the else branches
#   Cms::SectionNode   (section_node.rb:26) default scope "1 = 1" -- ditto
#   Cms::FormField                          Symbol scope -- the then branches
#
# Removing the Forms subsystem took Cms::FormField with it, and with it the only
# caller in the engine that passes a Symbol. Measured: acts_as_list.rb went 29/46
# branches to 27/46, the two lost being acts_as_list.rb:35 (append `_id` to a bare
# symbol) and acts_as_list.rb:38 (generate the Symbol form of `scope_condition`).
#
# The code is still shipped and still documented in the macro's own comment
# (acts_as_list.rb:26-30), and downstream applications built on this engine use it.
# Untested, not unreachable -- so it gets a test rather than a deletion.
#
# WHAT IS ACTUALLY AT RISK HERE
#
# `scope_condition` is built by string interpolation and spliced raw into a WHERE
# clause (`higher_item`, `lower_item`, `bottom_item`). A change to the generated text
# is a change to SQL, and the only thing that catches a malformed one is a query that
# runs. So the behavioural tests below create real rows rather than asserting on the
# generated string alone.

# Top level, not under `Cms`, deliberately: namespaces_test.rb enumerates the
# constants in that namespace at load time and would adopt a test-only model as
# engine surface. Same reasoning as publishing_sql_test.rb.
ActiveRecord::Base.connection.instance_eval do
  drop_table(:scoped_list_items) if table_exists?(:scoped_list_items)
  create_table(:scoped_list_items) do |t|
    t.integer :todo_list_id
    t.integer :position
  end
end

# The documented spelling: a bare association name, which the macro turns into
# `todo_list_id` at acts_as_list.rb:35.
class ScopedListItem < ActiveRecord::Base
  self.table_name = 'scoped_list_items'
  acts_as_list :scope => :todo_list
end

# The same scope written out. This one skips acts_as_list.rb:35 (the name already ends
# in `_id`) and must arrive at an identical condition -- the regression it guards
# against is a fix to the `_id` logic that produces `todo_list_id_id`.
class PreSuffixedScopedListItem < ActiveRecord::Base
  self.table_name = 'scoped_list_items'
  acts_as_list :scope => :todo_list_id
end

class ActsAsListTest < ActiveSupport::TestCase

  def teardown
    ScopedListItem.delete_all
  end

  # ---------------------------------------------------------------------------
  # The generated condition (acts_as_list.rb:38-45)
  # ---------------------------------------------------------------------------

  test "a Symbol scope generates a condition naming the foreign key" do
    item = ScopedListItem.new(:todo_list_id => 7)
    assert_equal "todo_list_id = 7", item.scope_condition
  end

  test "a Symbol scope generates IS NULL rather than `= ` when the key is nil" do
    item = ScopedListItem.new(:todo_list_id => nil)
    # The nil arm exists because the interpolated form would emit `todo_list_id = `
    # and take down every query the condition is spliced into.
    assert_equal "todo_list_id IS NULL", item.scope_condition
  end

  test "`_id` is appended once, whether or not the caller wrote it" do
    assert_equal ScopedListItem.new(:todo_list_id => 7).scope_condition,
                 PreSuffixedScopedListItem.new(:todo_list_id => 7).scope_condition,
                 "acts_as_list.rb:35 appends `_id` only when the symbol does not " +
                 "already end in it. Doubling it would scope on a column that does " +
                 "not exist."
  end

  # ---------------------------------------------------------------------------
  # The condition in a real query -- what a String-scoped caller cannot prove
  # ---------------------------------------------------------------------------

  test "positions are numbered within a scope, not across the table" do
    first_in_one = ScopedListItem.create!(:todo_list_id => 1)
    second_in_one = ScopedListItem.create!(:todo_list_id => 1)
    first_in_two = ScopedListItem.create!(:todo_list_id => 2)

    # before_create -> add_to_list_bottom -> next_position_in_list -> bottom_item,
    # which is where scope_condition reaches the database.
    assert_equal 0, first_in_one.position
    assert_equal 1, second_in_one.position
    assert_equal 0, first_in_two.position,
                 "a second list must start its own numbering. Sharing one sequence " +
                 "means the scope was not applied."
  end

  test "neighbour lookups do not cross the scope" do
    top = ScopedListItem.create!(:todo_list_id => 1)
    bottom = ScopedListItem.create!(:todo_list_id => 1)
    other_list = ScopedListItem.create!(:todo_list_id => 2)

    assert_equal bottom, top.lower_item
    assert_equal top, bottom.higher_item
    assert_nil other_list.lower_item,
               "other_list is alone in list 2. A neighbour here means the WHERE " +
               "clause lost its scope and the whole table is one list."
    assert_nil other_list.higher_item
  end

  test "moving an item renumbers only its own list" do
    top = ScopedListItem.create!(:todo_list_id => 1)
    bottom = ScopedListItem.create!(:todo_list_id => 1)
    untouched = ScopedListItem.create!(:todo_list_id => 2)

    bottom.move_to_top

    assert_equal 0, bottom.reload.position
    assert_equal 1, top.reload.position
    assert_equal 0, untouched.reload.position,
                 "increment_positions_on_higher_items runs an UPDATE built from " +
                 "scope_condition. An unscoped one would push list 2 down too."
  end
end
