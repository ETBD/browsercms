# Phase 1 — Implementation Plan

**Implements:** [`phase-1-gem-compatibility-and-dual-boot.md`](phase-1-gem-compatibility-and-dual-boot.md)
**Exit criteria:** all **9** live in [`phase-1-gem-compatibility-and-dual-boot.md` § Exit criteria](phase-1-gem-compatibility-and-dual-boot.md#exit-criteria), not in this file. This plan references them by number throughout.
**Entry condition:** Phase 0 complete — suite green, CI running, baseline committed ([`phase-0-baseline.md`](phase-0-baseline.md)).
**Rails at the end of this phase:** `Gemfile` still 4.2.11.3 and still green. `Gemfile.next` resolves to 5.0.x and **boots**. The suite does not pass there, and is not expected to.

Same shape as the [Phase 0 plan](phase-0-implementation-plan.md): findings first, then an ordered work stream, then the decisions that need a human.

> ### Status: ✅ done
> Measured results are in [`phase-1-gem-report.md`](phase-1-gem-report.md); that file, not this one, is the record. All 9 exit criteria pass. Where execution contradicted the plan:
>
> | Plan said | Reality |
> |---|---|
> | `panoramic` is "likely the only true blocker"; test a fork first ([D2](#d2-panoramic)) | **Not a blocker.** Bundler resolved it *down* to 0.0.6, which declares `rails (>= 3.0.7)` with no upper bound — the cap was introduced in 0.0.7. No fork needed. `bundle_report` could not see this: it only searches *forward* for newer compatible versions. |
> | The blocker list is six gems | Six for resolution, but a **seventh** blocks actually running anything: `minitest`. Rails 5.0's own test reporter predates `Minitest::Result`, so on minitest ≥ 5.11 it raises while formatting the first failure and takes the run down. Declared caps cannot express this; only running it finds it. |
> | Ruby 2.7 vs Rails 5.0 is a live risk that could re-plan the hop sequence ([§1.5](#15-the-risk-the-phase-doc-does-not-mention)) | **Not fatal.** Boots and executes 754 tests; no failure has a framework-only backtrace. Proceed on 2.7.8. |
> | `HTML::FullSanitizer` is invisible to coverage because the file is 100% covered | Sharper than that: line 12 **is** hit twice by the units suite, and it **does** fail on Rails 5. Coverage did not miss an unexercised line — it cannot express version-dependent resolution. *A covered line is not a portable line.* |
>
> **The plan missed the finding that mattered most.** `test/dummy/config/boot.rb` reassigned `BUNDLE_GEMFILE` unconditionally, so every `Rake::TestTask` and cucumber subprocess silently ran on 4.2. The first Rails 5 probe reported the entire suite passing with numbers identical to the 4.2 baseline — because it *was* the 4.2 baseline. Stage D's verification step (`rake -T` plus an app boot) was not enough; only diffing the boot deprecations between the two versions exposed it. The CI job now asserts `Rails.version` explicitly for that reason.

> ### The useful thing happened before this plan was written
>
> `Gemfile.lock` already contains the answer to most of work item 1.2. Every gem
> declares its Rails-component requirements in the lock, so **which gems exclude
> Rails 5.0.0 is computable locally, offline, in about a second** — no
> `bundle_report`, no network, no resolver. [§1](#1-pre-flight-findings) is that
> computation.
>
> This does not make 1.2 redundant. The lock shows *resolution* blockers; it is
> blind to gems that resolve cleanly and then raise at runtime — which is the
> entire point of the `HTML::FullSanitizer` example, and the class of failure
> this phase exists to catch. But it means you start Phase 1 with the blocker
> list already in hand, and `bundle_report` becomes a check on it rather than a
> discovery exercise.

---

## 1. Pre-flight findings

Computed against `Gemfile.lock` at `b00c2c04` + the Phase 0 commits. The script is in [A.0](#a0--reproduce-the-blocker-scan).

### 1.1 The complete Rails 5.0 resolution-blocker list

Six gems, excluding the Rails components themselves. **This is the phase's central artifact and it is already done.**

| # | Gem | Requirement excluding 5.0 | Pinned at | Resolution path |
|---|---|---|---|---|
| **B1** | `browsercms` 5.2.0 | `rails (~> 4.2.0)` | [`browsercms.gemspec:33`](../../browsercms.gemspec#L33) | **Conditionalize.** The engine caps itself. Nothing else can be tested until this moves — see [D1](#d1-how-to-conditionalize-the-gemspec). |
| **B2** | `panoramic` 0.0.7 | `rails (~> 4)` | [`browsercms.gemspec:44`](../../browsercms.gemspec#L44) | **Likely the only true blocker.** Last released 2013, no Rails 5 version exists. Runtime dependency, not a test gem — it supplies database-backed view resolution, which is how `Cms::PageTemplate` / `Cms::PagePartial` render at all. Needs a fork/vendor/replace decision ([D2](#d2-panoramic)). |
| **B3** | `jquery-rails` 3.1.5 | `railties (>= 3.0, < 5.0)` | [`browsercms.gemspec:41`](../../browsercms.gemspec#L41) (`~> 3.1`) | Bump to 4.x. Asset-only; the risk is jQuery API drift in CMS JavaScript, not Rails. |
| **B4** | `simple_form` 3.1.1 | `actionpack (~> 4.0)`, `activemodel (~> 4.0)` | [`browsercms.gemspec:47`](../../browsercms.gemspec#L47) (`~> 3.1.0`) | Bump to 3.5+. Custom inputs under `app/inputs/` ride on its API — expect real work, but in Phase 2, not here. |
| **B5** | `minitest-rails` 2.2.1 | `railties (~> 4.1)` | [`Gemfile:25`](../../Gemfile#L25) | **Delete it.** Every reference in `test/minitest_helper.rb` is commented out (lines 12, 22, 38, 46, 51). The gem is unused. Cheapest blocker in the list — note that `minitest_helper.rb` itself is required by 19 test files and must stay. |
| **B6** | `rails-dom-testing` 1.0.9 | `activesupport (>= 4.2.0, < 5.0)` | transitive | Resolves to 2.x on its own. **This is the `HTML::FullSanitizer` chain, confirmed** — see [1.2](#12-the-htmlfullsanitizer-chain-is-real). |

Also pinned and needing conditionals to let `Gemfile.next` resolve, though not blockers themselves: [`Gemfile:10`](../../Gemfile#L10) `gem 'railties', '~> 4.2'`.

### 1.2 The `HTML::FullSanitizer` chain is real

Confirmed exactly as [`phase-1`](phase-1-gem-compatibility-and-dual-boot.md) describes. [`lib/cms/content_filter.rb:12`](../../lib/cms/content_filter.rb#L12) calls `HTML::FullSanitizer.new.sanitize`, and the lock shows the chain:

```
rails-dom-testing (1.0.9)
  rails-deprecated_sanitizer (>= 1.0.1)   <- supplies HTML::FullSanitizer
  activesupport (>= 4.2.0, < 5.0)         <- forces the 1.x line out on Rails 5
```

One nuance worth having before Phase 3 writes the fix: **`rails-deprecated_sanitizer 1.0.4` declares `activesupport (>= 4.2.0.alpha)` with no upper bound.** So there are two exits, and they are not equivalent —

- *Declare it explicitly* in the Gemfile and `HTML::FullSanitizer` keeps working on Rails 5 unchanged. A one-line unblock that adds a dependency whose entire purpose was easing the 4.2→5.0 transition.
- *Fix the call site* to `Rails::Html::FullSanitizer` (or `ActionView::Base.full_sanitizer`), which is where it should end up.

Phase 1 only needs to know the second exists. Recording both here so Phase 3 does not rediscover it under time pressure. Note the file is 100% covered — coverage will not tell you about this.

### 1.3 Where the phase doc's gem table overstates the work

The doc's §1.2 table lists 13 gems needing a verdict. Measured against the lock, most are not resolution blockers at their **currently locked** versions:

| Doc's claim | Measured | Consequence |
|---|---|---|
| `mocha` 1.2.0 — "`mocha/setup` removed in 2.0; **109** call sites" | `mocha/setup` appears in **exactly one file**: [`test/test_helper.rb:13`](../../test/test_helper.rb#L13). The ~113 figure is `expects`/`stubs`/`mock`/`any_instance` **API** calls, which survive a 2.x bump. | Mocha is a **one-line** change (`require 'mocha/setup'` → `'mocha/minitest'`), not a 109-site migration. And it does not block Rails 5 at all — 1.2.0 has no Rails cap. |
| `compass-rails`, `sass-rails` — "Compass EOL 2018" | They cap **`sass < 3.5`**, not Rails. Neither excludes Rails 5.0. | Not a 5.0 problem. It is the Sprockets/Propshaft problem [`phase-6:59`](phase-6-subsequent-hops.md) already assigns to the 7.2 → 8.0 hop. Record and defer. |
| `devise` — "skill wants 4.2+ for Rails 5" | `~> 4.0` already resolves to **4.9.4**. | Already compatible. The real work is the `Devise::TestHelpers` → `Devise::Test::ControllerHelpers` deprecation Phase 0 surfaced — Phase 2. |
| `paperclip` — EOL, "the whole attachment subsystem" | 5.3.0, requires `activemodel >= 4.2.0`, no upper bound. | Compatible through the 5.0 hop, as the doc's own "not in this phase" note says. Confirmed rather than assumed. |
| `cucumber` / `cucumber-rails` — "53 features depend on it" | `cucumber-rails 1.4.5` caps `railties (>= 3, < 5.1)`. **5.0 satisfies it.** | Not a 5.0 blocker — it is the **first blocker of hop 2 (5.0 → 5.1)**. Worth knowing now: it buys Phase 2 room to sequence the cucumber stack after the first bump rather than before it. |
| `capybara`, `poltergeist`, `aruba`, `database_cleaner`, `simplecov`, `factory_girl` | No Rails cap on any of them. | None blocks resolution. Each is still *harness* work — but that is Phase 2's budget, and Phase 1 should not report them as Rails 5 blockers. |

**Net:** the doc's 13-gem verdict list is really **one probable blocker (`panoramic`), three routine bumps, one deletion, one self-cap, and one transitive drop-out.** That is a materially smaller Phase 1 than the doc implies — and a materially different Phase 2, because most of that table turns out to be harness modernisation with no Rails deadline attached.

### 1.4 Two findings carried forward from Phase 0

| Finding | Why it matters here |
|---|---|
| **Poltergeist is never used.** Zero `@javascript` tags; both driver assignments commented out at [`features/support/env.rb:16-17`](../../features/support/env.rb#L16-L17); suite green in CI with no browser installed. | The doc lists `poltergeist` as needing a verdict. The verdict is nearly free: **remove it.** Nothing selects the driver. This shrinks Phase 2's driver migration from "port 53 features to a new driver" to "delete a gem and a require." |
| **`simplecov` 0.12.0 calls `Fixnum`** (`configuration.rb:207`, `source_file.rb:29-30`). | Deprecated on 2.7, **removed in Ruby 3.2** → `NameError`. Not a Rails 5 blocker, but it is a hard Ruby blocker further out. It belongs in the report's third bucket with a note, not omitted because it passes today. |

### 1.5 The risk the phase doc does not mention

**Rails 5.0 was released before Ruby 2.7 existed, and does not officially support it.** The repo is pinned to Ruby 2.7.8 ([`.ruby-version`](../../.ruby-version), [`Gemfile:3`](../../Gemfile#L3)). Rails 5.0.x on Ruby 2.7 is known to hit removed-method and keyword-argument problems that have nothing to do with browsercms.

Phase 1's bar is only that Rails **boots**, so this may not bite until [Phase 5](phase-5-the-5.0-bump.md) tries to make the suite pass. But Phase 1 is where it first becomes observable, and if it is fatal the whole hop sequence needs re-planning. Treat it as a first-class output of [Stage D](#stage-d--boot-smoke-test-13) — see [D3](#d3-ruby-27-vs-rails-50) and [contingencies](#4-contingencies).

---

## 2. Execution order

| Stage | Work item | Produces | Size |
|---|---|---|---|
| **A** | — | Blocker scan reproduced and committed as a script; `next_rails` installed | S |
| **B** | 1.1 | `Gemfile.next` resolving to 5.0.x — the six caps conditionalized or removed | M |
| **C** | 1.2 | `bundle_report compatibility` run; three-bucket report committed | M |
| **D** | 1.3 | Rails boots under `Gemfile.next`; `HTML::FullSanitizer` confirmed; Ruby-2.7 question answered | **M–L / unknown** |
| **E** | 1.1 (CI) | Third CI job on `Gemfile.next`, non-gating | S |
| **F** | 1.4 | Supporting docs corrected where measurement contradicted them | S |

Two deviations from the doc's numbering, both for the same reason — the pre-flight scan moved information earlier:

- **The compatibility check (C) comes after dual-boot (B), not before.** The doc has this order already; what changes is *why* B is achievable first. You do not need `bundle_report` to know which caps to conditionalize — [§1.1](#11-the-complete-rails-50-resolution-blocker-list) lists them.
- **Stage D is the unbounded one**, and it is where `panoramic` and the Ruby-2.7 question resolve. Everything before it is mechanical.

---

## Stage A — Reproduce the scan, install the tooling

### A.0 — Reproduce the blocker scan

Commit this as `script/rails_blockers.rb` so it is rerunnable at every hop rather than a one-off in a chat log. Change `TARGET` per hop — Phase 6 will want it six more times.

```ruby
#!/usr/bin/env ruby
# Which locked gems declare a Rails-component requirement that excludes TARGET?
# Answers the resolution half of the gem-compatibility question offline, with no
# resolver and no network. Blind to gems that resolve and then raise at runtime
# -- that is what the boot smoke test is for.
require "rubygems"

TARGET     = Gem::Version.new(ENV.fetch("TARGET", "5.0.0"))
COMPONENTS = %w[rails railties activesupport actionpack activerecord activemodel actionview].freeze
CORE       = COMPONENTS + %w[actionmailer activejob]

current, blockers = nil, {}
File.readlines("Gemfile.lock").each do |line|
  if line =~ /^    ([a-zA-Z0-9_\-]+) \(([^)]+)\)$/
    current = [$1, $2]
  elsif line =~ /^      (#{COMPONENTS.join('|')}) \((.+)\)$/
    name, constraint = $1, $2
    next if CORE.include?(current&.first)
    req = begin
      Gem::Requirement.new(constraint.split(",").map(&:strip))
    rescue StandardError
      next
    end
    (blockers[current] ||= []) << "#{name} (#{constraint})" unless req.satisfied_by?(TARGET)
  end
end

puts "Gems whose Rails requirement excludes #{TARGET}:"
blockers.sort.each { |(gem, version), deps| puts format("  %-24s %-10s %s", gem, version, deps.join("; ")) }
puts "  (none)" if blockers.empty?
exit(blockers.empty? ? 0 : 1)
```

`TARGET=5.1.0 ruby script/rails_blockers.rb` is how you find out that `cucumber-rails` is hop 2's problem before hop 2 starts.

- [ ] Script committed; output matches [§1.1](#11-the-complete-rails-50-resolution-blocker-list) (6 gems)

### A.1 — Install `next_rails`

`next_rails` supplies both halves of this phase: `next_rails --init` for dual-boot and `bundle_report compatibility` for Stage C. Neither `next_rails`, `bootboot`, nor `appraisal` is currently installed.

Add to the `:development` group in the `Gemfile`, and **not** to the gemspec — it is a maintainer tool, not a dependency of the engine.

- [ ] `gem 'next_rails'` in the development group; `bundle install`; default bundle still resolves to 4.2.11.3
- [ ] `bundle exec next_rails --version` and `bundle exec bundle_report --help` both work

### A.2 — Generate `Gemfile.next`, then check what it actually is

```bash
test -f Gemfile.next && echo "STOP: already exists"   # the doc's warning: avoid a duplicate next? definition
bundle exec next_rails --init
ls -l Gemfile.next && cat Gemfile.next
```

**Verify rather than assume the mechanism.** Current `next_rails` makes `Gemfile.next` a *symlink* to `Gemfile` plus a separate `Gemfile.next.lock`, and injects a `next?` helper that keys off which filename Bundler loaded. [D1](#d1-how-to-conditionalize-the-gemspec) depends on this being true — if `--init` instead writes a standalone copy, the gemspec conditional below is unnecessary and the two files diverge by hand instead.

- [ ] `Gemfile.next` exists; its nature (symlink vs. copy) recorded
- [ ] A `next?` helper is defined exactly once

---

## Stage B — Make `Gemfile.next` resolve (1.1)

Six caps, four kinds of fix. Do them in this order — B1 first, because until the engine stops capping itself nothing else is observable.

### B.1 — The gemspec's four constraints

`browsercms.gemspec` carries **four** of the six blockers: `rails ~> 4.2.0` (B1), `jquery-rails ~> 3.1` (B3), `simple_form ~> 3.1.0` (B4), and `panoramic` (B2, unconstrained but capped by its own 0.0.7).

The gemspec cannot call the Gemfile's `next?` helper — Bundler evaluates it in a `Gem::Specification` context that has never heard of it. Use the environment, and **default to the 4.2 branch** so a plain `gem build` is byte-identical to today's release:

```ruby
# browsercms.gemspec
#
# Dual-boot: the Gemfile's next? helper is not in scope here -- Bundler evaluates
# this file in a Gem::Specification context. Key off BUNDLE_GEMFILE instead, and
# default to the 4.2 branch so `gem build` with no bundler environment produces
# exactly what it produced before this phase.
next_boot = ENV["BUNDLE_GEMFILE"].to_s.end_with?("Gemfile.next")

if next_boot
  s.add_dependency("rails", "~> 5.0.0")
  s.add_dependency("jquery-rails", "~> 4.0")
  s.add_dependency("simple_form", "~> 3.5")
else
  s.add_dependency("rails", "~> 4.2.0")
  s.add_dependency("jquery-rails", "~> 3.1")
  s.add_dependency("simple_form", "~> 3.1.0")
end
```

This is a decision, not the only option — see [D1](#d1-how-to-conditionalize-the-gemspec).

### B.2 — The Gemfile's `railties` pin

[`Gemfile:10`](../../Gemfile#L10) is `gem 'railties', '~> 4.2'`. Here `next?` *is* in scope:

```ruby
gem 'railties', next? ? '~> 5.0.0' : '~> 4.2'
```

### B.3 — Delete `minitest-rails` (B5)

Remove [`Gemfile:25`](../../Gemfile#L25). It is unused — every reference in `test/minitest_helper.rb` is commented out. Confirm before and after:

```bash
grep -rn 'minitest/rails\|MiniTest::Rails' test/ spec/ features/ lib/ | grep -v '^\s*#'
RAILS_ENV=test bundle exec rake            # still green on 4.2
```

Keep `test/minitest_helper.rb` — 19 test files require it.

### B.4 — `panoramic` (B2)

No Rails 5 version exists, so there is nothing to conditionalize. `Gemfile.next` **will not resolve** until [D2](#d2-panoramic) is decided and acted on. This is the stage's real gate; expect to arrive here quickly and then stop.

Interim move that keeps Stage C and D unblocked while D2 is being decided: point `Gemfile.next` at a git ref or path override for `panoramic` so resolution completes, and mark it loudly in the report as unresolved. Booting on a fork you have not committed to is still more informative than not booting.

### B.5 — Resolve both bundles

```bash
bundle install                                    # 4.2 -- must not change
BUNDLE_GEMFILE=Gemfile.next bundle install        # 5.0
bundle list | grep " rails "                      # criterion 3
BUNDLE_GEMFILE=Gemfile.next bundle list | grep " rails "   # criterion 2
TARGET=5.0.0 ruby script/rails_blockers.rb        # expect: none, on the next lock
RAILS_ENV=test bundle exec rake                   # criterion 3: still green
```

- [ ] `Gemfile.next.lock` resolves to a Rails 5.0.x
- [ ] `Gemfile.lock` **unchanged apart from the `minitest-rails` removal** — inspect the diff; an incidental bump here silently changes what Phase 0 measured
- [ ] Default suite still green, coverage gate still at 75.82%

---

## Stage C — The compatibility report (1.2)

### C.1 — Run it

```bash
bundle exec bundle_report compatibility --rails-version 5.0 | tee tmp/phase1/compatibility.txt
bundle exec bundle_report outdated     | tee tmp/phase1/outdated.txt
```

Escalate to the railsbump API only under the conditions the skill's `gem-compatibility-workflow.md` specifies — not by default.

### C.2 — Commit the three-bucket report

Create `docs/rails-upgrade/phase-1-gem-report.md`. Criterion 5 requires every gem from the doc's table to appear in **exactly one** bucket; the pre-flight work means most rows are already known:

| Bucket | Means | Expected members from [§1.1](#11-the-complete-rails-50-resolution-blocker-list) / [§1.3](#13-where-the-phase-docs-gem-table-overstates-the-work) |
|---|---|---|
| **Blockers** | No version exists that supports the target | `panoramic` (pending [D2](#d2-panoramic)) |
| **Required bumps** | A compatible version exists; we must move to it | `jquery-rails` → 4.x · `simple_form` → 3.5+ · `rails-dom-testing` → 2.x (automatic) · `minitest-rails` (resolved by deletion) |
| **Already compatible** | Locked version is fine for 5.0 | `devise` 4.9.4 · `paperclip` 5.3.0 · `mocha` · `factory_girl` · `capybara` · `aruba` · `database_cleaner` · `simplecov` · `cucumber`/`cucumber-rails` · `compass-rails` · `sass-rails` · `will_paginate` · `ancestry` · `ckeditor_rails` · `jquery-ui-rails` · `actionpack-page_caching` |

"Already compatible" must not be read as "fine." Each of these carries a note:

- `cucumber-rails` — compatible with 5.0, **blocks 5.1**. First blocker of hop 2.
- `simplecov` 0.12.0 — fine on Rails 5, **dies on Ruby 3.2** (`Fixnum`). Line coverage only.
- `poltergeist` — compatible and **unused**; recommend removal ([§1.4](#14-two-findings-carried-forward-from-phase-0)).
- `compass-rails` / `sass-rails` — caps `sass < 3.5`; the 7.2 → 8.0 problem.
- `mocha` / `factory_girl` / `capybara` / `database_cleaner` — no Rails deadline; Phase 2 harness work by choice, not by force.

- [ ] Report committed; every gem in the phase doc's table appears exactly once
- [ ] Every blocker has a named fork/vendor/replace decision, not a question mark (criterion 6)
- [ ] Where `bundle_report` contradicts [§1.1](#11-the-complete-rails-50-resolution-blocker-list), **the report wins** — and the contradiction is written down, because it means the scan script has a bug worth fixing before Phase 6 relies on it six more times

---

## Stage D — Boot smoke test (1.3)

The unbounded stage.

### D.1 — Boot it

```bash
BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test bundle exec rake -T > tmp/phase1/boot.log 2>&1; echo "exit=$?"
BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test bundle exec ruby -e \
  'require "./test/dummy/config/environment"; puts Rails.version'
```

`rake -T` is the doc's suggested bar, but note what Phase 0 established: `rake -T` loads the Rakefile and `engine.rake`, which does **not** boot the dummy app. The second command does. Run both — the second is what actually exercises `Bundler.require` plus the full initializer chain, and it is the one that will surface `HTML::FullSanitizer`-class failures.

Also from Phase 0: **`RAILS_ENV=test` is mandatory.** Without it the dummy app boots in `development`, which `test/dummy/config/database.yml` does not define, and you get `AdapterNotSpecified` — a red herring that has nothing to do with Rails 5.

### D.2 — Triage each failure

For every `LoadError` / `NameError` / `NoMethodError`: name the gem, check RubyGems for a target-compatible version, add it to the required-bumps bucket, re-run. Iterate until Rails boots.

### D.3 — Confirm `HTML::FullSanitizer` (criterion 7)

The doc is emphatic and correct: if the smoke test passes without flagging it, **the smoke test is not loading enough of the app — fix the test, not the expectation.** `lib/cms/content_filter.rb` is only loaded when the filter runs, so a boot that merely initializes Rails may never touch line 12. Force it:

```bash
BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test bundle exec ruby -e \
  'require "./test/dummy/config/environment"; Cms::ContentFilter.new.filter({title: "<b>x</b>"})'
```

Expect `NameError: uninitialized constant HTML`. Commit that output next to the report.

### D.4 — Answer the Ruby 2.7 question ([§1.5](#15-the-risk-the-phase-doc-does-not-mention))

While triaging D.2, classify each failure as **browsercms's problem** or **Rails-5.0-on-Ruby-2.7's problem**. The second kind looks like removed core methods or keyword-argument errors raised from inside `activesupport`/`actionpack` frames with no application code in the backtrace.

This is a genuine Phase 1 output, because it determines whether the hop sequence is viable as planned. Record the verdict in the report either way — including "no such failures observed," which is the good outcome and equally worth committing.

- [ ] Rails boots under `Gemfile.next` (criterion 4)
- [ ] `HTML::FullSanitizer` failure captured and committed (criterion 7)
- [ ] Every boot failure classified: app / gem / Ruby-vs-Rails
- [ ] No `respond_to?`-style version branching introduced (criterion 9)

---

## Stage E — CI on `Gemfile.next` (1.1, last item)

A third job in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml), non-gating. Its output is the scoreboard for Phases 2–5.

```yaml
  next-rails:
    name: Rails 5.0 (Gemfile.next, reporting only)
    runs-on: ubuntu-22.04
    timeout-minutes: 45
    # Expected red for the whole of Phases 1-4. Booting is Phase 1's bar; the
    # suite passing is Phase 5. Make it gating there, not before.
    continue-on-error: true

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_HOST_AUTH_METHOD: trust
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready --health-interval 10s
          --health-timeout 5s --health-retries 5

    env:
      BUNDLE_GEMFILE: Gemfile.next
      RAILS_ENV: test
      PGHOST: localhost
      PGPORT: '5432'
      PGUSER: postgres
      launch_on_failure: 'false'

    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '2.7.8'
          bundler: '1.17.3'
          bundler-cache: true

      # Phase 1's actual bar. Split from the suite so a boot failure is
      # distinguishable from a test failure at a glance in the job list.
      - name: Boot under Rails 5.0
        run: bundle exec ruby -e 'require "./test/dummy/config/environment"; puts Rails.version'

      - name: Suite (expected red until Phase 5)
        if: always()
        run: bundle exec rake
```

Notes on the choices:

- **`BUNDLE_GEMFILE` at job level**, so `ruby/setup-ruby`'s `bundler-cache` keys on the right lockfile. `Gemfile.next.lock` must be committed for the cache to work.
- **Boot and suite are separate steps.** Phase 1 is judged on the first; keeping them apart means the job list tells you which one regressed without opening a log.
- **`bundler: '1.17.3'`** — if `Gemfile.next` needs Bundler 2 for a modern gem, that is a finding for the report, not something to paper over here.
- **`launch_on_failure: 'false'`** for the same reason as the other jobs: the failure hook shells out to a browser that does not exist on the runner.

- [ ] Job runs and reports (criterion 8); red is expected and fine
- [ ] `Gemfile.next.lock` committed

---

## Stage F — Correct the record (1.4)

Measurement beats working knowledge, and this phase produces measurements that contradict the supporting documents. Update them rather than leaving future readers to rediscover:

- [ ] [`phase-1-gem-compatibility-and-dual-boot.md`](phase-1-gem-compatibility-and-dual-boot.md) §1.2's table — the mocha "109 call sites" figure, the compass/sass verdict, devise's actual version, and cucumber-rails's `< 5.1` cap ([§1.3](#13-where-the-phase-docs-gem-table-overstates-the-work))
- [ ] [`RAILS_UPGRADE_TEST_PRIORITY.md`](../../RAILS_UPGRADE_TEST_PRIORITY.md) §3 B4 — Paperclip's verdict, now measured rather than reasoned
- [ ] [`phase-2-harness-migration.md`](phase-2-harness-migration.md) — the largest re-scope. Its §2.4 assumes a Poltergeist driver migration; there is no driver to migrate. And most of its gem list turns out to have no Rails deadline, which changes what is forced versus chosen.
- [ ] [`phase-6-subsequent-hops.md`](phase-6-subsequent-hops.md) — record `cucumber-rails` as hop 2's known first blocker

---

## 3. Decisions that need a human

### D1: How to conditionalize the gemspec
**(a)** ENV-conditional inside the gemspec, defaulting to 4.2 — contained, reversible, `gem build` unchanged; but the gemspec's meaning now depends on the environment, which is a genuine wart in a file that defines a published artifact.
**(b)** Move the Rails-ish dependencies out of the gemspec into the `Gemfile` under `if next?` — cleaner conditionals; but the published gem would stop declaring a `rails` dependency, which is worse for consumers than the wart.
**(c)** Loosen the gemspec to `rails >= 4.2, < 6` and let each Gemfile pin — where an engine should end up; but it advertises Rails 5 support that will not exist until Phase 5.
**Recommendation: (a) now, (c) at Phase 5** when the claim becomes true. (b) trades a small internal wart for a real external regression.

### D2: `panoramic`
The only hard blocker, an unmaintained 2013 runtime dependency, and load-bearing: it provides the database-backed view resolver behind `Cms::PageTemplate` and `Cms::PagePartial`. Options, in ascending cost:
- **Fork and bump the constraint.** `rails (~> 4)` may be pessimism rather than a real incompatibility — 0.0.7 is a small gem. Cheapest, and the first thing to test: vendor it, relax the constraint, boot, see what breaks.
- **Vendor it into the engine.** browsercms is the only consumer that matters here; a resolver is a few hundred lines, and owning it removes a dependency that will block every remaining hop.
- **Replace it** with a `ActionView::Resolver` subclass written against modern Rails. Correct destination, largest cost, and it is Phase 2/3 work regardless of what Phase 1 decides.

**Recommendation: test the fork first** — it is an afternoon and it either unblocks the whole phase or proves the incompatibility is real, which is exactly the information D2 needs. Then plan to vendor, because a gem last released in 2013 will block hops 2 through 8 as well.

### D3: Ruby 2.7 vs Rails 5.0
Only actionable once [D.4](#d4--answer-the-ruby-27-question-15) reports. If Rails 5.0 proves unworkable on Ruby 2.7.8, the choices are: pin Ruby *down* for the intermediate hops and raise it at the end; or bump Ruby *first*, to a version 5.0 and 5.2 both tolerate; or accept a broken middle and use 5.0 purely as a resolution waypoint without a green suite. **Do not decide in advance** — but do surface it the moment the data exists, because the third option quietly voids Phase 5's exit criteria.

---

## 4. Contingencies

| If | Then |
|---|---|
| `panoramic` cannot be forked cheaply | Stop and get a decision on vendor-vs-replace before continuing. Do not carry a path-override fork into Phase 2 as if it were resolved — that converts a known blocker into an invisible one. |
| Rails 5.0 will not run on Ruby 2.7.8 | Raise it immediately; it re-plans the hop sequence, not just this phase. See [D3](#d3-ruby-27-vs-rails-50). |
| `bundle_report` contradicts the scan script | The report wins. Fix the script and record the bug — Phase 6 reruns it six times. |
| The default `Gemfile.lock` drifts during Stage B | Revert and redo. Criterion 3 is that 4.2 stays green and unchanged; an incidental bump invalidates the Phase 0 baseline everything else is measured against. |
| `Gemfile.next` needs Bundler 2 | Record it as a finding and pin per-job in CI rather than raising the default. Changing the default Bundler changes the 4.2 build too. |

---

## 5. Exit criteria traceability

| # | Criterion | Stage | Verification |
|---|---|---|---|
| 1 | `Gemfile.next` exists and resolves | B | `test -f Gemfile.next && BUNDLE_GEMFILE=Gemfile.next bundle check` |
| 2 | It resolves to Rails 5.0.x | B | `BUNDLE_GEMFILE=Gemfile.next bundle list \| grep " rails "` |
| 3 | Default still 4.2.11.3 and green | B | `bundle list \| grep " rails "`; `rake` green; coverage still 75.82% |
| 4 | Rails **boots** under `Gemfile.next` | D | `rake -T` exits 0 **and** the dummy app environment loads |
| 5 | Committed three-bucket report | C | `phase-1-gem-report.md`; every gem in the doc's table appears exactly once |
| 6 | Every blocker has a fork/vendor/replace decision | C, D2 | Named decisions, no question marks |
| 7 | `HTML::FullSanitizer` confirmed by the smoke test | D.3 | Committed output naming it |
| 8 | A CI job runs against `Gemfile.next` | E | Job present and reporting; may be red |
| 9 | No `respond_to?`-style version branching | B, D | `grep -rn "respond_to?(:.*Rails\|Rails::VERSION" app/ lib/` shows nothing new |

**A note on criterion 4 versus the goal.** "Boots" is a low bar deliberately, and it is worth being honest that clearing it with a path-overridden `panoramic` fork is not the same as clearing it for real. If that is how the phase ends, say so plainly in the report — the difference is the whole of [D2](#d2-panoramic), and it will be much more expensive to discover in Phase 5.
