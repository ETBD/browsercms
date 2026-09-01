# The suite runs as five separate processes (units, spec, functionals, orphans,
# features) that merge through coverage/.resultset.json. SimpleCov discards any stored
# result older than merge_timeout, which defaults to 600s -- so on a full run,
# which takes longer than that, the earliest suites silently drop out and the
# reported percentage covers only whatever finished inside the window.
SimpleCov.start 'rails' do
  merge_timeout 3600

  # Reported, not gated -- coverage:check prints the branch figure but has no
  # branch floor to compare it against. Phase 3 sets one once there is a
  # measured number to set it from.
  enable_coverage :branch

  # Each suite must name itself. Left to CommandGuesser, two suites can guess the
  # same name and overwrite each other's entry in the resultset. Set by the
  # Rakefile, one prerequisite task per suite.
  command_name ENV['COVERAGE_SUITE'] if ENV['COVERAGE_SUITE']

  # Generator *templates* are copied into a user's application, not executed
  # here. demo.seeds.rb alone is 249 counted lines -- 13.5% of every missed line
  # in the report -- and it is a seed script: loading it would run it.
  #
  # Block filters, not regexes. This was once a hard constraint: SimpleCov 0.12's
  # parse_filter accepted only a String, an Array, a Filter or a block and raised
  # ArgumentError on a Regexp, which defaults.rb rescued around `load .simplecov`
  # -- so a regex filter did not fail loudly, it abandoned the rest of this file
  # with one line on stderr. 0.22 accepts regexes and the constraint is gone; the
  # block form is kept because it works and rewriting it would buy nothing.
  # Match on the absolute path; that is what #filename returns.
  add_filter { |src| src.filename.include?("/lib/generators/") && src.filename.include?("/templates/") }
  add_filter { |src| src.filename.include?("/lib/templates/") }

  # The generator *classes* stay in the denominator. Excluding them was the
  # standing recommendation, on the grounds that the @cli cucumber features
  # cover them out of process where SimpleCov cannot see it. Phase 0 measured
  # those features: 7 of 34 scenarios pass. The 0% is a measurement gap sitting
  # on top of a real testing gap, and hiding it would misreport the second one.
end
