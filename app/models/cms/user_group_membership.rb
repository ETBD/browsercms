module Cms
  class UserGroupMembership < ActiveRecord::Base

    extend Cms::DefaultAccessible

    belongs_to :group, :class_name => 'Cms::Group', :required => false
    belongs_to :user, :class_name => 'Cms::PersistentUser', :required => false
  end
end