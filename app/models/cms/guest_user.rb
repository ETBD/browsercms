#
# Guests are a special user that represents a non-logged in user. The main reason to create an explicit
# instance of this type of user is so that the permissions a Guest user can have can be set via the Admin interface.
#
# Every request that a non-logged in user makes will use this User's permissions to determine what they can/can't do.
#
module Cms
  class GuestUser < Cms::User

    def initialize(attributes={})
      super({:login => Cms::Group::GUEST_CODE, :first_name => "Anonymous", :last_name => "User"}.merge(attributes))
      @guest = true
    end

    def able_to?(*name)
      group && group.permissions.where("name in (?)", name.map(&:to_s)).count > 0
    end

    # Guests never get access to the CMS.
    # Overridden from user so that able_to_view? will work correctly.
    def cms_access?
      false
    end

    # Return a list of the sections associated with this user that can be viewed.
    # Overridden from user so that able_to_view? will work correctly.
    def viewable_sections
      group.sections
    end

    def able_to_edit?(section)
      false
    end

    def group
      @group ||= Cms::Group.guest
    end

    def groups
      [group]
    end

    # You shouldn't be able to save a guest user.
    #
    # NOTE: this guard is incomplete, and deliberately left that way for now.
    # `update_attributes` is an *alias*, not the method -- persistence.rb reads
    # `def update(attributes)` … `alias update_attributes update` on both 4.2 (:247/:256)
    # and 5.0 (:270/:279). Overriding the alias name in a subclass leaves `update` bound
    # to the original implementation, so `guest.update(...)` reaches
    # ActiveRecord::Persistence#update and walks straight past this guard. The write still
    # fails, but at `save` below rather than here, and only by luck.
    #
    # Closing it means renaming the definition to `update` and aliasing the old name --
    # a behaviour change, in a phase whose contract is that there are none. Phase 3 chose
    # to leave the hole in place and record it instead. The characterization test is
    # test/unit/models/user_test.rb, GuestUserTest, marked skipped.
    #
    # `save(perform_validation=true)` is a second, separate signature-override bug of the
    # kind Phase 2 fixed on create_or_update: 5.0's save is `save(*args)`, so a keyword
    # hash lands harmlessly in the positional slot. It is not breaking today and will not
    # survive later hops.
    def update_attribute(name, value)
      false
    end

    def update_attributes(attrs={})
      false
    end

    def save(perform_validation=true)
      false
    end

  end
end
