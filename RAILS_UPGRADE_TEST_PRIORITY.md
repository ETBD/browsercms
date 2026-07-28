# Rails 8 Upgrade — Test Priority, Ordered by Breakage Risk

**Date:** 2026-07-28 (reconciled against the `rails-upgrade` skill 2026-07-28)
**Baseline:** Rails **4.2.11.3**, Ruby 2.7.8, coverage 72.64% (see `TEST_COVERAGE_PLAN.md` for the coverage data this builds on)
**Goal:** not a coverage number — *confidence that the upgrade did not break BrowserCMS*.
**Method:** static sweep of `app/` and `lib/` for APIs removed or changed between Rails 4.2 and 8, cross-referenced against per-file coverage, then reconciled against the `rails-upgrade` skill (FastRuby.io methodology) — its `version-guides/`, `detection-scripts/patterns/rails-42-patterns.yml`, `rails-50-patterns.yml`, `rails-51-patterns.yml`, `rails-52-patterns.yml`, `rails-60-patterns.yml`, and `references/breaking-changes-by-version.md`.

> **Status: reconciled for the 4.2 → 5.0 hop.** Every ⚠️-flagged version claim in the original draft has been checked against the skill and now carries an explicit verdict (§0). Claims the skill does not cover are labelled **skill silent** rather than confirmed — those are the only ones still requiring independent verification, and they are named individually. Claims about hops beyond 5.0 (Tier C removal versions) were corrected where the skill contradicted them, but the *detection sweep* was scoped to 4.2 → 5.0; re-run the skill's per-version patterns at each subsequent hop rather than trusting this document for 6.x/7.x/8.x.

> **Correction to the original header:** the baseline was recorded as Rails 4.2.0. That is the gemspec *constraint* (`s.add_dependency "rails", "~> 4.2.0"`); `Gemfile.lock` resolves **rails 4.2.11.3**, the final 4.2 patch. This matters: the skill makes "be on the latest patch of the current series" a **mandatory pre-step (Step 0)** before any version hop. **That step is already satisfied** — no patch upgrade is needed, and the sequence in §6 can begin at the test suite.

---

## 0. Reconciliation verdicts

Every version-removal claim in the original draft, checked against the skill. **Verdict legend:** ✅ confirmed · ✏️ corrected · 🔇 skill silent (still unverified — do not treat as fact) · ➕ skill found something the sweep missed.

### 0.1 Claims that were flagged ⚠️

| # | Claim as drafted | Skill source | Verdict |
|---|---|---|---|
| C1 | `before_filter` / `after_filter` / `skip_before_filter` removed in **5.1** | `rails-51-patterns.yml` → `FILTER_METHODS`, `kind: breaking`: "Rails 5.1 removes all `*_filter` controller callbacks" | ✅ **confirmed.** Note the skill also searches `lib/` for this pattern, which is why the sweep's 3 non-controller sites (`acts/content_page.rb`, `admin_tab.rb`, `authentication/controller.rb`) count. |
| C2 | `render text:` removed in **5.1** | `upgrade-5.0-to-5.1.md` §2 + `rails-51-patterns.yml` → `RENDER_TEXT`, `kind: breaking` | ✅ **confirmed.** Skill adds: use `render plain:` for text/plain, `render html:` for HTML. |
| C3 | `Relation#uniq` removed in **5.1** | `rails-51-patterns.yml` → `RELATION_UNIQ`, `kind: breaking` | ✅ **confirmed.** Skill warns the pattern false-positives on `Array#uniq`; the sweep's single site (`section_nodes_controller.rb:75`) was already receiver-verified. |
| C4 | `.deliver` removed in **5.0** | `rails-42-patterns.yml` → `kind: deprecation` at 4.2; `upgrade-4.1-to-4.2.md` §1 | ✅ **confirmed, and promoted.** The deprecation is firing **on the current version** — this is fixable today, before any bump, and the skill's methodology says deprecations get cleared *before* the hop. See ➕A4: the sweep also undercounted the sites. |
| C5 | bare `HashWithIndifferentAccess` removed in **5.2** | no matching pattern in `rails-51/52-patterns.yml`; the skill's 5.0→5.1 guide covers only the *indexing* change | 🔇 **skill silent.** 2 sites confirmed by grep (`page_component.rb:10`, `portlet.rb:228`). Fix is free and version-agnostic — qualify to `ActiveSupport::HashWithIndifferentAccess` now and stop tracking the removal version. |
| C6 | `alias_method_chain` removed in **5.1** | no skill entry | 🔇 **skill silent** — and moot. Sole occurrence is a comment (`versioning.rb:209`). No action. |
| C7 | `update_attributes` removed in **7.0** | `upgrade-5.2-to-6.0.md` §3 "`update_attributes` and `update_attributes!` are removed"; `references/breaking-changes-by-version.md` lists it under 5.2 → 6.0; `rails-60-patterns.yml` calls it "deprecated in Rails 6.0" | ✏️ **corrected — much earlier than drafted.** The skill places this at the **6.0 hop**, not 7.0. (The skill is itself inconsistent on removed-vs-deprecated at 6.0; either way it is a 6.x problem.) All 16 sites must be rewritten before the 6.0 bump. `update` works identically on Rails 4.2, so this is a **safe pre-emptive change to make now**. |
| C8 | Classic autoloader removed in **7**; `require_dependency`'s fate uncertain | `upgrade-5.2-to-6.0.md` §1 (Zeitwerk); `rails-60-patterns.yml` → `require_dependency`; `references/breaking-changes-by-version.md`: "Zeitwerk autoloader / ALL apps / Remove require_dependency" at 5.2 → 6.0 | ✏️ **corrected — one hop earlier than drafted.** Zeitwerk becomes the default at **6.0** and is where the work lands; the classic autoloader's final removal at 7.0 is the deadline, not the trigger. The skill is unambiguous that `require_dependency` calls are to be **removed**, so `content_types_controller.rb:1` is a 6.0-hop item. **This promotes B10's eager-load test** — it is the cheapest defence against the largest single item in the plan, and it is needed two hops sooner than the draft assumed. |
| C9 | `belongs_to` required by default at **5.0** | `upgrade-4.2-to-5.0.md` §3, 🔴 HIGH; `rails-50-patterns.yml` → `BELONGS_TO_REQUIRED` | ✅ **confirmed** — and see ➕A1 for a materially larger blast radius than drafted. |
| C10 | `ActionController::Parameters` is no longer a Hash at 5.0; uncertain which operations changed | `upgrade-4.2-to-5.0.md` §5, 🔴 HIGH; `rails-50-patterns.yml` → `PARAMS_AS_HASH` names `slice`, `except`, `merge`, `symbolize_keys`, `to_hash` | ✅ **confirmed, with the specifics filled in.** The skill's named methods do **not** include `.delete` — which is all 8 sites the sweep found. See ➕A2: running the skill's actual pattern surfaced 2 more sites the sweep missed, both of which *are* on the skill's list. |
| C11 | `find_by_<attribute>` is still supported; only `find_all_by_*` / `find_last_by_*` / `scoped_by_*` were removed (4.1). *"The claim most worth double-checking — wrongly fixing 14 call sites would be pure waste."* | `upgrade-4.0-to-4.1.md` §1: "`activerecord-deprecated_finders` was removed as a Rails dependency. `find_all_by_*`, `find_last_by_*`, `scoped_by_*`, `find_or_initialize_by_*`, `find_or_create_by_*` no longer work out of the box"; `rails-40-patterns.yml` confirms the 4.1 removal boundary | ✅ **confirmed.** The skill's removal list matches exactly, and `find_by_<attribute>` appears nowhere in it. **Do not touch the ~13 `find_by_*` call sites.** The draft's instinct was right and the waste is avoided. |
| C12 | `respond_with` + class-level `respond_to` extracted to `responders` | `rails-42-patterns.yml` flags both as `kind: **breaking**` — i.e. already breaking as of the *current* version | ✅ **confirmed, and promoted out of Tier C.** `Gemfile.lock` shows `responders (2.4.1)` arriving only as a transitive dependency of `devise`; nothing in `browsercms.gemspec` declares it. The skill's methodology puts `kind: breaking` in **fix-before-bump**. Declare `responders` explicitly in the gemspec now — a one-line, zero-risk change that removes a dependency landmine before the Devise upgrade can move it. |
| C13 | Callback halting: `return false` no longer halts (5.0); sweep found **no** `return false` inside any callback body | `upgrade-4.2-to-5.0.md` §8; `rails-50-patterns.yml` → `CALLBACK_HALT`, which the skill itself calls "a noisy pattern — only matches inside `before_*` callbacks need fixing" | ✅ **confirmed clean.** The sweep's method (inspect all 11 sites individually across `app/` **and** `lib/`) is *wider* than the skill's search paths (`app/models/`, `app/controllers/` only) and reached the same conclusion. Additionally verified: `ActiveSupport.halt_callback_chains_on_return_false` — which `rails-52-patterns.yml` flags as a boot-time `NoMethodError` at 5.2 — appears **nowhere** in the repo. No action at 5.0 or 5.2. |
| C14 | `ColumnDumper` folded into `SchemaDumper`, `column_spec` signature changed, somewhere in 5.1–6.0 | **no skill entry** for `ColumnDumper`, `column_spec`, or schema-dumper internals in any version guide or pattern file | 🔇 **skill silent.** B1 remains the top Tier-B item on the strength of its *failure mode* (a monkeypatch on a vanished module silently defines an empty module — no error, truncated `db/schema.rb`), which does not depend on knowing the exact version. But **the version claim is still unverified.** The guard test B1 prescribes — assert `ActiveRecord::ConnectionAdapters::ColumnDumper` is already defined when the patch file loads — is precisely the right response to an unverified claim: it converts the unknown into a loud failure at the hop where it actually happens. Write it before the 5.1 bump. |
| C15 | Rails 5 rewrote the attribute layer; internal reads route through `_read_attribute`, bypassing the `read_attribute` alias chain | **no skill entry** for `read_attribute` / `_read_attribute` / the attribute-object rewrite | 🔇 **skill silent.** B2's ranking stands on the alias-chain fragility and the 0.19x test-to-source ratio, not on the version claim. As with C14, the prescribed test (assert `read_attribute` **and** `_read_attribute` both resolve dynamic attributes) is version-agnostic and will fail loudly at whichever hop breaks it. |
| C16 | Two-argument `connection.quote(value, column)` deprecated and removed | **no skill entry** | 🔇 **skill silent.** B7's hand-built SQL in `publishing.rb:143-146` is worth a test regardless — the prescribed test (assert `publish!` flips `published` in the database, read back through a fresh query) tests the *behaviour*, so it survives being wrong about the version. |
| C17 | Paperclip 5.3.0 is EOL and will not work on Rails 8 | not a Rails API claim; the skill routes this to **Step 4.5** (`workflows/gem-compatibility-workflow.md`, `next_rails` `bundle_report compatibility`) and **Step 4.6** (boot smoke test against `Gemfile.next`) | ✅ **confirmed as a process gap, not a knowledge gap.** Stop reasoning about gem EOL by hand. The skill's per-lockfile compatibility check will bucket Paperclip — and `mocha`, `factory_girl`, `cucumber`, `capybara`, `database_cleaner`, `aruba`, `poltergeist`, `compass-rails`, `jquery-rails`, `simplecov` — into required-bumps / blockers / already-compatible with real data. **Run it before finalising Phase 0's scope.** B4's validation-macro tests remain correct and necessary either way; they are the acceptance criteria for whatever replaces Paperclip. |

### 0.2 What the skill's patterns found that the sweep missed

Running the skill's `rails-42` and `rails-50` pattern sets against `app/` and `lib/` surfaced six items absent from the original draft. Coverage figures are from `coverage/index.html`; per-line hit counts from `coverage/.resultset.json`.

| # | Finding | Location | Coverage | Why it matters |
|---|---|---|---|---|
| ➕A1 | **`belongs_to` blast radius is 29 declarations, not 24 — and 5 of them are injected into every model that uses a behavior** | the drafted 24 in `app/models/` **plus** `behaviors/userstamping.rb:16-17` (`created_by`, `updated_by`), `behaviors/categorizing.rb:16` (`category`), `behaviors/versioning.rb:115` (version row → parent), `behaviors/dynamic_attributes.rb:168` (`base_class`) | `userstamping.rb` 100%, `categorizing.rb` 88.89%, `versioning.rb` 96.91%, `dynamic_attributes.rb` 91.47% | The 24 static declarations affect 24 models. The 5 injected ones affect **every model in BrowserCMS and every downstream project that uses the behavior.** `created_by` / `updated_by` becoming required would fail every save made without a logged-in user — and the *only* existing `userstamping` tests are the nil-user cases, so they would go red immediately. That is fortunate, not sufficient: it is the one place the flag fails loudly. `Cms::Category#parent` (self-referential) and every polymorphic `belongs_to` fail silently into validation errors instead. |
| ➕A2 | **Two more `ActionController::Parameters`-as-Hash sites, both using methods the skill explicitly names** | `content_controller.rb:72` — `params.except(:controller, :action, :path)` inside `render_editing_frame`, passed to `ActionDispatch::Http::URL.url_for`; `path_helper.rb:33-36` — `params.clone` then `.delete` ×2 then `.merge!`, passed to `polymorphic_path` | `content_controller.rb:72` hit **153×**; `path_helper.rb:33-36` hit **49×** — both **covered** | B9 grows from 8 sites to 10. But note the asymmetry: these two are on well-exercised lines, so a `Parameters`-vs-`Hash` breakage here surfaces as a **loud CI failure**. The four sites in `form_fields_controller.rb:16`, `forms_controller.rb:33` (both **0% files**) and the untested branches of `pages_controller.rb:126-128` / `sections_controller.rb:43` are the dangerous ones. **This sharpens B9's priority rather than raising it: test the uncovered `.delete` sites, and let CI catch `.except` / `.clone` / `.merge!`.** |
| ➕A3 | **`HTML::FullSanitizer` — a Rails-4.2-era API kept alive by a transitive gem that cannot survive the 5.0 bump** | `lib/cms/content_filter.rb:12` — `HTML::FullSanitizer.new.sanitize(c[key]).strip`. Also asserted directly at `test/functional/cms/inline_controller_test.rb:7` | `content_filter.rb` **100%** (8 relevant lines) | The skill's `rails-42-patterns.yml` flags sanitizer usage as `kind: **breaking**`. `HTML::FullSanitizer` does not exist in Rails 4.2 itself — it comes from `rails-deprecated_sanitizer (1.0.4)`, pulled in only because `rails-dom-testing (1.0.9)` requires it. `rails-dom-testing 1.x` is capped at `activesupport < 5.0`, so **the moment Rails 5 resolves, `rails-dom-testing` goes to 2.x, `rails-deprecated_sanitizer` disappears from the bundle, and `content_filter.rb:12` raises `NameError`.** Loud and covered, so Tier C — but it is a *gem-topology* failure invisible to a code grep, which is exactly what the skill's Step 4.6 boot smoke test exists to catch. Rewrite to `ActionView::Base.full_sanitizer` / `Rails::Html::FullSanitizer` before the bump. Note `inline_controller_test.rb:7` asserts on the doomed gem — the draft correctly observed this test says nothing about its controller; it turns out to be worse than useless, it is a test of a dependency about to be removed. |
| ➕A4 | **`.deliver!` at a second, *uncovered* site** | `email_message.rb:18` — `m.deliver!`. (`:15` is `def self.deliver!`, a definition, not a call.) The draft found only `:58` `.deliver` | `:58` hit **14×** (covered); **`:18` hit 0× — uncovered** | The draft listed 1 site and it was the covered one. The skill's `rails-42` pattern covers `.deliver!` as well as `.deliver`, and the bang form needs `deliver_now!`, not `deliver_now`. An uncovered mail-delivery call on the form-notification path is exactly the class of thing that fails in production rather than CI. |
| ➕A5 | **`File.exists?` at 5 sites, not 1 — two of them uncovered** | `list_portlet.rb:22` (**0 hits**), `lib/cms/caching.rb:42` (24 hits), `lib/cms/attachments/attachment_serving.rb:44` (9 hits), `lib/tasks/core_tasks.rake:51`, `content_block_generator.rb:26` (the only one the draft found) | `list_portlet.rb` 36.36% / 14 missed; `caching.rb` 100%; `attachment_serving.rb` 88.46% | Undercounted 5× in the original draft. `caching.rb` and `attachment_serving.rb` are live request-path code, not generator code. Mechanical fix (`File.exist?`), no test needed — but the count matters for scoping. |
| ➕A6 | **`config.serve_static_assets` in the test harness's own dummy app** | `test/dummy/config/environments/test.rb:11`, `test/dummy/config/environments/production.rb:20` | n/a (config) | `rails-42-patterns.yml` flags this as `kind: deprecation`; it is renamed to `config.public_file_server.enabled` at 5.0. Both sites are in **`test/dummy`** — the app the entire suite boots against. A config that stops being recognised takes the whole suite down, so this belongs in Phase 0 (harness) rather than in the application backlog. Trivial to fix; easy to overlook precisely because it is not application code. |
| ➕A7 | **No `ApplicationRecord`; 28 models inherit `ActiveRecord::Base` directly** | 28 files under `app/models/cms/`; no `app/models/application_record.rb` | Models group: 91.82% | `upgrade-4.2-to-5.0.md` §2 makes this a 🔴 HIGH item and `rails-50-patterns.yml` classifies it `kind: **migration**` — i.e. **fix-when-ready, not fix-before-bump.** Rails 5 does not require it; the generator convention does. For an isolated engine (`isolate_namespace Cms`) the correct target is a `Cms::ApplicationRecord`, not the app-level `ApplicationRecord` the guide describes. **Deliberately deferred.** Recorded here so it is a decision rather than an oversight, and flagged because `lib/browsercms.rb:36-67` does `ActiveRecord::Base.send(:include, ...)` at require time — introducing an intermediate base class interacts with that, and with Zeitwerk at 6.0. Revisit as part of the 6.0 autoloading work, not now. |

### 0.3 The engine problem the skill's guide does not address

The skill's 4.2 → 5.0 guide offers an escape hatch for `belongs_to` required-by-default:

```ruby
# config/application.rb
config.active_record.belongs_to_required_by_default = false
```

**BrowserCMS cannot use it.** `load_defaults` and `belongs_to_required_by_default` appear **nowhere** in this repository (verified: zero occurrences outside `vendor/bundle`), because BrowserCMS is a mountable engine — `lib/cms/engine.rb:7` declares `isolate_namespace Cms`. The flag is owned by the **host application's** `config/application.rb`, and every downstream BrowserCMS project sets it independently.

Three consequences that reorder the plan:

1. **B5 is not deferrable.** The usual mitigation — bump the gem, leave `load_defaults` at 4.2, decide later — is unavailable to a library. A host app on `load_defaults 5.0` will exercise required-by-default against BrowserCMS's models the day it upgrades, whatever BrowserCMS's own dummy app is configured to do.
2. **All 29 declarations must be correct under *both* settings.** `optional: true` is explicit and behaves identically on Rails 4.2, so the entire audit is a **safe pre-emptive change to land now, on 4.2** — which also makes it reviewable in isolation instead of buried in the bump.
3. **The test must force the flag on.** A test written against the dummy app's defaults proves nothing. Set `belongs_to_required_by_default = true` in the test environment (or per-test) so the assertions actually bind. Without this, B5's "highest confidence-per-hour item in Tier B" quietly tests nothing.

The same reasoning applies to every `load_defaults`-gated behaviour change across all nine hops. The skill's **Step 7** (delegate to the `rails-load-defaults` skill, walk the config changes one tier at a time *after* the version bump) assumes an application. For an engine, the honest position is that BrowserCMS must be correct across the *range* of host `load_defaults` values it claims to support — which is a decision to make and document, not a config line to flip.

---

## 1. The finding that reorders everything

**The test suite will not run under Rails 8.** Not "will fail" — will not boot. Before a single line of the upgrade can be validated, the harness needs rebuilding:

| Dependency | Pinned | Problem | Call sites |
|---|---|---|---|
| `mocha` | 1.2.0 | `require 'mocha/setup'` (`test/test_helper.rb:13`) was removed in Mocha 2.0. `require "mocha/mini_test"` (`spec/minitest_helper.rb:8`) became `mocha/minitest`. | **109** (`.expects(` 88, `.stubs(` 15, `mock(` 6) |
| `factory_girl` / `factory_girl_rails` | 4.7.0 | Renamed to `factory_bot` in 2017; `factory_girl` is EOL and will not support Rails 8. | **38** `FactoryGirl` references + every `create(:x)` |
| `minitest/unit` | — | `require 'minitest/unit'` (`test/test_helper.rb:9`, `spec/minitest_helper.rb:7`) — a Minitest 4 compatibility shim. | 2 requires, suite-wide effect |
| `cucumber` / `cucumber-rails` | 2.4.0 / 1.4.5 | Rails 8 needs cucumber-rails 3.x. `features/cucumber.feature` *already documents* Rails-4 incompatibility warnings. | 17 features, ~4,860 LOC |
| `capybara` | 2.10.1 | Needs 3.x. Selector/matcher semantics changed in 3.0. | all feature step definitions |
| `database_cleaner` | 1.5.3 | Split into `database_cleaner-active_record` 2.x. | `test/support/database_helpers.rb` |
| controller test call style | — | `get :show, :id => 5` was removed in Rails 5.1 in favour of `get :show, params: {id: 5}`. | `content_block_controller_test.rb:48,63,68`, `links_controller_test.rb:38,41,49,52,60,63`, `pages_controller_test.rb:136,139`, `sections_controller_test.rb:92`, `file_blocks_controller_test.rb:22` |
| `assigns` / `assert_template` | — | Extracted to the `rails-controller-testing` gem in Rails 5.0; not in the `Gemfile`. | 4 test files |
| `simplecov` | 0.12.0 | 2016. No branch coverage, so every figure in the coverage plan is line-only. | — |
| `aruba` | 0.14.14 | Drives the `@cli` generator features. | 9 feature files |

**Consequence for sequencing:** writing new tests against the current harness means writing them twice. **Phase 0 below is harness migration, and it is not optional.** The 9,807 lines of existing test code are the asset being protected here; porting them is cheaper than rewriting them, but it has to happen before new tests are worth writing.

There is a silver lining: migrating the harness *is* a coverage-preserving refactor, and the existing 72.64% becomes the regression check on the migration itself. Port the harness, confirm coverage holds at 72.64% on Rails 4.2, *then* start the Rails upgrade.

---

## 2. The prioritization principle: silence, not likelihood

The instinct is to prioritize by "what will break." That produces the wrong order, because **loud breakage is self-reporting.**

`before_filter` was removed in Rails 5.1. There are 37 calls across 17 files — 14 controllers plus `lib/cms/acts/content_page.rb`, `lib/cms/admin_tab.rb`, and `lib/cms/authentication/controller.rb`. On Rails 8 the application will not boot — `NoMethodError` at class definition time. That needs *zero* tests. It needs a grep and a sed. Writing a test to catch it is writing a test to tell you something the boot sequence already screams.

What needs tests is code that **keeps running and quietly does something different**: a monkeypatch whose target method vanished (so the patch defines a method nobody calls), a validation that now fires where it didn't, an attribute read that silently returns `nil`.

So the ordering below is:

1. **Tier A — Harness migration.** Prerequisite for everything.
2. **Tier B — Silent behavior change.** Where tests are the *only* detector. Highest value per test.
3. **Tier C — Loud breakage.** Grep-and-fix. Tests are for regression-locking after the fix, not for finding it.

Coverage-per-effort ordering from `TEST_COVERAGE_PLAN.md` §3 is a legitimate secondary lens — use it to sequence *within* a tier, and for the long tail after Tier B is done.

---

## 3. Tier B — Silent behavior change (write these tests)

Ranked by blast radius × silence × current test weakness.

### B1. `schema_dumper.rb` — a monkeypatch on a module that was removed

**File:** `lib/cms/extensions/active_record/connection_adapters/abstract/schema_dumper.rb` — **62.5% covered, 3 of 8 lines missed. Lowest coverage of any extension file.**

```ruby
module ActiveRecord
  module ConnectionAdapters
    module ColumnDumper
      def column_spec(column, types)
```

`ColumnDumper` was folded into `SchemaDumper` in the Rails 5.1–6.0 range, and `column_spec`'s signature changed (the `types` argument went away). 🔇 **Skill silent (C14) — the skill has no entry for `ColumnDumper`, `column_spec`, or schema-dumper internals at any version. The version claim remains unverified.** It does not need to be verified for this item to rank first, because the ranking rests on the *failure mode*, not the version — and the guard test below turns the unknown into a loud failure at whichever hop it actually lands.

Why this is the top item: **when the target module no longer exists, `module ActiveRecord::ConnectionAdapters::ColumnDumper` does not fail. It silently defines a brand-new, empty module that nothing includes.** The patch evaporates. No error, no warning.

And we know exactly what that failure looks like, because the file's own comment documents it happening already:

> *"...any table with a boolean default (every content table has published/deleted/archived) blew up with "can't modify frozen String" and was skipped by the dumper, leaving `db/schema.rb` missing half its tables."*

A silently-truncated `db/schema.rb` is close to the worst possible upgrade outcome: it corrupts every developer's database and every CI run downstream, and it looks like a working build.

**Test to write:** dump the schema for a table with boolean defaults and assert the output contains the `published`/`deleted`/`archived` columns with their defaults. Assert on the *dumped output*, not on `column_spec`'s return value — the point is to detect the patch going missing, so the test must exercise the real dumper end to end. Add a guard test that fails loudly if `ActiveRecord::ConnectionAdapters::ColumnDumper` is not already defined when the file loads.

### B2. `dynamic_attributes.rb` — manual alias_method chain on the attribute API

**File:** `lib/cms/behaviors/dynamic_attributes.rb` — 91.47%, 11 missed. `nonversioned_class` (5 missed) is the largest gap.

```ruby
# lines 186-195
alias_method :method_missing_without_dynamic_attributes, :method_missing
alias_method :method_missing, :method_missing_with_dynamic_attributes
private
alias_method :read_attribute_without_dynamic_attributes, :read_attribute
alias_method :read_attribute, :read_attribute_with_dynamic_attributes
alias_method :write_attribute_without_dynamic_attributes, :write_attribute
alias_method :write_attribute, :write_attribute_with_dynamic_attributes
```

Rails 5 rewrote the attribute layer around an `Attribute` object model and routes internal reads through `_read_attribute`, not `read_attribute`. 🔇 **Skill silent (C15) — no entry for `read_attribute` / `_read_attribute` / the attribute-object rewrite in any version guide or pattern file. Unverified.** The item's rank stands on the alias-chain fragility and the 0.19x test-to-source ratio, both of which are measured facts about this codebase. The failure mode is partial and silent: attributes written through one path, read back through another, returning `nil` for values that are present in the database.

The 91% line coverage is misleading here. High line coverage on a method-aliasing patch tells you the lines execute; it does not tell you the *chain is intact*. A test that reads a dynamic attribute it just wrote passes identically whether the patch is working or Rails is handling it natively.

**Test to write:** assert the chain explicitly — that `read_attribute` and `_read_attribute` both resolve dynamic attributes, that `respond_to?` agrees with `method_missing`, and that a dynamic attribute survives `save` → `reload` → read. Then a round-trip through `assign_attributes` and through direct `[]=`. Also cover `nonversioned_class`, which currently has none.

### B3. `schema_statements.rb` — the migration DSL every BrowserCMS project depends on

**File:** `lib/cms/extensions/active_record/connection_adapters/abstract/schema_statements.rb` — 86.79%, 7 missed, 53 relevant lines.

Reopens `ActiveRecord::ConnectionAdapters::SchemaStatements` to add `create_content_table`, `cms_`, and friends. Internally calls `create_table`, `change_table`, `column_exists?` — all of which have shifted signatures and keyword-argument requirements across six majors.

Blast radius is the largest in the codebase: **every migration in BrowserCMS and in every downstream project that uses it.** Unlike B1, this one is likely to fail loudly (`ArgumentError` on `create_table table_name, options` once options become keyword arguments) — but it fails at *migration* time, which in practice means it fails in someone's deploy rather than in CI.

**Test to write:** a migration test that calls `create_content_table` with each option combination (`versioned: true/false`, `name: true/false`) and asserts the resulting column set on both the content table and the `_versions` table. This is cheap and there is currently no test that runs the DSL.

### B4. Paperclip 5.3.0 is end-of-life

**Files:** `lib/cms/behaviors/attaching.rb` (82.67%, 26 missed), `app/models/cms/attachment.rb` (92.37%, 9 missed), `lib/cms/attachments/configuration.rb`

Not a Rails API change — a dead dependency. Paperclip was deprecated in 2018 in favour of ActiveStorage and will not work on Rails 8. Either migrate to ActiveStorage (a large, semantics-changing project: `has_attached_file` → `has_one_attached`, different storage layout, different URL generation) or move to the `kt-paperclip` fork.

✅ **Confirmed as a process gap (C17), not a knowledge gap.** The skill does not answer gem questions from a table — it has a dedicated step for them: **Step 4.5**, `workflows/gem-compatibility-workflow.md`, running `next_rails`'s `bundle_report compatibility` against `Gemfile.next` per lockfile, escalating to the railsbump API only under defined conditions, and bucketing every gem into *required bumps* / *blockers* / *already compatible*. **Stop hand-reasoning about gem EOL and run that check** — it covers Paperclip alongside `mocha (1.2.0)`, `factory_girl (4.7.0)`, `cucumber (2.4.0)`, `capybara (2.10.1)`, `database_cleaner (1.5.3)`, `aruba (0.14.14)`, `poltergeist (1.11.0)`, `compass-rails`, `jquery-rails (3.1)`, and `simplecov (0.12.0)` in one pass, with real resolver data instead of recollection. Step **4.6** (boot smoke test against `Gemfile.next`) then catches the gems that *resolve* cleanly but call removed Rails internals at runtime — the failure class that produced ➕A3.

The validation-macro tests below are correct and necessary regardless of which replacement wins; they are the acceptance criteria for it.

The untested parts are precisely the parts that differ between Paperclip and any replacement:

| Method | Missed lines |
|---|---|
| `validates_attachment_size` | 9 |
| `validates_attachment_content_type` | 6 |
| `validates_attachment_presence` | 3 |
| `handle_setting_attachment_path` | 3 |

**All three validation macros are untested.** ActiveStorage's validation story is completely different (it has none built in — you need `active_storage_validations` or custom validators). Without tests pinning current behavior, a migration will silently drop file-size and content-type enforcement — a security-relevant regression on a public upload path.

⚠️ Note before starting: `validates_attachment_presence` is **defined twice**, at `attaching.rb:89` and `:98`. The first is dead code silently overwritten by the second.

**Test to write:** for each macro, one test that a valid attachment passes and one that an invalid one produces a specific error on a specific attribute. Pin the current messages. These become the acceptance criteria for whatever replaces Paperclip.

### B5. `belongs_to` required by default

**Evidence:** 24 `belongs_to` declarations in `app/models`. **Zero** carry `optional: true` or `required: false`. ✅ *Both figures re-verified.*

✏️ **Corrected scope (➕A1): the real count is 29, and the 5 additions matter more than the 24.** Five further live `belongs_to` calls sit inside the behaviors, where they are injected into every model that uses the mixin:

| Site | Association | Coverage |
|---|---|---|
| `lib/cms/behaviors/userstamping.rb:16-17` | `created_by`, `updated_by` (`Cms::User`) | 100% |
| `lib/cms/behaviors/categorizing.rb:16` | `category` (`Cms::Category`) | 88.89% |
| `lib/cms/behaviors/versioning.rb:115` | version row → parent record | 96.91% |
| `lib/cms/behaviors/dynamic_attributes.rb:168` | `base_class` | 91.47% |

(Grep also matches `belongs_to_category?` / `@belongs_to_category` in `categorizing.rb` and a `:belongs_to_attachment` option guard in `acts/content_block.rb` — those are method and option names, not associations. Excluded.)

The 24 static declarations affect 24 models. **The 5 injected ones affect every model in BrowserCMS and in every downstream project that uses the behavior** — `userstamping` alone is included 199 times per the coverage run's hit count.

✅ **Version confirmed (C9):** `upgrade-4.2-to-5.0.md` §3 lists this as 🔴 HIGH for the 5.0 hop; `rails-50-patterns.yml` → `BELONGS_TO_REQUIRED`, with the skill's own instruction to "review each match to determine if the association can be nil" and to "add `optional: true` **only** to associations that can legitimately be nil."

Silent in the worst way: models that saved fine now fail validation, and because BrowserCMS swallows some save failures into `flash` (`Cms::Portlet#store_errors_in_flash`, 2 missed lines — untested), the failure may surface as a UI no-op rather than an exception.

Genuinely optional associations here are likely to include `Cms::SectionNode#node` (polymorphic, `:24`), `Cms::Connector#connectable` (polymorphic, `:5`), `Cms::Attachment#attachable` (polymorphic, `:19`), `Cms::Tagging#taggable` (polymorphic, `:4`), **`Cms::Category#parent` (self-referential — every root category has a nil parent, so required-by-default breaks the category tree outright)**, `Cms::Task#assigned_by` / `#assigned_to`, and `userstamping`'s `created_by` / `updated_by`.

**One piece of luck worth naming:** the only existing `userstamping` tests are the *nil-user* cases (the happy path is untested — see `TEST_COVERAGE_ANALYSIS.md` §3.5). Under required-by-default those tests go **red immediately**. That is the single place this flag fails loudly instead of silently, and it is an accident of the coverage gap rather than a designed safety net.

**Test to write:** for each of the **29**, a test that either (a) asserts the association is required, or (b) asserts a record saves without it. **Critically — set `config.active_record.belongs_to_required_by_default = true` in the test environment first (see §0.3).** BrowserCMS is an engine with no `load_defaults` of its own, so tests written against the dummy app's inherited defaults will pass whether or not the declarations are correct, and this "highest confidence-per-hour item" will quietly assert nothing. Mechanical, fast, and it forces a decision on all 29 before any host app flips the flag. `optional: true` behaves identically on Rails 4.2, so **land the whole audit now, on 4.2, as a reviewable standalone change.**

### B6. `versioning.rb` — documented dependence on ActiveRecord's `save` call chain

**File:** `lib/cms/behaviors/versioning.rb` — 96.91%, 5 missed, 162 relevant lines. Well covered by line count.

Lines 206–225 are a comment block enumerating the exact order in which `ActiveRecord::Base` composes `save`:

> *"ActiveRecord 3 now uses basic inheritance rather than alias_method_chain. The order in which ActiveRecord::Base includes methods (at the bottom of activerecord) repeatedly overrides save/save! with chains of 'super' ... Callstack order as observed: AR::Transactions#save, AR::Dirty#save, AR::Validations#save, ActiveRecord::Persistence#save..."*

Code that documents its dependence on an *observed* internal call order is code that will break when that order changes — and it has changed repeatedly since Rails 3.

96.91% line coverage with 162 lines is good, so the risk is not "untested" but "tested for the wrong thing." Line coverage cannot tell you whether a test asserts that versioning happens *in the right order relative to validation and dirty-tracking*.

**Action:** this is an audit before it is a test-writing task. Read `test/unit/behaviors/versioning_test.rb` and `publishing_mini_test.rb` and answer: does anything assert that a failed validation produces no new version? That `version_comment` reflects the changes from *this* save? That a rolled-back transaction leaves no orphan version row? Add whichever of those is missing. Budget a day for reading before writing.

### B7. `publishing.rb` — hand-built SQL against connection internals

**File:** `lib/cms/behaviors/publishing.rb` — 96.51%, 3 missed.

```ruby
# :143-146
self.class.connection.update(
  "UPDATE #{self.class.quoted_table_name} SET published = #{self.class.connection.quote(true, self.class.columns_hash["published"])} ..."
)
```

`connection.quote(value, column)` — the two-argument form was deprecated and removed; `columns_hash` returns different objects than it did in 4.2. 🔇 **Skill silent (C16) — no entry for `connection.quote` arity or `columns_hash` return types. Unverified.** Likely loud (`ArgumentError`), but on a code path (`publish!` on a versioned record) that runs in production far more than in tests. The prescribed test asserts *behaviour* rather than the API shape, so it holds regardless of which version the arity change lands in.

**Test to write:** assert that `publish!` actually flips `published` in the database for both versioned and non-versioned models — reading back through a fresh query, not through the in-memory object.

### B8. `soft_deleting.rb` — `default_scope` plus a startup rescue

**File:** `lib/cms/behaviors/soft_deleting.rb` — 92.86%, 3 missed.

```ruby
default_scope {where(:deleted => false)}
rescue ...
  handle_missing_table_error_during_startup("Can't set a default_scope for soft_deleting", e)
```

Two upgrade interactions: `default_scope` composition semantics have shifted (notably around `unscoped` and `or`), and the rescue exists to survive class loading before the table exists — which is exactly the behavior Zeitwerk's eager-loading changes. Under Rails 7+ eager loading, this rescue may swallow a real error at boot or fire in new situations.

**Test to write:** assert `deleted` records are excluded by default, included under `unscoped`, and that the default scope composes correctly with `where` and `or`.

### B9. `ActionController::Parameters` is not a Hash

**10 sites** treating a params sub-hash as a Hash — 8 found by the original sweep, **2 more surfaced by running the skill's own `PARAMS_AS_HASH` pattern** (➕A2):

```
app/controllers/cms/pages_controller.rb:126-128   params[:page].delete :hidden / :archived / :visibility
app/controllers/cms/sections_controller.rb:43     params[:section].delete('group_ids')
app/controllers/cms/form_fields_controller.rb:16  params[:form_field].delete(:form_id)
app/controllers/cms/forms_controller.rb:33        params[:form].delete(:new_entry)
app/helpers/cms/path_helper.rb:34-35              filtered_params.delete(:action) / (:controller)
app/helpers/cms/path_helper.rb:33,36              params.clone → .merge!(:order => ...) → polymorphic_path   ← NEW
app/controllers/cms/content_controller.rb:72      params.except(:controller, :action, :path) → url_for       ← NEW
```

✅ **Version confirmed (C10)** — `upgrade-4.2-to-5.0.md` §5, 🔴 HIGH — **with an important asymmetry the original draft could not see.** The skill's pattern names `slice`, `except`, `merge`, `symbolize_keys`, `to_hash`. It does **not** name `.delete`, which is all 8 of the sweep's original sites. The two new sites are the ones that use the methods the skill actually flags:

- `path_helper.rb:33` clones `params` (a `Parameters`, not a `Hash`), mutates it with `.delete` ×2 and `.merge!`, then hands it to `polymorphic_path` — passing unpermitted `Parameters` into a URL helper is exactly what Rails 5 stopped tolerating.
- `content_controller.rb:72` passes `params.except(...)` into `ActionDispatch::Http::URL.url_for(params:)`, which wants a Hash. This is inside `render_editing_frame` — the CMS edit-mode iframe, i.e. the admin's primary editing surface.

**But both new sites are well covered** — `content_controller.rb:72` is hit **153×**, `path_helper.rb:33-36` **49×**. A `Parameters`-vs-`Hash` breakage there raises on a line CI executes, so **CI is already the detector and no new test is warranted.**

**So this finding sharpens B9's targeting rather than raising its rank.** Write tests for the sites CI *cannot* see:

`.delete` still exists on `Parameters`; what changed is that the object is no longer a `Hash`, so surrounding code that expected Hash semantics (`merge`, `each` yielding pairs, implicit `to_hash` coercion, permitted-state propagation) may behave differently.

Coverage status makes this worse than it looks:

- `pages_controller.rb#strip_visibility_params` — **3 of its lines are untested** (85.87% file)
- `sections_controller.rb:43` — inside the 9 missed lines
- `form_fields_controller.rb:16` — **0% file**
- `forms_controller.rb:33` — **0% file**
- `path_helper.rb:33-36` — inside `sortable_column_path` (`:32`); **these lines are covered (49 hits)**; the file's 14 missed lines are concentrated in `link_to_usages` (`:40`) and `engine` (`:65`)
- `content_controller.rb:72` — **covered (153 hits)**; file is 92.16%

So four of the ten sites are in code with **no test at all**, and those four are the entire job here. These are cheap tests (assert the stripped key is absent from the resulting record) and they sit directly on a security boundary: `strip_visibility_params` and the `group_ids` deletion are *authorization* logic — they exist to stop a non-admin from setting fields they shouldn't. `form_fields_controller.rb` and `forms_controller.rb` are both **0%-coverage files**, which is why the Forms subsystem holds its rank in §6.

### B10. Zeitwerk and `require_dependency`

**File:** `app/controllers/cms/content_types_controller.rb:1` — `require_dependency "cms/application_controller"`. **The file is 0% covered.**

✏️ **Corrected — one hop earlier than drafted (C8), which promotes this item.** The draft placed Zeitwerk at Rails 7. The skill places it at **6.0**: `references/breaking-changes-by-version.md` lists "Zeitwerk autoloader / impact: ALL apps / fix: Remove `require_dependency`, fix naming" under **5.2 → 6.0**, and `upgrade-5.2-to-6.0.md` §1 is unambiguous — "Remove **all** `require_dependency` calls." The classic autoloader's final removal at 7.0 is the *deadline*; 6.0 is where the work happens and where a red suite appears.

For a mountable engine with `isolate_namespace Cms` and a `Cms::` namespace spread across `app/models/cms/`, `app/controllers/cms/`, and `lib/cms/`, Zeitwerk's stricter file-path-to-constant-name rules are a substantial migration in their own right — and `TEST_COVERAGE_ANALYSIS.md` §3.6 identifies `lib/cms/engine.rb` (135 LOC, a **7-line test with 1 assertion**) as the single biggest concentration of upgrade work in the codebase, pushing 6 directories onto `ActiveSupport::Dependencies.autoload_paths`, an API that does not exist under Zeitwerk.

**Being two hops sooner than assumed is the most consequential correction in this reconciliation.** The eager-load test below is one hour of work and is the cheapest possible defence against the largest single item in the plan. It should be written in Phase 1, and its results will scope the 6.0 hop.

Watch specifically: `lib/cms/behaviors.rb:32` and `lib/cms/concerns.rb:6` build class names from filenames with `File.basename(b, ".rb").camelize` and `constantize` them at load time, and `lib/browsercms.rb:36-67` does `ActiveRecord::Base.send(:include, ...)` at require time. Runtime `constantize` against eager-loaded constants plus monkeypatching `ActiveRecord::Base` during initialization is the classic Zeitwerk failure pattern.

**Test to write:** a boot/eager-load test — `Rails.application.eager_load!` and assert every expected `Cms::` constant resolves. One test, catches an entire class of autoload regressions. Do this early; it is the cheapest high-signal test available.

---

## 4. Tier C — Loud breakage (grep and fix; test only to lock the fix)

Ordered by how much code sits behind them. **None of these need a test to be *found*.** Fix them, then add a test only where the fix has a behavioral choice in it.

**Removal versions are now skill-sourced.** ✅ = confirmed against the skill · ✏️ = corrected · 🔇 = skill has no entry (unverified).

| API | Removed | Sites | Notes |
|---|---|---|---|
| `respond_with` + class-level `respond_to` | **already breaking at 4.2** ✏️ | 6 | ✏️ **Promoted out of Tier C into fix-before-bump.** `rails-42-patterns.yml` classifies both as `kind: **breaking**` on the *current* version, not a future one. Works today only because `devise` pulls `responders 2.4.1` in transitively — `Gemfile.lock:142` confirms it arrives as a Devise dependency and **nothing in `browsercms.gemspec` declares it.** Declare it explicitly now: one line, zero risk, and it defuses the landmine *before* the Devise upgrade can move it. `content_controller.rb:79` is the main page-serving path (202 hits — CI will catch a regression). |
| `HTML::FullSanitizer` | **breaks at 5.0** ➕ | 1 + 1 test | ➕ **New (A3) — missed entirely by the original sweep.** `content_filter.rb:12`. `rails-42-patterns.yml` flags sanitizer usage as `kind: breaking`. The constant comes from `rails-deprecated_sanitizer (1.0.4)`, in the bundle only because `rails-dom-testing (1.0.9)` requires it — and that gem is capped at `activesupport < 5.0`. **Resolving Rails 5 removes the gem and `content_filter.rb:12` raises `NameError`.** File is 100% covered so it fails loudly, but a code grep cannot see it — this is the failure class the skill's Step 4.6 boot smoke test exists for. Also: `test/functional/cms/inline_controller_test.rb:7` asserts on the doomed gem directly. |
| `before_filter` / `after_filter` / `around_filter` / `skip_before_filter` | 5.1 ✅ | **37 across 17 files** | ✅ `rails-51-patterns.yml` → `FILTER_METHODS`, `kind: breaking`. Mechanical rename to `_action`. Boot-time failure. Safe to do now — `_action` works on 4.2. |
| `render :text =>` / `render text:` | 5.1 ✅ | 4 | ✅ `upgrade-5.0-to-5.1.md` §2 + `rails-51-patterns.yml` → `RENDER_TEXT`. → `render plain:` (skill: `render html:` if HTML was intended). **Both production sites are on untested error branches:** `content_block_controller.rb:138` ("Not Implemented") and `form_fields_controller.rb:43` ("Fail", 500). Worth a test *because* they're error paths nothing exercises. |
| `Relation#uniq` | 5.1 ✅ | 1 | ✅ `rails-51-patterns.yml` → `RELATION_UNIQ`. `section_nodes_controller.rb:75` → `.distinct`. Inside `nodes_to_update_on_success` (`:73`), which has **2 untested lines**, in a file at 41.18% whose `move_to_position` has 9 more. |
| `.deliver` / `.deliver!` | 5.0 ✅ (deprecated **at 4.2**) | **2** ➕ | ✅ `rails-42-patterns.yml`, `kind: deprecation` — **already warning on the current version, so fixable today.** ➕ **Undercounted (A4):** `email_message.rb:58` `.deliver` (14 hits, covered) **and `email_message.rb:18` `m.deliver!` — 0 hits, uncovered.** The bang form needs `deliver_now!`, not `deliver_now`. (`:15` `def self.deliver!` is a definition, not a call.) On the form-notification path (`form_entries_controller#submit`, **0% covered**). |
| `config.serve_static_assets` | 5.0 ➕ | 2 | ➕ **New (A6).** `test/dummy/config/environments/test.rb:11` and `production.rb:20` → `config.public_file_server.enabled`. `rails-42-patterns.yml`, `kind: deprecation`. **These are in the dummy app the entire suite boots against — this is a Phase 0 harness item, not application backlog.** Easy to miss because it isn't application code. |
| `update_attributes` / `update_attributes!` | **6.0** ✏️ (was drafted 7.0) | **16** | ✏️ **Corrected — a full hop earlier (C7).** `upgrade-5.2-to-6.0.md` §3 and `references/breaking-changes-by-version.md` both place this at 5.2 → 6.0. → `update` / `update!`, which work identically on 4.2, so **make this change now.** Note `guest_user.rb:48` *defines* `update_attributes` — check callers before renaming. |
| `require_dependency` (Zeitwerk) | **6.0** ✏️ (was drafted 7.0) | 1 | ✏️ **Corrected (C8).** `content_types_controller.rb:1`; file is **0% covered**. See B10 — this is the tip of the largest item in the plan, and it arrives two hops sooner than the draft assumed. |
| bare `HashWithIndifferentAccess` | 🔇 unverified (drafted 5.2) | 2 | 🔇 **Skill silent (C5).** `page_component.rb:10` (3 hits, covered) and `portlet.rb:228` (**0 hits, uncovered**) → `ActiveSupport::HashWithIndifferentAccess`. Fix is free and version-agnostic; qualify both now and stop tracking the removal version. |
| unversioned `ActiveRecord::Migration` | 5.0 🔇 | 2 | 🔇 Skill has no pattern for migration versioning, though `upgrade-4.2-to-5.0.md` implies it. `db/migrate/20130327184912_browsercms400.rb`, `20080815014337_browsercms300.rb` → `[4.2]`. Low risk, do it at the 5.0 bump. |
| `File.exists?` | Ruby (deprecated) | **5** ➕ | ➕ **Undercounted 5× (A5).** `list_portlet.rb:22` (**0 hits, uncovered**), `lib/cms/caching.rb:42` (24 hits), `lib/cms/attachments/attachment_serving.rb:44` (9 hits), `lib/tasks/core_tasks.rake:51`, `content_block_generator.rb:26` (the only one originally found). Two are **live request-path** code, not generator code. → `File.exist?`. Mechanical. |
| `match "*path", via: [...]` | — | 1 | `route_extensions.rb:62` — the CMS catch-all route. Still valid syntax; verify glob + format behavior. 98.57% covered. |
| `jquery_ujs` | — | 2 | `application.js:5`, `page_editor.js:2` → `rails-ujs`/Turbo. `jquery-rails 3.1.5` is far behind. Route through the skill's Step 4.5 gem check. |
| `compass-rails` + `sass-rails` | — | gemspec:35,37 | **Compass is EOL (2018).** Rails 8 defaults to Propshaft (`references/breaking-changes-by-version.md`, 7.2 → 8.0). `app/assets/stylesheets/cms/*.scss` needs a new pipeline. Not unit-testable — needs the feature suite. Also see the skill's `references/js-compressor-sprockets-mismatch.md` if the JS compressor breaks en route. |

**Sites that can be fixed today, on Rails 4.2, with no dual-boot conditional** — the new API works on both sides, so these are backwards-compatible changes that can be reviewed and deployed independently of any bump (the skill's Step 6 principle, and its "deploy small changes to production before the version bump" methodology):

`before_filter` → `before_action` (37) · `update_attributes` → `update` (16) · `.deliver`/`.deliver!` → `deliver_now`/`deliver_now!` (2) · `File.exists?` → `File.exist?` (5) · bare → `ActiveSupport::HashWithIndifferentAccess` (2) · `belongs_to ... optional: true` (29, §B5) · declare `responders` in the gemspec (1 line) · `render text:` → `render plain:` (4).

**That is ~96 mechanical changes that reduce the 5.0/5.1/6.0 hops without a single version bump, and every one of them is independently reviewable.** Doing them first shrinks the diff that the actual bump has to be debugged against — which is the whole point of the pre-bump phase.

---

## 5. Checked and clean — do *not* spend time here

Negative findings, recorded so nobody re-investigates:

- **`return false` to halt callbacks.** Rails 5 changed halting to `throw(:abort)`. All **11** real `return false` sites in `app/` + `lib/` were inspected individually; **none is in a callback body**:
  - predicates — `first?`/`last?` (`acts_as_list.rb:159,165`), `live?` (`publishing.rb:180`), `visible?`/`deletable?` (`section_node.rb:63-66,89`)
  - helpers — `deliver!` (`email_message.rb:56`), `database_exists?` (`extensions/active_record/base.rb:26`)
  - a guard clause in a yielding method — `exec_if_related` (`dynamic_attributes.rb:354`)

  The two `before_*` callbacks in `acts_as_list.rb` are `remove_from_list_without_saving` → `remove_from_list(false)`, which returns `nil` because `update_attribute(...) if save` is skipped, and `add_to_list_bottom`, which ends in an assignment. `nil` never halted the chain, so neither is affected. **No action needed.** (Two further grep hits are not Ruby statements at all: `task.rb:58` is a comment, and `application_helper.rb:37` is `return false` inside a JavaScript `onchange` string.)
- **`alias_method_chain`** (removed 5.1) appears only inside a comment at `versioning.rb:209`. No live usage.
- **`attr_accessible`** — all 10 occurrences are commented out. `protected_attributes` is not in the Gemfile.
- **`attribute_changed?` / `_was` inside `after_save`** (semantics changed in 5.1/5.2) — only in comments at `attaching.rb:213` and `taggable.rb:47`.
- **`Fixnum` / `Bignum`**, **`serialize`**, **`dependent: :restrict`** — zero occurrences.
- **`find_by_<attribute>` dynamic finders** — `find_by_login`, `find_by_path`, `find_by_code`, `find_by_from_path` are present, but `find_by_<attribute>` is **still supported**; only `find_all_by_*`, `find_last_by_*`, and `scoped_by_*` were removed (4.1). Most hits are locally-defined `def self.find_by_key` methods anyway. **Not a risk.** ✅ **CONFIRMED against the skill (C11).** `upgrade-4.0-to-4.1.md` §1 gives the removal list as exactly `find_all_by_*`, `find_last_by_*`, `scoped_by_*`, `find_or_initialize_by_*`, `find_or_create_by_*` — when `activerecord-deprecated_finders` stopped being a bundled dependency at 4.1 — and `find_by_<attribute>` appears nowhere in it. `rails-40-patterns.yml` independently confirms the 4.1 boundary. **Do not touch the ~13 call sites.** This was flagged as the claim most worth checking; it held, and the waste is avoided.

### Additionally verified clean during reconciliation

Ten more skill patterns were run against the codebase and returned **zero** hits. Recorded so the next person does not re-run them:

| Skill pattern | Version | Result |
|---|---|---|
| `redirect_to :back` (`REDIRECT_TO_BACK_DEPRECATED` / `REDIRECT_TO_BACK`) | deprecated 5.0, removed 5.1 | **0 sites.** The skill flags this as 🔴 HIGH for the very first hop, so it was the most likely miss. Clean. |
| `render nothing: true` (`RENDER_NOTHING`) | removed 5.1 | 0 sites |
| `use_transactional_fixtures` (`USE_TRANSACTIONAL_FIXTURES`) | removed 5.1 | 0 sites in `test/` or `spec/` |
| `class_name:` with an unquoted constant (`CLASS_NAME_CONSTANT`) | **raises `ArgumentError` at 5.2** | **0 sites in browsercms.** Worth noting: `TEST_COVERAGE_ANALYSIS.md` §5.3 finds **11 such sites in `cms`** and describes them as breaking "under modern Rails autoloading." The skill pins it precisely — `rails-52-patterns.yml` says Rails 5.2 raises `ArgumentError: A class was passed to :class_name but we are expecting a string` at model load time, finishing a deprecation begun in 5.1. So cms's item 17 is a **hard 5.2 boot failure**, not a vague future autoloading concern. Fix is free (quote the constant) and works on 4.2. |
| `ActiveSupport.halt_callback_chains_on_return_false` | `NoMethodError` at boot, 5.2 | 0 sites (also `error_on_ignored_order_or_limit`: 0) |
| String `if:` / `unless:` conditions on filters and model callbacks | 5.1 / 5.2 | 0 sites |
| `assert_tag` / `TagAssertions` | deprecated 4.2 | 0 sites |
| `serialize :attr, SomeCoder` | breaking 4.2 | 0 sites |
| `form_authenticity_token` in non-Rails forms | breaking 4.2 | 0 sites in `app/` or `lib/` |
| `Timecop` | 4.2 | not in the bundle |
| `ActionDispatch::Http::UploadedFile` in tests (`UPLOAD_FILE_TEST`) | 5.0 → `Rack::Test::UploadedFile` | **0 sites in test code.** Matches appear only in `test/dummy/log/test.log`. Uploads go through a custom `Cms::MockFile` shim (`test/support/factory_helpers.rb:68-82`), used by ~15 tests. The shim insulates the suite from this change — but it is Paperclip-shaped, so it becomes part of the B4 attachment decision rather than a Rails-5 fix. |
| dynamic `:controller/:action` route segments | deprecated 5.2 | 0 sites |
| `protected_attributes` gem / live `attr_accessible` | breaking 5.0 | 0 sites (all `attr_accessible` occurrences already commented out — reconfirms the original finding) |
| Ruby version floor | 2.2.2+ at 5.0 | **Ruby 2.7.8** — clears 5.0 (2.2.2+), 6.0 (2.5+), and 7.0 (2.7+). Becomes a **hard gate at 7.2, which needs 3.1+.** Plan the Ruby upgrade into the 7.1 → 7.2 hop, not earlier. |

---

## 6. Recommended sequence

**Reconciled against the skill's mandated workflow.** The original phases were sound but omitted four of the skill's required steps. They are inserted below, marked ★.

**★ Step 0 — Verify latest patch. ✅ ALREADY SATISFIED.** The skill makes this a mandatory pre-step before any hop. `Gemfile.lock` resolves **rails 4.2.11.3**, the final 4.2 patch. No action. (The draft's "Rails 4.2.0" was the gemspec constraint, not the resolved version.)

**★ Step 1 — Establish that the suite passes, and get CI. BLOCKING.** The skill's Step 1 is explicit: *if any tests fail, STOP; do not proceed until all tests pass.* Two things must be true before anything else happens:
- The suite is green. `git log` shows `[CMS-420] tests are running` — "running" is not "passing." Confirm the actual pass/fail count and record it as the baseline alongside the 72.64%.
- **There is a working CI.** The only CI config is a dead `.travis.yml`; there is no `.github/`. The skill treats CI as non-negotiable (`workflows/ci-sync-workflow.md` is mandatory *before every upgrade PR*), and `TEST_COVERAGE_ANALYSIS.md` ranks this item 2. **You cannot run a nine-hop upgrade without a green button.** Port to GitHub Actions (Ruby 2.7.8, Postgres) now.

**Phase 0 — Harness migration (Rails 4.2, no upgrade yet).** factory_girl → factory_bot, mocha → 2.x, drop `minitest/unit`, cucumber/capybara → current, add `rails-controller-testing` (✅ the skill confirms this is the fix for the `assigns` / `assert_template` extraction at 5.0), convert the positional controller-test calls, bump simplecov and enable branch coverage. **Add ➕A6: `config.serve_static_assets` → `config.public_file_server.enabled` in `test/dummy/config/environments/{test,production}.rb`** — the suite's own dummy app, easy to overlook. Also delete `$VERBOSE = nil` from `test/test_helper.rb`: the skill's methodology treats deprecation warnings as the upgrade roadmap (`references/deprecation-warnings.md`, and `RUBYOPT="-W:deprecated"` in `references/testing-checklist.md`), and that line hides them.
**Acceptance: coverage still reads 72.64% on Rails 4.2.** Anything less means the port lost tests.

**★ Step 2 — Set up dual-boot with `next_rails`. Do this BEFORE any bump.** Entirely absent from the original plan. There is no `Gemfile.next` and no `next_rails` in the bundle. The skill puts this at Step 2, immediately after tests pass, and delegates to the `dual-boot` skill for `next_rails --init`. It also mandates a code pattern: **when a fix genuinely cannot work on both versions, branch on `NextRails.next?` — never on `respond_to?` or other feature detection.** Most fixes here need no branch at all (see the ~96 backwards-compatible changes listed at the end of §4).

**Phase 1 — Backwards-compatible fixes and cheap high-signal tests, still on 4.2.** Reordered by the reconciliation:
1. **B10 eager-load test first** — one test, one hour. ✏️ Promoted: Zeitwerk lands at **6.0**, not 7.0, so this defends the plan's largest item two hops sooner than assumed.
2. **B5 `belongs_to` audit — now 29 declarations, not 24** (➕A1), with `belongs_to_required_by_default = true` forced in the test env (§0.3). Not deferrable: BrowserCMS is an engine and the host app owns the flag.
3. **B3** (`create_content_table` DSL) and **B1** (schema dump, including the `ColumnDumper`-is-defined guard test — the right response to an unverified claim, C14).
4. **The ~96 mechanical backwards-compatible changes** from the end of §4. All work on 4.2; land them as reviewable standalone commits, and per the skill's methodology, deploy them before the bump.

**★ Step 4.5 / 4.6 — Gem compatibility and boot smoke test.** Also absent from the original plan, and it is where ➕A3 came from. Run `bundle_report compatibility` against `Gemfile.next` per the skill's `workflows/gem-compatibility-workflow.md` to bucket every gem (Paperclip, mocha, factory_girl, cucumber, capybara, database_cleaner, aruba, poltergeist, compass-rails, jquery-rails, simplecov) into required-bumps / blockers / already-compatible with real resolver data. Then run a Rails-loading command against `Gemfile.next` (`BUNDLE_GEMFILE=Gemfile.next bundle exec rspec --dry-run`) to catch gems that resolve fine but call removed internals at runtime. **`HTML::FullSanitizer` (➕A3) is exactly that failure class** — invisible to a code grep, invisible to the resolver, fatal at boot. **Run this before finalising Phase 0's scope**, because its output determines how much of the harness migration is actually forced.

**Phase 2 — Remaining Tier C fixes.** Whatever the pre-emptive pass in Phase 1 could not do on 4.2. Add tests only for the `render :text` error branches and `Relation#uniq` in `move_to_position`, since those are untested code paths regardless.

**Phase 3 — The hard silent ones.** B2 (attribute chain — 🔇 version unverified, but the test is version-agnostic), B6 (versioning audit), B4 (attachment decision + the three untested validation macros), **B9 narrowed to the four uncovered `.delete` sites** (➕A2: the two new `.except` / `.clone` sites are covered, so CI is already the detector — do not spend test budget there). Each needs real thought; none should be rushed.

**Phase 4 — Begin the version-by-version upgrade.** 4.2 → 5.0 → 5.1 → 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0. The skill is emphatic that **version skipping is not allowed**, and adds two rules the draft omitted:
- **★ Re-run the skill's detection patterns at each hop.** This document's sweep is reconciled for **4.2 → 5.0 only**. Do not treat its 6.x/7.x/8.x rows as a detection pass.
- **★ Re-check Step 0 (latest patch) after every hop**, and run `workflows/ci-sync-workflow.md` before every upgrade PR — stale CI is the skill's stated most common cause of red builds on upgrade branches.
- **★ Step 7 — align `load_defaults` *after* each version bump**, as a separate change, delegating to the `rails-load-defaults` skill. But see §0.3: for an engine this is a support-range decision, not a config line.
- Ruby 2.7.8 carries through 7.1; **3.1+ is a hard gate at 7.2.** Plan that Ruby bump into the 7.1 → 7.2 hop.

**Phase 5 — Coverage-per-effort backlog** from `TEST_COVERAGE_PLAN.md` §3, as regression pressure demands.

---

## 7. Is the coverage adequate?

The question this document exists to answer. Measured against the skill's `references/testing-checklist.md` categories:

| Checklist area | Current state | Verdict |
|---|---|---|
| Unit / model tests | 91.82%, 47 files | ✅ **Adequate.** Also the layer Rails 5→8 changes least. |
| Library / concern tests | 73.04%, 91 files | ⚠️ **Adequate in aggregate, wrong in distribution.** The monkeypatches and behaviors carrying the upgrade risk are the thin ones (`dynamic_attributes` 0.19x test-to-source, `schema_dumper` 62.5%). Tier B targets exactly these. |
| Controller tests | **57.71%**, 612 missed lines | ❌ **Not adequate.** This is where params, `render :text`, and `*_filter` changes land. Four 0% files (`form_entries` 140 lines, `form_fields` 74, `forms` 35, `content_types` 18) hold two Tier-C breakages and three of B9's four dangerous sites. |
| Integration / multi-step workflows | none in this repo | ❌ **Absent.** No test chains create → edit → publish → connect → render → version → revert. See `TEST_COVERAGE_ANALYSIS.md` §Phase 3. |
| System / feature (JS, forms, uploads, navigation) | 53 Cucumber features, 4,860 LOC | ⚠️ **Exists but brittle and unmeasured.** On Poltergeist/PhantomJS (abandoned 2018), `aruba` hard-pinned, `@cli` features excluded from the default task. **The true pass rate is still unknown** — establish it before relying on it. |
| Auth / authorization | permission join-models untested; `persistent_user.rb` (209 LOC) has no test | ❌ **Not adequate**, and the worst possible regression (permissions failing *open*). B9's `strip_visibility_params` and `group_ids` deletion are authorization logic on untested lines. |
| Email | `email_message.rb` 93.55% — but the `.deliver!` call at `:18` is **uncovered** (➕A4) | ⚠️ One concrete hole, now identified. |
| Assets / asset compilation | not unit-testable; Sprockets 3 + EOL Compass | ❌ Needs the feature suite, which needs Phase 0 first. Deferred to the 7.2 → 8.0 Propshaft hop. |
| Background jobs / ActionCable / API | not applicable | — |
| Boot / eager-load | `engine.rb`: 135 LOC, **7-line test, 1 assertion** | ❌ **The single largest gap relative to risk.** B10 addresses it for one hour of work. |

**Answer: not yet — but the gap is specific, bounded, and now fully enumerated.** Three things are true:

1. **The 72.64% aggregate is adequate; its distribution is not.** Coverage is inversely correlated with upgrade risk — 92% on models that barely change, 58% on controllers where the breakage lives.
2. **Tier B plus Phase 0 closes the gap that matters.** Every item is named, located to a line, and priced. Nothing in the reconciliation added a new category of risk — it corrected versions, expanded three counts, and found one gem-topology landmine.
3. **The largest remaining unknown is not coverage at all.** It is whether the suite currently passes and whether the 53 Cucumber features are green. Both are unmeasured, both are answerable in days, and the skill makes both blocking. **Answer those before committing to any of the estimates in this document.**

The reconciliation's net effect on the plan: **one item promoted two hops earlier (B10/Zeitwerk), one broadened by 5 injected declarations (B5), one narrowed to 4 sites from 10 (B9), one new fix-before-bump landmine (`HTML::FullSanitizer`), three undercounts corrected (`.deliver!`, `File.exists?`, `serve_static_assets`), one claim vindicated (`find_by_*` — 13 call sites saved from pointless churn), and four missing workflow steps restored (patch check, dual-boot, gem compatibility, boot smoke test).** Four version claims remain unverified and are labelled as such; in every case the prescribed test is version-agnostic, so none of them blocks starting.

## 8. Where this diverges from the coverage-per-effort plan

Items promoted by risk that the coverage plan ranked low or not at all:

| Item | Coverage-plan rank | Why promoted |
|---|---|---|
| `schema_dumper.rb` (B1) | unranked — only 3 missed lines | Silent monkeypatch loss corrupts `db/schema.rb` for everyone downstream |
| `belongs_to` audit (B5) | unranked — not a coverage gap | **29** silent validation flips (24 static + 5 injected into every model via the behaviors), and as an engine BrowserCMS cannot opt out — the host app owns the flag |
| Eager-load test (B10) | unranked | One test covers an entire failure class — and Zeitwerk arrives at **6.0**, not 7.0 |
| `create_content_table` (B3) | unranked — 7 missed lines | Every migration in every downstream project |
| `versioning.rb` audit (B6) | unranked — 96.91% covered | High coverage hides untested *ordering* assumptions |
| Paperclip validations (B4) | Phase 6, rank 44 | EOL dependency on a public upload path |
| `HTML::FullSanitizer` (➕A3) | unranked — file is **100% covered** | A gem-topology break no coverage metric can surface: the constant's supplying gem leaves the bundle when Rails 5 resolves |
| `config.serve_static_assets` (➕A6) | unranked — config, not code | Renamed at 5.0, and it is in the **dummy app the whole suite boots against** |

Items demoted, despite being large coverage gaps: **`demo.seeds.rb`** (249 missed — a generator template, filter it), the **generators** (198 missed — out-of-process, unmeasurable), and the **Devise shim helpers** (50 missed — may not survive the Devise upgrade at all, so testing them now is likely wasted).

Item demoted *by the reconciliation*: **the two new B9 sites** (`content_controller.rb:72`, `path_helper.rb:33-36`). They are real `Parameters`-as-Hash hazards, but at 153 and 49 hits they are on lines CI executes — so CI is the detector and test budget belongs elsewhere. Worth stating explicitly, because the reflex on finding a new breakage site is to write a test for it.

The **Forms subsystem** (249 missed lines, `TEST_COVERAGE_PLAN.md` Phase 2) holds its high rank under both lenses — it is both the largest genuine coverage gap and the location of two Tier-C breakages (`params[:form_field].delete`, `render text:`) plus a `.deliver` call. It stays near the front.

---

## Appendix — Reconciliation method and limitations

- **Authority:** the `rails-upgrade` skill (FastRuby.io methodology, "The Complete Guide to Upgrade Rails"), read at `ombulabs-ai/rails-upgrade/3.3.0/rails-upgrade/`. Sources cited per claim in §0.1.
- **Detection scope:** the skill's `rails-42` and `rails-50` pattern sets were run in full against `app/` and `lib/` (plus `test/`, `spec/`, `config/`, `db/`, `Gemfile*` where a pattern's `search_paths` specified them). Selected `rails-51`, `rails-52`, and `rails-60` patterns were run where the original draft made a claim about those versions. **The 6.x / 7.x / 8.x hops have not had a detection pass** — re-run the skill's patterns at each hop.
- **Coverage figures** are read from `coverage/index.html` (the run at `d0d108cc`), with per-line hit counts from `coverage/.resultset.json`. **A trap worth recording:** the `.resultset.json` RSpec suite entry reports every file as fully relevant / zero covered for files that suite never loaded. Naively merging the four suites' arrays therefore *inflates* missed-line counts — `path_helper.rb` reads 26% merged that way versus its true 68.18%. Use `index.html` for file totals; use `.resultset.json` only for per-line hits, and skip any suite where `relevant == total` for the file in question.
- **Every file:line reference in this document was re-verified by grep during reconciliation.** Counts corrected: `.deliver` 1 → 2, `File.exists?` 1 → 5, `belongs_to` 24 → 29, B9 sites 8 → 10.
- **Four claims remain unverified** (C5, C14, C15, C16 — bare `HashWithIndifferentAccess` removal version, `ColumnDumper`/`column_spec`, the `_read_attribute` attribute-layer rewrite, two-arg `connection.quote`). The skill has no entry for any of them. They are labelled 🔇 throughout rather than silently promoted to fact. In each case the prescribed test asserts behaviour rather than an API version, so **none of them blocks starting**, and each will fail loudly at whichever hop actually breaks it.
- **Effort estimates were not revisited** and remain the original draft's.
