module Cms
  module Behaviors
    module Categorizing
      def self.included(model_class)
        model_class.extend(MacroMethods)
      end
      module MacroMethods      
        def belongs_to_category?
          !!@belongs_to_category
        end
        def belongs_to_category
          @belongs_to_category = true
          extend ClassMethods
          include InstanceMethods
          
          # Categorising is opt-in per instance -- nil is the normal state. required: false
          # rather than optional: true because :optional is not valid on 4.2. See
          # test/unit/belongs_to_optionality_test.rb.
          belongs_to :category, :class_name => 'Cms::Category', :required => false
          
          scope :in_category, lambda{|cat| {:conditions => ["category_id = ?", cat.id]}}
          
        end
      end
      module ClassMethods
      end
      module InstanceMethods
        def category_name
          category && category.name
        end
      end
    end
  end
end