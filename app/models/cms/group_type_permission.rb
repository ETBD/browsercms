module Cms
  class GroupTypePermission < ActiveRecord::Base
    belongs_to :group_type, :class_name => 'Cms::GroupType', :required => false
    belongs_to :permission, :class_name => 'Cms::Permission', :required => false

    extend DefaultAccessible
  end
end