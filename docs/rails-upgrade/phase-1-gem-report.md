# Phase 1 — Gem Report and Boot Smoke Test

> Exit criteria 5, 6 and 7 of [`phase-1-gem-compatibility-and-dual-boot.md`](phase-1-gem-compatibility-and-dual-boot.md).
> Measurements. Reasoning is in [`phase-1-implementation-plan.md`](phase-1-implementation-plan.md).

**Date:** 2026-07-29 · **Branch:** `feature/cms-420-migrate-tests`
**Ruby:** 2.7.8 · **Default bundle:** Rails 4.2.11.3 · **`Gemfile.next`:** Rails **5.0.7.2**
**Tooling:** `next_rails` 1.6.0 (`bundle_report`), plus [`script/rails_blockers.rb`](../../script/rails_blockers.rb)

---

## Headline

| | |
|---|---|
| `Gemfile.next` resolves | ✅ Rails **5.0.7.2**, zero remaining resolution blockers |
| Rails **boots** under `Gemfile.next` | ✅ `rake -T` exits 0; the dummy app loads and prints `5.0.7.2` |
| Default bundle still 4.2 and green | ✅ 994 tests, 0 failures, 0 errors; cucumber 154/154; coverage gate 75.82% |
| `HTML::FullSanitizer` breakage | ✅ Confirmed — see [below](#the-htmlfullsanitizer-confirmation) |
| Hard blockers with no path | **none** — `panoramic` was expected to be one and is not |
| Suite under Rails 5.0 | ❌ Not expected to pass, and does not. **754 unit tests → 2 failures, 323 errors** — but see the shape of that number. |

**The most consequential finding is not in the gem list.** Dual-boot did not
apply to the test suite at all until `test/dummy/config/boot.rb` was fixed, and
the failure mode was a **false green**. Details in
[The false-green trap](#the-false-green-trap).

---

## The three buckets

### Blockers — no compatible version exists

**None.**

`panoramic` was the expected blocker and survived on a technicality worth
recording, because it shows the two tools disagreeing and the *less* famous one
being right:

| Tool | Verdict on `panoramic` |
|---|---|
| `bundle_report compatibility` | `panoramic 0.0.7` — **"new version not found"**, i.e. an unfixable blocker |
| Bundler's resolver | Resolved it **down** to `0.0.6`, which declares `rails (>= 3.0.7)` with **no upper bound** |

`bundle_report` only searches *forward* for a newer compatible release. The cap
was introduced *in* 0.0.7 — the immediately preceding version is open-ended, so
the resolver found a backwards solution that the report is structurally unable
to see. Both tools were needed.

**Caveat, recorded deliberately:** this is a downgrade of a gem last released in
2013, and 0.0.7 presumably added `rails (~> 4)` for a reason. Nothing in the
suite has yet exercised `panoramic` under Rails 5 — the runs below abort long
before template resolution. `panoramic` is load-bearing: `Cms::DynamicView`
calls its `store_templates` ([`app/models/cms/dynamic_view.rb:3`](../../app/models/cms/dynamic_view.rb#L3)),
and both `Cms::PageTemplate` and `Cms::PagePartial` subclass it. **Treat "not a
blocker" as provisional until a page renders on Rails 5.**

### Required bumps — a compatible version exists

Handled in `Gemfile.next` via `next?` / `NEXT_BOOT` conditionals; the 4.2 bundle is untouched.

| Gem | 4.2 | 5.0 | Notes |
|---|---|---|---|
| `rails` | 4.2.11.3 | 5.0.7.2 | [`browsercms.gemspec`](../../browsercms.gemspec), [`Gemfile`](../../Gemfile) (`railties`) |
| `jquery-rails` | 3.1.5 | 4.6.1 | capped `railties < 5.0`. Asset-only; jQuery API drift is the risk, not Rails |
| `simple_form` | 3.1.1 | 3.5.1 | capped `actionpack ~> 4.0`. Custom inputs in `app/inputs/` ride its API — Phase 2 |
| `rails-dom-testing` | 1.0.9 | 2.3.0 | transitive; drops `rails-deprecated_sanitizer` and with it `HTML::FullSanitizer` |
| `minitest` | 5.19.0 | **5.10.3** (pinned down) | Rails 5.0's own test reporter is incompatible with newer minitest — [below](#the-minitest-reporter-wall) |
| `panoramic` | 0.0.7 | **0.0.6** (resolved down) | see above |

### Removed

| Gem | Why |
|---|---|
| `minitest-rails` 2.2.1 | Capped `railties ~> 4.1` — a genuine Rails 5 blocker, and **entirely unused**: every reference in `test/minitest_helper.rb` was already commented out. Deleted rather than bumped. `minitest_helper.rb` itself stays; 19 test files require it. |

### Already compatible — with notes

None of these blocks Rails 5.0 resolution. "Compatible" is not "fine":

| Gem | Locked | Note |
|---|---|---|
| `cucumber-rails` | 1.4.5 | Caps `railties < 5.1`. Clears this hop; **first blocker of hop 2 (5.0 → 5.1)**. |
| `simplecov` | 0.12.0 | Fine on Rails 5. Calls `Fixnum` (`configuration.rb:207`, `source_file.rb:29-30`) — **removed in Ruby 3.2**, so a hard Ruby blocker later. Line coverage only. |
| `poltergeist` | 1.11.0 | Compatible, and **unused**. Zero `@javascript` tags; both driver assignments commented out at [`features/support/env.rb:16-17`](../../features/support/env.rb#L16-L17). Recommend removal. |
| `compass-rails` / `sass-rails` | 4.0.0 / 5.0.6 | Cap **`sass < 3.5`**, not Rails. The 7.2 → 8.0 Propshaft problem, not a 5.0 problem. |
| `devise` | 4.9.4 | Already well past the 4.2+ the skill wants. Work is the `Devise::TestHelpers` deprecation — Phase 2. |
| `paperclip` | 5.3.0 | `activemodel >= 4.2.0`, no upper bound. Compatible through this hop, as planned. |
| `mocha` | 1.2.0 | No Rails cap. `mocha/setup` appears in **one** file ([`test/test_helper.rb:13`](../../test/test_helper.rb#L13)) — a one-line change if bumped, not the 109 sites previously assumed. |
| `factory_girl` / `_rails` | 4.7.0 | No Rails cap. Renaming to `factory_bot` is elective. |
| `capybara` | 2.10.1 | No Rails cap. |
| `database_cleaner` | 1.5.3 | No Rails cap. |
| `aruba` | 0.14.14 | No Rails cap. Hard-pinned; drives the `@cli` features, which are 7/34 (Phase 0 O1). |
| `will_paginate`, `ancestry`, `ckeditor_rails`, `jquery-ui-rails`, `underscore-rails`, `bootstrap-sass`, `actionpack-page_caching`, `responders` | — | No caps. |

### Tool output, for the record

`bundle_report compatibility --rails-version=5.0.7`, run before `minitest-rails` was deleted:

```
=> Incompatible with Rails 5.0.7 (with new versions that are compatible):
jquery-rails 3.1.5      - upgrade to 4.0.1
rails-dom-testing 1.0.9 - upgrade to 2.2.0
simple_form 3.1.1       - upgrade to 3.5.1

=> Incompatible with Rails 5.0.7 (with no new versions):
browsercms 5.2.0 - new version not found     <- the engine itself; expected
panoramic 0.0.7  - new version not found     <- disproved by the resolver

5 gems incompatible with Rails 5.0.7
```

`bundle_report ruby_check --ruby-version=2.7.8 --rails-version=5.0.7`:

```
The required ruby version is >= 2.2.2 for matched rails version 5.0.7
```

The offline scan agrees with the report on every gem. It found one more
(`minitest-rails`) only because it ran first; and it does **not** find
`minitest`, whose incompatibility is behavioural rather than declared.

---

## The false-green trap

**This is the finding to carry forward.**

The first Rails 5 probe reported the *entire* suite passing — units, spec,
functionals, orphans and all 154 cucumber scenarios, numbers identical to the
4.2 baseline. That was wrong. Every one of those runs was on **Rails 4.2**.

[`test/dummy/config/boot.rb`](../../test/dummy/config/boot.rb) assigned
`ENV['BUNDLE_GEMFILE']` to the engine's root `Gemfile` unconditionally. Because
`Rake::TestTask` and cucumber each spawn a **fresh** Ruby process, and in a fresh
process `boot.rb` runs *before* Bundler is set up, the hardcoded path won —
silently overriding `BUNDLE_GEMFILE=Gemfile.next` on the command line.

It looked like it worked from `bundle exec ruby -e 'require ".../environment"'`,
because there Bundler is already loaded by the time `boot.rb` runs and its
assignment is a no-op. So the *boot* smoke test was honest and the *suite* was
not.

Fixed by honouring an explicitly-provided value:

```ruby
default_gemfile = File.expand_path('../../../../Gemfile', __FILE__)
gemfile = ENV['BUNDLE_GEMFILE'] ? File.expand_path(ENV['BUNDLE_GEMFILE']) : default_gemfile
```

**Why it matters beyond this phase:** a `Gemfile.next` CI job on top of the
unfixed `boot.rb` would have reported green through Phases 2, 3 and 4 while
testing 4.2 the entire time. Phase 6 warns that the cucumber rate is "the metric
most likely to erode silently"; this was worse — a metric that would have read
*success* while measuring the wrong thing.

**Verification, for anyone re-running this:** the two Rails versions emit
different deprecations at boot. Grep the log rather than trusting the command
line — `public_file_server` means Rails 5, `serve_static_assets` means 4.2. The
CI job below asserts the version explicitly for the same reason.

---

## The boot smoke test

### Booting — criterion 4

```
$ BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test bundle exec rake -T           # exit 0
$ BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test bundle exec ruby -e \
    'require "./test/dummy/config/environment"; puts "BOOTED Rails #{Rails.version}"'
BOOTED Rails 5.0.7.2
```

`RAILS_ENV=test` is mandatory — without it the dummy app boots in `development`,
which `test/dummy/config/database.yml` does not define, and the resulting
`AdapterNotSpecified` has nothing to do with Rails 5 (Phase 0, F1).

### The `HTML::FullSanitizer` confirmation — criterion 7

Predicted by the phase document from static reading, and confirmed:

```
$ BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test bundle exec ruby -e \
    'require "./test/dummy/config/environment"; Cms::ContentFilter.new.filter({title: "<b>x</b>"})'

lib/cms/content_filter.rb:12:in `block in filter':
  uninitialized constant Cms::ContentFilter::HTML (NameError)
```

Chain: `rails-dom-testing 1.x` → depends on `rails-deprecated_sanitizer` (which
supplies `HTML::FullSanitizer`) and caps `activesupport < 5.0`. Rails 5 forces
`rails-dom-testing` to 2.x, `rails-deprecated_sanitizer` leaves the bundle, and
the constant is gone. Confirmed absent: `grep -c rails-deprecated_sanitizer
Gemfile.next.lock` → `0`.

**A correction to the phase doc's framing.** It says the file is 100% covered and
therefore that coverage cannot see this. The first half is true —
`content_filter.rb` is 8/8 lines in the units suite and **line 12 is hit twice**.
The second half needs restating: coverage did not hide this because the line was
unexercised, it hid it because *coverage cannot express version-dependent
resolution*. The test does call the line, and it does fail on Rails 5 — it is
one of the 2 failures in the run below. The lesson is unchanged but sharper:
**a covered line is not a portable line.**

Phase 3 has two exits, and they are not equivalent:

- **Fix the call site** to `Rails::Html::FullSanitizer` (or `ActionView::Base.full_sanitizer`) — where it should end up.
- **Declare `rails-deprecated_sanitizer` explicitly.** It requires only `activesupport >= 4.2.0.alpha`, with no upper bound, so the constant survives on Rails 5 unchanged. A one-line unblock that keeps a transition-shim gem alive indefinitely.

### The minitest reporter wall

The first attempt to run a suite on Rails 5 died before reporting anything:

```
railties-5.0.7.2/lib/rails/test_unit/reporter.rb:70:in `method':
  undefined method `test_accessible_to_guests?' for class `Minitest::Result' (NameError)
```

Rails 5.0's `Rails::TestUnitReporter` calls `result.method`, which predates
`Minitest::Result` (introduced in minitest 5.11). The next bundle had resolved
minitest to 5.26.1, so the reporter raised while formatting the **first** failure
and took the whole run down — turning any number of real failures into zero
usable output.

Pinned to `~> 5.10.3` for the next bundle only. This is harness work and
properly belongs to Phase 2; it was done here because without it Phase 1 cannot
report a Rails 5 number at all.

### The Rails 5.0 unit suite, measured

With the boot fix and the minitest pin, against a database whose schema was built
by **4.2** migrations:

```
754 tests, 657 assertions, 2 failures, 323 errors, 0 skips
```

Not a pass, and not expected to be — Phase 1's bar is booting. But the *shape*
is the useful part, and it is far better than 323 suggests:

| Errors | Cause |
|---|---|
| **320** | `ArgumentError: wrong number of arguments (given 1, expected 0)`, all from **one line**: [`lib/cms/behaviors/versioning.rb:230`](../../lib/cms/behaviors/versioning.rb#L230) |
| 2 | `NameError: uninitialized constant Cms::ContentFilter::HTML` — the finding above |
| 1 | `Before process_action callback :redirect_to_cms_site has not been defined` |

**99% of the failures are a single method signature.** Rails 4.2 declares
`def create_or_update` (`persistence.rb:502`); Rails 5.0 declares
`def create_or_update(*args, &block)` (`persistence.rb:546`). browsercms
overrides it with the old zero-arity signature, so every save on Rails 5 raises.

The fix is backwards-compatible — `def create_or_update(*args, &block)` passing
through — so it belongs in [Phase 3](phase-3-backwards-compatible-fixes.md) and
works on 4.2 unchanged. It is plausibly the single highest-leverage change in the
whole upgrade.

**Caveats on this number.** It is one suite, not five. It ran against a
4.2-built schema — the full `db:drop`/`create`/`migrate`/`seed` chain has *not*
been exercised on Rails 5, deliberately, because a Rails 5 `db:migrate` would
rewrite `test/dummy/db/schema.rb` into Rails 5 format and break the 4.2 suite
that Phase 0 gated. Sequencing that is Phase 5's problem and it is not trivial.

---

## Ruby 2.7 vs Rails 5.0 — D3 answered

The plan flagged that Rails 5.0 predates Ruby 2.7 and does not officially support
it, as a risk that could re-plan the whole hop sequence. **It is not fatal.**

- Rails 5.0.7 declares `required_ruby_version >= 2.2.2`, no upper bound.
- The dummy app boots cleanly on 5.0.7.2 under Ruby 2.7.8.
- 754 unit tests execute. None of the errors is a Ruby-vs-Rails incompatibility —
  they are one browsercms method override, one missing constant, one callback.
- One accommodation already exists and is worth knowing about:
  [`test/dummy/config/boot.rb`](../../test/dummy/config/boot.rb) loads
  `cms/extensions/big_decimal` before `rails/all`, because Rails 4.2's
  `duplicable.rb` calls the removed `BigDecimal.new` at load time. That patch was
  needed for **4.2** on modern Ruby; Rails 5 may not need it. Check whether it
  can be dropped rather than carrying it forward by inertia.

**Verdict: proceed on Ruby 2.7.8.** Revisit if Phase 5 hits framework-internal
failures with no application code in the backtrace.

---

## What changed in the repo

| Change | Why |
|---|---|
| [`script/rails_blockers.rb`](../../script/rails_blockers.rb) | Offline blocker scan, parameterised by target. `TARGET=5.1.0` already shows `cucumber-rails` as hop 2's addition. Rerunnable at all seven remaining hops. |
| `Gemfile` — `next?` helper, `next_rails` in `:development` | Dual-boot. `Gemfile.next` is a **symlink** to `Gemfile`, so `next?` is the only thing distinguishing the two bundles. |
| `Gemfile` — `railties` and `minitest` conditionals; `minitest-rails` deleted | Two of the six blockers, plus the reporter wall. |
| `browsercms.gemspec` — `NEXT_BOOT` conditional on `rails`, `jquery-rails`, `simple_form` | The gemspec cannot see the Gemfile's `next?` (Bundler evaluates it in a `Gem::Specification` context), so it keys off `BUNDLE_GEMFILE`. **Defaults to the 4.2 branch**, so `gem build` with no bundler environment is byte-identical to before. |
| [`test/dummy/config/boot.rb`](../../test/dummy/config/boot.rb) | The false-green fix. The most important change in the phase. |
| `Gemfile.next`, `Gemfile.next.lock` | Committed so CI can cache on the lockfile. |
| `.github/workflows/ci.yml` — `next-rails` job | Non-gating scoreboard for Phases 2–5. Asserts the Rails version explicitly. |

`Gemfile.lock`'s only changes are `minitest-rails` out and `next_rails` in. No
incidental bumps — verified by diff, because an accidental bump here would
invalidate the Phase 0 baseline everything else is measured against.

---

## Open items

| ID | Item |
|---|---|
| **P1-1** | `panoramic` 0.0.6 is unproven under Rails 5. Nothing has rendered a template there. Verify before treating "no blockers" as settled; plan to vendor regardless, since a gem last released in 2013 will block hops 2–8 too. |
| **P1-2** | `create_or_update` arity ([`versioning.rb:230`](../../lib/cms/behaviors/versioning.rb#L230)) — 320 of 323 unit errors. Backwards-compatible; Phase 3, and it should be first. |
| **P1-3** | `HTML::FullSanitizer` ([`content_filter.rb:12`](../../lib/cms/content_filter.rb#L12)) — Phase 3, with the two exits above. |
| **P1-4** | `minitest` pinned to 5.10.3 on the next bundle to work around Rails 5.0's reporter. Revisit at 5.1; it is a pin, not a fix. |
| **P1-5** | The Rails 5 `db:migrate`/`schema.rb` collision. A Rails 5 migration run rewrites the schema dump in a format 4.2 cannot load, so the two bundles cannot share the committed file. Phase 5 needs a plan — most likely gitignoring the dummy schema (Phase 0 O2 proposed this for unrelated reasons). |
| **P1-6** | `cms/extensions/big_decimal` may be unnecessary on Rails 5; check rather than inherit. |
| **P1-7** | `poltergeist` and `minitest-rails`-style dead weight: `poltergeist` is unused and removable. Phase 2. |
