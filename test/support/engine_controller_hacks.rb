# Rewrite test methods to avoid need to repeat :use_route => :cms in EVERY functional test call
# See http://edgeguides.rubyonrails.org/engines.html#testing-an-engine for why this would be necessary.
#
# The call sites are written in the Rails 5 keyword form, so these wrappers take
# kwargs and hand them straight to the framework. On the 4.2 bundle the
# KeywordControllerArgs shim in test_helper.rb is what turns that back into the
# three positional slots -- this module deliberately does not do that itself, so
# there is exactly one place that knows about the 4.2/5.0 calling-convention
# difference.
#
# NOTE: `use_route` is deprecated on 4.2 and *removed* on 5.0, where it would
# reach the controller as an ordinary request parameter instead of being
# consumed. It is a route *name* hint into the application's route set
# (@routes.path_for(options, :cms)), not a route-set swap, so the documented
# replacement -- @routes = Cms::Engine.routes -- is not equivalent: the
# dummy app's own controllers (dummy/sample_blocks) are not in the engine's
# route set and stop resolving. Untangling that is a Rails 5 blocker in its own
# right and is out of scope for the harness migration. See
# docs/rails-upgrade/phase-2-harness-report.md.
module EngineControllerHacks
  %w(get post put patch delete head).each do |verb|
    define_method(verb) do |action, **kwargs|
      super(action, **with_engine_route(kwargs))
    end
  end

  private

  def with_engine_route(kwargs)
    params = (kwargs[:params] || {}).dup
    if params[:use_route] == false
      params.delete(:use_route)
    else
      params[:use_route] = :cms
    end
    kwargs.merge(params: params)
  end
end

ActionController::TestCase.send(:include, EngineControllerHacks)
