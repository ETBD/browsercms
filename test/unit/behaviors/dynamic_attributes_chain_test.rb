require 'test_helper'

# Phase 4, stage H -- work item 4.7 / Tier B B2.
# Docs: docs/rails-upgrade/phase-4-implementation-plan.md
#
# dynamic_attributes.rb is 387 lines against 73 lines of test -- the worst
# test-to-source ratio in the engine -- and what it does is replace ActiveRecord's
# attribute chain by alias_method:
#
#   dynamic_attributes.rb:190-198
#     alias_method :method_missing,  :method_missing_with_dynamic_attributes
#     private
#     alias_method :read_attribute,  :read_attribute_with_dynamic_attributes
#     alias_method :write_attribute, :write_attribute_with_dynamic_attributes
#
# Every model built by `Cms::Portlet.inherited` gets this, so it is on every portlet
# in every installation.
#
# WHAT IS ALREADY COVERED
#
# dynamic_attributes_test.rb asserts the happy path: setting an undeclared property,
# persisting strings and integers, `attributes=`, and construction-time assignment.
# This file does not repeat any of that. It covers the chain itself -- the parts where
# the aliases and ActiveRecord disagree, which is where a Rails hop lands.
#
# WHAT IT FOUND
#
# Three disagreements, all of which behave identically on 4.2 and 5.0 and none of
# which is caused by the upgrade:
#
#   1. `read_attribute` and `write_attribute` become PRIVATE, and calling them
#      returns nil instead of raising.
#   2. `_read_attribute` -- the method ActiveRecord itself uses -- is not aliased at
#      all, so it never sees a dynamic attribute.
#   3. `nonversioned_class` raises FrozenError in the one case it exists to handle.
#
# All three are characterized, not fixed. Each is explained at its test.
ActiveRecord::Base.connection.instance_eval do
  drop_table(:chain_things) if table_exists?(:chain_things)
  drop_table(:chain_thing_attributes) if table_exists?(:chain_thing_attributes)
  create_table(:chain_things) do |t|
    t.string :name
    t.timestamps null: true
  end
  create_table(:chain_thing_attributes) do |t|
    t.integer :chain_thing_id
    t.string :name
    t.text :value
  end
end

# Top level, like `Thing` in dynamic_attributes_test.rb: namespaces_test.rb enumerates
# constants under `Cms` and would treat a test-only model as engine surface.
class ChainThing < ActiveRecord::Base
  has_dynamic_attributes
end

class DynamicAttributesChainTest < ActiveSupport::TestCase

  def setup
    @thing = ChainThing.create!(name: "Real Column")
    @thing.price = 42
    @thing.save!
    @reloaded = ChainThing.find(@thing.id)
  end

  # ---------------------------------------------------------------------------
  # The paths that work, and that nothing asserted
  # ---------------------------------------------------------------------------

  # `Model#[]` calls read_attribute with an implicit receiver, so it reaches the
  # private alias where an explicit call cannot. This is why the engine works despite
  # the characterization below: everything internal uses the implicit form.
  test "[] reads a dynamic attribute and a real column alike" do
    assert_equal "42", @reloaded['price']
    assert_equal "Real Column", @reloaded['name']
  end

  test "[]= writes a dynamic attribute that survives save and reload" do
    @reloaded['price'] = 99
    @reloaded.save!

    assert_equal "99", ChainThing.find(@thing.id)['price'],
                 "the []= path goes through write_attribute_with_dynamic_attributes " +
                 "and then save_modified_dynamic_attributes (dynamic_attributes.rb:266)"
  end

  test "assign_attributes sets dynamic attributes and real columns in one call" do
    @reloaded.assign_attributes(price: 7, name: "Renamed")
    @reloaded.save!

    fresh = ChainThing.find(@thing.id)
    assert_equal "7", fresh.price, "the dynamic half"
    assert_equal "Renamed", fresh.name, "the real-column half, in the same call"
  end

  # dynamic_attributes.rb:235 overrides assign_attributes with `(new_attributes,
  # options = {})`. 4.2's signature is `assign_attributes(new_attributes)` and 5.0's is
  # the same, so the extra parameter is harmless today -- but it means the override
  # silently accepts a call shape ActiveRecord would reject, and a future signature
  # change lands on this method rather than on Rails'.
  test "a dynamic attribute is absent from #attributes" do
    refute @reloaded.attributes.key?('price'),
           "dynamic attributes live in a separate table and are not columns. Anything " +
           "iterating #attributes -- serializers, the version builder, form helpers -- " +
           "will not see them, which is the design, not a defect."
    assert @reloaded.attributes.key?('name')
  end

  # ---------------------------------------------------------------------------
  # CHARACTERIZATION 1: has_dynamic_attributes makes read_attribute private, and
  # calling it answers nil rather than raising.
  #
  # The cause is NOT the `private` on dynamic_attributes.rb:193, which is where it
  # looks. `alias_method` ignores the current default visibility and copies the
  # visibility of the method being aliased:
  #
  #     module M; private; def secret; end; end
  #     class C; include M; alias_method :pub, :secret; end
  #     C.new.respond_to?(:pub)   # => false
  #
  # So line 193 does nothing at all, and the aliases are private because their targets
  # are: `read_attribute_with_dynamic_attributes` is defined at line 284, after the
  # module-level `private` on **line 261**. Verified by sabotage -- removing line 193
  # changes nothing and these tests stay green; removing line 261 turns them red.
  # Worth stating because the misleading line is the one a reader will reach for.
  #
  # The effect either way: on any model with dynamic attributes `read_attribute` and
  # `write_attribute` stop being public API, while on every other ActiveRecord model
  # they remain public, as Rails documents them.
  #
  # The second half is what makes it dangerous. An explicit-receiver call to a private
  # method raises NoMethodError, and method_missing_with_dynamic_attributes
  # (dynamic_attributes.rb:327) rescues NoMethodError and treats the method name as the
  # name of a dynamic attribute. So `record.read_attribute('price')` is answered as
  # "the dynamic attribute called read_attribute", which does not exist:
  #
  #     record.read_attribute('price')   # => nil, no error
  #     record['price']                  # => "42"
  #
  # Nothing in the engine calls either with an explicit receiver
  # (`grep -rn "\.read_attribute(\|\.write_attribute(" app/ lib/` is empty), which is
  # why this has never surfaced. A downstream project or a gem doing so gets nil.
  #
  # NOT FIXED. Making these public again changes the public surface of every portlet
  # class in every installation, and the nil-instead-of-raise behaviour is a property of
  # method_missing rescuing NoMethodError -- narrowing that is the same decision as
  # narrowing `publish`'s `rescue Exception`, characterized in publishing_sql_test.rb.
  # Both are failure-handling design, not upgrade work.
  # ---------------------------------------------------------------------------

  test "CHARACTERIZATION: read_attribute is public on an ordinary model and private here" do
    assert Cms::HtmlBlock.new.respond_to?(:read_attribute),
           "ActiveRecord's read_attribute is public API"
    refute @reloaded.respond_to?(:read_attribute),
           "has_dynamic_attributes privatised it -- the alias inherits the visibility " +
           "of read_attribute_with_dynamic_attributes, which is private from " +
           "dynamic_attributes.rb:261"
    refute @reloaded.respond_to?(:write_attribute)
  end

  test "CHARACTERIZATION: read_attribute answers nil instead of the value or an error" do
    assert_nil @reloaded.read_attribute('price'),
               "not the value, and not a NoMethodError -- method_missing rescued the " +
               "private-method error and looked up a dynamic attribute named " +
               "'read_attribute'"
    assert_nil @reloaded.read_attribute('name'),
               "a real column answers nil through this path too, which is the clearer " +
               "statement of the problem"
    assert_equal "42", @reloaded['price'],
                 "while the implicit-receiver path is correct throughout"
  end

  # ---------------------------------------------------------------------------
  # CHARACTERIZATION 2: _read_attribute is not aliased.
  #
  # B2 asks whether `read_attribute` **and** `_read_attribute` both resolve dynamic
  # attributes. `_read_attribute` is the method ActiveRecord calls internally -- 5.0's
  # `read_attribute` is a thin wrapper that normalises the name and delegates to it --
  # and dynamic_attributes.rb aliases only the wrapper.
  #
  # Benign today: `_read_attribute` reads the loaded attribute set, and a dynamic
  # attribute is not in it, so Rails never asks it for one. It is recorded because the
  # asymmetry is invisible and the direction of travel is against it -- each release
  # moves more internals onto the underscore form. The day something in Rails resolves
  # a portlet attribute through it, portlets go blank with no error.
  # ---------------------------------------------------------------------------
  test "CHARACTERIZATION: _read_attribute does not see dynamic attributes" do
    assert @reloaded.respond_to?(:_read_attribute, true),
           "precondition: both bundles have it"

    assert_equal "Real Column", @reloaded.send(:_read_attribute, 'name'),
                 "real columns resolve, so the method itself is working"
    assert_nil @reloaded.send(:_read_attribute, 'price'),
               "the dynamic attribute does not. Only `read_attribute` was aliased " +
               "(dynamic_attributes.rb:195-196); `_read_attribute` was not."
  end

  # ---------------------------------------------------------------------------
  # CHARACTERIZATION 3: nonversioned_class raises in the only case it exists for.
  #
  #     def nonversioned_class(kls)                     # dynamic_attributes.rb:376
  #       if kls.name =~ /\:\:Version$/
  #         base_class = kls.name
  #         base_class.sub!(/\:\:Version$/, '')         # <- mutates kls.name itself
  #         return base_class.constantize
  #       end
  #       kls
  #     end
  #
  # `base_class` is not a copy -- it is the string `Class#name` returned, and `sub!`
  # mutates it in place. Since Ruby 2.7 that string is frozen, so this raises
  # FrozenError. Before it was frozen it would have mutated the class's own name.
  #
  # The guard clause is the whole point of the method: `dynamic_options`
  # (dynamic_attributes.rb:371) calls it so that a Version record can find its parent's
  # dynamic-attribute configuration. That branch cannot execute.
  #
  # Unreachable in this engine -- portlets are the only dynamic-attributes model and
  # portlet.rb:42 declares `acts_as_content_block(versioned: false)`, so no
  # Portlet::Version exists. A downstream project that combines has_dynamic_attributes
  # with is_versioned reaches it immediately.
  #
  # NOT FIXED. `kls.name.dup` or `kls.name.sub` is a one-word fix, but it turns a
  # raise into a code path that has never run anywhere, on a model shape this engine
  # does not have and cannot test end to end. Phase 4 characterizes; making that branch
  # work is a feature.
  # ---------------------------------------------------------------------------

  test "nonversioned_class returns an ordinary class unchanged" do
    assert_equal ChainThing, @reloaded.send(:nonversioned_class, ChainThing)
  end

  test "CHARACTERIZATION: nonversioned_class raises on the Version class it is for" do
    error = assert_raises(FrozenError) do
      @reloaded.send(:nonversioned_class, Cms::HtmlBlock::Version)
    end
    assert_match(/can't modify frozen String/, error.message)

    assert_equal "Cms::HtmlBlock::Version", Cms::HtmlBlock::Version.name,
                 "and the class's own name survived -- which it would not have before " +
                 "Ruby froze it, since sub! would have renamed the class in place"
  end

  # ---------------------------------------------------------------------------
  # CHARACTERIZATION 4: respond_to? disagrees with method_missing.
  #
  # method_missing_with_dynamic_attributes answers any attribute name, but
  # `respond_to_missing?` is never implemented, so `respond_to?` says no to a method
  # the object will happily answer. Anything that asks before calling gets nothing:
  # `try`, `as_json`, form builders, serializers, and `delegate ... allow_nil`.
  #
  # NOT FIXED. A `respond_to_missing?` that returns true for a dynamic attribute would
  # have to return true for *every* name -- dynamic attributes have no declared set,
  # which is the point of them -- and an object that claims to respond to everything
  # breaks more than it fixes. Making this coherent means declaring the attributes,
  # which is a redesign.
  # ---------------------------------------------------------------------------
  test "CHARACTERIZATION: respond_to? says no to a dynamic attribute that works" do
    assert_equal "42", @reloaded.price, "precondition: method_missing answers it"

    refute @reloaded.respond_to?(:price),
           "respond_to_missing? is not implemented (dynamic_attributes.rb has no " +
           "definition of it), so respond_to? and method_missing disagree"
    refute @reloaded.respond_to?(:price=)

    assert_nil @reloaded.try(:price),
               "this is the consequence that bites: try consults respond_to? first, " +
               "so it returns nil for an attribute that is right there"
  end
end
