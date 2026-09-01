module Cms
  module Behaviors
    module Userstamping
      def self.included(model_class)
        model_class.extend(MacroMethods)
      end
      module MacroMethods      
        def userstamped?
          !!@is_userstamped
        end
        def is_userstamped(options={})
          @is_userstamped = true
          extend ClassMethods
          include InstanceMethods
        
          # required: false, not optional: true -- :optional is not a valid belongs_to
          # option on Rails 4.2 (ArgumentError at class-definition time); :required is
          # valid on both, and 5.0 normalises it to optional = !required.
          #
          # These two are nil for anything created outside a request -- seeds, rake
          # tasks, migrations, console. This behaviour is injected into every model
          # that stamps users, here and in every downstream project, so a host app
          # turning on load_defaults 5.0 would otherwise start rejecting all of them.
          belongs_to :created_by, :class_name => "Cms::User", :required => false
          belongs_to :updated_by, :class_name => "Cms::User", :required => false
        
          before_save :set_userstamps
        
          scope :created_by, lambda{|user| {:conditions => {:created_by => user}}}
          scope :updated_by, lambda{|user| {:conditions => {:updated_by => user}}}        
        end
      end
      module ClassMethods
      end
      module InstanceMethods
        def set_userstamps
          current_user = Cms::User.current ? Cms::User.current : nil
          if new_record?
            self.created_by = current_user
          end
          self.updated_by = current_user

        end
      end
    end
  end
end
