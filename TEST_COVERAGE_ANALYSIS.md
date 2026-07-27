# Test Coverage Analysis — browsercms & cms

**Date:** 2026-07-27
**Purpose:** Establish the regression net required before upgrading browsercms from Rails 4.2 to Rails 8.
**Method:** Static analysis — source-to-test file mapping, test corpus inspection, and parsing of the existing SimpleCov report in `cms/coverage/`. No suites were executed; see [Appendix B](#appendix-b--getting-real-numbers) for how to produce real numbers.

---

## 1. Executive summary

The upgrade cannot start yet. Not because coverage is low in aggregate — it isn't catastrophic — but because **coverage is inversely correlated with upgrade risk**. The code most likely to break across six Rails majors is precisely the code with no tests.

| | browsercms | cms |
|---|---|---|
| App + lib Ruby | 13,540 LOC | ~1,638 tracked LOC (+ ~929 untracked) |
| Test + spec code | 9,807 LOC | ~1,180 LOC |
| Cucumber features | 4,860 LOC (53 features) | — (none) |
| Test files | 92 minitest + 11 specs | 16 specs (~79 examples, 3 pending, 1 empty) |
| Measured coverage | **unknown — never measured** | 69.18% line / 22.79% branch (July 2025, inflated) |
| CI | Travis (`.travis.yml`, dead — no `.github/`) | GitHub Actions, `--fail-fast`, no coverage gate |

### The five findings that matter

1. **browsercms has never had its coverage measured.** `.simplecov` exists (`SimpleCov.start 'rails'`) and `test/test_helper.rb` requires it, but there is no `coverage/` directory, no CI publishing, and no threshold. Every number in this document for browsercms is a *file-existence* proxy, not line coverage. Real line coverage is very likely well below what the file counts suggest.

2. **The controller layer is 78% untested.** 32 of 46 controllers have no test file of any kind. Controllers are where Rails 5's `get :action, params: {}` change, strong parameters, `render :text` removal, and `ActionController::Parameters` no longer being a Hash will all bite. See [§3.2](#32-controllers--the-single-largest-gap).

3. **The monkeypatches are the real bomb, and 5 of 10 are completely untested.** `lib/cms/extensions/` reopens `ActiveModel::Errors`, `ActionView::Base`, `ActiveSupport::Cache::FileStore`, `NilClass`, `String`, `Hash`, and `ActiveRecord::ConnectionAdapters::SchemaStatements`. Several patch APIs that Rails rewrote entirely (Errors in 6.1) or that Ruby 3 now provides natively (`Hash#except`). These fail *silently*, not loudly. See [§3.4](#34-libcmsextensions--highest-breakage-risk-per-line).

4. **The test suite itself will not run after the upgrade.** `test/test_helper.rb` uses `Devise::TestHelpers` (removed in Devise 4.2), `mocha/setup` (deprecated), `assert_template`/`assigns` (extracted to `rails-controller-testing` in Rails 5), 88 old-style `get :action, param` calls (removed in Rails 5), and `factory_girl` (renamed `factory_bot` in 2017). Fixing the harness is a prerequisite to using it, and touching all of it at once destroys its value as a regression baseline. See [§4](#4-the-test-harness-itself-blocks-the-upgrade).

5. **The content-block lifecycle is covered only in browsercms's Cucumber suite, and not at all in cms.** browsercms's features do exercise most of the flow — `manage_custom_blocks.feature` (create → delete → render on public page → view version history), `manage_html_blocks.feature` (Save And Publish, edit-then-republish, draft viewing), `add_content_to_pages.feature` (create from page editor → connect to page → assert render) — and all run in the default `rake` task. But no single test chains create → edit → publish → connect → render → version → revert, and **cms has zero coverage of any of it**: 33 `acts_as_content_block` models show "100% covered" because only the macro line executed at load, and 19 `Cms::ContentBlockController` subclasses plus 34 `content_blocks` route entries have none. Cucumber is also the most fragile part of the suite under upgrade (Capybara/Poltergeist, PhantomJS-era). Treat it as a real but brittle asset to be *migrated*, not as a gap.

**Recommendation:** ~5–7 weeks of test work before the first `gem 'rails', '~> 5.0'` bump. Phases 0–2 ([§6](#6-the-plan)) are non-negotiable; Phase 3 can run in parallel with the upgrade itself.

---

## 2. Why file-existence is the wrong metric (and what to do about it)

Three distinct measurement problems are in play:

**browsercms:** no coverage has ever been collected. A file having `foo_test.rb` next to `foo.rb` says nothing about whether the 400-line file has 4 assertions or 400. `dynamic_attributes.rb` is 384 lines with a 73-line test — nominally "tested," effectively not.

**cms:** the July 2025 SimpleCov report is inflated three ways.
- `spec/spec_helper.rb` has **no `add_filter`**, so the 23 spec files (481 lines, 89% "covered") are counted as application code. Excluding them, real coverage is **63.2%**, not 69.18%.
- **No `track_files`**, so 75 Ruby files (~932 lines) that were never `require`d during the run are *absent* from the report rather than showing 0%. `app/controllers` reads 82.7% because only 4 of 56 controllers were loaded — real file-level controller coverage is **7%**.
- The run is ~12 months stale; two files in it no longer exist, and two files with specs (`discount_tours_controller.rb`, `content_splitter_service.rb`) are missing from it entirely.

Treat 63.2% as a ceiling, and the true figure as closer to **~40% of all application code**.

**Fix first (30 minutes, Phase 0):** add `add_filter '/spec/'` + `track_files 'app/**/*.rb'` etc. to cms's SimpleCov config, and wire browsercms's existing `.simplecov` into a rake task that writes a report. You cannot manage what you have not measured, and every phase below should be validated against a real delta.

---

## 3. browsercms — gap analysis

Legend: **DIRECT** = a matching `*_test.rb` / `*_spec.rb` exists. **mention-only** = class name appears in some test but has no dedicated file. **NONE** = no reference anywhere in `test/`, `spec/`, or `features/`.

### 3.1 Models — 24 DIRECT / 12 mention-only / 11 NONE (of 47)

Models are the best-covered layer. The notable gaps:

| File | LOC | Status | Why it matters for the upgrade |
|---|---|---|---|
| `app/models/cms/persistent_user.rb` | 209 | **NONE** | Largest untested model. Devise integration point; Devise majors gate the whole upgrade. |
| `app/models/cms/section.rb` | 286 | mention-only | Largest model without a dedicated test. `ancestry` gem + tree traversal; `ancestry ~> 3.0` is Rails-4-era. |
| `app/models/cms/section_node.rb` | 169 | mention-only | `acts_as_list` (vendored fork) + `touch` semantics, both changed in Rails 5/6. |
| `app/models/cms/view_context.rb` | 53 | **NONE** | Wraps `ActionView` internals — high churn area across Rails versions. |
| `app/models/cms/dynamic_view.rb` | 81 | mention-only | DB-backed view resolution via `panoramic`; interacts with view path lookup. |
| `app/models/cms/guest_user.rb` | 57 | mention-only | Auth null-object; pairs with `persistent_user`. |
| `app/models/cms/group_permission.rb`, `group_section.rb`, `user_group_membership.rb`, `group_type_permission.rb` | 12/9/9/8 | **NONE** | The entire join-model layer of the permission system is untested. Small files, but permissions failing open is the worst possible upgrade regression. |
| `app/models/cms/email_message_mailer.rb` | 12 | **NONE** | `ActionMailer` API changed in Rails 5 (`deliver` → `deliver_now`). |
| `app/models/cms/page_route_option.rb`, `page_route_condition.rb`, `page_route_requirement.rb` | 7/5/5 | **NONE** | Feed dynamic route generation. |

### 3.2 Controllers — the single largest gap

**11 DIRECT / 4 mention-only / 31 NONE of 46.** By line count, 1,289 of 2,311 controller LOC (**56%**) sit in files with no test.

(`inline_content_controller.rb` has a test file — `test/functional/cms/inline_controller_test.rb` — but it contains a single `assert_equal` on `HTML::FullSanitizer` and never touches the controller. It is counted DIRECT below for accuracy and listed in the untested table anyway, because it provides no protection.)

Largest untested:

| File | LOC | Notes |
|---|---|---|
| `cms/form_entries_controller.rb` | 140 | Public form submission — user-facing, handles params. |
| `cms/resource_controller.rb` | 125 | **Base class for much of the admin UI.** Untested inheritance root. |
| `cms/users_controller.rb` | 125 | User CRUD + Devise. |
| `cms/dynamic_views_controller.rb` | 81 | Template editing; touches view resolution. |
| `cms/section_nodes_controller.rb` | 78 | Sitemap drag/drop — AJAX + `acts_as_list`. |
| `cms/form_fields_controller.rb` | 74 | |
| `cms/connectors_controller.rb` | 73 | Core page↔block wiring. |
| `cms/page_route_options_controller.rb` | 58 | |
| `cms/page_routes_controller.rb` | 51 | Dynamic routing admin. |
| `cms/inline_content_controller.rb` | 50 | In-place editing. Nominal test file exists but asserts nothing about the controller. |
| `cms/attachments_controller.rb` | 48 | File serving; Paperclip + `send_file`. |
| `cms/base_controller.rb` | 21 | Another untested inheritance root. |
| `cms/sites/passwords_controller.rb`, `passwords_controller.rb` | 32/22 | Password reset — Devise controllers. |
| `cms/portlet_controller.rb`, `portlets_controller.rb` | 21/35 | Portlet rendering pipeline. |
| ...plus 17 smaller controllers, all NONE | | |

Two untested base controllers (`resource_controller`, `base_controller`) is the structural problem: a single change in their filter chain silently alters 30+ subclasses with nothing to catch it.

### 3.3 Helpers — 5 DIRECT / 1 mention-only / 11 NONE (of 17)

Helpers are ~40% of the rendering surface and mostly dark:

| File | LOC | Status |
|---|---|---|
| `cms/ui_elements_helper.rb` | 168 | **NONE** — largest untested helper; generates raw HTML strings, uses `next_tabindex` (an untested `ActionView::Base` monkeypatch). |
| `cms/path_helper.rb` | 115 | **mention-only** — included into `ActiveSupport::TestCase` by `test_helper.rb:158` but never asserted against. URL generation for content blocks; route helper behavior changed across versions, and cms monkeypatches it. |
| `cms/template_support.rb` | 18 | **NONE** |
| `cms/section_nodes_helper.rb` | 101 | **NONE** — sitemap rendering. |
| `cms/content_block_helper.rb` | 55 | **NONE** |
| `cms/form_tag_helper.rb` | 38 | **NONE** — wraps `ActionView` form tag helpers, which changed substantially in Rails 5.1 (`form_with`) and 6 (default `local: true`). |
| `cms/sites/devise_shim_helper.rb` | 31 | **NONE** — literally a compatibility shim, untested. |
| `cms/mobile_helper.rb` | 29 | **NONE** |
| `cms/sites/authentication_helper.rb` | 25 | **NONE** |
| `cms/nav_menu_helper.rb` | 23 | **NONE** |
| `login_portlet_helper.rb`, `forgot_password_portlet_helper.rb` | 10/9 | **NONE** |

### 3.4 `lib/cms/extensions/` — highest breakage risk per line

Ten monkeypatch files, 244 lines. These are loaded by a bare `Dir[].each { require }` glob (`lib/cms/extensions.rb`, untested).

| File | LOC | Patches | Tested | Upgrade hazard |
|---|---|---|---|---|
| `active_record/connection_adapters/abstract/schema_statements.rb` | 97 | `SchemaStatements` | ✅ `test/unit/schema_statements_test.rb` (80) | **Reopens a Rails internal module with no wrapper.** Calls `create_table table_name, options, &block` — the positional-options signature changed in Rails 5+. Best-tested extension, still the riskiest file. |
| `active_record/base.rb` | 37 | `ActiveRecord::Base` | ✅ (25 lines) | Adds `updated_on_string`, `database_exists?`. |
| `active_model/name.rb` | 12 | `ActiveModel::Name` | ❌ **NONE** | Self-described **Rails 3.2 back-compat shim** re-adding `foreign_key`. Depended on by `dynamic_attributes.rb` (384 LOC / 73 test LOC). |
| `active_record/errors.rb` | 12 | `ActiveModel::Errors` | ❌ **NONE** | `add_from_hash` calls `errors.add(k, v)`. **`ActiveModel::Errors` was rewritten in Rails 6.1** — this will change semantics silently. Used live by `app/portlets/email_page_portlet.rb`. |
| `action_view/base.rb` | 12 | `ActionView::Base` | ❌ **NONE** | `next_tabindex`, used by the untested 168-LOC `ui_elements_helper.rb`. |
| `active_support/cache/file_store.rb` | 8 | `ActiveSupport::Cache::FileStore` | ❌ **NONE** | **Reopens the class with no wrapper** — a load-order change creates a phantom class rather than raising. Uses the private `cache_path`. |
| `nil.rb` | 18 | `NilClass` | ❌ **NONE** (only `round_bytes` incidentally) | Defines `to_formatted_s` on `NilClass` — direct collision risk with Rails 7 core-ext changes. |
| `string.rb` | 23 | `String` | ⚠️ partial (13 lines, only `pluralize_unless_one`) | Defines `String#indent`, **which collides with Rails' own**. `markdown`, `to_slug` untested. |
| `hash.rb` | 10 | `Hash` | ⚠️ partial | Overrides **Ruby 3.0+ native `Hash#except`** via `reject`. Should simply be deleted. |
| `integer.rb` | 15 | `Integer` | ✅ | Fine. |

**5 of 10 fully untested, 2 partial.** These are ~10-line files — writing characterization tests for all of them is under a day's work and is the highest ROI in the entire plan.

### 3.5 `lib/cms/behaviors/` — the core mixins

16 files, 2,081 LOC, auto-included into `ActiveRecord::Base` by a glob-and-`constantize` loader (`lib/cms/behaviors.rb`, untested). Test-to-source ratio matters more than presence here:

| Behavior | LOC | Test LOC | Ratio | Assessment |
|---|---|---|---|---|
| `dynamic_attributes.rb` | 384 | 73 | **0.19x** | **Worst ratio in the repo.** EAV via `method_missing` + `ActiveModel::Name` shim. |
| `versioning.rb` | 368 | 140 | **0.38x** | Callback + STI machinery. Callback ordering changed in Rails 5 (`return false` no longer halts). |
| `attaching.rb` | 375 | 736 | 1.96x | Best covered. Paperclip 5 → needs replacement anyway. |
| `publishing.rb` | 195 | 238 | 1.22x | Adequate. |
| `rendering.rb` | 195 | 68 | 0.35x | Thin. |
| `connecting.rb` | 141 | 93 | 0.66x | Thin. |
| `soft_deleting.rb` | 94 | 0 | — | **No dedicated test.** 2 incidental mentions. |
| `taggable.rb` | 66 | 113 | 1.71x | Good. |
| `hiding.rb` | 46 | 0 | — | **Zero references to `Hiding` / `is_hideable` anywhere in tests.** The `hidden` *attribute* is touched by `page_test.rb` visibility assertions; the mixin's own scopes and API are completely dark. |
| `searching.rb` | 45 | 85 | 1.89x | Good. |
| `archiving.rb` | 43 | 0 | — | Incidental `archive` mentions only. |
| `userstamping.rb` | 39 | 26 | 0.67x | Both tests cover nil-user cases; **the happy path (user present → `created_by` set) is untested.** |
| `flush_cache_on_change.rb` | 30 | 0 | — | **Zero references.** `after_save`/`after_destroy` → `Cms::Cache.flush`. |
| `categorizing.rb` | 30 | 0 | — | The category *models* are tested; the mixin is not. |
| `naming.rb` | 16 | 23 | 1.44x | Fine. |
| `namespacing.rb` | 14 | — | — | Empty body, deprecated shim. Delete. |

### 3.6 Engine, routing, and autoloading — near-zero coverage on the hardest part

| File | LOC | Test | Hazard |
|---|---|---|---|
| `lib/cms/engine.rb` | 135 | **7-line test, 1 assertion** | Pushes 6 dirs onto `ActiveSupport::Dependencies.autoload_paths` — **classic autoloader only, incompatible with Zeitwerk** (mandatory from Rails 7). Initializer anchored `:after => 'action_controller.deprecated_routes'`, an initializer that **no longer exists**. Calls `routes_reloader.reload!` in `after_initialize`. Sprockets-3-style `assets.precompile`. This one file is the single biggest concentration of upgrade work and it has essentially no test. |
| `lib/cms/route_extensions.rb` | 157 | 62 (0.4x) | Mixed into `ActionDispatch::Routing::Mapper`; the test stubs a fake builder rather than exercising a real `Mapper`. |
| `lib/cms/behaviors.rb` / `concerns.rb` / `acts.rb` / `extensions.rb` | 34/6/7/5 | **NONE** | Glob + `constantize` + include-into-`ActiveRecord::Base`. Zeitwerk forbids this pattern. |
| `lib/cms/polymorphic_single_table_inheritance.rb` | 18 | **NONE** | Overrides AR STI column behavior. |
| `lib/cms/configuration/devise.rb` | 256 | **NONE** | Second-largest untested file. Devise is a hard upgrade gate. |
| `lib/cms/authentication/controller.rb` | 120 | **NONE** direct | |
| `lib/cms/configure_simple_form.rb` + `_bootstrap.rb` | 200 | Cucumber only | SimpleForm 3.1 → 5.x DSL changes. |
| `lib/cms/attachments/configuration.rb` | 88 | **NONE** | Runs in `to_prepare` on every dev request. |
| `lib/acts_as_list.rb` | 295 | **NONE** | **Largest untested file in `lib/`.** A vendored fork of the gem. Deep AR callback/scope code. |

**~2,050 of 6,142 `lib/` lines (33%) have no dedicated test**, and the untested set is disproportionately monkeypatches, engine config, and gem glue.

---

## 4. The test harness itself blocks the upgrade

Independent of coverage, the browsercms suite cannot execute on Rails 5+ without a rewrite:

| Issue | Count / location | Breaks at |
|---|---|---|
| `get :action, param_hash` (positional params) | **88 occurrences** in `test/` | Rails 5 (requires `params: {}`) |
| `assert_template` | 19 | Rails 5 (extracted to `rails-controller-testing`) |
| `render :text` in tested controllers | 4 | Rails 5.1 |
| `assigns(...)` | 11 | Rails 5 (same gem) |
| `Devise::TestHelpers` | `test/test_helper.rb:185` | Devise 4.2 (→ `Devise::Test::ControllerHelpers`) |
| `mocha/setup` | `test/test_helper.rb` | Mocha 2 (→ `mocha/minitest`) |
| `factory_girl` / `FactoryGirl` | throughout both repos | renamed `factory_bot` in 2017 |
| `MonitorMixin`/`recycle!` monkeypatch | `test/test_helper.rb` (guarded, self-disables on Rails 5+) | benign |
| `$VERBOSE = nil` | `test/test_helper.rb` | hides deprecation warnings — **the single most useful signal during a Rails upgrade** |
| Travis CI | `.travis.yml`; no `.github/` | Travis OSS is effectively dead; **browsercms has no working CI** |

Also: `test/unit/lib/cms_domain_support_test.rb` and `test/unit/lib/cms/domain_support_test.rb` are duplicate/overlapping tests of the same file.

**Implication for sequencing:** modernizing the harness (Phase 1) must happen *before* writing new tests, or every new test gets written twice. And `$VERBOSE = nil` must be removed early — deprecation warnings are how you find the next thing to fix.

On the cms side: **Capybara is not in the Gemfile or lockfile at all**, yet two `spec/features/**` specs call `visit`/`click_on` (a third, `spec/features/cms/admin/sitemap_spec.rb`, is a **0-byte file**). Nearly all their assertions are `pending`. Feature-level coverage of cms is effectively zero. CI runs with `--fail-fast`, which during an upgrade means one early failure hides the entire tail of the suite — remove it before starting.

---

## 5. cms — the integration surface

cms is the regression detector that matters most: it is the real consumer of every browsercms API. 52 Ruby files under `app/`/`lib/`/`config/` reference `Cms::` directly (110 including `db/migrate`), plus 57 migrations. At the view layer, 9 views reference `Cms::` constants explicitly, but the coupling is far wider through implicit CMS locals — **`@content_block` appears 260 times** across `app/views/`, `@page` 32, `Cms::ContentType` 30 — and 17 engine views are overridden in-app.

### 5.1 Highest-risk files (heavy CMS coupling × poor coverage)

| File | Line cov | Branch cov | Coupling |
|---|---|---|---|
| `config/initializers/browsercms_overrides.rb` | **28.8%** (64/222) | **0/67** | 567 physical lines, **40 `Cms::` refs.** Monkeypatches `Cms::Attachment` (~145 lines), `Authentication::Controller#current_user`, `ContentController#show`, `PagesController#new`, `Page.currently_connected_to`, `RenderingHelper#show`, `PageHelper#page_header`, `SectionNode#touch_node`, `Behaviors::Publishing#publishable?`, `Behaviors::Searching#is_searchable`, and more. **This one file is 24% of all uncovered lines in cms.** |
| `app/helpers/cms/menu_helper.rb` | **9.8%** (4/41) | **0/28** | Reimplements the engine's own helper inside the app. |
| `config/initializers/override_csrf_encode_decode.rb` | **25.9%** | 1/8 | **Hard-fails boot with `exit(1)` unless `Rails.version == '4.2.11'`.** Reimplements `masked_authenticity_token` / `valid_authenticity_token?`. This aborts the app on the first boot after any version bump. |
| `config/initializers/override_bcms_partial_error_rescue.rb` | **15.4%** | 0/8 | Replaces `RenderingHelper#render_connectable`. |
| `config/initializers/override_show_link.rb` | **20.0%** | 0/6 | Replaces `Cms::PathHelper#link_to_usages`; branches on `Cms::Portlet === block`. |
| `lib/audio_file_uploader.rb` | 22.2% | 0/4 | `Cms::Section.find_by_path`, builds attachments. |
| `lib/connectable.rb` | 23.1% | 1/6 | `Cms::Connector` heuristics. |
| `app/helpers/cms/destination_helper.rb` | 28.0% | 0/4 | 10 `@content_block` calls. |
| `app/helpers/application_helper.rb` | 44.0% (40/91) | 0/6 | Raw SQL against `data_file_path`, `attachable_type`. |
| `lib/image_extractor.rb` | **no data (0%)** | — | 145 lines, 8 `Cms::` refs. |

Aggregate: the 50 tracked integration-surface files are **60.0% line covered**; another 30 surface files have no coverage data at all.

### 5.2 The illusion of coverage

- `config/routes.rb` reads **100%** — because routes are drawn at boot. It carries zero signal that any of the **34 `content_blocks` CRUD surfaces** work.
- The 33 `acts_as_content_block` models read **100%** — several are 3-line class bodies where only the macro line executed at load time.
- **All 19 `Cms::ContentBlockController` subclasses in `app/controllers/rse/` have zero coverage.** (40 files in `app/controllers/rse/` total.)
- **No test in cms exercises the create/edit/publish/render lifecycle of a content block.** (browsercms's Cucumber suite does — see Finding 5 in §1.)

### 5.3 Rails-4-isms in cms

**11 associations across 3 files pass `class_name:` a bare constant rather than a string** — which breaks under modern Rails autoloading: `app/models/rse/article.rb` (8, including `class_name: Cms::Connector`), `app/models/rse/tile.rb` (2), `app/models/rse/site_tile.rb` (1). Other content-block models (`audio_tour.rb`, `page_link.rb`, `extra_link.rb`, `generic_subsection.rb`, `audio_europe.rb`, `image_collection_image.rb`) use the correct string form and are not affected.

Also in cms: 4 `before_filter`, `Rse::VideoEpisode::Version.class_eval` patching a CMS-generated versions class, and `monkeypatch_active_record.rb` patching `PostgreSQLAdapter`. No live `attr_accessible` (only a comment in `config/application.rb` and a commented line in `db/browsercms.seeds.rb`).

In browsercms: **38 filter macros** — 34 `before_filter`, 2 `after_filter`, 2 `skip_before_filter`, zero `around_filter` (all renamed in Rails 5.1); **16 `update_attributes`** (removed in Rails 7: 7 in models, 4 in controllers, 5 in behaviors); **~13 live dynamic `find_by_*` call sites** (17 non-comment matches, but 4 are hand-written `def self.find_by_*` definitions in `site.rb`, `dynamic_view.rb`, `section.rb`, `content_type.rb`); **4 `render :text`** sites (removed in Rails 5.1) in `tests/pretend_controller.rb` ×2, `content_block_controller.rb:138`, `form_fields_controller.rb:43`; 1 `alias_method_chain` (removed in Rails 5.1). All **11 `attr_accessible` lines are already commented out** — dead code, no work required.

### 5.4 Dependency gates

cms pulls `browsercms 5.2.0` from a private Gem Fury source and **Rails 4.2.10 from `gems.railslts.com`** (Rails LTS — a commercial patched fork). The LTS source disappears the moment you move off 4.2, so the very first bump changes the dependency topology. `faker` is pinned to a git tag from `github.com/stympy/faker`, a repo since renamed — a bundle-resolution hazard on any `bundle update`.

---

## 6. The plan

Sequencing principle: **make the suite runnable and measurable → freeze current behavior with characterization tests → build end-to-end safety nets → only then bump Rails.** Characterization tests assert what the code *does today*, not what it should do; their job is to scream when a Rails upgrade silently changes semantics.

### Phase 0 — Instrumentation (2–3 days)

Do this first. Everything after depends on being able to see the delta.

1. **cms SimpleCov fix.** Add `add_filter '/spec/'`, `add_filter '/vendor/'`, `track_files 'app/**/*.rb'`, `track_files 'lib/**/*.rb'`, `track_files 'config/initializers/**/*.rb'`, plus `add_group`s. Re-run. Expect the headline to drop from 69% into the low 40s — that is the real baseline.
2. **browsercms coverage.** Wire the existing `.simplecov` into a rake task that emits HTML + JSON. Add the same filters/`track_files`. **Get the first real number this repo has ever had.**
3. **Remove `--fail-fast`** from `.github/workflows/ci.yml` in cms. Add `--format documentation` so failures are legible.
4. **Stand up CI for browsercms.** Port `.travis.yml` to GitHub Actions (Ruby 2.7.8, Postgres). Travis is dead; browsercms currently has no CI at all. This is a hard blocker — you cannot do a six-version upgrade without a green button.
5. **Set a coverage floor** in both repos (`minimum_coverage` at whatever the real baseline is) so the upgrade cannot silently delete tests.
6. **Find out whether the 53 Cucumber features actually pass.** They are the only end-to-end coverage that exists anywhere, and they run on Poltergeist/PhantomJS (abandoned since 2018). If a large share are already red, Phase 3 grows substantially — better to know on day one.

**Exit criteria:** both suites run green in GitHub Actions and publish a real coverage number, and the true pass rate of the Cucumber suite is known.

### Phase 1 — Harness modernization (1 week)

Mechanical, unglamorous, and blocking. Do it while still on Rails 4.2 so failures are unambiguous.

1. `factory_girl` → `factory_bot` in both repos (`FactoryGirl::Syntax::Methods` → `FactoryBot::Syntax::Methods`, block syntax `m.name 'Root'` → `m.name { 'Root' }`).
2. `mocha/setup` → `mocha/minitest`.
3. Add `rails-controller-testing` to preserve the 19 `assert_template` and 11 `assigns` call sites through Rails 5.
4. Mechanically convert the **88 positional `get :action, params`** calls to `get :action, params: {...}` — Rails 4.2 accepts the keyword form, so this is a safe pre-emptive change.
5. `Devise::TestHelpers` → `Devise::Test::ControllerHelpers`.
6. **Delete `$VERBOSE = nil`** from `test/test_helper.rb`. Fix or explicitly silence the resulting noise. Deprecation warnings are your upgrade roadmap.
7. Add Capybara + `rack_test` to cms, un-`pending` the three feature specs, delete or write `spec/features/cms/admin/sitemap_spec.rb` (currently 0 bytes).
8. De-duplicate `cms_domain_support_test.rb` / `cms/domain_support_test.rb`.

**Exit criteria:** suites green, no positional-param or `factory_girl` call sites remain, deprecation warnings visible in CI logs.

### Phase 2 — Characterization tests on the breakage surface (2–3 weeks)

Ordered by (risk × exposure) ÷ effort. This is the actual safety net.

**2a. Monkeypatch characterization — ~1 day, highest ROI in the plan.**
One test file per extension, asserting exact current behavior:
- `active_record/errors.rb` — `add_from_hash` with single/multiple/empty/nil hashes. *(Rails 6.1 rewrote `ActiveModel::Errors`; this is the most likely silent breakage in the codebase.)*
- `active_model/name.rb` — `foreign_key` output for namespaced and plain models.
- `action_view/base.rb` — `next_tabindex` sequencing across calls.
- `active_support/cache/file_store.rb` — `flush` behavior and `cache_path` dependency.
- `nil.rb` — all four methods, **especially `to_formatted_s`**.
- `string.rb` — `indent` (**document the collision with Rails' own**), `markdown`, `to_slug`.
- `hash.rb` — `except`; then **delete the patch** and confirm Ruby 3 native behavior is identical.
- Extend `schema_statements_test.rb` to cover `create_content_table` / `drop_content_table` option-passing, since the `create_table` signature changed.

**2b. Untested behaviors — ~3 days.**
`hiding.rb` (46 LOC, completely dark), `flush_cache_on_change.rb` (30, zero refs), `soft_deleting.rb` (94), `archiving.rb` (43), `categorizing.rb` (30). Plus the **`userstamping` happy path** — currently only nil-user cases are asserted, so a broken `created_by` would pass CI today.

**2c. Deepen the two thinnest large behaviors — ~1 week.**
`dynamic_attributes.rb` (384 LOC / 73 test LOC) and `versioning.rb` (368 / 140). Both are `method_missing` + AR-callback machinery, and **Rails 5 changed callback halting** (`return false` no longer halts a chain — it must be `throw :abort`). Target ≥1.0x test-to-source ratio. Pay particular attention to callback ordering and `_versions` table generation.

**2d. Engine and autoloading — ~3 days.**
Tests asserting: which paths land in `autoload_paths`; the initializer ordering contract; the `assets.precompile` list; that all 16 behaviors are actually included into `ActiveRecord::Base`; that `Cms::RouteExtensions` reaches `ActionDispatch::Routing::Mapper`. These will *all* need rewriting for Zeitwerk — which is precisely the point. They document the contract you must reproduce.

**2e. Controller smoke tests — ~1 week.**
Not deep tests. For each of the 32 untested controllers: authenticate, hit each action, assert a non-5xx response and correct redirect-vs-render. Start with the two base classes (`resource_controller`, `base_controller`), then `form_entries`, `users`, `connectors`, `attachments`, `section_nodes`, `page_routes`, and the two Devise `passwords_controller`s. This is where Rails 5's param and `render :text` changes surface.

**Exit criteria:** every file in [§3.4](#34-libcmsextensions--highest-breakage-risk-per-line) and [§3.5](#35-libcmsbehaviors--the-core-mixins) has a dedicated test; no controller is entirely dark.

### Phase 3 — End-to-end content-block lifecycle (1–2 weeks)

**The most valuable single deliverable in the plan.** browsercms's Cucumber suite already covers much of this flow (see Finding 5), so Phase 3 has two halves:

**3a. Protect the existing Cucumber coverage.** It runs on `capybara` + `poltergeist` (PhantomJS, abandoned) and `cucumber-rails`, and `aruba` is hard-pinned to `0.14.14`. This stack will not survive the upgrade untouched. Migrate the driver to `cuprite` or headless Chrome **while still on Rails 4.2**, so you find out now whether the 53 features actually pass. If a meaningful share are already red, that changes the plan — this is worth checking in Phase 0.

**3b. Build the equivalent in cms**, where coverage is genuinely zero. One integration spec per representative content-block archetype:
1. plain block (`Rse::Accordion`)
2. block with attachments (`Rse::ImageBlock`, `Rse::AudioRadio` with its 17 attachments)
3. taggable block (`Rse::VideoClip`)
4. versioned/publishable block (`Rse::Article`)
5. addressable block (`Rse::Destination`)

Each covering the **full chain in one test: create → edit → publish → connect to page → render on the public page → view version history → revert.** browsercms's Cucumber scenarios cover these steps but split across separate features; chaining them is what catches state-transition bugs. That single flow exercises `acts_as_content_block`, `Connecting`, `Publishing`, `Versioning`, `Attaching`, `Taggable`, `RenderingHelper`, `PathHelper`, the `content_blocks` route DSL, and `ContentBlockController` — i.e. most of the surface [§5.2](#52-the-illusion-of-coverage) shows as falsely covered.

Also in Phase 3:
- Characterization tests for `config/initializers/browsercms_overrides.rb` (567 physical / 222 relevant lines, 0/67 branches, 40 `Cms::` refs). Given that it monkeypatches ~145 lines of `Cms::Attachment`, **strongly consider upstreaming those overrides into browsercms** where they can be tested properly, rather than testing them from the app side.
- **Resolve `override_csrf_encode_decode.rb` before the first bump.** Its `exit(1)` version guard will abort boot immediately. Decide now whether to reimplement against the new Rails or drop it.
- Factories for the content-block models — currently **30 of 33 have none** (only `Rse::Tour`, `Rse::TourDestinationCategory`, `Rse::TourTypeCategory` do).

### Phase 4 — Ongoing, during the upgrade

- Bump one Rails minor at a time (4.2 → 5.0 → 5.1 → 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0). Green suite at every step.
- Keep `deprecation_behavior = :raise` in test env from 5.0 onward.
- Zeitwerk is the hardest single step (7.0). Phase 2d's tests are what make it tractable.
- Replace, don't port: **Paperclip** (dead since 2018 → ActiveStorage or Shrine), **Devise** (config rewrite), **SimpleForm 3.1 → 5.x**, **jquery-rails 3.1 → 4.x**, the **vendored `acts_as_list` fork** (295 untested lines — adopt the maintained gem), **Sprockets 3 → Propshaft or Sprockets 4**, and the **Rails LTS gem source** (disappears at 4.2).
- Ratchet the coverage floor upward after each phase.

---

## 7. Priority-ordered backlog

| # | Item | Repo | Effort | Risk addressed |
|---|---|---|---|---|
| 1 | Fix SimpleCov config; get real baselines | both | 0.5d | Flying blind |
| 2 | GitHub Actions CI for browsercms | browsercms | 1d | **No CI at all** |
| 3 | Remove `--fail-fast`; remove `$VERBOSE = nil` | both | 0.5d | Hidden failures & deprecations |
| 3b | Establish true Cucumber pass rate; migrate off Poltergeist | browsercms | 2–3d | **Only E2E coverage that exists, on a dead driver** |
| 4 | Harness modernization (Phase 1) | both | 1w | Suite won't run on Rails 5 |
| 5 | Monkeypatch characterization tests | browsercms | 1d | **Silent semantic breakage** |
| 6 | Untested behaviors (hiding, flush_cache, soft_delete, archiving, categorizing, userstamping happy path) | browsercms | 3d | Dark core mixins |
| 7 | Content-block lifecycle integration specs | cms | 1–2w | **Core flow, zero coverage in cms** |
| 8 | Deepen `dynamic_attributes` + `versioning` | browsercms | 1w | Rails 5 callback halting |
| 9 | Engine/autoload contract tests | browsercms | 3d | **Zeitwerk migration** |
| 10 | Controller smoke tests (31 files) | browsercms | 1w | 56% of controller LOC dark |
| 11 | `browsercms_overrides.rb` characterization / upstream | cms | 1w | 24% of cms's uncovered lines |
| 12 | Resolve `override_csrf_encode_decode.rb` `exit(1)` guard | cms | 0.5d | **Boot failure on first bump** |
| 13 | Helper tests (11 untested, esp. `ui_elements`, `path_helper`, `form_tag_helper`) | browsercms | 1w | Rendering surface |
| 14 | Factories for 31 content-block models | cms | 3d | Enables everything above |
| 15 | Permission join-model tests | browsercms | 2d | **Auth failing open** |
| 16 | Delete dead code (`sequence.rb`, `namespacing.rb`, `hash.rb` patch, 11 commented `attr_accessible` lines, `override_bcms_associations.rb`, `page_helper_old.rb.old`, cms's legacy 12-file `test/` tree, duplicate domain-support tests) | both | 1d | Reduces surface to port |
| 17 | Fix 11 bare-constant `class_name:` associations in cms (`article.rb`, `tile.rb`, `site_tile.rb`) | cms | 0.5d | Breaks under modern autoloading |

**Phases 0–2 ≈ 5–6 weeks. Phase 3 ≈ 1–2 weeks, partly parallelizable.** Items 1–3 should start today regardless of anything else.

---

## Appendix A — Method and limitations

- Source-to-test mapping by filename convention **and** class-name occurrence across the full test/spec/feature corpus, so "NONE" means no textual reference of any kind — a strong signal.
- **"DIRECT" does not mean well-tested.** It means a file exists. Test-to-source line ratios are given wherever they were checked, and several DIRECT files (`engine_configuration_test.rb`: 7 lines for a 135-line engine; `commands_actions_test.rb`: 22 lines for 106; `inline_controller_test.rb`: asserts nothing about its controller) are effectively smoke tests or worse.
- Figures in this document were independently fact-checked against both repos on 2026-07-27; corrections have been applied. Remaining unverified items are the `lib/` untested-line estimate (~2,050 of 6,142), the 60.0% integration-surface figure, the "~40% of all application code" projection, and all effort estimates.
- browsercms line coverage is **unmeasured**. All browsercms figures are file-existence proxies and should be treated as optimistic.
- cms figures derive from a stale, unfiltered SimpleCov run; see [§2](#2-why-file-existence-is-the-wrong-metric-and-what-to-do-about-it).

## Appendix B — Getting real numbers

```bash
# browsercms (Ruby 2.7.8, Postgres)
cd browsercms
createdb browsercms_test
bundle install
bundle exec rake            # units + spec + functionals + features
open coverage/index.html

# cms (Ruby 3.1.6, Postgres 16, needs Gem Fury + Rails LTS credentials)
cd cms
bundle install
bundle exec rake db:test:prepare
bundle exec rspec spec --format documentation   # note: drop --fail-fast
open coverage/index.html
```

Run these before starting Phase 1 so the Phase 0 baseline is measured rather than estimated. If the numbers differ materially from this analysis, §6 priorities should be re-sorted against them.
