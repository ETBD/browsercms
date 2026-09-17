# Phase 3 — Backwards-Compatible Code Fixes

> ## Goal
> **Land ~96 mechanical API changes that work identically on Rails 4.2 and 5.0+, so the bump diff contains only the things that genuinely require a version change.**
>
> Every change in this phase can be reviewed, merged, and deployed on Rails 4.2 today. None needs a `NextRails.next?` branch.

**Blocking:** 🟡 Not strictly — but skipping it means debugging these ~96 changes *simultaneously* with the bump.
**Rails version at the end of this phase:** 4.2.11.3. (The source methodology says "deployed to production" here; browsercms is an engine shipped as a gem, so there is no application to deploy — see the README's note on engine-vs-application criteria.)

> ## Two measured items to do first
>
> [Phase 1](phase-1-gem-report.md) ran the unit suite on Rails 5.0.7.2 and got **2 failures and 323 errors**. Both causes are backwards-compatible fixes and therefore belong here — and between them they account for **all but one** of those errors.
>
> | Fix | Impact | Detail |
> |---|---|---|
> | **`create_or_update` arity** — [`lib/cms/behaviors/versioning.rb:230`](../../lib/cms/behaviors/versioning.rb#L230) | **320 of 323 errors** | Rails 4.2 declares `def create_or_update` (`persistence.rb:502`); Rails 5.0 declares `def create_or_update(*args, &block)` (`persistence.rb:546`). The override still has the old zero-arity signature, so **every save on Rails 5 raises** `ArgumentError: wrong number of arguments`. Accepting `(*args, &block)` and passing through works identically on 4.2. Plausibly the highest-leverage single change in the whole upgrade. |
> | **`HTML::FullSanitizer`** — [`lib/cms/content_filter.rb:12`](../../lib/cms/content_filter.rb#L12) | 2 failures | The constant comes from `rails-deprecated_sanitizer`, which is only in the bundle because `rails-dom-testing 1.x` depends on it — and 1.x caps `activesupport < 5.0`. On Rails 5 it leaves the bundle and the line raises `NameError`. **Two exits:** fix the call site to `Rails::Html::FullSanitizer`, or declare `rails-deprecated_sanitizer` explicitly (it requires only `activesupport >= 4.2.0.alpha`, no upper bound). The first is where it should end up. |
>
> Do the arity fix first and re-measure before scoping the rest of this phase — with 99% of the errors gone, what remains underneath is currently unknown.
>
> One caution carried from Phase 1: `content_filter.rb` is **8/8 lines covered and line 12 is hit twice**, and it still breaks. Coverage did not miss it; coverage cannot express version-dependent resolution. Do not use the coverage report to decide which of the ~96 changes are safe.

---

## Why this phase exists

This is the skill's "deploy small changes to production before the version bump" principle, applied concretely.

Each of these APIs has a replacement that already exists in Rails 4.2. `before_action` works on 4.2. `update` works on 4.2. `optional: true` works on 4.2. So there is no reason to carry them into the bump, where a failure could be caused by the rename *or* by Rails 5 *or* by a gem — three hypotheses instead of one.

Two of these items also retire risk that later phases inherit:

- **`belongs_to ... optional: true` (29 sites) is not deferrable.** BrowserCMS is an engine — `lib/cms/engine.rb:7` declares `isolate_namespace Cms` — and `load_defaults` appears nowhere in the repo. The `belongs_to_required_by_default` flag is owned by the **host application**, so the usual "bump the gem, leave `load_defaults` at 4.2, decide later" escape hatch does not exist for a library. A host app on `load_defaults 5.0` exercises required-by-default against these models the day it upgrades.
- **`HTML::FullSanitizer` breaks the instant Rails 5 resolves**, because the gem supplying it leaves the bundle. It has to be fixed before the bump can be green, not after.

## Supporting documentation

- [`RAILS_UPGRADE_TEST_PRIORITY.md` §4](../../RAILS_UPGRADE_TEST_PRIORITY.md) — the Tier C table, with skill-sourced removal versions, and the closing list of backwards-compatible changes
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §3, B5](../../RAILS_UPGRADE_TEST_PRIORITY.md) — the full `belongs_to` breakdown, all 29 sites
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §0.3](../../RAILS_UPGRADE_TEST_PRIORITY.md) — **read this before touching `belongs_to`.** Why an engine cannot opt out, and why the test must force the flag on.
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §0.2](../../RAILS_UPGRADE_TEST_PRIORITY.md) — ➕A1 (29 not 24), ➕A3 (sanitizer), ➕A4 (`.deliver!`), ➕A5 (`File.exists?` ×5)
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §5](../../RAILS_UPGRADE_TEST_PRIORITY.md) — **the do-not-touch list.** Notably: leave the ~13 `find_by_*` call sites alone.
- Skill: `version-guides/upgrade-4.2-to-5.0.md` §3 (`belongs_to`), `detection-scripts/patterns/rails-42-patterns.yml`, `rails-50-patterns.yml`, `rails-51-patterns.yml`

## Work items

Grouped by what breaks if you get them wrong. Counts are grep-verified.

### 3.1 — Breaks at 5.0 (must land before the bump)

- [ ] **`belongs_to` → add `optional: true` where the association is legitimately nil. 29 sites.**
  - 24 in `app/models/cms/`
  - **5 injected by behaviors**, which is where the blast radius is: `behaviors/userstamping.rb:16-17` (`created_by`, `updated_by`), `behaviors/categorizing.rb:16` (`category`), `behaviors/versioning.rb:115` (version → parent), `behaviors/dynamic_attributes.rb:168` (`base_class`). These apply to *every* model using the behavior, in this engine and in every downstream project.
  - Near-certain candidates for `optional: true`: all polymorphic associations (`SectionNode#node`, `Connector#connectable`, `Attachment#attachable`, `Tagging#taggable`), **`Category#parent`** (self-referential — every root category has a nil parent, so required-by-default breaks the category tree outright), `Task#assigned_by` / `#assigned_to`, and userstamping's pair.
  - The skill's instruction: add `optional: true` **only** where nil is legitimate. Leave genuinely-required associations alone — this is an audit, not a find-and-replace.
- [ ] **`HTML::FullSanitizer` → `Rails::Html::FullSanitizer` / `ActionView::Base.full_sanitizer`.** One site: `lib/cms/content_filter.rb:12`. Also update `test/functional/cms/inline_controller_test.rb:7`, which asserts on the doomed gem directly.
- [ ] **`.deliver` / `.deliver!` → `deliver_now` / `deliver_now!`. 2 sites.** `app/models/cms/email_message.rb:58` (`.deliver`, covered) and **`:18` (`m.deliver!`, uncovered)**. Preserve the bang — `deliver!` becomes `deliver_now!`, not `deliver_now`. (`:15` is `def self.deliver!`, a definition; leave it.)
- [ ] **Declare `responders` in `browsercms.gemspec`.** It's currently in the bundle only as a transitive dependency of `devise`. Six `respond_with` / class-level `respond_to` sites depend on it, including `content_controller.rb:79` — the main page-serving path. One line; removes a landmine before the Devise upgrade can move it.
- [ ] **Unversioned `ActiveRecord::Migration` → `ActiveRecord::Migration[4.2]`. 2 sites.** `db/migrate/20080815014337_browsercms300.rb`, `db/migrate/20130327184912_browsercms400.rb`.
- [ ] **`save!` takes `(*args, &block)`. 1 site** *(added after Phase 2)*. [`lib/cms/behaviors/versioning.rb:271`](../../lib/cms/behaviors/versioning.rb#L271) declares `save!(perform_validations=true)`, but no Rails version calls `save!` with a positional boolean: 4.2 calls `save!(:validate => x)` and 5.0 calls `save!(validate: x, &block)`, both from the collection-association insert path. The parameter therefore receives a truthy Hash and validations run in the path where the framework asked for them to be skipped — **silently, on both versions** — and on 5.0 the block `create_or_update` yields after insert is discarded here, one method above the `(*args, &block)` signature Phase 2 gave that method. Same defect as the arity fix, one level up, and the arity fix is what makes it reachable. ⚠️ **This one changes behaviour** — see the implementation plan's D8.

### 3.2 — Breaks at 5.1 (free to do now)

- [ ] **`*_filter` → `*_action`. 37 sites across 17 files.** 14 controllers plus `lib/cms/acts/content_page.rb`, `lib/cms/admin_tab.rb`, `lib/cms/authentication/controller.rb`. Behaviour is identical; this is a rename. Failure mode on 5.1 is a boot-time `NoMethodError`, so it needs no test.
- [ ] **`render text:` → `render plain:`. 4 sites.** `content_block_controller.rb:138`, `form_fields_controller.rb:43`, plus 2 in `tests/pretend_controller.rb`. Use `render html:` if HTML was actually intended. **Both production sites are on untested error branches** — see [Phase 4](phase-4-characterization-tests.md), which adds tests for them precisely because nothing exercises them.
- [ ] **`Relation#uniq` → `.distinct`. 1 site.** `section_nodes_controller.rb:75`, inside `nodes_to_update_on_success`. Receiver already verified as a Relation, not an Array.

### 3.3 — Breaks at 6.0 (free to do now, and 16 sites is worth removing early)

- [ ] **`update_attributes` / `update_attributes!` → `update` / `update!`. 16 sites.** 7 in models, 4 in controllers, 5 in behaviors. ⚠️ `app/models/cms/guest_user.rb:48` *defines* a method called `update_attributes` — check its callers before renaming anything.

### 3.4 — Version-agnostic cleanups

- [ ] **`File.exists?` → `File.exist?`. 5 sites** (the supporting analysis originally found 1): `app/portlets/list_portlet.rb:22` (**uncovered**), `lib/cms/caching.rb:42`, `lib/cms/attachments/attachment_serving.rb:44`, `lib/tasks/core_tasks.rake:51`, `lib/generators/cms/content_block/content_block_generator.rb:26`. Two are live request-path code.
- [ ] **Bare `HashWithIndifferentAccess` → `ActiveSupport::HashWithIndifferentAccess`. 2 sites.** `app/models/cms/page_component.rb:10` (covered), `app/models/cms/portlet.rb:228` (**uncovered**). The removal version is unverified, so qualify both now and stop tracking it.
- [ ] **Delete dead code** rather than porting it: `lib/cms/commands/to_version400.rb` (BrowserCMS 4.0.0 upgrade command, two majors dead), `app/portlets/deprecated_placeholder.rb`. Also `lib/cms/behaviors/namespacing.rb` — an empty deprecated shim. Note `lib/cms/form_builder/deprecated_inputs.rb` is still contractually alive (`features/content_blocks/deprecated_form_inputs.feature` exists) — keep it.

### 3.5 — The Rails 5 asset chain *(added after Phase 2)*

**Neither of these is a backwards-compatible mechanical change, and they are in this phase because nothing else in it can close the phase without them.** Phase 2 handed over five remaining Rails 5 defects; one is an asset failure worth **132 of the 148 cucumber failures**, and a second sits directly behind it, unmeasured until the first clears. Both are argued in the [implementation plan](phase-3-implementation-plan.md) — findings §1.14 and §1.15, decisions D6 and D7, stage D′.

- [ ] **Move `ckeditor_rails` off 4.3.4 on the Rails 5 bundle.** [`browsercms.gemspec:51`](../../browsercms.gemspec#L51) pins `~> 4.3.0`, and 4.3.4 dispatches its own Railtie on `case ::Rails.version.to_s` with branches for `/^4/` and `/^3/` only. Under Rails 5 no branch matches, the gem defines no `Rails::Engine`, its `lib/assets` never joins the asset load path, and `//= require ckeditor-jquery` ([`app/assets/javascripts/bcms/ckeditor.js:5`](../../app/assets/javascripts/bcms/ckeditor.js#L5)) cannot resolve — so every page that renders the CMS layout raises `ActionView::Template::Error`. **No gem-compatibility instrument could have caught this**: the gem declares no Rails constraint, resolves cleanly on both bundles, and boots. It fails only when something renders. ⚠️ The gem's version *is* CKEditor's version, so this is an editor upgrade as well as a dependency bump, and the suite has zero `@javascript` scenarios to detect a regression in it.
- [ ] **Declare the engine's assets to sprockets-rails 3.** `Gemfile.next.lock` resolves sprockets-rails **3.2.2** where `Gemfile.lock` has **2.3.3**, and 3.x raises `Sprockets::Rails::Helper::AssetNotPrecompiled` for anything referenced through `image_tag` / `asset_path` that is not declared. [`lib/cms/engine.rb:122-133`](../../lib/cms/engine.rb#L122) declares eight JS/CSS files and no images, and there is no `app/assets/config/manifest.js` anywhere in the engine. The first failure is `cms/logo.png` from [`app/views/layouts/cms/_main_menu.html.erb:5`](../../app/views/layouts/cms/_main_menu.html.erb#L5), and it will not be the last — this item has no measured upper bound. **The declaration belongs in the engine, not in `test/dummy/`**: consuming applications hit this identically at [Phase 5](phase-5-the-5.0-bump.md), and a dummy-app fix does not travel to them.

---

## Exit criteria

Every criterion is a grep that must return **zero results**, plus the behavioural one at the end.

Three rows have changed since this table was written: **12 and 15 are struck**, and **16 moved to [Phase 4](phase-4-characterization-tests.md)**. Criterion **1 was amended** to the 4.2 bundle for the same reason 16 moved. Marked in place rather than deleted, so the numbering in [`phase-3-report.md`](phase-3-report.md) still lines up and the reasoning stays on the record — each row says where it went.

**That leaves 14 live criteria, and all 14 pass.**

| # | Criterion | How to verify |
|---|---|---|
| 1 | Suite green on the **`Gemfile` (4.2)** bundle, coverage at or above the Phase 2 number | The `test` job passing. ⚠️ **Amended after Phase 3.** This originally read "both Gemfiles"; the 5.0 half moved to [Phase 4](phase-4-characterization-tests.md) with criterion 16, for the same reason — what keeps 5.0 red is not in this phase's scope. Splitting it is what makes the remaining criteria honestly closable |
| 2 | All 29 `belongs_to` declarations have been **audited**, with `optional: true` added where nil is legitimate | Every `belongs_to` in `app/models/` and `lib/cms/behaviors/` either carries `optional:` or is covered by a test asserting it is required (see [Phase 4](phase-4-characterization-tests.md)) |
| 3 | No `*_filter` callbacks remain | `grep -rnE "\b(before\|after\|around\|skip_before\|skip_after)_filter\b" app/ lib/` |
| 4 | No `update_attributes` calls remain | `grep -rn "update_attributes" app/ lib/` — expect only the `guest_user.rb` definition if it was kept deliberately |
| 5 | No `render text:` / `render :text =>` remains | `grep -rnE "render\s+(:text\s*=>\|text:)" app/ lib/` |
| 6 | No `.uniq` on a Relation remains | `grep -rn "\.uniq" app/controllers/ app/models/` reviewed — any remaining receiver is an Array |
| 7 | No `HTML::FullSanitizer` reference anywhere | `grep -rn "HTML::FullSanitizer" app/ lib/ test/ spec/` |
| 8 | No bare `.deliver` / `.deliver!` **call** on a mailer | `grep -rn "\.deliver\b\|\.deliver!" app/ lib/ \| grep -v deliver_now \| grep -v deliver_later \| grep -v "def self\.deliver"` — the `def self.deliver!` definition at `email_message.rb:15` is excluded deliberately; it stays |
| 9 | No `File.exists?` remains | `grep -rn "File.exists?" app/ lib/` |
| 10 | No unqualified `HashWithIndifferentAccess` | `grep -rnE "(^\|[^:A-Za-z])HashWithIndifferentAccess" app/ lib/` |
| 11 | `responders` is declared in the gemspec | `grep -n responders browsercms.gemspec` returns a line |
| 12 | ~~Both legacy migrations are version-qualified~~ | **Struck** — `ActiveRecord::Migration[4.2]` does not exist on 4.2, so this would have taken the production bundle down, and 5.0 does not need it. Moved to [Phase 5](phase-5-the-5.0-bump.md) / the 5.1 hop. See the report's deviation 6 |
| 13 | **The ~13 `find_by_*` call sites are untouched** | `git diff` shows no changes to `find_by_login`, `find_by_path`, `find_by_code`, `find_by_from_path`. These are *still supported*; changing them is pure waste. |
| 14 | **Zero `NextRails.next?` branches were added** | `grep -rn "NextRails" app/ lib/` returns nothing. If any change needed a version branch, it did not belong in this phase. |
| 15 | ~~The changes are deployed to production on Rails 4.2~~ | **Struck — this criterion does not apply to an engine.** It comes from the skill's "deploy small changes before the version bump" methodology, which assumes an *application*. browsercms ships as a gem; there is no production to deploy it to. The real equivalent — release, and upgrade the consuming `cms` app — happens once, after the last hop. See the README's note on engine-vs-application criteria |
| 16 | ~~**The `next-rails` CI job is green**~~ *(added after Phase 2)* | **Moved to [Phase 4](phase-4-characterization-tests.md), work item 4.0.** Phase 2 made the job gating on the note that *"CI is red on every PR until Phase 3 lands"* — but Phase 3 cleared every defect that was in its own scope and the job stayed red. What remains is ten failures needing characterization, which is Phase 4's method, not this phase's. The job **stays gating and red** in the meantime, deliberately. See the report's §6 |
| 17 | **The Rails 5 asset chain is clear, and the fix is in the engine** *(added after Phase 2)* | No `couldn't find file` and no `AssetNotPrecompiled` in the `Gemfile.next` functional and cucumber logs — **and** `git diff` for §3.5 touches `lib/cms/engine.rb`, `app/assets/config/manifest.js` or `browsercms.gemspec` and nothing under `test/dummy/`. The second half is the one that can pass wrongly |

**Done means:** criteria 3–11 are all empty greps, criterion 14 is empty, and the **4.2** suite is green with coverage intact. The bump diff is now small enough to reason about. Rails 5 being green is no longer this phase's bar — that moved to Phase 4 with criterion 16.

**Criteria 16 and 17 were added after Phase 2** measured what was actually still red on Rails 5. Neither is a grep, which is why the original table could not express them. 16 has since moved to Phase 4 — it turned out to state a *goal* the phase could not reach with the tools it had, which is why 17, scoped to the asset chain alone, is the one that closed.

> **Criterion 14 is the phase's definition of correctness.** If a change required a `NextRails.next?` branch, it isn't backwards-compatible and belongs in [Phase 5](phase-5-the-5.0-bump.md) instead.

---

## Explicitly not in this phase

- **No Rails bump.** Still 4.2.11.3. That is the point — these all work on 4.2.
- **No new tests**, except where a Tier C fix has a behavioural choice in it. The `render text:` error branches and `Relation#uniq` in `move_to_position` get tests in [Phase 4](phase-4-characterization-tests.md), not here.
- **No Zeitwerk work.** `require_dependency` at `content_types_controller.rb:1` stays. Zeitwerk lands at **6.0** and is a phase of its own on a later hop.
- **No `ApplicationRecord`.** 28 models inherit `ActiveRecord::Base` directly. The skill classifies this `kind: migration` — fix-when-ready, not fix-before-bump — and for an isolated engine the right target is `Cms::ApplicationRecord`, which interacts with `lib/browsercms.rb:36-67` doing `ActiveRecord::Base.send(:include, ...)` at require time. **Deliberately deferred to the 6.0 autoloading work.** Recorded so it reads as a decision, not an oversight.
- **No Paperclip, Devise, SimpleForm, Compass, or jquery-rails migration.** Later hops.
- **`ckeditor_rails` is the one gem that moves** (§3.5), and it is an exception with its reasoning recorded rather than a precedent. It is not a migration — it is the minimum version change that lets the engine's own layout render under Rails 5 at all, and without it criterion 17 — and any hope of a green 5.0 suite — cannot be met by any amount of code fixing.
- **Not fixing the two new `ActionController::Parameters` sites** (`content_controller.rb:72`, `path_helper.rb:33-36`). They're real, but at 153 and 49 hits they're on lines CI executes — CI is the detector. See [Phase 4](phase-4-characterization-tests.md) for the four sites that *do* need attention.
