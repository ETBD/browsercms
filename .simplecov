# The suite runs as four separate processes (units, spec, functionals, features)
# that merge through coverage/.resultset.json. SimpleCov discards any stored
# result older than merge_timeout, which defaults to 600s -- so on a full run,
# which takes longer than that, the earliest suites silently drop out and the
# reported percentage covers only whatever finished inside the window.
SimpleCov.start 'rails' do
  merge_timeout 3600
end
