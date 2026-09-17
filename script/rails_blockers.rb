#!/usr/bin/env ruby
#
# Which locked gems declare a Rails-component requirement that excludes the
# target Rails version?
#
# Answers the *resolution* half of the gem-compatibility question offline: no
# resolver, no network, no bundle install. Every gem records its dependency
# constraints in Gemfile.lock, so the set of gems that cannot coexist with a
# given Rails version is already sitting on disk.
#
# It is blind to the other half -- a gem that resolves cleanly and then raises
# at runtime because it calls something that no longer exists. That is what the
# boot smoke test is for. See docs/rails-upgrade/phase-1-implementation-plan.md.
#
#   ruby script/rails_blockers.rb                    # target 5.0.0
#   TARGET=5.1.0 ruby script/rails_blockers.rb       # next hop
#   LOCKFILE=Gemfile.next.lock ruby script/rails_blockers.rb
#
# Exits 0 when nothing blocks, 1 otherwise, so it can gate a CI step.

require "rubygems"

TARGET   = Gem::Version.new(ENV.fetch("TARGET", "5.0.0"))
LOCKFILE = ENV.fetch("LOCKFILE", "Gemfile.lock")

# The components a gem might constrain.
COMPONENTS = %w[
  rails railties activesupport actionpack activerecord activemodel actionview
].freeze

# Rails' own gems pin each other exactly (activesupport (= 4.2.11.3)), so they
# always "block" and never carry information. Skip them as subjects; still read
# them as dependencies of anything else.
CORE = (COMPONENTS + %w[actionmailer activejob actioncable activestorage]).freeze

abort "#{LOCKFILE} not found (run from the repository root)" unless File.exist?(LOCKFILE)

subject  = nil
blockers = {}

File.readlines(LOCKFILE).each do |line|
  case line
  when /^    ([a-zA-Z0-9_.\-]+) \(([^)]+)\)$/         # a gem being specified
    subject = [Regexp.last_match(1), Regexp.last_match(2)]
  when /^      (#{COMPONENTS.join('|')}) \((.+)\)$/    # one of its dependencies
    next if subject.nil? || CORE.include?(subject.first)

    name       = Regexp.last_match(1)
    constraint = Regexp.last_match(2)
    requirement =
      begin
        Gem::Requirement.new(constraint.split(",").map(&:strip))
      rescue StandardError
        next
      end

    next if requirement.satisfied_by?(TARGET)

    (blockers[subject] ||= []) << "#{name} (#{constraint})"
  end
end

puts "#{LOCKFILE}: gems whose Rails requirement excludes #{TARGET}"
puts

if blockers.empty?
  puts "  none"
else
  blockers.sort.each do |(name, version), deps|
    puts format("  %-22s %-10s %s", name, version, deps.join("; "))
  end
  puts
  puts "  #{blockers.size} blocker(s)"
end

exit(blockers.empty? ? 0 : 1)
