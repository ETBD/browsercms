# Phase 3 — Report

**Implements:** [`phase-3-backwards-compatible-fixes.md`](phase-3-backwards-compatible-fixes.md)
**Plan:** [`phase-3-implementation-plan.md`](phase-3-implementation-plan.md)
**Entry state:** `10ac4ace` — 4.2 green at 78.35% / cucumber 154/154; `Gemfile.next` at 756 tests / 2F / 3E, functional suite down with a load error, cucumber 6 of 154 passing.

---

## 1. Headline

`Gemfile` is still Rails 4.2.11.3 and still green — 1007 tests, 0F/0E, cucumber 154/154.

`Gemfile.next` went from **"the functional suite does not load and 148 of 154 cucumber
scenarios fail"** to **85 of 88 functional and 150 of 154 cucumber passing.**

**Criterion 16 is not met, and has moved to [Phase 4](phase-4-characterization-tests.md).**
Ten failures/errors remain on 5.0, so the `next-rails` job is still red — and stays gating,
deliberately. None of them is a work item of this phase, and none is caused by it: seven are one
pre-existing optimistic-locking cluster (ruled out against this phase's only behaviour change
by a control run — §6), and three are singletons. They need characterization before they can
be fixed, which is [Phase 4](phase-4-characterization-tests.md)'s job. **The honest summary is
that Phase 3 removed everything in its own scope that was holding the job red, and what
remains is a different kind of problem than the one this phase was built to solve.**

| | Entry (Phase 2) | Exit (Phase 3) |
|---|---|---|
| 4.2 unit + spec + functional + orphan | 996, 0F / 0E | **1007, 0F / 0E** |
| 4.2 cucumber | 154 / 154 | **154 / 154** |
| 5.0 unit | 756, 2F / 3E | 767, 1F / 2E |
| 5.0 spec | — | 145, 0F / 0E |
| 5.0 functional | **load error — 0 tests ran** | **88 runs, 0F / 3E** |
| 5.0 cucumber | 6 passed / 148 failed | **150 passed / 4 failed** |

---

## 2. Final measurements

### Rails 4.2 (`Gemfile`) — green

| Suite | Result |
|---|---|
| unit | **767** tests, 1766 assertions, **0F / 0E**, 4 skips |
| spec | 145 tests, 260 assertions, 0F / 0E, 7 skips |
| functional | 88 runs, 203 assertions, 0F / 0E, 9 skips |
| orphan | 7 runs, 9 assertions, 0F / 0E |
| **total** | **1007 tests, 0F / 0E** |
| cucumber | **154 scenarios (154 passed)**, 837 steps (837 passed) |
| line coverage | **78.37%** — baseline 78.35%, passes |
| branch coverage | **70.83%** — Phase 2 measured 70.79% on the same instrument |

Both figures are from a full chain on a **cleared** `coverage/.resultset.json`, so they are the
authoritative ones. (The earlier run against a stale resultset also read 78.37% — the
contamination turned out not to have distorted anything, but that is now verified rather than
assumed.)

767 unit tests, up from 756: **+9** from the stage-B oracle, **+2** from the `GuestUser`
characterization pair (one of which is the deliberate skip, taking skips 3 → 4).

### Rails 5.0 (`Gemfile.next`)

| Suite | Entry (Phase 2) | Exit |
|---|---|---|
| unit | 756, 2F / 3E | **767, 1F / 2E**, 4 skips |
| spec | — | **145, 0F / 0E** |
| functional | **load error — 0 tests ran** | **88, 0F / 3E**, 9 skips |
| orphan | 1E | **7, 0F / 0E** |
| cucumber | 154 collected, **6 passed** / 148 failed | **150 passed / 4 failed** |

The cucumber figure is the closing run's 148 plus the two `manage_users` scenarios fixed by
§4's `users_controller` change, verified by re-running that feature. The remaining four are
characterised in §6 and are **not** caused by anything in this phase — see the control run
there.

**Cucumber went from 6 passing to 150 passing, and the functional suite from "does not load"
to 85 of 88 green.**

---

## 3. What the plan got right, and where measurement moved it

Three findings changed the shape of the work. All three were caught by reading the vendored
gems or the shipped code rather than by a test, which is the same lesson Phase 1 recorded
about `panoramic` and Phase 2 recorded about `ckeditor_rails`.

### 3.1 `optional: true` is not backwards-compatible — the audit uses `required: false`

**This is the largest correction in the phase.** The phase document and the implementation
plan both specify `optional: true` for the `belongs_to` audit. That declaration **breaks the
4.2 bundle at class-definition time**:

```
ArgumentError: Unknown key: :optional. Valid keys are: :class_name, :anonymous_class,
:foreign_key, :validate, :autosave, :dependent, :primary_key, :inverse_of, :required,
:foreign_type, :polymorphic, :touch, :counter_cache
```

`:optional` enters `valid_options` only at Rails 5.0
([`builder/belongs_to.rb:8`](../../vendor/bundle/gems/activerecord-5.0.7.2/lib/active_record/associations/builder/belongs_to.rb#L8)).
4.2's list comes from `Association.valid_options` +
[`singular_association.rb:6`](../../vendor/bundle/gems/activerecord-4.2.11.3/lib/active_record/associations/builder/singular_association.rb#L6),
and `validate_options` runs `assert_valid_keys` against it. Applying the phase document
literally would have taken the production bundle down with a load error on 29 models — the
same category of mistake finding 1.2 already caught and struck for the migration item.

**`required: false` is the spelling that works on both.** `:required` is in `valid_options`
on 4.2 *and* 5.0, and 5.0 normalises it in `define_validations`:
`options[:optional] = !options.delete(:required)`. Measured directly on both bundles:

| | `belongs_to :x, optional: true` | `belongs_to :x, required: false` |
|---|---|---|
| 4.2.11.3 | `ArgumentError: Unknown key: :optional` | accepted — `options={:required=>false}`, **no validator added** |
| 5.0.7.2 | accepted — `options={:optional=>true}` | accepted — `options={:optional=>true}`, no validator added |

On 4.2 the option is consumed at
[`singular_association.rb:31-36`](../../vendor/bundle/gems/activerecord-4.2.11.3/lib/active_record/associations/builder/singular_association.rb#L31)
— `if reflection.options[:required]` — so `false` is a provable no-op. On 5.0 it means
exactly what `optional: true` means. **Criterion 2's verification grep is amended accordingly**
(see §8).

### 3.2 Stage B's mechanism could not have worked as scoped

The plan describes stage B as a `setup` block that "flips
`ActiveRecord::Base.belongs_to_required_by_default = true` around a model-instantiation
sweep." Two independent reasons that cannot work:

1. **The flag does not exist on 4.2.** It is introduced at
   [`activerecord-5.0.7.2 core.rb:117`](../../vendor/bundle/gems/activerecord-5.0.7.2/lib/active_record/core.rb#L117);
   `grep -rn belongs_to_required_by_default` over the 4.2 gem returns nothing. Touching it
   raises `NoMethodError` on the bundle in production — and the plan requires the test to pass
   on both.
2. **The flag is read at class-definition time, not validation time.** It is consumed inside
   `Builder::BelongsTo.define_validations`, which runs when `belongs_to` is *called*. Flipping
   it in `setup`, after the models are loaded, cannot retroactively add validations to
   associations that already exist. It would be a no-op even on 5.0.

**What was built instead** ([`test/unit/belongs_to_optionality_test.rb`](../../test/unit/belongs_to_optionality_test.rb)):
the flag's entire effect is one line — `model.validates_presence_of reflection.name` — so the
audit's claim is checkable directly without ever setting it.

- `:required` ⇒ the model already rejects nil through its own presence validation, so
  required-by-default adds nothing and the declaration is left bare.
- `:optional` ⇒ nothing rejects nil today, on either bundle, so `required: false` pins that.

Both halves are assertions about the loaded class, so both run on both bundles. The test also
carries a probe asserting that `required: false` adds no presence validation — if that ever
stops holding, all 22 verdicts are wrong at once.

### 3.3 The one "genuinely dead" file is not dead — `bin/` was not searched

The plan's finding 1.7 clears `lib/cms/commands/to_version400.rb` for deletion on the strength
of "zero references across `app lib test spec features config`". That search omits `bin/`:

- [`bin/bcms:11`](../../bin/bcms#L11) — `require 'cms/commands/to_version400'`
- [`bin/bcms:28`](../../bin/bcms#L28) — `include Cms::Commands::ToVersion400`

`bcms` is a shipped executable ([`browsercms.gemspec:43`](../../browsercms.gemspec#L43)), and
`generate_devise_configuration` — the module's only method — is called by `bcms new`, `demo`,
`module`, `install` and `upgrade`. Deleting the file breaks the command at require time for
every downstream user.

**Stage F therefore deletes nothing.** All three of its candidates are load-bearing, for three
different reasons, and each now carries a comment saying which.

---

## 4. Stage-by-stage

### A — The orphan skips ✅

Two lines deleted, comments left in their place:
[`content_controller.rb:11`](../../app/controllers/cms/content_controller.rb#L11) and
[`portlet_controller.rb:4`](../../app/controllers/cms/portlet_controller.rb#L4).

Provably a no-op on 4.2 (`skip_callback` finds nil, `chain.delete(nil)` does nothing);
`ArgumentError` at class-definition time on 5.0.

### A′ — Re-measure ✅

Stage A did exactly what was predicted, and nothing more:

| | Before A | After A |
|---|---|---|
| 4.2, everything | 996, 0F/0E, cucumber 154/154, 78.36% | unchanged |
| 5.0 unit | 756, 2F / 3E | 756, 2F / **2E** |
| 5.0 functional | **did not load** | **88 runs, 0F / 30E** |
| 5.0 cucumber | 6 passed | **23 passed / 131 failed** |

**Every one of the 131 cucumber failures, and 28 of the 30 functional errors, was
`couldn't find file 'ckeditor-jquery'`** — a single signature. Per the plan's own contingency,
that pulled stage D′ ahead of B and C.

The four Phase 2 §5 defects that survived stage A: `StaleObjectError` ×2,
`PortletTest#test_.blacklist`, `PublishableTestCase#test_publish_on_save`. §6 covers where
they stand.

### D′ — The Rails 5 asset chain ✅

**D′.1 — `ckeditor_rails`.** [D6](phase-3-implementation-plan.md#d6--how-far-to-move-ckeditor_rails)(c),
as recommended: `NEXT_BOOT ? "~> 4.5.10" : "~> 4.3.0"`.

4.5.10 was verified as the first release whose dispatch reads `/^[45]/` — 4.4.8, 4.5.1, 4.5.2
and 4.5.3 were each unpacked and all still read `/^4/`. The lock resolves **4.5.11**, which
was checked to have the same branch, to ship `lib/assets/javascripts/ckeditor-jquery.js`, and
to still default to the `moono` skin (4.16 is where `moono-lisa` arrives). `Gemfile.lock`'s
`ckeditor_rails` line is untouched.

Result: `couldn't find file 'ckeditor-jquery'` went to **zero** in both the functional and
cucumber logs — and `cms/logo.png` surfaced immediately behind it, exactly as finding 1.15
predicted.

**D′.2 — the sprockets-rails 3 declaration.** [D7](phase-3-implementation-plan.md#d7--how-to-satisfy-sprockets-rails-3)(a)
was recommended and **does not work on this bundle.** sprockets-rails only honours
`app/assets/config/manifest.js` when sprockets **4** is loaded
([`railtie.rb:104-110`](../../vendor/bundle/gems/sprockets-rails-3.2.2/lib/sprockets/railtie.rb#L104),
`if using_sprockets4?`), and both locks resolve sprockets 3.7.x. The file would have been inert.

What was done instead is D7(a)'s *intent* by the mechanism that works here, in
[`lib/cms/engine.rb`](../../lib/cms/engine.rb). sprockets-rails' own default already covers
loose assets — but only the host application's:

```ruby
LOOSE_APP_ASSETS = lambda do |logical_path, filename|
  filename.start_with?(::Rails.root.join("app/assets").to_s) && ...
```

An engine's `app/assets` is never under `Rails.root`, which is why every image and font this
engine ships is undeclared. The fix applies the same rule rooted at the engine instead, so it
**declares the class rather than the instances** — which is what bounded the one item in the
phase with no measured upper bound. Enumerating filenames was never viable anyway: the icon
helpers build their paths at runtime
([`application_helper.rb:66`](../../app/helpers/cms/application_helper.rb#L66), `:70`;
[`file_blocks/render.html.erb:2`](../../app/views/cms/file_blocks/render.html.erb#L2)), so the
set is not readable from the views.

**The sprockets tail the plan budgeted for did not materialise: one iteration closed it.**
Rails 5 functional errors went **30 → 3**, with no `AssetNotPrecompiled` and no
`couldn't find file` anywhere in the logs. The change is in the engine; `git diff` for this
stage touches nothing under `test/dummy/` (criterion 17, second half).

### B — The oracle ✅

[`test/unit/belongs_to_optionality_test.rb`](../../test/unit/belongs_to_optionality_test.rb),
9 tests. Redesigned per §3.2; passes on both bundles.

### C — The `belongs_to` audit ✅

29 sites. **7 left bare, 22 given `required: false`.**

Left bare, each backed by an existing presence validation on the foreign key — so
required-by-default in a host app would agree with the model's stated intent:

| Site | Evidence |
|---|---|
| `Cms::Category#category_type` | [`category.rb:12`](../../app/models/cms/category.rb#L12) |
| `Cms::Connector#page`, `#connectable` | [`connector.rb:44`](../../app/models/cms/connector.rb#L44) |
| `Cms::PageRoute#page` | [`page_route.rb:26`](../../app/models/cms/page_route.rb#L26) |
| `Cms::Task#assigned_by`, `#assigned_to`, `#page` | [`task.rb:27-29`](../../app/models/cms/task.rb#L27) |

That confirms all four of the plan's finding 1.10 contradictions of the phase document: the
doc named `Connector#connectable`, `Task#assigned_by` and `Task#assigned_to` as "near-certain"
`optional:` candidates, and all three are validated as required today.

The remaining 17 model sites and 5 behavior sites carry `required: false`, on the rule that
**nothing rejects nil there today on either bundle, so pinning it is exactly
behaviour-preserving.** That is a stronger justification than "we judged nil to be legitimate",
and it is what makes the whole audit a no-op change rather than 22 judgement calls. Where the
plan's R2 said "where B cannot decide, prefer optional", this rule reaches the same answer for
a reason that is checkable.

**Two of the five behavior sites are dynamic declarations that grep will not find** —
[`versioning.rb:115`](../../lib/cms/behaviors/versioning.rb#L115) passes the option into
`version_class.belongs_to(...)`'s options hash, and
[`dynamic_attributes.rb:168`](../../lib/cms/behaviors/dynamic_attributes.rb#L168) does the same.
Both are commented as such at the site, and stage B asserts the versioning one through the
reflection (`Cms::HtmlBlock::Version`), which is the only place it is visible.

**The 30th site is flagged, not fixed.**
[`lib/templates/active_record/model/model.rb`](../../lib/templates/active_record/model/model.rb)
emits a bare `belongs_to` into every model scaffolded downstream. It now carries an ERB comment
explaining why it cannot simply gain `required: false` and that Phase 5 owns the decision —
including the note that `optional: true` would be *wrong* for a 4.2 target, per §3.1.

### D — The rest of the 5.0-breaking set ✅

- **`deliver` → `deliver_now`, one site**: [`email_message.rb:58`](../../app/models/cms/email_message.rb#L58).
  `:15` (`def self.deliver!`) and `:18` (`m.deliver!`) left alone — `m` is a `Cms::EmailMessage`
  and `deliver!` is the model's own instance method, so renaming it would have broken the model.
  Criterion 8 expects exactly these two survivors.
- **`responders` in the gemspec, unconstrained.** Both locks re-resolved; neither moved
  `responders` (2.4.1 on 4.2, 3.0.1 on 5.0). Re-resolving did pull incidental drift on
  `net-protocol`, `websocket-driver` and `websocket-extensions`; per R7 that was reverted, so
  each lock's diff is now exactly the intended lines and nothing else.
- **The `save!` override forwards** ([D8](phase-3-implementation-plan.md#d8--the-save-override-forwards-and-that-changes-behaviour),
  decided: fix now). [`versioning.rb:271`](../../lib/cms/behaviors/versioning.rb#L271) now takes
  `(*args, &block)`. **This is the only behaviour change in the phase**: autosaved children of a
  versioned record were being validated in a path where Rails asked for `validate: false`, and
  will no longer be. See §5.

### E — The renames ✅

| Change | Sites |
|---|---|
| `*_filter` → `*_action` | **34** across 16 files, plus the comment at [`content_page.rb:73`](../../lib/cms/acts/content_page.rb#L73) |
| `update_attributes` → `update` | **14** call sites |
| `render text:` → `plain:` / `html:` | **2 + 2** |
| `.uniq` → `.distinct` | **1** |
| `HashWithIndifferentAccess` → qualified | **2** |

The two `pretend_controller` sites took `render html:` with `.html_safe`, not `plain:` — both
are cucumber-covered ([`acts_as_content_page.feature:25`](../../features/acts_as_content_page.feature#L25)
and `:49`) and emit markup, so `plain:` would have changed a passing feature's Content-Type.

The `.distinct` site carries a `TODO(Phase 4)` recording that the dedupe is on the wrong side
of the parenthesis: it binds to the second relation only and does nothing about duplicates
*between* the two halves, which is the only kind the method can produce. Fixing that is a
behaviour change and belongs with the `move_to_position` characterization test.

**`GuestUser` was left alone** ([D3](phase-3-implementation-plan.md#d3--guestuserupdate_attributes-becomes-an-alias),
decided: leave the hole, record it). The file now documents that `update_attributes` is an
alias and `guest.update(...)` walks past the guard, and
[`test/unit/models/user_test.rb`](../../test/unit/models/user_test.rb) gains two tests: a
**skipped** one asserting the behaviour the fix should produce, and a passing one that pins the
defect as it actually stands and fails the moment someone defines `update` on `GuestUser` — so
the skip cannot be silently orphaned.

### Added — an empty `WHERE` clause (not in any work item)

Found by cucumber once D′ cleared the asset errors: 2 scenarios in
[`manage_users.feature`](../../features/authentication/manage_users.feature) died with

```
PG::SyntaxError: ERROR:  syntax error at or near "ORDER"
... WHERE  ORDER BY first_name, last_name, email LIMIT $1 OFFSET $2
```

[`users_controller.rb:10-35`](../../app/controllers/cms/users_controller.rb#L10) builds its
filter list from three optional clauses, so `query` is empty whenever `show_expired` is set
with no keyword and no group — making `conditions` equal `[""]`. **4.2 dropped an empty
condition string and emitted no `WHERE` at all; 5.0 emits a literal empty one.** Skipping the
`where` call when `query` is empty reproduces 4.2's SQL exactly on both versions, so it is
backwards-compatible by construction — the same standard as the rest of the phase.

Verified both ways: the two scenarios pass on 5.0 after the change, and
`manage_users.feature` is still 14/14 on 4.2.

### G.2 — The branch-coverage floor ✅

Phase 2 measured branch coverage and reported it without gating, on the explicit grounds that
"inventing a floor in the same commit that first measures the number would be gating on
something nobody has looked at." Phase 3 sets it, which is what both
[`.simplecov`](../../.simplecov) and [`core_tasks.rake`](../../lib/tasks/core_tasks.rake) said
this phase would do.

`COVERAGE_MINIMUM_BRANCH` did not exist — the task *printed* the branch figure and compared
nothing — so this is a new gate, not a changed number. It defaults to **70.83**, the measured
value on a cleared resultset after the Phase 3 diff landed, set with no slack for the same
reason `COVERAGE_MINIMUM` was: a floor with headroom silently absorbs the first regression.

The task now prints both figures *before* aborting and collects both failures, so a run that
trips one gate still reports where the other stands. Verified in three directions:

```
$ rake coverage:check                            → Coverage 78.37% (baseline 78.35%)
                                                   Branch coverage 70.83% (baseline 70.83%)   exit 0
$ COVERAGE_MINIMUM_BRANCH=70.9 rake coverage:check → Branch coverage 70.83% is below 70.90%   exit 1
$ COVERAGE_MINIMUM=99 COVERAGE_MINIMUM_BRANCH=99   → both reported                            exit 1
```

### F — Dead code ✅ (nothing deleted)

Per §3.3, zero deletions. All three candidates commented in place:
`to_version400.rb` (required by `bin/bcms`), `deprecated_placeholder.rb` (STI target of a
shipped migration), `namespacing.rb` (satisfies `behaviors.rb:30`'s glob and carries the public
`Cms.table_prefix=` deprecation).

---

## 5. The one behaviour change

[`versioning.rb`](../../lib/cms/behaviors/versioning.rb)'s `save!` override. Before:

```ruby
def save!(perform_validations=true)
  save(:validate => perform_validations) || raise(...)
end
```

Rails never calls `save!` with a positional boolean. 4.2 calls it as `save!(:validate => x)`
([`has_many_association.rb:39`](../../vendor/bundle/gems/activerecord-4.2.11.3/lib/active_record/associations/has_many_association.rb#L39))
and 5.0 as `save!(validate: x, &block)`
([`collection_association.rb:510`](../../vendor/bundle/gems/activerecord-5.0.7.2/lib/active_record/associations/collection_association.rb#L510)).
So `perform_validations` was bound to a Hash — truthy — and the override called
`save(validate: true)` in precisely the path where the framework had asked for validations to
be skipped. **That is wrong on 4.2 today, silently, on the bundle in production.** On 5.0 it
additionally dropped the block that `create_or_update` yields after insert — the same defect
Phase 2 fixed one method below, which is what made this one reachable.

A bare `record.save!` is unchanged (`save` with no arguments validates by default). The path
that changes is autosave.

---

## 6. Rails 5 residue

Ten failures/errors across three suites, and they are **essentially one cluster plus three
singletons** — seven plus three.

They reconcile against §2 per-suite: unit `1F/2E` = 2 `StaleObjectError` + `test_publish_on_save`;
functional `0F/3E` = 2 missing-partial + `test_complete_no_tasks`; cucumber 4 failed = 2
`manage_images` + 1 `sitemap/pages` + 1 `portlets_with_params`.

### The cluster: content updates do not persist on 5.0

Seven of the ten are one problem wearing four different masks:

| Where | Symptom |
|---|---|
| unit ×2 | `ActiveRecord::StaleObjectError: Attempted to touch a stale object: Cms::Page` |
| functional ×2 | `Missing partial cms/shared/_version_conflict_error` |
| cucumber ×2 | `manage_images.feature` — the image's section and path are unchanged after save |
| cucumber ×1 | `sitemap/pages.feature:19` — "I change the page name" |

**The missing partial is a symptom of a symptom.**
`Cms::PagesControllerTest#test_unhide` does `put :update` and expects a redirect; on 5.0 the
update fails, so the controller falls through to re-render the form, and
[`_main_form.html.erb:2`](../../app/views/cms/pages/_main_form.html.erb#L2) renders
`cms/shared/version_conflict_error` — which does not exist. The real file is
`app/views/cms/application/_version_conflict_error.html.erb`. **That partial reference is
broken on 4.2 too**; 4.2 simply never takes the branch. So there is a latent view bug sitting
behind an optimistic-locking difference, and the locking difference is what to diagnose first.

The two `manage_images` failures read backwards because the step definitions have expected and
actual reversed ([`image_steps.rb:1-9`](../../features/step_definitions/image_steps.rb#L1) —
`expect(section_name).to eq(image.parent.name)`). Decoded: `image.parent.name` is still
`"My Site"` and `image.path` is still the old path. Same shape as `test_unhide` — the update
did not take.

**This is not caused by anything in this phase.** The `save!` change (§5) is the only
behaviour change here and it lands in exactly this area, so it was ruled out directly: with
`save!` reverted to its old signature and everything else in place, the same four cucumber
scenarios fail in the same way (`12 scenarios (4 failed, 8 passed)` vs the identical four with
the fix in). The cluster is pre-existing Rails 5 behaviour.

Not a rename and not backwards-compatible — **Phase 4**, characterization first.

### Singletons

- **`PublishableTestCase#test_publish_on_save`** (unit failure) — `Expected false to be truthy`.
  Survives from Phase 2's §5. Worth re-reading now that `save!` forwards.
- **`Cms::TasksControllerTest#test_complete_no_tasks`** (functional) —
  `PG::InvalidTextRepresentation: invalid input syntax for type integer: ""`. Rails 5 stopped
  coercing `""` to nil on integer casts. Application behaviour; scope in Phase 4.
- **`features/portlets/portlets_with_params.feature`** (cucumber) — the portlet renders the
  page layout instead of its own `"I worked"` content. Unrelated to this phase's work.

### Resolved since Phase 2's §5 list

- **`ckeditor-jquery`** — gone (stage D′.1).
- **`PortletTest#test_.blacklist`** — passed in the closing run. It compares a class list whose
  order depends on load order, so treat it as flaky rather than fixed.
- **The orphan-suite error** — gone; that suite is 7/7.
- **`use_route`** ([`test/support/engine_controller_hacks.rb`](../../test/support/engine_controller_hacks.rb))
  was expected to surface at A′ and never became a blocker. Still not this phase's.

**`use_route`** ([`test/support/engine_controller_hacks.rb`](../../test/support/engine_controller_hacks.rb))
was expected to surface at A′ and did not become a blocker. Still not this phase's.

---

## 7. Deviations from the plan

| # | Deviation | Why |
|---|---|---|
| 1 | Audit uses `required: false`, not `optional: true` | §3.1 — `optional:` raises `ArgumentError` on 4.2 and would take the production bundle down |
| 2 | Stage B is a reflection-and-validation invariant, not a forced flag | §3.2 — the flag does not exist on 4.2 and is read at class-definition time on 5.0 |
| 3 | Stage F deletes nothing | §3.3 — `bin/bcms` requires `to_version400.rb` |
| 4 | D′.2 uses an engine-rooted precompile lambda, not `manifest.js` | §4, D′ — sprockets-rails ignores `manifest.js` unless sprockets 4 is loaded |
| 5 | Stages run in order A, A′, D′, C+B, D, E, F | The plan's own contingency: A′'s cucumber number was 131/131 one signature |
| 6 | Migration item deferred ([D1](phase-3-implementation-plan.md#d1--the-migration-item-leaves-the-phase)) | `ActiveRecord::Migration[4.2]` does not exist on 4.2 and 5.0 does not need it. Criterion 12 struck |
| 7 | `GuestUser` left alone, documented + skipped test ([D3](phase-3-implementation-plan.md#d3--guestuserupdate_attributes-becomes-an-alias)) | Human decision: preserve the phase's no-behaviour-change contract; record the hole rather than close it |
| 8 | `test/`'s four `_filter` sites were renamed after all | See below — [D5](phase-3-implementation-plan.md#d5--scope-of-the-_filter-rename) miscounted what they are |

**On D5.** The plan scoped `test/`'s four `_filter` sites out, on the reading that they "break
at 5.1 exactly like the production ones". They are not independent declarations. All four are
in [`test/unit/lib/acts_as_content_page_test.rb`](../../test/unit/lib/acts_as_content_page_test.rb),
and all four are mocha expectations *on the production call*:

```ruby
NewController.expects(:before_filter).with(:check_access_to_section, {})
```

`before_action` and `before_filter` are aliases into one chain, but they are distinct methods
as far as mocha is concerned — so renaming `lib/cms/acts/content_page.rb` made all three tests
fail on 4.2 with "expected exactly once, invoked never". They are mirrors of the renamed call
and had to move with it. **This is what caught the rename**, and it is the reason the plan's
instruction to re-run the 4.2 suite after every stage is worth following: a white-box test
asserting a method name is exactly the thing a "pure rename" does not stay pure through.

After the update there are **zero** `*_filter` references anywhere in `app/`, `lib/`, `test/`,
`spec/` or `features/`.

---

## 8. Exit criteria

Every grep was run and its output pasted, including the ones that already passed — so the
record shows they were checked rather than assumed.

| # | Criterion | Verification | Result |
|---|---|---|---|
| 1 | Suite green on the `Gemfile` (4.2) bundle | `test` job | ✅ **green** — 1007 tests, 0F/0E, cucumber 154/154, line 78.37% / branch 70.83%. ⚠️ Criterion **amended**: it originally read "both Gemfiles", and the 5.0 half moved to [Phase 4](phase-4-characterization-tests.md) alongside criterion 16 (5.0 is at **10** remaining, §6) |
| 2 | All 29 `belongs_to` audited | `grep -rnE "belongs_to.*required(:\| =>) *false" app/ lib/` | ✅ **22** declarations + **7** left bare = 29. Two of the 22 are dynamic (§4, C) and are asserted through the reflection in stage B instead |
| 3 | No `*_filter` callbacks | `grep -rnE "\b(before\|after\|around\|skip_before\|skip_after)_filter\b" app/ lib/` | ✅ **0** (also 0 across `test/ spec/ features/`) |
| 4 | No `update_attributes` calls | `grep -rn "update_attributes" app/ lib/` | ✅ **0 calls.** Survivors: the definition at [`guest_user.rb:66`](../../app/models/cms/guest_user.rb#L66) (kept by [D3](phase-3-implementation-plan.md#d3--guestuserupdate_attributes-becomes-an-alias)), plus 3 comment lines that name the Rails API. The criterion anticipates 1–2 |
| 5 | No `render text:` | `grep -rnE "render\s+(:text\s*=>\|text:)" app/ lib/` | ✅ **0** |
| 6 | No `.uniq` on a Relation | `grep -rn "\.uniq" app/controllers/ app/models/` | ✅ **3 hits, all Arrays** — `portlet.rb:86` (`.flatten.compact.uniq`), `content_type.rb:52` (`subclasses.uniq!`), `page_template.rb:29` (`.map{}.sort.uniq`). The one Relation is now `.distinct` |
| 7 | No `HTML::FullSanitizer` | `grep -rn "HTML::FullSanitizer" app/ lib/ test/ spec/` | ✅ **1 hit, a comment** at [`content_filter.rb:12`](../../lib/cms/content_filter.rb#L12) that names the constant to say it is *not* used. Passed on entry (Phase 2) |
| 8 | No bare mailer `.deliver` | amended grep | ✅ **2 survivors, both correct**: `email_message.rb:15` (`def self.deliver!`) and `:18` (`m.deliver!`, the model's own instance method). The one real site is now `deliver_now` |
| 9 | No `File.exists?` | `grep -rn "File.exists?" app/ lib/` | ✅ **0**. Passed on entry (Phase 0, `6da1d60d`) |
| 10 | No unqualified `HashWithIndifferentAccess` | `grep -rnE "(^\|[^:A-Za-z])HashWithIndifferentAccess" app/ lib/` | ✅ **0** |
| 11 | `responders` in the gemspec | `grep -n responders browsercms.gemspec` | ✅ [`:83`](../../browsercms.gemspec#L83), unconstrained |
| 12 | ~~Migrations version-qualified~~ | — | **Struck** ([D1](phase-3-implementation-plan.md#d1--the-migration-item-leaves-the-phase)). Moved to Phase 5 / the 5.1 hop |
| 13 | `find_by_*` untouched | `git diff` for `find_by_login\|path\|code\|from_path` | ✅ **0 changed lines** |
| 14 | Zero `NextRails` branches | `grep -rn "NextRails" app/ lib/` | ✅ **0**. The one conditional the phase needed (`NEXT_BOOT`, D′.1) is in the gemspec, which is outside this criterion's scope |
| 15 | ~~Deployed to production on 4.2~~ | — | **Struck — does not apply to an engine.** browsercms ships as a gem; there is no production to deploy it to. The equivalent (release, then upgrade the consuming `cms` app) happens once, after the last hop. See the README's note on engine-vs-application criteria |
| 16 | ~~The `next-rails` CI job is green~~ | both jobs | **Moved to [Phase 4](phase-4-characterization-tests.md), work item 4.0.** ❌ **not met** — **10** failures/errors remain across the 5.0 suites, down from "the functional suite does not load and 148 of 154 cucumber scenarios fail". §6 shows they are one pre-existing cluster plus three singletons, none of them a Phase 3 work item and none caused by this phase. The job **stays gating and red** in the meantime — see [`ci.yml`](../../.github/workflows/ci.yml) |
| 17 | Rails 5 asset chain clear, fix in the engine | logs + `git diff` | ✅ **both halves.** No `couldn't find file` and no `AssetNotPrecompiled` anywhere in the 5.0 logs; `git diff --name-only -- test/dummy/` is **empty**, so the fix is in [`lib/cms/engine.rb`](../../lib/cms/engine.rb) and [`browsercms.gemspec`](../../browsercms.gemspec) where a consuming application will inherit it |

---

## 9. Open items

- ~~**Commits.**~~ ✅ Resolved, with a caveat. The work is committed as `70b22bdf`
  ("[CMS-420] phase 3 mostly done", 61 files) and pushed to
  `origin/feature/cms-420-migrate-tests`. What did *not* happen is the per-stage split the plan
  calls for in §4 — `git commit` was refused by the environment's permission layer during
  execution, so it landed as one tree. **Decision: leave it.** The branch is already pushed, and
  re-splitting means rewriting shared history for bisect value that the stage-by-stage record in
  §4 already provides in prose.
- ~~**Coverage.**~~ ✅ Resolved. Measured on a cleared resultset: line **78.37%**, branch
  **70.83%**, and `COVERAGE_MINIMUM_BRANCH` is now set and gating (§4, G.2).
- **The by-hand CKEditor check (D′.1) has not been done.** The gem moved 4.3.4 → 4.5.11, which
  is two minor versions of CKEditor itself, and there are zero `@javascript` scenarios — a green
  cucumber run proves the asset *resolves*, not that the editor *works*. This is the only oracle
  that exists and it is a human's to run.
  **It requires the next bundle.** The bump is gated behind `NEXT_BOOT` at
  [`browsercms.gemspec:64`](../../browsercms.gemspec#L64), which is true only when
  `BUNDLE_GEMFILE` ends with `Gemfile.next`; `Gemfile.lock` still resolves **4.3.4** and
  `Gemfile.next.lock` resolves **4.5.11**. So pointing a downstream `cms` app at this branch
  exercises the *old* editor — that app sets its own `BUNDLE_GEMFILE`, so `NEXT_BOOT` is false.
  Check it via the dummy app under `BUNDLE_GEMFILE=Gemfile.next`, or with `ckeditor_rails
  4.5.11` forced in the consuming app's own Gemfile. Also still open: the default-skin decision
  at [the plan's D′.1 recommendation](phase-3-implementation-plan.md#L551).
- ~~**Criterion 15 (deployed to production on 4.2)**~~ — **struck.** It assumes an
  application; browsercms is an engine. See §8 and the README's note on engine-vs-application
  criteria. The same objection applies to Phase 5's criterion 12 and Phase 6's criteria 10 and
  B, which are recorded but not yet amended.
- **Watch `test/dummy/db/schema.rb`.** Running the suite regenerates it from the live database:
  `app:test:prepare` rewrote it during this phase, dropping ~500 lines of dynamically-created
  test tables and reformatting it in 5.0's style. It was reverted, and criterion 17's
  "nothing under `test/dummy/`" check is clean — but it will come back on the next run, and
  committing it would be a silent, large, and entirely accidental change. Check
  `git status` for it before every commit.
- **Criterion 16 is not met, and has moved to [Phase 4](phase-4-characterization-tests.md) as
  work item 4.0.** §6 is the argument for why this is the right place to stop rather than a
  reason to keep going: what remains needs characterization, which is Phase 4's method, and the
  gating decision made in Phase 2 assumed Phase 3 would clear items that were in Phase 3's
  scope. All of those are cleared. **The job stays gating and red** — a decision re-made
  deliberately after this phase closed, so the red stays in the merge path. Two consequences to
  carry: every PR is red until Phase 4 lands, and Phase 0's criteria 1–2 (a green run on the
  default branch) cannot close until then either.
