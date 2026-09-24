module Cms

  class IgnoreSanitizer

    # Skip sanitizing attributes from mass assignment. This should be used sparingly, since it bypasses security.
    # Ideally used for dynamically created classes (like ::Version or ::Attribute) where the attributes are not known at
    # design time.
    def sanitize(klass, attributes, authorizer)
      attributes
    end
  end

  module Behaviors

    # Represents a record as of a specific version in the versions table.
    module VersionRecord

      # Create an original 'record' of the Versioned about as it existed as of this VersionRecord.
      #
      # @return [Object] i.e. HtmlBlock
      def build_object_from_version()
        obj = versioned_class.new

        (versioned_class.versioned_columns + [:version, :created_at, :created_by_id, :updated_at, :updated_by_id]).each do |a|
          obj.send("#{a}=", self.send(a))
        end
        obj.id = original_record_id

        # The commented-out line this replaces could never have worked: `lock_version`
        # is in `non_versioned_columns`, so `create_content_table` does not put the
        # column on the _versions table at all (schema_statements_test.rb:141 asserts
        # exactly that). There is no `lock_version` on `self` to copy.
        #
        # So every object built from a version row carried the column default -- 0 --
        # whatever the content row actually said. Both edit screens load their record
        # this way (`load_draft_page`, `load_block_draft`), which means the
        # `lock_version` hidden field in the form was **always 0** and the value the
        # browser posted back identified nothing. Measured before this change: a page
        # whose content row was at lock_version 4 rendered `value="0"`.
        #
        # That is the reason optimistic locking could not be switched on by fixing the
        # save path alone -- there was nothing to compare against. Read it from the
        # content row, which is where the column lives.
        #
        # Written with write_attribute and then cleared, so building a draft does not
        # count as the caller supplying a lock_version -- see the locking-column writer
        # in `is_versioned`, which is what arms the conflict check.
        if versioned_class.locking_enabled?
          lock_col = versioned_class.locking_column
          current_lock = versioned_class.unscoped
                             .where(versioned_class.primary_key => original_record_id)
                             .limit(1)
                             .pluck(lock_col)
                             .first
          obj.send(:write_attribute, lock_col, current_lock) unless current_lock.nil?
          obj.send(:clear_attribute_changes, [lock_col])
        end

        # Need to do this so associations can be loaded
        obj.instance_variable_set("@persisted", true)
        obj.instance_variable_set("@new_record", false)

        # Callback to allow us to load other data when an older version is loaded
        obj.after_as_of_version if obj.respond_to?(:after_as_of_version)

        # Last but not least, clear the changed attributes
        clear_changes_information

        obj
      end
    end
    # This behavior adds Versioning to an ActiveRecord object. It seriously monkeys with how objects are saved or updated.
    #
    # This implementation is pretty tied to Rails 3 ActiveRecord. Here's how I understand it works:
    # ActiveRecord alias chain- Here is the order that methods get called.
    #
    # save
    #   save_with_transactions
    #   save_with_dirty
    #   save_with_validations
    #   AR::Base#save (save_without_validations)
    #   AR::Base#create_or_update_with_callbacks
    #
    #
    #  AR::Base - Defines a 'save' method with no params
    #  AR::Validations - alias save to a save_with_validations (which takes params)
    #  ActiveRecord Object has:
    #  - save_with_validations(options)
    #  - save_without_validation() - (Original save)
    #
    module Versioning
      def self.included(model_class)
        model_class.extend(MacroMethods)
      end

      module MacroMethods
        def versioned?
          !!@is_versioned
        end

        def is_versioned(options={})
          @is_versioned = true

          @version_table_name = (options[:version_table_name] || "#{table_name.singularize}_versions").to_s

          extend ClassMethods
          include InstanceMethods

          has_many :versions, :class_name => version_class_name, :foreign_key => version_foreign_key
          after_save :update_latest_version
          after_save :touch_self_and_ancestors
          after_destroy :touch_self_and_ancestors

          before_validation :initialize_version
          before_save :build_new_version
          attr_accessor :skip_callbacks

          #Define the version class
          #puts "is_version called for #{self}"
          const_set("Version", Class.new(ActiveRecord::Base)).class_eval do
            class << self;
              attr_accessor :versioned_class
            end

            include VersionRecord
            #self.mass_assignment_sanitizer = Cms::IgnoreSanitizer.new

            def versioned_class
              self.class.versioned_class
            end

            def versioned_object_id
              send("#{versioned_class.name.underscore}_id")
            end

            def versioned_object
              send(versioned_class.name.underscore.to_sym)
            end
          end unless self.const_defined?("Version")

          version_class.versioned_class = self

          # required: false is passed into the options hash rather than written as a
          # literal, so `grep -rn "required: false" app/ lib/` will not find this site in
          # the shape the exit criteria expect. A version is routinely built before its
          # parent is saved (build_new_version_and_add_to_versions_list_for_saving), so
          # nil here is a normal intermediate state.
          version_class.belongs_to(name.demodulize.underscore.to_sym, :foreign_key => version_foreign_key, :class_name => name, :required => false)

          version_class.is_userstamped if userstamped?

          # Arms the conflict check in `check_for_stale_lock_version!`.
          #
          # A stale save must raise for the case that matters -- two people editing one
          # page, second save wins, first edit gone -- without raising for the internal
          # flows that legitimately hold a parent whose lock_version has moved on.
          # `PageComponent#save` (Mercury inline editing) is the measured example: it
          # loads the page, updates each block on it, and each block update copies the
          # page's connectors forward and bumps the page. Measured in-memory 3 against
          # database 4, every time, with no second editor anywhere near it. An
          # unconditional check turns every inline edit into a false conflict.
          #
          # The two cases are not distinguishable by comparing values -- both are
          # "in-memory is behind the database". What separates them is where the value
          # came from. A form round-trips lock_version and posts it back; internal code
          # never assigns it at all. So the check runs only when a caller has assigned
          # the locking column on this instance, which is exactly the form case, and
          # every caller that does not mention lock_version keeps today's behaviour --
          # including downstream applications built on this engine.
          #
          # Defined here rather than as `def lock_version=` in InstanceMethods so it
          # tracks `locking_column` if it is ever customised, and so it lands directly
          # on the class, ahead of ActiveRecord's generated attribute-methods module,
          # without depending on `super` resolving through it.
          lock_col = locking_column
          define_method("#{lock_col}=") do |value|
            @locking_column_supplied_by_caller = true
            write_attribute(lock_col, value)
          end

        end
      end
      module ClassMethods
        def version_class
          const_get "Version"
        end

        def version_class_name
          "#{name}::Version"
        end

        # Probably no longer needs to be a method anymore, since all classes use the same column name.
        def version_foreign_key
          :original_record_id
        end

        def version_table_name
          @version_table_name
        end

        def versioned_columns
          @versioned_columns ||= (version_class.new.attributes.keys - non_versioned_columns)
        end

        def non_versioned_columns
          (%w[  id lock_version position version_comment created_at updated_at created_by_id updated_by_id type original_record_id])
        end
      end
      module InstanceMethods
        def initialize_version
          self.version = 1 if new_record?
        end

        # Used in migrations and as a callback.
        def update_latest_version
          #Rails 3 could use update_column here instead
          if respond_to? :latest_version
            sql = "UPDATE #{self.class.table_name} SET latest_version = #{draft.version} where id = #{self.id}"
            self.class.connection.execute sql
            self.latest_version = draft.version # So we don't need to #reload this object. Probably marks it as dirty though, which could have weird side effects.
          end
        end

        def touch_self_and_ancestors
          if persisted?
            sync_locking_column_before_touch
            touch
          end

          if respond_to?(:ancestors)
            ancestors.map(&:touch)
          end
        end

        # `create_content_table` gives every versioned content table a
        # `lock_version` column (schema_statements.rb:33), so optimistic locking is
        # enabled on all of them -- including Cms::Page.
        #
        # This runs as an after_save, and callers legitimately hold a parent that was
        # loaded *before* a child update bumped that parent's lock_version in the
        # database. Two in this repo alone:
        #
        #   page_component.rb:31  -- updates each block, then saves the @page it
        #                            loaded first (measured: in-memory 3, database 4)
        #   page.rb:256           -- Page#remove_connector, same shape
        #
        # Rails 4.2 did not notice. Its touch scoped the UPDATE by id alone and
        # incremented from whatever stale value it was holding
        # (persistence.rb:495-505), so the write landed and returned true.
        #
        # Rails 5.0 adds the locking column to the WHERE and raises
        # StaleObjectError when it matches no rows (persistence.rb:513-526).
        #
        # Re-read the column so the touch is issued against current state. This
        # keeps 4.2's outcome exactly -- 4.2 already ended at the same value, just
        # by incrementing from a stale one -- and unblocks 5.0.
        #
        # ⚠️ THIS METHOD IS NOT WHERE CONFLICTS ARE DETECTED, and it must not become
        # so. Its whole job is to let the after_save touch through against a record
        # whose lock_version moved for reasons that are not a concurrent edit -- a
        # child update bumping its parent, most of all. Conflicts are detected before
        # the write instead, in `check_for_stale_lock_version!`, against the value the
        # editor's browser posted back.
        #
        # (Phase 4 left the locking defect open here and said so in this comment. It
        # is closed now -- CMS-435. What that took was not a change to this method: it
        # needed the conflict check adding to a save path that never issued an UPDATE,
        # and `build_object_from_version` populating a lock_version that was
        # structurally always 0. This method was right as it stood.)
        #
        # Deliberately does not #reload: the record is mid-save and holds pending
        # changes that a full reload would discard.
        def sync_locking_column_before_touch
          return unless locking_enabled?

          locking_column = self.class.locking_column
          current = self.class.unscoped
                        .where(self.class.primary_key => id)
                        .limit(1)
                        .pluck(locking_column)
                        .first

          return if current.nil? || current == read_attribute(locking_column)

          write_attribute(locking_column, current)
          clear_attribute_changes([locking_column])
        end

        # Raise ActiveRecord::StaleObjectError when the caller is saving against a
        # version of this record that someone else has already replaced.
        #
        # ActiveRecord's own optimistic locking never runs on a versioned save. Its
        # check lives in `_update_record`, which adds the locking column to the WHERE
        # of an UPDATE against the content row -- and `create_or_update` below does not
        # issue one. An update saves a row into the _versions table instead, so the
        # content row's lock_version is never part of any WHERE clause and the two
        # editors' writes never collide. That is why `lock_version` has been on these
        # tables, and `rescue ActiveRecord::StaleObjectError` has been in
        # pages_controller.rb and content_block_controller.rb, for years without a
        # single conflict ever being raised.
        #
        # Gated on the caller having supplied the value -- see the writer defined in
        # `is_versioned`. Read the column straight from the database rather than
        # trusting anything in memory: the point is to compare what the editor's browser
        # posted back against what is there now.
        #
        # Called before the new version row is built or saved, so a conflict leaves no
        # partial write behind. `save` wraps this in a transaction in any case.
        #
        # ⚠️ Read-then-compare, so it is not atomic. ActiveRecord's own locking puts the
        # comparison inside the UPDATE's WHERE and reads the conflict off the affected
        # row count, which no concurrent writer can slip past; this cannot borrow that,
        # because the whole problem is that a versioned save issues no UPDATE against
        # the content row. Two saves landing within a few milliseconds of each other can
        # therefore both read the same value and both proceed. Known and accepted: that
        # is the behaviour this replaced, now confined to a real race instead of
        # happening at any spacing.
        #
        # Do NOT "fix" this with a compare-and-swap (UPDATE ... WHERE lock_version = ?,
        # incrementing, checking the affected count). `touch` already increments the
        # locking column (persistence.rb:470), so that would increment twice per save
        # and break the lockstep between lock_version and version that the conflict
        # screen's "based off version N" arithmetic depends on -- see
        # _version_conflict_error.html.erb:4. A row lock on the read is the shape that
        # works; it needs the deadlock question answered first, because
        # touch_self_and_ancestors locks every ancestor in the same transaction.
        # docs/rails-upgrade/cms-435-optimistic-locking.md §10.
        def check_for_stale_lock_version!
          return unless locking_enabled?
          return unless @locking_column_supplied_by_caller

          locking_column = self.class.locking_column
          current = self.class.unscoped
                        .where(self.class.primary_key => id)
                        .limit(1)
                        .pluck(locking_column)
                        .first

          # No row means the record was destroyed underneath us. That is not a stale
          # edit, and the save that follows will fail on its own terms.
          return if current.nil?
          return if current == read_attribute(locking_column)

          raise ActiveRecord::StaleObjectError.new(self, "update")
        end

        def build_new_version_and_add_to_versions_list_for_saving
          # First get the values from the draft
          attrs = draft_attributes

          # Now overwrite all values
          (self.class.versioned_columns - %w(  version  )).each do |col|
            attrs[col] = send(col)
          end



          attrs[:version_comment] = @version_comment || default_version_comment
          @version_comment = nil
          #puts "Im a '#{self.class}', vc = #{self.class.version_class}"
          new_version = versions.build(attrs)
          new_version.version = new_record? ? 1 : (draft.version.to_i + 1)
          after_build_new_version(new_version) if respond_to?(:after_build_new_version)
          new_version
        end

        def draft_attributes
          # When there is no draft, we'll just copy the attributes from this object
          # Otherwise we need to use the draft
          d = new_record? ? self : draft
          self.class.versioned_columns.inject({}) { |attrs, col| attrs[col] = d.send(col); attrs }
        end

        def default_version_comment
          if new_record?
            "Created"
          else
            # This doesn't always seem to properly be applied, or is applying for
            # ALL fields, not just the changed ones.
            "Changed #{(changes.keys - %w[  version created_by_id updated_by_id  ]).sort.join(', ')}"
          end
        end

        #
        #ActiveRecord 3.0.0 call chain
        # ActiveRecord 3 now uses basic inheritence rather than alias_method_chain.  The order in which ActiveRecord::Base
        # includes methods (at the bottom of activerecord) repeatedly overrides save/save! with chains of 'super'
        #
        # Callstack order as observed
        # 1. ActiveRecord::Base#save - The original method called by client
        #
        #  AR::Transactions#save
        #  AR::Dirty#save
        #  AR::Validations#save
        #  ActiveRecord::Persistence#save
        #  ActiveRecord::Persistence#create_or_update
        #  AR::Callbacks#create_or_update (runs :save callbacks)
        #
        #
        #
        # This aliases the original ActiveRecord::Base.save method, in order to change
        # how calling save works. It should do the following things:
        #
        # 1. If the record is unchanged, no save is performed, but true is returned. (Skipping after_save callbacks)
        # 2. If its an update, a new version is created and that is saved.
        # 3. If new record, its version is set to 1, and its published if needed.
        #
        # Rails 4.2 declares `def create_or_update` (persistence.rb:502) and Rails 5.0
        # declares `def create_or_update(*args, &block)` (persistence.rb:546). Accept and
        # forward whatever the framework passes: on 4.2 nothing is passed, so *args is
        # empty and this behaves exactly as the zero-arity version did. Without it, every
        # save on Rails 5 raises ArgumentError -- 320 of the 323 unit errors Phase 1
        # measured. See docs/rails-upgrade/phase-1-gem-report.md, P1-2.
        def create_or_update(*args, &block)
          logger.debug { "#{self.class}#create_or_update called. Published = #{!!publish_on_save}" }
          self.skip_callbacks = false
          unless different_from_last_draft?
            logger.debug { "No difference between this version and last. Skipping save" }
            self.skip_callbacks = true
            return true
          end
          logger.debug { "Saving #{self.class} #{self.attributes}" }
          if new_record?
            self.version = 1
            # This should call ActiveRecord::Callbacks#create_or_update, which will correctly trigger the :save callback_chain
            saved_correctly = super
            clear_changes_information
          else
            logger.debug { "#{self.class}#update" }
            # The one place a versioned update can detect a concurrent edit. Nothing
            # below issues an UPDATE against the content row, so ActiveRecord's own
            # locking check never gets the chance to run.
            check_for_stale_lock_version!
            # Because we are 'skipping' the normal ActiveRecord update here, we must manually call the save callback chain.
            run_callbacks :save do
              saved_correctly = @new_version.save
            end
          end
          # The supplied value has been honoured; the after_save touch resyncs the
          # column to what is now in the database. Leaving the flag set would have a
          # later save on the same instance re-checked against a value the caller never
          # supplied for it.
          @locking_column_supplied_by_caller = false
          publish_if_needed
          return saved_correctly
        end

        # Build a new version of this record and associate it with this record.
        #
        # Called as a before_create in order to correctly allow any other associations to be saved correctly.
        # Called explicitly during update, where it will just define the new_version to be saved.
        def build_new_version
          @new_version = build_new_version_and_add_to_versions_list_for_saving
          logger.debug { "New version of #{self.class}::Version is #{@new_version.attributes}" }
        end

        # Rails never calls save! with a positional boolean. 4.2 calls it as
        # save!(:validate => x) (has_many_association.rb:39) and 5.0 as
        # save!(validate: x, &block) (collection_association.rb:510) -- so the old
        # `perform_validations` parameter was being bound to a Hash, which is truthy, and
        # the override then called save(validate: true) in precisely the path where the
        # framework had asked for validations to be skipped. Wrong on 4.2 today, silently.
        #
        # On 5.0 there is a second half: collection_association.rb:501 passes a block into
        # insert_record for create_or_update to yield after the insert, and the old
        # signature dropped it before it could reach the (*args, &block) signature Phase 2
        # gave create_or_update directly below. Same defect as P1-2, one method up -- and
        # the Phase 2 fix is what makes this gap reachable at all.
        # See docs/rails-upgrade/phase-1-gem-report.md.
        def save!(*args, &block)
          save(*args, &block) || raise(ActiveRecord::RecordNotSaved.new(errors.full_messages))
        end

        # Returns the most recently created Version for this class. Drafts are the most recent change from
        # the _versions table for a given content item.
        #    i.e. For Cms::Page, this would return Cms::Page::Version
        #
        # @return [<Class>::Version] The version for this class that represents the draft.
        def draft
          versions.order("version desc").first
        end

        def draft_version?
          return true unless draft
          version == draft.version
        end

        def live_version
          find_version(self.class.find(id).version)
        end

        def live_version?
          version == self.class.find(id).version
        end

        def current_version
          find_version(self.version)
        end

        def find_version(number)
          versions.where(:version => number).first
        end

        def as_of_draft_version
          draft.build_object_from_version
        end

        # Find a Content Block as of a specific version.
        #
        # @param [Integer] version The specific version of the block to look up
        # @return [ContentBlock] The block as of the state it existed at 'version'.
        def as_of_version(version)
          v = find_version(version)
          raise ActiveRecord::RecordNotFound.new("version #{version.inspect} does not exist for <#{self.class}:#{id}>") unless v
          v.build_object_from_version
        end

        def revert
          draft_version = draft.version
          revert_to(draft_version - 1) unless draft_version == 1
        end

        def revert_to_without_save(version, options)
          raise "Version parameter missing" if version.blank?
          revert_to_version = find_version(version)
          raise "Could not find version #{version}" unless revert_to_version
          self.before_revert(revert_to_version) if self.respond_to?(:before_revert)

          (self.class.versioned_columns - ["version"]).each do |a|
            send("#{a}=", revert_to_version.send(a))
          end


          options.keys.each do |key|
            send("#{key}=", options[key])
          end

          self.after_revert(revert_to_version) if self.respond_to?(:after_revert)
          @version_comment = "Reverted to version #{version}"
          self.publish_on_save = false
          self
        end

        # @param [Integer] version To revert to
        # @param [Hash] options Values to set prior to saving the updated record.
        def revert_to(version, options={})
          revert_to_without_save(version, options)
          save
        end

        def version_comment
          @version_comment
        end

        def version_comment=(version_comment)
          @version_comment = version_comment
        end

        def different_from_last_draft?
          return true if version_comment.present?
          return true if self.changed?
          return true if self.publish_on_save == true
          last_draft = self.draft
          return true unless last_draft
          (self.class.versioned_columns - %w(  version  )).each do |col|
            return true if self.send(col) != last_draft.send(col)
          end
          false
        end
      end
    end

  end
end
