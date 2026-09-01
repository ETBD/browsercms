module Cms
  class PortletController < Cms::ApplicationController

    # There is deliberately no skip of :redirect_to_cms_site here. That callback is
    # registered only on Cms::BaseController (base_controller.rb:3), which is a
    # sibling of this class, not an ancestor -- so there has never been anything to
    # skip. 4.2's skip_callback silently deleted nil; 5.0 raises ArgumentError.

    def execute_handler
      @portlet = Portlet.find(params[:id])
      @portlet.controller = self

      method = params[:handler]
      if @portlet.class.superclass.method_defined?(method) or @portlet.class.private_method_defined?(method) or @portlet.class.protected_method_defined?(method)
        raise Cms::Errors::AccessDenied
      else
        redirect_to @portlet.send(method)
      end

    end

  end
end

