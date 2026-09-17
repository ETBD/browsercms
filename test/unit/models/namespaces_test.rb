
# This test is to verify that for all of our namespaced objects that the named reflections are valid.  
# Mostly to ensure that :class_name is set where needed.

require 'test_helper'

class NamespacesTest < ActiveSupport::TestCase
  
  
  # Fetches all of the subclasses from a given module by grabbing the defined constants
  # and seeing if they are a Class or something else.  Does not check to see if it is an 
  # AR class or if it has a blueprint.
  def self.subclasses_from_module(module_name)
    subclasses = []
    mod = module_name.constantize
    if mod.class == Module
      mod.constants.each do |module_const_name|
        begin
          klass_name = "#{module_name}::#{module_const_name}"
          klass = klass_name.constantize
          if klass.class == Class
            subclasses << klass
            # Rails 4.2's Class#descendants also yields singleton classes (the
            # guard for that wasn't added until Rails 5). They are never valid
            # targets here, and calling respond_to? on the singleton class of a
            # Railtie instance raises TypeError, so drop them first.
            descendants = klass.send(:descendants).reject { |x| x.singleton_class? }
            subclasses += descendants.collect{|x| x.respond_to?(:constantize) ? x.constantize : x}
          else
            subclasses += subclasses_from_module(klass_name)
          end
        rescue NameError
          raise $!
          puts $!.inspect
        end
      end
    end
    return subclasses
  end
  
  # If you want to test more namespaces add them here.
  classes = []
  classes += subclasses_from_module("Cms")
  classes.uniq!
  
  classes.each do |klass|
    test "ensure a #{klass.name} has valid reflections" do
      if klass.kind_of? ActiveRecord::Base
        @obj = klass.new
        klass.reflections.each do |name, reflection|
          assert_nothing_thrown("Error with #{name} reflection") do
            @obj.send(name)
            reflection.klass unless reflection.options[:polymorphic]
          end
        end
      end
    end
  end
  
  
end

