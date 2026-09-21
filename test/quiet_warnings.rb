# Minitest sets `Warning[:deprecated] = true` (minitest-5.19.0/lib/minitest.rb), which
# switches Ruby's deprecation category back on for every suite regardless of the
# `t.warning = false` on each Rake::TestTask. That is ~650 lines per full run, and all
# but a handful come from inside gems: Rails 4.2 tripping Ruby 2.7 deprecations in code
# we do not own and cannot fix before the Rails 5 hop.
#
# Filtering happens at warn-time rather than by resetting the flag, because minitest
# sets the flag when it loads -- which is after this file, whichever entry point is used.
#
# Only gem-origin warnings are dropped. Anything from browsercms, the dummy app or the
# stdlib still reaches you, which is the point: there is one in our own code right now,
#
#   test/unit/models/sections_test.rb:179: warning: constant ::Fixnum is deprecated
#
# and Fixnum is gone in Ruby 3.2, so it must stay visible.
#
# Two ways to switch the filtering off and see everything:
#
#   VERBOSE_WARNINGS=1                -- the short local form
#   RUBYOPT='-W:deprecated'           -- asking Ruby for the warnings directly
#
# The second is what CI already does. .github/workflows/ci.yml sets
# `RUBYOPT: '-W:deprecated'` on the 4.2 `test` job specifically to surface Ruby-level
# deprecations, so keying off it means this filter cannot quietly undo that: if you have
# asked Ruby for the warnings, you get all of them. The `next-rails` job does not set it,
# which is unchanged from before this file existed -- Ruby-level warnings were never
# enabled there.
unless ENV['VERBOSE_WARNINGS'] || ENV['RUBYOPT'].to_s.include?('-W:deprecated')
  module QuietGemWarnings
    def warn(message, *args, **kwargs)
      return if message.to_s.include?('/gems/')

      # Ruby 2.7 warns when an empty kwargs splat is forwarded, which would make this
      # filter a source of the noise it exists to remove.
      kwargs.empty? ? super(message, *args) : super
    end
  end

  Warning.extend(QuietGemWarnings)
end
