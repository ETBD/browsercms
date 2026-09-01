# Phase 2 — Implementation Plan

**Implements:** [`phase-2-harness-migration.md`](phase-2-harness-migration.md)
**Entry condition:** Phase 1 complete — `Gemfile.next` resolves to 5.0.7.2 and boots; the `next-rails` CI job reports ([`phase-1-gem-report.md`](phase-1-gem-report.md)). **Plus two Phase 3 items — see [D1](#d1-phase-3s-two-unblockers-come-first).**
**Rails at the end of this phase:** `Gemfile` still 4.2.11.3 and green at the Phase 0 baseline. `Gemfile.next` green too, and its CI job no longer `continue-on-error`.

Same shape as the [Phase 0](phase-0-implementation-plan.md) and [Phase 1](phase-1-implementation-plan.md) plans: findings first, then an ordered work stream, then the decisions that need a human.

> ### Status: not started
> When this phase finishes, the measured record goes in `phase-2-harness-report.md` and *that* file, not this one, becomes the record — the same split Phases 0 and 1 used.

> ### The phase document's premises have moved twice
>
> Its own re-scope callout corrected the "does not boot" claim after Phase 1. **This plan corrects it again**, because Phase 1 measured only the unit suite and only against a bundle it never made render a view. Running the other three suites changes the shape of the phase substantially:
>
> | The phase doc says | Measured (§1) |
> |---|---|
> | 9 blockers, headed by 109 mocha call sites and 88 positional controller args | **Rails 5.0 breaks on exactly one of the nine.** `assigns`/`assert_template` genuinely raise. Positional args only *deprecate* at 5.0. `mocha`, `factory_girl` and `minitest/unit` all work unchanged on Rails 5.0.7.2 today. |
> | "The suite does not currently fail on Rails 5 — it does not boot" | Three of four suites run. The **functional suite does not load at all**, and the **cucumber suite does not load at all** — for two different one-line reasons, neither of them in the doc. |
> | §2.4 is the big item: a 53-feature driver migration | There is still no driver. But cucumber is **0/154** on Rails 5 rather than the doc's implied "mostly fine", and the cause is assets, not the driver. |
> | The dominant risk is test-code volume | The dominant risk is **two gems that declare no Rails cap and are hard-gated on Rails 4 at runtime** — invisible to Phase 1's resolution scan *and* to its boot smoke test. |
>
> **The one-sentence version:** Phase 2 is much less typing than the doc implies and much more debugging. The 89 mechanical conversions are real but they are not what is red.

---

## 1. Pre-flight findings

Measured 2026-08-31 on `feature/cms-420-migrate-tests` @ `29b7f92e`, Ruby 2.7.8, `BUNDLE_GEMFILE=Gemfile.next` (Rails 5.0.7.2), against the existing 4.2-built schema. Reproduction commands in [A.0](#a0--reproduce-the-probe).

### 1.1 The Rails 5.0 state of all four suites

Phase 1 reported one suite. Here are four. Two of them needed a temporary patch before they would even load — the patches are named below and were reverted; nothing in this measurement is committed.

| Suite | Rails 4.2 (Phase 0) | Rails 5.0, as the tree stands | Rails 5.0, with the two [D1](#d1-phase-3s-two-unblockers-come-first) patches |
|---|---|---|---|
| Unit (754) | 754 / 0F / 0E | 754 / 2F / **323E** | 754 / **2F / 4E** |
| Spec (145) | 145 / 0F / 0E | 145 / 0F / **13E** | 145 / 0F / **0E** (all 13 were the same arity bug) |
| Functional (88) | 88 / 0F / 0E | **does not load** | 88 / 0F / **33E** |
| Cucumber, default profile (154) | 154 / 154 pass | **does not load** | **23 pass / 131 fail** ⚠️ also needs [1.3](#13-the-cucumber-suite-does-not-load-and-it-is-one-line) |

**Read the third column, not the second.** 320 of the 323 unit errors and all 13 spec errors are [P1-2](phase-1-gem-report.md#open-items), one method signature, already assigned to Phase 3. Measuring Phase 2 through that noise measures Phase 3.

The residue is small and it is nearly all *one thing per suite*:

| Suite | Remaining problems | Owner |
|---|---|---|
| Unit | 2 × `NameError: uninitialized constant Cms::ContentFilter::HTML` ([P1-3](phase-1-gem-report.md#open-items)) · 2 × `ActiveRecord::StaleObjectError: Attempted to touch a stale object: Cms::Page` (new — `persistence.rb:523` `touch` under 5.0 optimistic locking) · `PublishableTestCase#test_publish_on_save` · `PortletTest#test_.blacklist` | Phase 3 / new |
| Spec | none | — |
| Functional | **27 × `couldn't find file 'ckeditor-jquery'`** ([1.2](#12-two-gems-with-no-rails-cap-that-are-hard-gated-on-rails-4)) · 2 × missing partial `cms/shared/_version_conflict_error` · **2 × `assigns has been extracted to a gem`** · 1 × `PG::InvalidTextRepresentation: invalid input syntax for type integer: ""` · 1 × `HTML::FullSanitizer` | Phase 2 ×2, rest Phase 3 |
| Cucumber | 131 × the same asset chain ([1.2](#12-two-gems-with-no-rails-cap-that-are-hard-gated-on-rails-4), [1.4](#14-sprockets-rails-3-requires-every-referenced-asset-to-be-declared)) | Phase 2 |

Only **two** of the 33 functional errors are the thing Phase 2 was written to fix (`assigns`). Everything else in that column is assets or application code.

### 1.2 Two gems with no Rails cap that are hard-gated on Rails 4

This is the finding to carry forward, and it is the mirror image of Phase 1's `panoramic` result.

`ckeditor_rails` 4.3.4 — declared `~> 4.3.0` at [`browsercms.gemspec:51`](../../browsercms.gemspec#L51), listed by Phase 1 under *already compatible, no caps* — dispatches its own Railtie on a **string match against the Rails version**:

```ruby
# ckeditor_rails-4.3.4/lib/ckeditor-rails.rb
case ::Rails.version.to_s
when /^4/      then require 'ckeditor-rails/engine'
when /^3\.[12]/ then require 'ckeditor-rails/engine3'
when /^3\.[0]/  then require 'ckeditor-rails/railtie'
end
```

On Rails 5 **no branch matches**, the engine is never required, `lib/assets/javascripts` never joins the asset load path, and `//= require ckeditor-jquery` ([`app/assets/javascripts/bcms/ckeditor.js:5`](../../app/assets/javascripts/bcms/ckeditor.js#L5)) becomes unresolvable. Every page that renders the CMS layout then raises `ActionView::Template::Error`. That is **27 of 33 functional errors and the first 131 cucumber failures**, from one `case` statement.

`ckeditor_rails` **4.5.10** (2016-08-07) is the first release whose branch reads `when /^[45]/`; 4.17.0 reads `/^[4567]/`. Verified against the upstream tags.

Two things make this worth a section rather than a line:

1. **Neither Phase 1 instrument could see it.** The offline scan reads declared requirements and there are none. `bundle_report` searches for newer compatible versions and 4.3.4 *is* compatible by every declaration. The boot smoke test booted — it just never rendered a view. A gem can pass resolution, pass boot, and still be Rails-4-only.
2. **The version number is CKEditor's, not the gem's.** 4.3.4 → 4.5.10 moves CKEditor itself two minor versions and changes the default skin (`moono` at 4.5, `moono-lisa` at 4.16+). This is a WYSIWYG editor in a CMS. See [D3](#d3-how-far-to-move-ckeditor_rails).

**Measured:** bumping to `~> 4.5` on the next bundle resolves to 4.17.0 and the `ckeditor-jquery` error disappears — and the next asset error takes its place ([1.4](#14-sprockets-rails-3-requires-every-referenced-asset-to-be-declared)). The cucumber headline does not move on that change alone.

The second gem in this class is `panoramic`, still unproven under Rails 5 ([P1-1](phase-1-gem-report.md#open-items)) — nothing has rendered a database-backed template yet, and nothing in Phase 2 will until the asset chain clears. Expect it to surface *during* Stage E, not before.

### 1.3 The cucumber suite does not load, and it is one line

```
undefined method `silence_stream' for main:Object
Did you mean?  silence_warnings (NoMethodError)
/Users/.../features/support/env.rb:85:in `<top (required)>'
```

[`features/support/env.rb:85`](../../features/support/env.rb#L85) wraps the seed load in `silence_stream(STDOUT)`. `Kernel#silence_stream` was deprecated in Rails 4.2 and **removed in 5.0**. Cucumber aborts while loading support files, so **exit criterion 11 is currently unmeasurable** — not failing, unmeasurable.

The replacement is version-neutral and needs no `next?` branch:

```ruby
begin
  _old_stdout, $stdout = $stdout, StringIO.new
  require File.join(File.dirname(__FILE__), '../../db/seeds.rb')
ensure
  $stdout = _old_stdout
end
```

This is harness code in `features/`, so it is unambiguously Phase 2's, and it is the cheapest item in the phase. Do it in Stage A, before anything else, because until it lands one of the twelve exit criteria has no number at all.

### 1.4 sprockets-rails 3 requires every referenced asset to be declared

With `ckeditor_rails` bumped, the cucumber failure moves to:

```
cms/logo.png (ActionView::Template::Error)
./app/views/layouts/cms/_main_menu.html.erb:5
```

Rails 5.0 brings **sprockets-rails 3.2.2** (4.2 has 2.3.3), which raises `Sprockets::Rails::Helper::AssetNotPrecompiled` for any asset referenced through `image_tag` / `asset_path` that is not reachable from `config.assets.precompile` or an `app/assets/config/manifest.js`. The engine has neither: [`lib/cms/engine.rb:122-133`](../../lib/cms/engine.rb#L122-L133) lists eight named JS/CSS files and no images, and there is no `app/assets/config/` directory at all.

`app/assets/images/cms/logo.png` is real and on disk. It is simply undeclared, which 4.2 tolerated and 5.0 does not.

Three exits, and they are not equivalent — [D4](#d4-how-to-satisfy-sprockets-rails-3).

**Scope warning.** `logo.png` is the *first* undeclared asset the layout reaches, not the only one. Assume iteration: fix, re-run, find the next. Budget Stage E accordingly, and do not let it be discovered as a surprise inside Phase 5.

### 1.5 What Rails 5.0 does *not* break — four items the phase doc lists as blockers

Each of these was measured on the next bundle at its currently locked version. All four run clean.

| Doc's blocker | Locked | Measured on Rails 5.0.7.2 |
|---|---|---|
| `require 'mocha/setup'` / `'mocha/mini_test'`, **109** call sites | `mocha` 1.2.0 | **Works unchanged.** The spec suite (which requires `mocha/mini_test`) produced zero mocha errors. The 109 figure is `expects`/`stubs`/`mock`/`stub` **API** calls — 127 by exact count — and none of them changes across the rename. `mocha/setup` and `mocha/mini_test` are removed in mocha **2.0**, which nothing forces us onto. |
| `require 'minitest/unit'`, "a Minitest 4 shim" | `minitest` 5.10.3 (next) / 5.19.0 | **Still shipped**, in both. It is a compatibility file that no-ops when `Minitest` is already defined — which `rails/test_help` guarantees. Removing it is hygiene, and it has a consequence: [1.7](#17-removing-minitestunit-exposes-two-tests-that-have-never-run). |
| `factory_girl` / `FactoryGirl`, **42** references | 4.7.0 | **Works unchanged.** No Rails cap, no deprecation on 5.0. The rename is elective, and the *reason* to do it is [1.8](#18-dual-boot-sets-a-ceiling-on-every-harness-bump), not Rails 5. |
| Positional controller args — `get :show, :id => 5`, **89** sites | — | **Deprecation only at 5.0**, removed at **5.1**. The functional run emitted 67 `Using positional arguments in functional tests has been deprecated` warnings and zero errors from them. |

The four that *do* break, and are Phase 2's real Rails-5 work, are `assigns`/`assert_template` (2 live errors, [C.1](#c1--rails-controller-testing-next-bundle-only)), `Devise::TestHelpers` (deprecation, [C.3](#c3--devisetestcontrollerhelpers)), `config.serve_static_assets` + `config.static_cache_control` (deprecations, [D.1](#d1--the-dummy-apps-three-renamed-keys)) and `silence_stream` ([1.3](#13-the-cucumber-suite-does-not-load-and-it-is-one-line)).

**Consequence for sequencing:** the 89 conversions and the two renames are not on the critical path to a green Rails 5 suite. They are on the critical path to **hop 2**. Doing them is right; doing them *first* would be a week spent not moving the number.

### 1.6 The coverage bump silently breaks `coverage:check`

Exit criterion 10 requires branch coverage. Branch coverage needs SimpleCov **≥ 0.18** (`enable_coverage :branch`); the lock is at **0.12.0**. That bump changes a contract Phase 0 built on:

```ruby
# simplecov 0.12.0 — defaults.rb:89
SimpleCov::LastRun.write(:result => {:covered_percent => covered_percent})

# simplecov 0.22.0 — simplecov.rb:285
SimpleCov::LastRun.write(result: result.coverage_statistics.transform_values { ... })
#   => {"result": {"line": 75.82, "branch": 41.3}}
```

[`lib/tasks/core_tasks.rake:43`](../../lib/tasks/core_tasks.rake#L43) does `.fetch('result').fetch('covered_percent')`. After the bump that raises `KeyError` — the *gate itself* fails, which at least fails loudly rather than passing wrongly. Fix it in the same commit as the bump.

Two more things about that bump, both checked:

- **`.last_run.json` is now written only when the coverage check passes** (`write_last_run(result) if result_exit_status == SUCCESS`). Nothing sets `minimum_coverage`, so this is currently always true — but if anyone ever sets it, `coverage:check` starts reading a stale file. Leave `minimum_coverage` unset; the Rakefile's own comment already explains why.
- **The `rails` profile changed from string filters to anchored regexes** (`add_filter "/config/"` → `add_filter %r{^/config/}`). Verified against this repo: zero files under `app/` or `lib/` contain `/config/`, `/db/`, `/test/`, `/spec/`, `/features/` or `/autotest/` in their path, so the anchoring is a no-op here and the denominator should not move for that reason. If the number moves anyway, something else did it — [D5](#d5-how-to-keep-criterion-1-meaningful-across-a-simplecov-bump).

`primary_coverage` must stay at its default `:line`, or `coverage:check` starts gating on branch coverage and the 75.82% baseline stops meaning what Phase 0 recorded.

### 1.7 Removing `minitest/unit` exposes two tests that have never run

Criterion 6 requires the `minitest/unit` requires to go. [`test/unit/extensions/active_record/base_test.rb:13`](../../test/unit/extensions/active_record/base_test.rb#L13) needs them:

```ruby
# Must use vanilla TestCase to avoid ActiveRecord setup conflicts
class TestExtensions < MiniTest::Unit
  def test_throws_error;  ActiveRecord::Base.expects(:connection).raises(StandardError)
                          assert_equal false, ActiveRecord::Base.database_exists?  end
  def test_exists;        assert_equal true,  ActiveRecord::Base.database_exists?  end
end
```

`Minitest::Unit` in minitest 5 is a deprecation shim, **not** a `Runnable`. Verified:

```
$ bundle exec ruby -e 'require "minitest/autorun"; require "minitest/unit"
  class T < MiniTest::Unit; def test_x; end; end
  puts T.ancestors.include?(Minitest::Runnable)      # => false
  puts Minitest::Runnable.runnables.include?(T)'     # => false
```

So both tests are collected by nothing and have never executed — consistent with Phase 0's count of 754 unit tests. Deleting the require converts a silent no-op into a loud `NameError`, which is the right outcome, but it is a decision about two tests, not a require-line edit. `ActiveRecord::Base.database_exists?` is live code ([`app/models/cms/page_route.rb:37`](../../app/models/cms/page_route.rb#L37) calls it), so the tests are worth having.

`test/support/mini_test_matchers.rb:2` reopens `MiniTest::Assertions` — that constant is a live alias in minitest 5 and is fine; rename it for consistency, not necessity.

### 1.8 Dual-boot sets a ceiling on every harness bump

Every gem in this phase has to install under **both** bundles, and that rules out the current major version of two of them. Checked against the RubyGems dependency API:

| Gem | Newest usable on **both** 4.2 and 5.0 | Why not newer |
|---|---|---|
| `factory_bot` / `_rails` | **5.2.0** (`activesupport >= 4.2.0`, `railties >= 4.2.0`) | 6.x requires `activesupport >= 5.0` — installs on the next bundle and **breaks the default one**. |
| `rails-controller-testing` | **not installable on 4.2 at all** (1.0.5 needs `actionpack >= 5.0.1.rc1`) | Must be `if next?`. Harmless: 4.2 supplies `assigns`/`assert_template` natively. |
| `mocha` | 2.8.2 (`ruby >= 2.1`, no Rails dependency) | — |
| `simplecov` | 0.22.0 (`ruby >= 2.5`) | 1.x requires Ruby 3.2. |
| `minitest` | pinned `~> 5.10.3` on next only ([P1-4](phase-1-gem-report.md#open-items)) | Rails 5.0's reporter predates `Minitest::Result`. Do not touch this pin in Phase 2. |

`factory_bot 5.x` removes static attributes, so `m.name "My Site"` must become `m.name { "My Site" }` — **48 sites** across [`test/factories/factories.rb`](../../test/factories/factories.rb) and [`test/factories/attachable_factories.rb`](../../test/factories/attachable_factories.rb). The block form works in `factory_girl` 4.7, so the rewrite can land on 4.2 first, on its own, and be verified against the Phase 0 baseline before the gem changes underneath it. See [D2](#d2-how-far-to-move-factory_girl).

### 1.9 Three of the twelve exit criteria need their commands corrected

Measured, not argued. Fix these in Stage H so the phase is judged on what it meant.

| # | Stated command | Problem |
|---|---|---|
| 4 | `grep -rn "factory_girl\|FactoryGirl" . --exclude-dir=vendor --exclude-dir=.git` | Matches `Gemfile.lock`, `Gemfile.next.lock` and **8 markdown files**, including this plan and the phase doc itself. It can never return nothing. Scope it to `test spec features Gemfile` — where the real count is **42 across 15 files**. |
| 5 | `grep -rnE "^\s*(get\|post\|...)\s+:[a-z_]+\s*,\s*:?[a-z_\"']" test/ spec/` | Correct, and returns **89**, not 88. A broader regex adds only two commented-out lines at `pages_controller_test.rb:207,210`. Keep the criterion; fix the number. |
| 12 | `grep -rn "NextRails" test/ spec/` | `NextRails.next?` is not the branching this repo would reach for — the Gemfile's own `next?` helper is not in scope inside a test. The real risk is `Rails::VERSION` / `Rails.version` / `respond_to?` branching. Grep for those too, exactly as [Phase 1's criterion 9](phase-1-implementation-plan.md#5-exit-criteria-traceability) does. |

---

## 2. Execution order

| Stage | Work item | Produces | Size |
|---|---|---|---|
| **A** | — | The Rails 5 number is measurable for all four suites; probe committed as a script; baseline recorded | S |
| **B** | 2.1 | `factory_bot`, `mocha/minitest`, no `minitest/unit`, SimpleCov with branch coverage | M |
| **C** | 2.2 | `rails-controller-testing`, 89 keyword conversions, `Devise::Test::ControllerHelpers` | M |
| **D** | 2.3 | Dummy app config renamed; both bundles boot clean | S |
| **E** | 2.4 | `poltergeist` gone; the cucumber number driven from 23/154 back to the baseline | **L / unknown** |
| **F** | 2.5 | Monkeypatch and warning-suppression checks discharged | S |
| **G** | criteria 2, 3 | `next-rails` CI job gating | S |
| **H** | 1.9 + corrections | Exit criteria commands fixed; superseded claims corrected in the phase docs | S |

Three deliberate departures from the doc's numbering:

- **Stage A exists and the doc has no equivalent.** Two suites do not load. Everything the doc calls Phase 2 is unverifiable until they do, and both fixes are one line each.
- **Stage E is the unbounded one, and it is assets, not drivers.** The doc budgets §2.4 for a Poltergeist migration that has nothing to migrate; the real cost is [1.2](#12-two-gems-with-no-rails-cap-that-are-hard-gated-on-rails-4) plus an unknown number of iterations of [1.4](#14-sprockets-rails-3-requires-every-referenced-asset-to-be-declared).
- **Stage C is late on purpose.** It is the largest diff in the phase and it fixes two live errors. Landing it early buries Stage E's real failures under 89 unrelated line changes in `git blame`.

**Commit granularity matters more in this phase than in Phase 0 or 1**, because criterion 1 compares a number. Each of B.3, B.4 and C.2 should be its own commit with no other change in it, so that a coverage delta is attributable to one cause. [D5](#d5-how-to-keep-criterion-1-meaningful-across-a-simplecov-bump) is the sharp end of this.

---

## Stage A — Make the Rails 5 number measurable

### A.0 — Reproduce the probe

The measurements in [§1.1](#11-the-rails-50-state-of-all-four-suites) come from running each suite directly rather than through `rake`, which avoids `app:test:prepare` — and therefore avoids a Rails 5 `db:migrate` rewriting `test/dummy/db/schema.rb` into a format the 4.2 suite cannot load ([P1-5](phase-1-gem-report.md#open-items)). Commit this as `script/next_suite.sh`; Stage E will run it many times and Phase 6 will want it at every hop.

```bash
#!/usr/bin/env bash
# Run one suite against Gemfile.next without going through rake.
#
# rake's test tasks depend on app:test:prepare, which on Rails 5 rewrites
# test/dummy/db/schema.rb in 5.0 format and breaks the 4.2 suite that Phase 0
# gated (P1-5). This runs the test files directly against whatever schema the
# database already has, which is what we want until Phase 5 sequences the
# migration properly.
set -u
suite="${1:?usage: next_suite.sh units|spec|functionals|cucumber}"
export BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test launch_on_failure=false

case "$suite" in
  units)       glob='test/unit/**/*_test.rb';       libs='-Ilib -Itest' ;;
  spec)        glob='spec/**/*_spec.rb';            libs='-Ilib -Ispec' ;;
  functionals) glob='test/functional/**/*_test.rb'; libs='-Ilib -Itest' ;;
  cucumber)
    exec bundle exec cucumber features --format progress \
      --tags ~@cli -t ~@missing-feature -t ~@known-bug ;;
esac

COVERAGE_SUITE="Next $suite" exec bundle exec ruby $libs \
  -e "Dir[\"$glob\"].sort.each { |f| require File.expand_path(f) }"
```

- [ ] Script committed; `script/next_suite.sh units` reproduces `754 runs … 2 failures`

### A.1 — Confirm the two Phase 3 unblockers have landed

See [D1](#d1-phase-3s-two-unblockers-come-first).

Both are backwards-compatible and belong to Phase 3, but Phase 2 cannot see its own failures through them.

| | Change | Effect on the Rails 5 numbers |
|---|---|---|
| [P1-2](phase-1-gem-report.md#open-items) | [`lib/cms/behaviors/versioning.rb:230`](../../lib/cms/behaviors/versioning.rb#L230) — `def create_or_update` → `def create_or_update(*args, &block)`; `super` already passes through | units 323E → 4E; spec 13E → 0E |
| new | [`content_controller.rb:11`](../../app/controllers/cms/content_controller.rb#L11) and [`portlet_controller.rb:4`](../../app/controllers/cms/portlet_controller.rb#L4) — `skip_before_filter :redirect_to_cms_site` on a controller that never registered it. Rails 5 raises `ArgumentError: Before process_action callback :redirect_to_cms_site has not been defined` **at class-definition time** | functional suite: does not load → loads |

The second one is worth understanding rather than pattern-matching. `Cms::ContentController` descends from `Cms::ApplicationController`, not `Cms::BaseController` — so `redirect_to_cms_site` was never in its callback chain and the skip was always a no-op. Rails 4.2 ignored it; Rails 5.0 makes `skip_callback` raise unless `raise: false`. **Deleting the line is the honest fix and `raise: false` is the compatible one** — that is Phase 3's call, not this plan's. Note there are 33 `before_filter` and 2 `skip_before_filter` sites in `app/` and `lib/` behind it.

- [ ] Both landed on the default bundle, 4.2 suite still green at 75.82%
- [ ] `script/next_suite.sh functionals` runs to completion

### A.2 — `silence_stream` ([1.3](#13-the-cucumber-suite-does-not-load-and-it-is-one-line))

This one *is* Phase 2's — it is in `features/`. Apply the version-neutral replacement from [1.3](#13-the-cucumber-suite-does-not-load-and-it-is-one-line).

```bash
bundle exec cucumber features/manage_sections.feature --format progress          # 4.2, still green
BUNDLE_GEMFILE=Gemfile.next bundle exec cucumber features/manage_sections.feature # 5.0, now loads
```

- [ ] Both load; the 4.2 default profile is still 154/154

### A.3 — Record the entry baseline

Create `docs/rails-upgrade/phase-2-harness-report.md` and put [§1.1](#11-the-rails-50-state-of-all-four-suites)'s third column in it as the **starting** number, before any Stage B–E work. Criterion 11 compares the cucumber rate to Phase 0's; this is the other end of that comparison and it is worth having in the repo rather than in a terminal.

- [ ] Report created with all four suites' entry numbers and every error classified as harness / app / gem

---

## Stage B — Gem renames and requires (2.1)

### B.1 — `mocha`

One require in each helper. `mocha/minitest` first appears in mocha **1.3.0**; the current 1.2.0 does not ship it, so this is a bump as well as a rename.

```ruby
# test/test_helper.rb:13
- require 'mocha/setup'
+ require 'mocha/minitest'

# spec/minitest_helper.rb:8
- require "mocha/mini_test"
+ require "mocha/minitest"
```

```ruby
# Gemfile, :test group -- no Rails dependency, ruby >= 2.1, installs on both bundles
gem 'mocha', '~> 2.8', require: false
```

Mocha 2.0's removals are exactly the two files being deleted here plus `mocha/test_unit`, none of which survive this commit. `expects`, `stubs`, `mock`, `stub` and `returns`/`raises`/`with` are unchanged — 127 call sites, verified to contain no `Mocha::Configuration`, `mocha_setup`, `mocha_teardown`, `stubba` or `unstub` usage. If 2.x surprises you, `~> 1.16` is the fallback: last of the 1.x line, ships `mocha/minitest`, keeps criterion 6 satisfied.

- [ ] Both bundles green on units + spec; criterion 6 grep is empty

### B.2 — `minitest/unit`, and the two dead tests ([1.7](#17-removing-minitestunit-exposes-two-tests-that-have-never-run))

Drop the require from `test/test_helper.rb:9`, `test/minitest_helper.rb:6` and `spec/minitest_helper.rb:7`. Then deal with what falls out:

- `test/unit/extensions/active_record/base_test.rb:13` — reparent `TestExtensions` to `ActiveSupport::TestCase`. **Expect it to fail on first run**: the comment says "must use vanilla TestCase to avoid ActiveRecord setup conflicts", and it stubs `ActiveRecord::Base.connection` to raise, which a transactional test case will not enjoy. Two tests that have never run are two tests to actually make pass. If they cannot be made to pass cheaply, quarantine them with a reason string in the Phase 0 register format rather than deleting them — `database_exists?` is live code.
- `test/support/mini_test_matchers.rb:2` — `MiniTest::Assertions` → `Minitest::Assertions`. Cosmetic; `MiniTest` is still a live alias.

**This is the one place in the phase where the test count legitimately goes up**, from 994 to 996. Say so in the report; criterion 1 is about coverage not dropping, and an *increase* here has a named cause.

- [ ] Criterion 6 grep empty; both bundles green; the count change recorded

### B.3 — `factory_girl` → `factory_bot`, in two commits

**Commit one, on 4.2 only, no gem change:** convert the **48** static attributes to blocks. `m.name "My Site"` → `m.name { "My Site" }`. `factory_girl` 4.7 accepts both, so this commit is provably behaviour-neutral — run the full 4.2 suite and confirm 994/0/0 and 75.82% before touching the Gemfile.

**Commit two:** the rename.

```ruby
# Gemfile -- 5.2.0 is the ceiling; 6.x needs activesupport >= 5.0 and breaks the 4.2 bundle (1.8)
- gem 'factory_girl_rails'
+ gem 'factory_bot_rails', '~> 5.2.0'
```

Then 42 references across 15 files: `FactoryGirl` → `FactoryBot`, `FactoryGirl::Syntax::Methods` → `FactoryBot::Syntax::Methods`, `FactoryGirl.define` → `FactoryBot.define`, `require 'factory_girl'` → `require 'factory_bot'`. `create(:x)` / `build(:x)` are unaffected. Both `test/test_helper.rb:52` and the two `minitest_helper.rb`s include the syntax module; `features/support/env.rb:12` does it through `World(...)`.

Splitting it this way means that if the suite goes red, you know which half did it.

- [ ] Criterion 4 grep (scoped per [1.9](#19-three-of-the-twelve-exit-criteria-need-their-commands-corrected)) empty
- [ ] 4.2 suite still 994/0/0 at 75.82% after *each* commit

### B.4 — SimpleCov, branch coverage, and the gate

The contract break is [1.6](#16-the-coverage-bump-silently-breaks-coveragecheck).

One commit, three edits, no other change in it.

```ruby
# Gemfile
- gem 'simplecov', require: false
+ gem 'simplecov', '~> 0.22.0', require: false
```

```ruby
# .simplecov -- inside the existing SimpleCov.start 'rails' block
  # Line-only coverage cannot see an untested branch of a conditional, and the
  # monkeypatches under lib/cms/extensions are almost entirely conditionals.
  # primary_coverage stays :line so coverage:check keeps gating on the number
  # Phase 0 recorded.
  enable_coverage :branch
```

```ruby
# lib/tasks/core_tasks.rake:43
# SimpleCov >= 0.18 writes {"result": {"line": x, "branch": y}}; 0.12 wrote
# {"result": {"covered_percent": x}}. Read line, and fail loudly on neither.
  result = JSON.parse(File.read(path)).fetch('result')
  actual = result['line'] || result['covered_percent'] or
    abort "#{path} has neither 'line' nor 'covered_percent' -- SimpleCov format changed again"
```

Also delete the now-obsolete half of the `.simplecov` comment about `parse_filter` raising on a `Regexp` — 0.18+ accepts regexes. Keep the block filters; they work in both and rewriting them is a second variable.

- [ ] `rake coverage:check` prints a number rather than raising `KeyError`
- [ ] The report shows a branch percentage (criterion 10)
- [ ] The **line** percentage is compared against 75.82% and the delta, if any, is explained in the report — see [D5](#d5-how-to-keep-criterion-1-meaningful-across-a-simplecov-bump)

---

## Stage C — Controller test API (2.2)

### C.1 — `rails-controller-testing`, next bundle only

The gem requires `actionpack >= 5.0.1.rc1` and **cannot be installed on the 4.2 bundle** ([1.8](#18-dual-boot-sets-a-ceiling-on-every-harness-bump)). That is fine — 4.2 supplies `assigns` and `assert_template` natively.

```ruby
# Gemfile, :test group
# assigns/assert_template were extracted from Rails at 5.0. On 4.2 they are
# still built in and this gem will not install (it needs actionpack >= 5.0.1).
# Conditional here so the *test code* stays identical on both bundles -- see
# exit criterion 12.
gem 'rails-controller-testing' if next?
```

It hooks itself into `ActionController::TestCase` and `ActionDispatch::IntegrationTest` through `ActiveSupport.on_load`; no include is needed. The 19 `assert_template` sites (`links`, `pages`, `sections` controller tests) and 11 `assigns` sites (`pages`, `sections`, `html_blocks`) stay exactly as written.

- [ ] `BUNDLE_GEMFILE=Gemfile.next bundle install`; the 2 live `assigns has been extracted to a gem` errors are gone
- [ ] `Gemfile.lock` unchanged — inspect the diff (criterion 2 depends on 4.2 not moving)

### C.2 — 89 positional calls → keyword form

Its own commit, nothing else in it. **89**, not 88 ([1.9](#19-three-of-the-twelve-exit-criteria-need-their-commands-corrected)), distributed:

| File | Sites |
|---|---|
| [`test/functional/cms/pages_controller_test.rb`](../../test/functional/cms/pages_controller_test.rb) | 25 |
| [`test/functional/cms/sections_controller_test.rb`](../../test/functional/cms/sections_controller_test.rb) | 18 |
| [`test/functional/cms/content_controller_test.rb`](../../test/functional/cms/content_controller_test.rb) | 16 |
| [`test/functional/cms/links_controller_test.rb`](../../test/functional/cms/links_controller_test.rb) | 10 |
| [`test/functional/cms/html_blocks_controller_test.rb`](../../test/functional/cms/html_blocks_controller_test.rb) | 9 |
| `tasks` 4 · `file_blocks` 3 · `content_block` 3 · `test/dummy/test/controllers/design_controller_test.rb` 1 | 11 |

`get :show, :path => "about"` → `get :show, params: { path: "about" }`. Rails 4.2 accepts the keyword form, so there is no conditional and no `next?`.

Two things that are *not* mechanical:

- `content_controller_test.rb:218,302` pass `:use_route => false` alongside real params. `use_route` is a test-framework option, not a param — it belongs outside the `params:` hash, and it is deprecated in 5.0. Handle these two by hand.
- Nothing in the suite uses `xhr :get` or `xml_http_request` (verified: zero sites), so the `xhr: true` conversion the skill's 4.2→5.0 guide describes does not apply here. Do not go looking for it.

Verify with the criterion-5 regex, which was checked against a broader one and differs only by two commented-out lines:

```bash
grep -rnE "^\s*(get|post|put|patch|delete)\s+:[a-z_]+\s*,\s*:?[a-z_\"']" test/ spec/   # expect: nothing
```

- [ ] Criterion 5 grep empty; both bundles green on functionals
- [ ] The 67 positional deprecation warnings are gone from the Rails 5 log

### C.3 — `Devise::Test::ControllerHelpers`

[`test/test_helper.rb:202`](../../test/test_helper.rb#L202). Devise is **4.9.4 in both bundles**, so the new constant exists on 4.2 as well and this needs no conditional.

```ruby
class ActionController::TestCase
-  include Devise::TestHelpers
+  include Devise::Test::ControllerHelpers
end
```

- [ ] Criterion 8 grep empty; the `[Devise] including Devise::TestHelpers is deprecated` warning is gone

---

## Stage D — Dummy app config (2.3)

### D.1 — The dummy app's three renamed keys

The doc lists two. The Rails 5 boot log shows a third.

| File | Line | Change |
|---|---|---|
| [`test/dummy/config/environments/test.rb`](../../test/dummy/config/environments/test.rb#L11) | 11 | `config.serve_static_assets = true` → `config.public_file_server.enabled = true` |
| [`test/dummy/config/environments/test.rb`](../../test/dummy/config/environments/test.rb#L12) | 12 | `config.static_cache_control = "public, max-age=3600"` → `config.public_file_server.headers = { 'Cache-Control' => 'public, max-age=3600' }` |
| [`test/dummy/config/environments/production.rb`](../../test/dummy/config/environments/production.rb#L20) | 20 | `config.serve_static_assets = true` → `config.public_file_server.enabled = true` |

**These are not backwards-compatible.** `public_file_server` does not exist in Rails 4.2 — assigning it on 4.2 raises `NoMethodError` on `Rails::Application::Configuration`. The dummy app is the thing the entire suite boots against, so this is the one place a `next?`-style conditional is unavoidable. Use the environment, the way [`browsercms.gemspec`](../../browsercms.gemspec#L13) already does, and comment it:

```ruby
# Renamed at Rails 5.0; the 4.2 name is gone at 5.1 and the 5.0 name does not
# exist on 4.2, so this cannot be written once for both bundles. Delete the
# else-branch at Phase 5, when the default Gemfile moves.
if Rails::VERSION::MAJOR >= 5
  config.public_file_server.enabled = true
  config.public_file_server.headers = { 'Cache-Control' => 'public, max-age=3600' }
else
  config.serve_static_assets = true
  config.static_cache_control = "public, max-age=3600"
end
```

**This trips criterion 12 as written, and it should.** Criterion 12 is about test *code* not branching on the Rails version; dummy-app environment config is exactly the case the criterion's own escape hatch ("any occurrence needs a comment justifying why the test genuinely cannot be version-neutral") exists for. Record it as the single justified occurrence, with this reason, in the report.

Two more keys in the dummy app are dead rather than renamed, and are worth deleting while you are here: `config.assets.compress` (`production.rb:23`, `development.rb:27`) was removed in Rails 4.0, and `config.action_dispatch.best_standards_support` (`development.rb:24`) in 4.1. Both are silently ignored today. Neither is load-bearing — `development` is never booted by the suite ([Phase 0, F1](phase-0-baseline.md#environment-findings)).

- [ ] Criterion 9 grep empty; both bundles boot; the two config deprecations are gone from the Rails 5 log

### D.2 — Boot both, and diff the deprecations

Phase 1's [false-green trap](phase-1-gem-report.md#the-false-green-trap) is the reason this step is not "it booted, move on":

```bash
RAILS_ENV=test bundle exec ruby -e 'require "./test/dummy/config/environment"; puts Rails.version' 2> tmp/phase2/boot-42.log
BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test bundle exec ruby -e 'require "./test/dummy/config/environment"; puts Rails.version' 2> tmp/phase2/boot-50.log
diff tmp/phase2/boot-42.log tmp/phase2/boot-50.log
```

Do not trust `BUNDLE_GEMFILE` on the command line — assert the printed version, exactly as the `next-rails` CI job does.

- [ ] Both print the expected version; the deprecation diff contains nothing unaccounted for

---

## Stage E — The cucumber stack (2.4)

**This is the unbounded stage** and its content bears no resemblance to the doc's §2.4. There is no driver to migrate: zero `@javascript` tags, both `Capybara.*_driver` assignments commented out at [`features/support/env.rb:19-20`](../../features/support/env.rb#L19-L20), and the suite is green in CI with no browser installed. The work is the asset chain from [1.2](#12-two-gems-with-no-rails-cap-that-are-hard-gated-on-rails-4) and [1.4](#14-sprockets-rails-3-requires-every-referenced-asset-to-be-declared).

### E.1 — Delete `poltergeist` ([P1-7](phase-1-gem-report.md#open-items))

`gem 'poltergeist'` at [`Gemfile:67`](../../Gemfile#L67), `require 'capybara/poltergeist'` at [`features/support/env.rb:16`](../../features/support/env.rb#L16), and the two commented assignments below it. Nothing else references it. This is free and it removes a PhantomJS dependency from the CI story permanently.

- [ ] Gone; cucumber default profile still 154/154 on 4.2

### E.2 — `ckeditor_rails` ([1.2](#12-two-gems-with-no-rails-cap-that-are-hard-gated-on-rails-4), [D3](#d3-how-far-to-move-ckeditor_rails))

Whatever [D3](#d3-how-far-to-move-ckeditor_rails) decides, the constraint lives at [`browsercms.gemspec:51`](../../browsercms.gemspec#L51) and follows the `NEXT_BOOT` pattern already established there:

```ruby
# 4.3.4 dispatches its Railtie on `case ::Rails.version` and has no Rails 5
# branch, so on 5.0 its asset path never loads and `//= require ckeditor-jquery`
# fails. 4.5.10 is the first release that matches /^[45]/. Note the version
# tracks CKEditor itself, so this is an editor upgrade as well as a gem bump.
s.add_dependency("ckeditor_rails", NEXT_BOOT ? "~> 4.5" : "~> 4.3.0")
```

**Verified:** this resolves to 4.17.0 and the `ckeditor-jquery` error disappears. It does **not** move the cucumber headline on its own — the next asset error takes its place.

- [ ] `couldn't find file 'ckeditor-jquery'` gone from the Rails 5 functional and cucumber logs
- [ ] The CMS editor loads and edits a block on Rails 5 by hand, not just in the suite ([D3](#d3-how-far-to-move-ckeditor_rails))

### E.3 — sprockets-rails 3 asset declaration

Background in [1.4](#14-sprockets-rails-3-requires-every-referenced-asset-to-be-declared); the choice is [D4](#d4-how-to-satisfy-sprockets-rails-3).

Iterate: run, read the raised asset name, declare it, run again. `cms/logo.png` is the first, reached from [`app/views/layouts/cms/_main_menu.html.erb:5`](../../app/views/layouts/cms/_main_menu.html.erb#L5); it will not be the last. Whichever exit [D4](#d4-how-to-satisfy-sprockets-rails-3) picks, apply it to the **engine** ([`lib/cms/engine.rb:122`](../../lib/cms/engine.rb#L122)) rather than the dummy app, because consuming applications hit exactly the same wall at Phase 5.

- [ ] No `AssetNotPrecompiled` / `couldn't find file` in the Rails 5 cucumber log
- [ ] The declaration is in the engine, so a consuming app inherits it

### E.4 — Drive the number, then compare

```bash
script/next_suite.sh cucumber                                       # target: 154/154
bundle exec rake features                                           # 4.2, must stay 154/154
```

Criterion 11 is "equal to or better than Phase 0's baseline". The 4.2 baseline is **154/154 in the default profile, 161/193 across all 53 files**. Both bundles are compared against it.

Two things this stage explicitly does not do:

- **The `@cli` / aruba features stay at 7/34.** They shell out through aruba and fail because `rails new petstore --skip-bundle` does not complete inside it ([Phase 0, O1](phase-0-baseline.md)). That is a generator problem, not a harness-migration problem, and fixing it is a coverage improvement — which the phase doc's "explicitly not in this phase" rules out. Keep the number visible in the `excluded-features` CI job; do not let it drift.
- **No `cucumber` / `cucumber-rails` / `capybara` / `database_cleaner` bump.** `cucumber-rails 1.4.5` caps `railties < 5.1`, which clears this hop and blocks the next one ([P1-4](phase-1-gem-report.md#open-items) neighbourhood). Moving four test gems at once, in the stage that is already unbounded, buys nothing for 5.0. It is hop 2's first task and Phase 6 already records it as such.

- [ ] Cucumber ≥ baseline on **both** bundles (criterion 11)

---

## Stage F — Housekeeping that affects signal (2.5)

Both items are verifications, and both are already discharged by the Stage A probe logs. Confirm rather than assume, then tick.

### F.1 — The `MonitorMixin` / `recycle!` monkeypatch

[`test/test_helper.rb:227-248`](../../test/test_helper.rb#L227-L248) patches `ActionController::TestResponse#recycle!` for the Ruby 2.6+/Rails 4.2 `ThreadError`. It is guarded by `Gem::Version.new(Rails.version) < '5.0.0'` and the Rails 5 runs print its else-branch:

```
Monkeypatch for ActionController::TestResponse no longer needed
```

**Verified benign.** Leave it in place — it is still load-bearing on 4.2, which is the default bundle until Phase 5. Delete it there, not here. Consider demoting the two `puts` to a comment; they are noise in every run of both bundles.

### F.2 — Warning suppression

`grep -rn '\$VERBOSE' test spec features lib Rakefile` returns nothing — Phase 0's removal held, and none of the gems bumped in Stage B reintroduced a blanket suppression. Re-run it after Stage B, since that is when the gems change.

One thing the newly-current gems *do* surface, and it should stay surfaced: `DEPRECATED: Use assert_nil if expecting nil` from minitest, raised at runtime by an `assert_equal` whose expected value is a nil variable. It does not grep (`assert_equal nil` appears zero times in source), so it can only be found by reading the run log. Record the sites in the report; fixing them is optional and version-neutral.

- [ ] Both greps re-run post-Stage-B and recorded

---

## Stage G — Make the Rails 5 CI job gating

Criteria 2 and 3. The `next-rails` job already exists from [Phase 1 Stage E](phase-1-implementation-plan.md#stage-e--ci-on-gemfilenext-11-last-item) and already asserts the Rails version explicitly. Two changes:

```yaml
   next-rails:
     name: Rails 5.0 (Gemfile.next)
     runs-on: ubuntu-22.04
     timeout-minutes: 45
-    # Expected red for the whole of Phases 1-4. ...
-    continue-on-error: true
+    # Gating from Phase 2 onward: the harness migration's contract is that the
+    # same suite passes on both bundles. Phase 2 exit criterion 3.
```

and add the coverage check, which the job currently never runs because `rake` is invoked directly rather than `ci:test`:

```yaml
      - name: Suite
        run: bundle exec rake
```

`rake`'s default *is* `ci:test`, which is enhanced with `coverage:check` — so this already holds once [B.4](#b4--simplecov-branch-coverage-and-the-gate) fixes the task. Confirm it in a real run rather than by reading the Rakefile.

**Do not flip `continue-on-error` until Stage E's number is actually green.** A gating job that is red on merge day is worse than a reporting job that is red, because the next person turns it off again.

- [ ] Both CI jobs green on a real run (criteria 2 and 3)
- [ ] `Gemfile.next.lock` committed with every gem change from Stages B–E

---

## Stage H — Correct the record

Measurement beats working knowledge, and this phase contradicts several documents.

- [ ] [`phase-2-harness-migration.md`](phase-2-harness-migration.md) — the "Blocker" table in *Why this phase exists*: mocha, factory_girl, `minitest/unit` and the 88 positional args are **not** Rails 5.0 blockers ([1.5](#15-what-rails-50-does-not-break--four-items-the-phase-doc-lists-as-blockers)); the `serve_static_assets` row is missing `static_cache_control`; §2.4's driver migration has no subject
- [ ] [`phase-2-harness-migration.md`](phase-2-harness-migration.md) — exit criteria 4, 5 and 12's commands ([1.9](#19-three-of-the-twelve-exit-criteria-need-their-commands-corrected))
- [ ] [`phase-1-gem-report.md`](phase-1-gem-report.md) — move `ckeditor_rails` out of *already compatible*. It has no cap and it is Rails-4-only. Add the general lesson next to the `panoramic` and `minitest` ones: **a declared requirement is not a compatibility claim, and a boot is not a render.**
- [ ] [`phase-3-backwards-compatible-fixes.md`](phase-3-backwards-compatible-fixes.md) — add the `skip_before_filter` / `skip_callback` item ([A.1](#a1--confirm-the-two-phase-3-unblockers-have-landed)), the `StaleObjectError` pair, the `to_hash` parameter-filtering deprecation (3 sites), and the `save!(perform_validations=true)` arity at [`versioning.rb:264`](../../lib/cms/behaviors/versioning.rb#L264), which is the same class of bug as [P1-2](phase-1-gem-report.md#open-items) and has not been hit yet only because nothing has called `save!(validate: false)`
- [ ] [`phase-5-the-5.0-bump.md`](phase-5-the-5.0-bump.md) — the sprockets-rails 3 asset declaration is engine-wide and consuming applications inherit it
- [ ] [`phase-6-subsequent-hops.md`](phase-6-subsequent-hops.md) — add `script/next_suite.sh` next to `script/rails_blockers.rb`, and record that `table_exists?` (19 harness sites, 3 in `app/`+`lib/`) changes behaviour at **5.1**; `data_source_exists?` does not exist on 4.2, so it is not a Phase 2 change
- [ ] [`README.md`](README.md) — Phase 2 status, and drop the "Needs re-scoping" note once this plan supersedes it

---

## 3. Decisions that need a human

### D1: Phase 3's two unblockers come first
The functional suite does not load and 333 of 336 unit+spec problems are one method signature. Phase 2 cannot measure itself through either.
**(a)** Land [P1-2](phase-1-gem-report.md#open-items) and the `skip_callback` fix as Phase 3's first two commits, *before* Phase 2 starts — both are backwards-compatible, both verify against the Phase 0 baseline on 4.2 alone, and Phase 2 then starts from a readable number.
**(b)** Keep the phase boundary and have Phase 2 carry them as local patches, reverting before each commit — preserves the doc's "no application code changes" rule and costs a day of friction.
**(c)** Move both into Phase 2 permanently, on the grounds that "beyond what the harness needs to boot" already licenses them.
**Recommendation: (a).** The phases are already documented as parallelisable, and this is a two-commit dependency, not a merge. (c) is defensible but it makes Phase 3's own scope harder to judge later, and Phase 3 wants the `before_filter` sweep in the same neighbourhood anyway.

### D2: How far to move `factory_girl`
**(a)** `factory_bot_rails ~> 5.2.0` — installs on both bundles, and requires rewriting **48** static attributes as blocks.
**(b)** `factory_bot_rails ~> 4.11.1` — a pure rename; static attributes still work, with a deprecation warning. Satisfies criterion 4 for a fraction of the diff.
**(c)** Stay on `factory_girl`. Rails 5.0 does not care ([1.5](#15-what-rails-50-does-not-break--four-items-the-phase-doc-lists-as-blockers)) — but criterion 4 says otherwise, and the gem's last release was 2017.
**Recommendation: (a), split into the two commits in [B.3](#b3--factory_girl--factory_bot-in-two-commits).** The block rewrite is provably behaviour-neutral on the current gem, so it costs verification effort rather than risk, and (b) just books the same 48 edits for hop 2 with a deprecation warning attached. 6.x is not an option at all: it needs `activesupport >= 5.0` and would break the default bundle.

### D3: How far to move `ckeditor_rails`
The gem's version *is* CKEditor's version, so this is an editor upgrade wearing a dependency bump's clothes.
**(a)** `NEXT_BOOT ? "~> 4.5" : "~> 4.3.0"` — resolves to 4.17.0 on Rails 5, leaves 4.2 untouched. Two bundles run two different editors, which is a real divergence in the thing users actually touch.
**(b)** `~> 4.5` unconditionally — both bundles get the same editor, so anything the upgrade breaks in the CMS UI is caught by the 4.2 suite too, which is the suite that is green. Costs a change to a bundle Phase 0 baselined.
**(c)** Pin `4.5.10` exactly — the oldest release that works on Rails 5, so the smallest CKEditor jump (4.3 → 4.5, same `moono` default skin; 4.16+ switches to `moono-lisa`).
**Recommendation: (c) for the next bundle, then (b) at Phase 5.** The default skin change is a visible, user-facing difference in a CMS's editor, and taking it during a harness migration means a UI regression and a Rails regression arrive in the same commit. Whichever is chosen, **open the editor by hand on Rails 5 and edit a block** — the cucumber suite has no `@javascript` scenarios, so it cannot tell you the editor works.

### D4: How to satisfy sprockets-rails 3
**(a)** `app/assets/config/manifest.js` in the engine with `link_tree ../images` — the Rails 5+ idiom, declares everything at once, and is what the engine will need at every subsequent hop anyway.
**(b)** Extend `config.assets.precompile` in [`lib/cms/engine.rb:122`](../../lib/cms/engine.rb#L122) — consistent with what is already there, and it grows one line per asset discovered.
**(c)** `config.assets.check_precompiled_asset = false` in the dummy app's `test.rb` — makes the tests pass today and guarantees the same failure appears in a consuming application at Phase 5, where it is far more expensive.
**Recommendation: (a).** It is the destination, it is one file, and it fixes the whole class rather than the instances. (c) is the trap: it converts a loud test failure into a silent production one, which is precisely the failure mode [`RAILS_UPGRADE_TEST_PRIORITY.md`](../../RAILS_UPGRADE_TEST_PRIORITY.md) ranks the whole plan by.

### D5: How to keep criterion 1 meaningful across a SimpleCov bump
Criterion 1 reads a coverage drop as lost tests. A version bump that changes how coverage is *computed* can move the number for reasons that have nothing to do with tests, and the criterion cannot tell the difference.
**(a)** Bump SimpleCov in a commit containing nothing else, measure before and after on 4.2, and if the line percentage moves, record the new baseline in the report **with the delta and its cause** and update `COVERAGE_MINIMUM`. Every later commit is then judged against a stable floor.
**(b)** Keep 0.12.0 and drop criterion 10. Branch coverage waits for the Ruby bump that 0.18+ needs anyway.
**(c)** Bump, and treat any movement as a real drop.
**Recommendation: (a).** The `rails` profile's only substantive change is filter anchoring, and that is verified to be a no-op for this repo ([1.6](#16-the-coverage-bump-silently-breaks-coveragecheck)) — so the honest expectation is that the number does not move, and (a) is how you find out rather than assume. (c) would block the phase on an artefact. (b) forfeits the one criterion that would tell you whether the monkeypatches under `lib/cms/extensions` are exercised on both sides of their conditionals, which is the most Rails-sensitive code in the engine.

---

## 4. Contingencies

| If | Then |
|---|---|
| The sprockets asset chain ([E.3](#e3--sprockets-rails-3-asset-declaration)) turns out to be dozens of assets deep | It is still Phase 2's — the suite cannot be green without it. But stop and re-scope out loud rather than absorbing it silently; it is the one item here with no measured upper bound. |
| `panoramic` 0.0.6 fails once templates finally render ([P1-1](phase-1-gem-report.md#open-items)) | Stop. That is Phase 1's deferred blocker coming due, and vendor-vs-replace is a [D2-class decision](phase-1-implementation-plan.md#d2-panoramic) that does not belong inside a harness migration. |
| `mocha 2.x` breaks call sites | Fall back to `~> 1.16`. It ships `mocha/minitest`, so criterion 6 is satisfied either way, and mocha's major version is not on any Rails deadline. |
| The 4.2 coverage number moves and the cause is not SimpleCov | Revert to the last commit where it held and bisect. Criterion 1 is the only instrument that can detect a lost test during a port, and a number nobody trusts is not an instrument. |
| `Gemfile.lock` drifts during Stages B–E | Revert and redo, exactly as in [Phase 1](phase-1-implementation-plan.md#4-contingencies). Criterion 2 is that 4.2 stays green; an incidental bump invalidates the baseline everything else is measured against. |
| Cucumber cannot reach the baseline on Rails 5 by the end of Stage E | Do **not** flip `continue-on-error` ([Stage G](#stage-g--make-the-rails-5-ci-job-gating)). Report the number, keep the job non-gating, and hand Phase 5 an honest gap. A gating job that is red on day one gets switched off by the next person and never switched back. |
| Someone proposes deleting a test to make Rails 5 green | That is the failure mode criteria 1 and 3 exist to catch, and it is why they must hold *simultaneously*. Quarantine with a reason string in the Phase 0 register format instead. |

---

## 5. Exit criteria traceability

| # | Criterion | Stage | Verification |
|---|---|---|---|
| 1 | Coverage still reads the Phase 0 baseline on 4.2 | B.4, all | `rake coverage:check` ≥ 75.82% (or the [D5](#d5-how-to-keep-criterion-1-meaningful-across-a-simplecov-bump) re-baseline, with its cause recorded) |
| 2 | Suite green on the default Gemfile | all | `test` CI job passing; `Gemfile.lock` diff contains only intended changes |
| 3 | Suite green on `Gemfile.next` | A–G | `next-rails` job passing with `continue-on-error` removed |
| 4 | Zero `factory_girl` references | B.3 | `grep -rn "factory_girl\|FactoryGirl" test spec features Gemfile` empty — scoped per [1.9](#19-three-of-the-twelve-exit-criteria-need-their-commands-corrected) |
| 5 | Zero positional controller-test calls | C.2 | The doc's regex, empty. Entry count is **89** |
| 6 | No `mocha/setup`, `mocha/mini_test`, `minitest/unit` | B.1, B.2 | `grep -rn "mocha/setup\|mocha/mini_test\|minitest/unit" test/ spec/` empty |
| 7 | `rails-controller-testing` declared; 19 + 11 sites pass | C.1 | Present under `if next?`; those tests green on `Gemfile.next` |
| 8 | No `Devise::TestHelpers` | C.3 | `grep -rn "Devise::TestHelpers" test/ spec/` empty |
| 9 | No `serve_static_assets` | D.1 | `grep -rn "serve_static_assets" test/ config/` empty. **Also** `static_cache_control` |
| 10 | Branch coverage enabled and reported | B.4 | Report shows a branch percentage; `primary_coverage` still `:line` |
| 11 | Cucumber ≥ Phase 0's baseline | A.2, E | 154/154 default profile on **both** bundles; 161/193 across all 53 files |
| 12 | No version branching added to make the suite pass | all | `grep -rn "NextRails\|Rails::VERSION\|Rails\.version" test/ spec/ features/` — one justified occurrence expected, at [D.1](#d1--the-dummy-apps-three-renamed-keys), with the reason recorded |

**A note on criterion 12.** [D.1](#d1--the-dummy-apps-three-renamed-keys) introduces a `Rails::VERSION::MAJOR` branch in the dummy app's `test.rb` because `public_file_server` does not exist on 4.2 and `serve_static_assets` is gone at 5.1 — there is no expression that is valid on both. That is the criterion's escape hatch being used as intended, and it disappears at Phase 5. Anything *else* that grep finds is a smell: it means a test was made to pass rather than made to be portable, which is the difference criteria 1 and 3 exist to detect.

**A note on criteria 1 and 3 together.** The phase document is right that these two holding simultaneously is the strongest signal, and [§1.1](#11-the-rails-50-state-of-all-four-suites) is why it matters here specifically: the fastest route to a green Rails 5 suite runs through 131 cucumber scenarios that fail on assets. Deleting or tagging out a scenario is cheap, invisible in the Minitest count, and shows up in criterion 11 only if someone compares against the committed baseline. Compare against it.
