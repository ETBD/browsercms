module Cms
  class GroupPermission < ActiveRecord::Base

    extend DefaultAccessible

    belongs_to :group, :class_name => 'Cms::Group', :required => false
    belongs_to :permission, :class_name => 'Cms::Permission', :required => false

    validates_uniqueness_of :permission_id, :scope => :group_id

  end
end