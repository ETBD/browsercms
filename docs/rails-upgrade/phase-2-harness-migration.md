# Phase 2 — Harness Migration

> ## Goal
> **Make the test suite capable of running on Rails 5, while still on Rails 4.2, without losing a single test.**
>
> The suite does not currently *fail* on Rails 5 — it does not boot. Until that's fixed, no test result from the upgrade means anything, and any test written before this phase gets written twice.

**Blocking:** 🔴 Yes.
**Rails version at the end of this phase:** 4.2.11.3, with the suite green on **both** the default Gemfile and `Gemfile.next`.

---

## Why this phase exists

The 9,807 lines of existing test code are the primary asset being protected by this entire upgrade. They are also written against a 2016-era harness that Rails 5 removes out from under them:

| Blocker | Sites | Breaks at |
|---|---|---|
| `require 'mocha/setup'` (`test/test_helper.rb:13`), `require 'mocha/mini_test'` (`spec/minitest_helper.rb:8`) | **109** mocha call sites | Mocha 2.0 |
| `factory_girl` / `FactoryGirl` | **42** references, plus every `create(:x)` | Renamed `factory_bot` in 2017 |
| `require 'minitest/unit'` (`test/test_helper.rb:9`, `spec/minitest_helper.rb:7`) | 2 requires, suite-wide effect | A Minitest 4 shim |
| Positional controller-test args — `get :show, :id => 5` | **88** | Rails 5 requires `params: {}` |
| `assert_template` | **19** | Extracted to `rails-controller-testing` at 5.0 |
| `assigns(...)` | **11** | Same gem |
| `Devise::TestHelpers` (`test/test_helper.rb:199`) | 1 | Devise 4.2 → `Devise::Test::ControllerHelpers` |
| `config.serve_static_assets` | 2 — `test/dummy/config/environments/{test,production}.rb` | Renamed `config.public_file_server.enabled` at 5.0 |
| `cucumber` 2.4.0 / `capybara` 2.10.1 / `poltergeist` / `aruba` 0.14.14 | 53 features | Rails 5 needs current versions; PhantomJS is abandoned |

**The `serve_static_assets` entry is the one most likely to be missed**, because it is configuration in the dummy app rather than test code — and the dummy app is what the entire suite boots against.

There's a genuine upside to doing this as its own phase: **migrating the harness is a coverage-preserving refactor**, so the Phase 0 baseline becomes the regression check on the migration itself. If coverage drops, the port lost tests.

## Supporting documentation

- [`RAILS_UPGRADE_TEST_PRIORITY.md` §1](../../RAILS_UPGRADE_TEST_PRIORITY.md) — "The finding that reorders everything," with the full dependency table
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §6, Phase 0](../../RAILS_UPGRADE_TEST_PRIORITY.md) — the harness-migration step and its acceptance criterion
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §0.2, ➕A6](../../RAILS_UPGRADE_TEST_PRIORITY.md) — the `serve_static_assets` finding
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §5](../../RAILS_UPGRADE_TEST_PRIORITY.md) — verified clean: no `use_transactional_fixtures`, no `ActionDispatch::Http::UploadedFile` in test code. Do not go looking for these.
- [`TEST_COVERAGE_ANALYSIS.md` §4](../../TEST_COVERAGE_ANALYSIS.md) — "The test harness itself blocks the upgrade"
- Skill: `version-guides/upgrade-4.2-to-5.0.md` §6 (`rails-controller-testing`), §7 (upload testing), `detection-scripts/patterns/rails-50-patterns.yml`
- **This phase's scope is set by [Phase 1](phase-1-gem-compatibility-and-dual-boot.md)'s gem report.** Read it before starting.

## Work items

### 2.1 — Gem renames and requires

- [ ] `factory_girl` → `factory_bot` (both repos' worth of syntax): `FactoryGirl::Syntax::Methods` → `FactoryBot::Syntax::Methods`, and the block syntax change — `m.name 'Root'` → `m.name { 'Root' }`.
- [ ] `mocha/setup` → `mocha/minitest`; `mocha/mini_test` → `mocha/minitest`. Verify all 109 call sites still work — `.expects`, `.stubs`, and `mock()` all survive the rename, so this should be a require-line change plus a version bump.
- [ ] Drop `require 'minitest/unit'` from both helpers.
- [ ] Bump `simplecov` and **enable branch coverage**. Every coverage figure to date is line-only; branch coverage is what reveals untested conditionals in the monkeypatches.

### 2.2 — Controller test API

- [ ] Add `rails-controller-testing` to preserve the 19 `assert_template` and 11 `assigns` call sites. The skill confirms this is the correct fix rather than rewriting the assertions.
- [ ] Convert all **88** positional `get :action, params` calls to `get :action, params: {...}`. **Rails 4.2 accepts the keyword form**, so this is a safe pre-emptive change with no dual-boot conditional.
- [ ] `Devise::TestHelpers` → `Devise::Test::ControllerHelpers` at `test/test_helper.rb:199`.

### 2.3 — Dummy app config

- [ ] `config.serve_static_assets = true` → `config.public_file_server.enabled = true` in `test/dummy/config/environments/test.rb:11` and `production.rb:20`.
- [ ] Boot the dummy app under both Gemfiles to confirm no other config key has been renamed out from under it.

### 2.4 — The Cucumber stack

Scope here depends on Phase 0's measured pass rate. If most features are already red, fix the driver before spending time on individual scenarios.

- [ ] Migrate the driver off Poltergeist/PhantomJS to `cuprite` or headless Chrome — **while still on Rails 4.2**, so failures are attributable to the driver rather than to Rails.
- [ ] Bring `cucumber`, `cucumber-rails`, `capybara`, and `database_cleaner` to versions from Phase 1's required-bumps bucket. Note `database_cleaner` splits into `database_cleaner-active_record`.
- [ ] Re-check the `@cli` / aruba features specifically; `aruba` is hard-pinned and drives 9 feature files out of process.

### 2.5 — Housekeeping that affects signal

- [ ] Confirm `$VERBOSE = nil` is still gone (Phase 0 removed it) and that the newly-current gems haven't reintroduced a suppression.
- [ ] Confirm the `MonitorMixin`/`recycle!` monkeypatch in `test/test_helper.rb` self-disables cleanly on Rails 5 — it is guarded, so it should be benign, but verify rather than assume.

---

## Exit criteria

| # | Criterion | How to verify |
|---|---|---|
| 1 | **Coverage still reads the Phase 0 baseline on Rails 4.2** | Compare the CI coverage number against Phase 0's committed baseline. A drop means the port lost tests — the phase is not done. |
| 2 | Suite green on the **default** Gemfile (4.2) | CI default job passing |
| 3 | Suite green on **`Gemfile.next`** (5.0) | `BUNDLE_GEMFILE=Gemfile.next bundle exec rake` passing in CI, **no longer allow-failure** |
| 4 | Zero `factory_girl` references remain | `grep -rn "factory_girl\|FactoryGirl" . --exclude-dir=vendor --exclude-dir=.git` returns nothing |
| 5 | Zero positional controller-test calls remain | `grep -rnE "^\s*(get\|post\|put\|patch\|delete)\s+:[a-z_]+\s*,\s*:?[a-z_\"']" test/ spec/` returns nothing |
| 6 | No `mocha/setup` or `mocha/mini_test` or `minitest/unit` requires | `grep -rn "mocha/setup\|mocha/mini_test\|minitest/unit" test/ spec/` returns nothing |
| 7 | `rails-controller-testing` is declared, and all 19 + 11 call sites still pass | Gem present; the tests using them are green on `Gemfile.next` |
| 8 | No `Devise::TestHelpers` reference | `grep -rn "Devise::TestHelpers" test/ spec/` returns nothing |
| 9 | No `serve_static_assets` reference | `grep -rn "serve_static_assets" test/ config/` returns nothing |
| 10 | Branch coverage is enabled and reported | The coverage report shows a branch percentage, not just line |
| 11 | The Cucumber pass rate is **equal to or better than** Phase 0's baseline | Compare against the committed number. Equal is acceptable; worse is a regression to fix. |
| 12 | No `NextRails.next?` branch was added to make the suite pass | `grep -rn "NextRails" test/ spec/` — ideally empty. Any occurrence needs a comment justifying why the test genuinely cannot be version-neutral. |

**Done means:** the same suite, with the same coverage, passes on both Rails 4.2 and Rails 5.0 — and the Rails 5.0 CI job is no longer allowed to fail.

> **The strongest signal that this phase succeeded:** criterion 1 and criterion 3 hold simultaneously. Green on 5.0 with reduced coverage means tests were deleted rather than ported.

---

## Explicitly not in this phase

- **No Rails bump on the default Gemfile.** Still 4.2.11.3. The suite passing under `Gemfile.next` is not the same as bumping — that's [Phase 5](phase-5-the-5.0-bump.md).
- **No new tests.** Not one. This is a port, and mixing new tests into it destroys criterion 1 as a signal — you could no longer tell a lost test from an added one.
- **No application code changes** beyond what the harness needs to boot. Application fixes are [Phase 3](phase-3-backwards-compatible-fixes.md).
- **No coverage improvement.** Preserving the number is the goal; raising it is not.
- **Not hunting `use_transactional_fixtures` or `ActionDispatch::Http::UploadedFile`.** Both verified absent ([§5](../../RAILS_UPGRADE_TEST_PRIORITY.md)). Uploads use a custom `Cms::MockFile` shim, which insulates the suite from the Rails 5 change — but ties it to Paperclip, making it a Phase 5-and-beyond attachment question, not a harness one.
