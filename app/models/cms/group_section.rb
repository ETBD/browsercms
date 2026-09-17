module Cms
  class GroupSection < ActiveRecord::Base

    extend DefaultAccessible

    belongs_to :group, :class_name => 'Cms::Group', :required => false
    belongs_to :section, :class_name => 'Cms::Section', :required => false
  end
end