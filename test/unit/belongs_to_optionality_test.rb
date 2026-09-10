require 'test_helper'

# Phase 3, stage B -- the audit test for the belongs_to declarations.
#
# WHAT `belongs_to_required_by_default` ACTUALLY DOES
#
# The flag is read inside ActiveRecord::Associations::Builder::BelongsTo.define_validations
# (activerecord-5.0.7.2/lib/active_record/associations/builder/belongs_to.rb:122), and its
# entire effect is one line:
#
#     model.validates_presence_of reflection.name, message: :required
#
# That runs when `belongs_to` is *called* -- at class-definition time. Two consequences,
# both of which rule out the "force the flag on around a model sweep" design this stage
# was originally scoped with:
#
#   1. Flipping the flag in a setup block cannot retroactively add validations to
#      associations that are already defined. It would be a no-op even on 5.0.
#   2. The accessor does not exist on 4.2 at all -- it arrives at activerecord-5.0.7.2
#      core.rb:117 -- so touching it raises NoMethodError on the bundle in production.
#
# WHY THE DECLARATION IS `required: false`, NOT `optional: true`
#
# `:optional` is not in 4.2's valid_options. 4.2 raises, at class-definition time, from
# Builder::Association#validate_options:
#
#     ArgumentError: Unknown key: :optional. Valid keys are: :class_name, :anonymous_class,
#     :foreign_key, :validate, :autosave, :dependent, :primary_key, :inverse_of, :required,
#     :foreign_type, :polymorphic, :touch, :counter_cache
#
# which takes the whole engine down on the default bundle. `:required` is valid on both,
# and 5.0 normalises it (belongs_to.rb:123): `options[:optional] = !options.delete(:required)`.
# Measured on both bundles:
#
#     4.2   belongs_to :x, required: false  ->  options={:required=>false}, no validator
#     5.0   belongs_to :x, required: false  ->  options={:optional=>true},  no validator
#
# So `required: false` is the only spelling that parses on both, means "nil is allowed"
# on 5.0, and is a provable no-op on 4.2.
#
# THE INVARIANT THIS TEST ENFORCES
#
# Nothing in either bundle turns the flag on (there is no `load_defaults` in this repo;
# the flag is the host application's to set), so the audit cannot be checked by observing
# a behaviour change. What it can be checked against is the claim each site is making:
#
#   :required -- the model already rejects nil here through its own presence validation.
#                Required-by-default would be redundant, so the declaration is left bare
#                and a host app on `load_defaults 5.0` gets behaviour matching the
#                model's stated intent.
#
#   :optional -- nothing rejects nil here today, on either bundle. `required: false` pins
#                that, so a host app on `load_defaults 5.0` keeps it.
#
# Both halves are assertions about the loaded class, so both run on both bundles. The
# test is what makes the audit falsifiable: adding a belongs_to without a verdict fails
# `test_every_belongs_to_is_audited`, and contradicting a verdict fails one of the other
# two.
#
# Phase 4 owns the permanent version of this.
class BelongsToOptionalityTest < ActiveSupport::TestCase

  # Verdict per site. :required means "left bare, backed by an existing presence
  # validation"; :optional means "carries required: false".
  #
  # Keys are "Class#association". The evidence for each is in the comment.
  AUDIT = {
    # --- backed by an existing presence validation: leave bare -----------------
    'Cms::Category#category_type'   => :required,  # category.rb:12   validates_presence_of :category_type_id
    'Cms::Connector#page'           => :required,  # connector.rb:44  validates_presence_of :page_id
    'Cms::Connector#connectable'    => :required,  # connector.rb:44  validates_presence_of :connectable_id, :connectable_type
    'Cms::PageRoute#page'           => :required,  # page_route.rb:26 validates_presence_of :page_id
    'Cms::Task#assigned_by'         => :required,  # task.rb:27       validates_presence_of :assigned_by_id
    'Cms::Task#assigned_to'         => :required,  # task.rb:28       validates_presence_of :assigned_to_id
    'Cms::Task#page'                => :required,  # task.rb:29       validates_presence_of :page_id

    # --- nothing rejects nil today: pin it with required: false ---------------
    'Cms::Category#parent'          => :optional,  # self-referential; every root category has a nil parent
    'Cms::Group#group_type'         => :optional,  # factory :group (factories.rb:74) creates one with no group_type
    'Cms::Attachment#attachable'    => :optional,  # attachment.rb:23 validates attachable_type but NOT attachable_id;
                                                   # the block factories build the attachment first and assign
                                                   # attachable afterwards (factories.rb:52, :68)
    'Cms::Tagging#tag'              => :optional,
    'Cms::Tagging#taggable'         => :optional,  # polymorphic, unvalidated
    'Cms::SectionNode#node'         => :optional,  # polymorphic, unvalidated; a node is built before it is linked
    'Cms::FormEntry#form'           => :optional,
    'Cms::FormField#form'           => :optional,
    'Cms::PageRouteOption#page_route' => :optional,
    'Cms::GroupSection#group'       => :optional,
    'Cms::GroupSection#section'     => :optional,
    'Cms::UserGroupMembership#user'  => :optional,
    'Cms::UserGroupMembership#group' => :optional,
    'Cms::GroupTypePermission#group_type' => :optional,
    'Cms::GroupTypePermission#permission' => :optional,
    'Cms::GroupPermission#group'    => :optional,
    'Cms::GroupPermission#permission' => :optional,
  }.freeze

  # The five behavior-injected declarations. These are not on one class -- they are
  # applied to every model that uses the behavior, in this engine and in every
  # downstream project, which is why they carry the blast radius. Verified here against
  # one consumer each; the enumeration test below also checks them everywhere they land.
  BEHAVIOR_AUDIT = {
    'created_by'  => :optional,  # userstamping.rb:16 -- nil for anything created outside a
    'updated_by'  => :optional,  # userstamping.rb:17    request: seeds, rake tasks, migrations
    'category'    => :optional,  # categorizing.rb:16 -- categorising is opt-in per instance
  }.freeze

  # Classes carrying the literal declarations audited above.
  AUDITED_CLASSES = %w[
    Cms::Category Cms::Connector Cms::PageRoute Cms::Task Cms::Group Cms::Attachment
    Cms::Tagging Cms::SectionNode Cms::FormEntry Cms::FormField Cms::PageRouteOption
    Cms::GroupSection Cms::UserGroupMembership Cms::GroupTypePermission Cms::GroupPermission
  ].freeze

  # `required: false` reads back differently per bundle -- 4.2 keeps the key it was given,
  # 5.0 rewrites it to :optional. Either spelling means the same thing.
  def optional_declared?(reflection)
    reflection.options[:optional] == true || reflection.options[:required] == false
  end

  # Required-by-default validates the *loaded object*, not the foreign key. A model that
  # validates the FK instead is making the same claim by a different route, so both count.
  def rejects_nil?(klass, name)
    [name, :"#{name}_id"].any? do |attribute|
      klass.validators_on(attribute).any? { |v| v.kind == :presence }
    end
  end

  def audited_reflections
    AUDITED_CLASSES.flat_map do |class_name|
      klass = class_name.constantize
      klass.reflect_on_all_associations(:belongs_to).map { |r| [klass, r] }
    end
  end

  def verdict_for(klass, reflection)
    AUDIT["#{klass.name}##{reflection.name}"] || BEHAVIOR_AUDIT[reflection.name.to_s]
  end

  test "every belongs_to on an audited class has a verdict" do
    unaudited = audited_reflections.reject { |klass, r| verdict_for(klass, r) }
    assert unaudited.empty?,
           "belongs_to declarations with no verdict in AUDIT/BEHAVIOR_AUDIT: " +
           unaudited.map { |klass, r| "#{klass.name}##{r.name}" }.join(', ')
  end

  test "every audited site is still declared" do
    live = audited_reflections.map { |klass, r| "#{klass.name}##{r.name}" }
    missing = AUDIT.keys - live
    assert missing.empty?, "AUDIT names associations that no longer exist: #{missing.join(', ')}"
  end

  test "associations judged required are backed by a presence validation" do
    offenders = audited_reflections.select { |klass, r| verdict_for(klass, r) == :required }
                                   .reject { |klass, r| rejects_nil?(klass, r.name) }
    assert offenders.empty?,
           "judged :required but nothing rejects nil -- either add a presence validation " +
           "or change the verdict to :optional: " +
           offenders.map { |klass, r| "#{klass.name}##{r.name}" }.join(', ')
  end

  test "associations judged required are left bare" do
    offenders = audited_reflections.select { |klass, r| verdict_for(klass, r) == :required }
                                   .select { |klass, r| optional_declared?(r) }
    assert offenders.empty?,
           "judged :required but declared required: false: " +
           offenders.map { |klass, r| "#{klass.name}##{r.name}" }.join(', ')
  end

  test "associations judged optional declare required: false" do
    offenders = audited_reflections.select { |klass, r| verdict_for(klass, r) == :optional }
                                   .reject { |klass, r| optional_declared?(r) }
    assert offenders.empty?,
           "judged :optional but not declared required: false -- a host app on " +
           "load_defaults 5.0 would start rejecting nil here: " +
           offenders.map { |klass, r| "#{klass.name}##{r.name}" }.join(', ')
  end

  test "associations judged optional are not contradicted by a presence validation" do
    offenders = audited_reflections.select { |klass, r| verdict_for(klass, r) == :optional }
                                   .select { |klass, r| rejects_nil?(klass, r.name) }
    assert offenders.empty?,
           "declared required: false but the model validates presence anyway -- " +
           "the verdict is wrong: " +
           offenders.map { |klass, r| "#{klass.name}##{r.name}" }.join(', ')
  end

  # The behavior declarations are the ones a reviewer needs to look at properly: they
  # apply to every model using the behavior, here and downstream. Check them where they
  # actually land rather than only on the behavior module.
  test "userstamping and categorizing inject required: false everywhere they apply" do
    consumers = [Cms::Page, Cms::HtmlBlock, Cms::Section]
    offenders = consumers.flat_map { |klass|
      klass.reflect_on_all_associations(:belongs_to)
           .select { |r| BEHAVIOR_AUDIT.key?(r.name.to_s) }
           .reject { |r| optional_declared?(r) }
           .map { |r| "#{klass.name}##{r.name}" }
    }
    assert offenders.empty?, "behavior-injected belongs_to missing required: false: #{offenders.join(', ')}"
  end

  # versioning.rb:115 and dynamic_attributes.rb:168 declare belongs_to dynamically, so
  # `grep -rn "required: false" app/ lib/` finds them in a shape no criterion expects.
  # Assert them through the reflection instead, which is the only place they are visible.
  test "the versioning behavior's version-to-parent association declares required: false" do
    reflection = Cms::HtmlBlock::Version.reflect_on_association(:html_block)
    assert reflection, "Cms::HtmlBlock::Version should belong_to :html_block"
    assert optional_declared?(reflection),
           "versioning.rb:115 must pass required: false into version_class.belongs_to"
  end

  # `required: false` must remain a no-op on 4.2 and must mean optional on 5.0. If this
  # ever stops holding, every verdict above is wrong at once.
  test "required: false adds no presence validation on either bundle" do
    probe = Class.new(ActiveRecord::Base) do
      self.table_name = 'cms_categories'
      belongs_to :parent, class_name: 'Cms::Category', required: false
    end
    assert_equal [], probe.validators_on(:parent).select { |v| v.kind == :presence },
                 "required: false must not add a presence validation"
    assert optional_declared?(probe.reflect_on_association(:parent))
  end
end
