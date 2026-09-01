# Phase 3 — Implementation Plan

**Implements:** [`phase-3-backwards-compatible-fixes.md`](phase-3-backwards-compatible-fixes.md)
**Entry condition:** Phase 2 complete at 11 of 12 criteria — the 4.2 suite is green at **78.35%** with cucumber 154/154, and on `Gemfile.next` the unit suite runs at 756 tests / 2F / 3E while cucumber collects 154 scenarios and passes 6 ([`phase-2-harness-report.md`](phase-2-harness-report.md)).
**Rails at the end of this phase:** `Gemfile` still 4.2.11.3, green, deployed. `Gemfile.next` green too — this is the phase where the `next-rails` job stops being red.

Same shape as the [Phase 0](phase-0-implementation-plan.md), [Phase 1](phase-1-implementation-plan.md) and [Phase 2](phase-2-implementation-plan.md) plans: findings first, then an ordered work stream, then the decisions that need a human.

> ### Read this first
> The phase document was written before Phases 0 and 2 ran, and **three of its work
> items have already been done** by those phases. Of the ones that remain, measurement
> moved four of them and removed one from the phase entirely. The single largest item —
> the load error that is currently taking down the whole Rails 5 functional suite — is
> **not in the phase document's work items at all**; it arrived in Phase 2's handoff.
>
> Net: the doc's "~96 mechanical changes" is **~89 edits**, they are not all mechanical,
> and the ordering matters more than the doc implies.

---

## 1. Pre-flight findings

Measured against the working tree at `10ac4ace`. Every count below is a grep or a read of the vendored gem, not a restatement of the phase document.

### 1.1 Three work items are already done

| Item | Doc says | Measured now | Landed in |
|---|---|---|---|
| `create_or_update` arity | 320 of 323 Rails 5 errors | done — `versioning.rb` takes `(*args, &block)` | Phase 2, stage A ([D1](phase-2-implementation-plan.md#d1--borrowing-two-fixes-from-phase-3)) |
| `HTML::FullSanitizer` | 1 site + 1 test | **0** — `grep -rn "HTML::FullSanitizer" app/ lib/ test/ spec/` returns nothing. The three surviving `FullSanitizer` hits are `Rails::Html::FullSanitizer` at [`content_filter.rb:18`](../../lib/cms/content_filter.rb#L18) and [`inline_controller_test.rb:7`](../../test/functional/cms/inline_controller_test.rb#L7), plus a comment | Phase 2, stage A |
| `File.exists?` → `File.exist?` | **5 sites** | **0.** All five named sites already read `exist?`. `git log -S "File.exists?" -- app lib` puts the removal in `6da1d60d` — *"[CMS-420] phase 0 implemented"* | Phase 0 |

Exit criteria 7 and 9 pass today. Do not open them as work.

### 1.2 The migration item cannot land in this phase — and does not break at 5.0

The doc files "unversioned `ActiveRecord::Migration` → `ActiveRecord::Migration[4.2]`" under **3.1, breaks at 5.0**. Both halves of that are wrong, and both are readable in the vendored gems.

**It is not backwards-compatible.** `self.[]` is defined at [`activerecord-5.0.7.2/lib/active_record/migration.rb:527`](../../vendor/bundle/gems/activerecord-5.0.7.2/lib/active_record/migration.rb#L527). The 4.2 gem has no `self.[]` anywhere in `migration.rb`, and no `active_record/migration/compatibility.rb` at all — the 4.2 directory holds only `command_recorder.rb` and `join_table.rb`. So `class Browsercms300 < ActiveRecord::Migration[4.2]` raises `NoMethodError` on the default bundle. Every other change in this phase runs on both; this one runs on neither-then-both.

**And it does not break at 5.0.** 5.0's guard is not a raise — [`migration.rb:520-525`](../../vendor/bundle/gems/activerecord-5.0.7.2/lib/active_record/migration.rb#L520):

```ruby
def self.inherited(subclass) # :nodoc:
  super
  if subclass.superclass == Migration
    subclass.include Compatibility::Legacy
  end
end
```

A direct subclass is silently given `Compatibility::Legacy`, which is 4.2 behaviour. The `StandardError: Directly inheriting from ActiveRecord::Migration is not supported` message arrives at **5.1**.

**Resolution: this item leaves Phase 3.** It belongs in [Phase 5](phase-5-the-5.0-bump.md) (where the 4.2 bundle no longer has to run it) or in the 5.1 hop of [Phase 6](phase-6-subsequent-hops.md) (where it becomes forced). Exit criterion 12 is struck — see [§7](#7-exit-criteria-traceability). Only two files are affected, so the deferral costs nothing.

### 1.3 The Rails 5 load error is a deletion, and it is the highest-leverage change in the phase

Phase 2's report names `skip_callback :redirect_to_cms_site` as the worst of five remaining defects — a *load* error that takes the entire functional suite down and causes most of the 148 cucumber failures. It is not in the phase document's work items. Here is the full trace, because the fix is not the obvious one.

**The callback is never registered in that class's chain.** `redirect_to_cms_site` is *defined* as a method in [`lib/cms/controllers/admin_controller.rb:42`](../../lib/cms/controllers/admin_controller.rb#L42), which is included into `Cms::ApplicationController`. But it is *registered as a callback* in exactly one place — [`base_controller.rb:3`](../../app/controllers/cms/base_controller.rb#L3). And `Cms::ContentController` inherits from `Cms::ApplicationController`, not `Cms::BaseController`. They are siblings. So the skip has always been skipping nothing; the method resolving is what let the mistake survive a decade.

**Two orphan sites, not one:**

| Site | Superclass | Chain has the callback? |
|---|---|---|
| [`content_controller.rb:11`](../../app/controllers/cms/content_controller.rb#L11) | `Cms::ApplicationController` | ❌ |
| [`portlet_controller.rb:4`](../../app/controllers/cms/portlet_controller.rb#L4) | `Cms::ApplicationController` | ❌ |

The report names only the first. The second is the same defect and will surface the moment the first is fixed.

**4.2 is silent, not warning.** [`activesupport-4.2.11.3/lib/active_support/callbacks.rb`](../../vendor/bundle/gems/activesupport-4.2.11.3/lib/active_support/callbacks.rb) `skip_callback` finds `nil` and calls `chain.delete(nil)` — a no-op with no deprecation. 5.0 added the guard:

```ruby
options[:raise] = true unless options.key?(:raise)
...
if !callback && options[:raise]
  raise ArgumentError, "#{type.to_s.capitalize} #{name} callback #{filter.inspect} has not been defined"
end
```

**Do not reach for `raise: false`.** It works on 5.0 by design and happens to work on 4.2 by accident — 4.2 would put `{raise: false}` into `options`, making `options.any?` true, and only the `if filter` guard (nil here) stops it being passed to `Callback#merge`, which understands `:if`/`:unless` and nothing else. That is a coincidence, not a contract, and it would preserve two lines that are documented no-ops. **Delete both lines.** Backwards-compatible by construction: on 4.2 the behaviour is provably identical because `chain.delete(nil)` did nothing.

This is stage A, alone, first — nothing else in this phase is measurable on Rails 5 until it lands.

### 1.4 `email_message.rb:18` is not a mailer call, and renaming it would break the model

The doc: *"**`.deliver` / `.deliver!` → `deliver_now` / `deliver_now!`. 2 sites.** … Preserve the bang — `deliver!` becomes `deliver_now!`."*

[`app/models/cms/email_message.rb:15-20`](../../app/models/cms/email_message.rb#L15):

```ruby
def self.deliver!
  undelivered.all(:limit => 100).each do |m|
    m.deliver!          # <- :18
  end
end
```

`m` is a `Cms::EmailMessage`, and `deliver!` is that model's **own instance method**, defined at `:57`. There is no `deliver_now!` on the model to rename it to. The model does already define `deliver_now` at `:53` — as a one-line wrapper around `deliver!` — so the name is taken and the meaning is inverted from the mailer's.

**One real site, not two:** `:58`, `Cms::EmailMessageMailer.email_message(self).deliver` → `.deliver_now`. Criterion 8's grep must keep tolerating `m.deliver!` alongside the excluded `def self.deliver!`; the amended form is in [§7](#7-exit-criteria-traceability).

### 1.5 `.uniq` measures four sites, and the one that must change has a latent bug in it

Three of the four are Arrays and stay: `portlet.rb:86` (`.flatten.compact.uniq`), `content_type.rb:52` (`subclasses.uniq!`), `page_template.rb:29` (`.map{}.sort.uniq`). The Relation is confirmed — [`section_node.rb:53`](../../app/models/cms/section_node.rb#L53) `not_of_type` is `where(...)`.

But look at the whole expression, [`section_nodes_controller.rb:74-75`](../../app/controllers/cms/section_nodes_controller.rb#L74):

```ruby
(previous_parent.children.not_of_type(HIDDEN) +
 target_parent.children.not_of_type(HIDDEN).uniq).map { |n| [n.id, n.position, n.depth] }
```

The `.uniq` binds to the **second** relation only. It becomes `SELECT DISTINCT` within that half and does nothing about duplicates between the two halves — which is the only kind this method could plausibly produce, since a node can be a sibling in both the previous and target parent. The code reads like a union dedupe and is not one.

**Take `.distinct` and change nothing else.** It is byte-for-byte the same behaviour and it is what this phase is for. Hoisting the `uniq` outside the parens would fix the bug and is therefore not a backwards-compatible mechanical change — hand it to [Phase 4](phase-4-characterization-tests.md), which already owns a test for `move_to_position`.

### 1.6 Two of the four `render text:` sites are cucumber-covered, and they render HTML

The doc says both production sites are on untested error branches, which is right, and implies the `pretend_controller` pair is scaffolding, which is wrong. [`features/acts_as_content_page.feature:25`](../../features/acts_as_content_page.feature#L25) visits `/tests/open` and asserts on two content rows; `:49` visits `/tests/restricted`. Both routes are live in [`test/dummy/config/routes.rb:12-16`](../../test/dummy/config/routes.rb#L12), and both actions emit `<h1>` markup.

`render plain:` sets `Content-Type: text/plain`. That is a behaviour change under a currently-passing feature, and it is avoidable. So the four sites split two and two:

| Site | Content | Target |
|---|---|---|
| `content_block_controller.rb:138` | `"Not Implemented"` | `render plain:` |
| `form_fields_controller.rb:43` | `"Fail"` | `render plain:` |
| `pretend_controller.rb:14` | `"<h1>Restricted</h1> …"` | `render html: "…".html_safe` |
| `pretend_controller.rb:18` | `"<h1>Open Page</h1> …"` | `render html: "…".html_safe` |

`render html:` exists on 4.2. Without `.html_safe` it escapes the markup, which is the same content-type-preserving-but-output-changing trap one layer down — so the `html_safe` is load-bearing, not decoration.

### 1.7 Two of the three "dead code" deletions are not dead

**`app/portlets/deprecated_placeholder.rb` — keep.** It is the STI target of a shipped migration, [`db/migrate/20130327184912_browsercms400.rb:76`](../../db/migrate/20130327184912_browsercms400.rb#L76):

```ruby
Cms::Portlet.connection.execute("UPDATE cms_portlets SET type = 'DeprecatedPlaceholder' WHERE type = 'ResetPasswordPortlet'")
```

Every downstream database that ran browsercms400 has rows whose `type` column names this class. Deleting it turns each of them into `ActiveRecord::SubclassNotFound` on load. The class's own comment says exactly this is its job. It is not deprecated code; it is a tombstone, and tombstones are load-bearing.

**`lib/cms/behaviors/namespacing.rb` — not an empty shim.** The empty `Cms::Behaviors::Namespacing` module exists to satisfy [`lib/cms/behaviors.rb:30`](../../lib/cms/behaviors.rb#L30), which globs the directory and `constantize`s a module name out of every filename:

```ruby
Dir["#{File.dirname(__FILE__)}/behaviors/*.rb"].each do |b|
  require File.join("cms", "behaviors", File.basename(b, ".rb"))
  ActiveRecord::Base.send(:include, "Cms::Behaviors::#{File.basename(b, ".rb").camelize}".constantize)
end
```

That part is safe to delete, because the glob is file-driven — remove the file and the include goes with it. But the file's actual payload is **`Cms.table_prefix=`**, a public deprecated API that emits a deprecation warning pointing at issue #639. Deleting the file removes a public method from the engine's surface without a deprecation cycle. Either relocate `Cms.table_prefix=` to `lib/browsercms.rb` and delete the rest, or leave the file alone. This plan takes the second option — see [D4](#d4--namespacingrb-stays).

**`lib/cms/commands/to_version400.rb` — genuinely dead. Delete.** Zero references across `app lib test spec features config`; nothing requires `cms/commands`; `lib/` is not on an autoload path ([`engine.rb:112-116`](../../lib/cms/engine.rb#L112) lists `vendor`, `app/mailers`, `app/helpers`, `app/controllers`, `app/models`, `app/portlets` and two `Rails.root` paths). Nothing can reach it.

### 1.8 `update_attributes` is 14 calls, and `guest_user.rb` is a security guard the rename would disarm

16 grep hits = **14 calls**, one definition (`guest_user.rb:48`), one comment (`dynamic_attributes.rb:231`).

The doc flags `guest_user.rb` with a *"check its callers"* warning. The real problem is sharper than that. [`app/models/cms/guest_user.rb:43-54`](../../app/models/cms/guest_user.rb#L43) blocks writes three ways:

```ruby
def update_attribute(name, value); false; end
def update_attributes(attrs={});   false; end
def save(perform_validation=true); false; end
```

But in **both** 4.2 and 5.0, `update_attributes` is an *alias*, not the method — `persistence.rb:247/256` on 4.2 and `:270/279` on 5.0 both read `def update(attributes)` … `alias update_attributes update`. Overriding the alias name in a subclass leaves `update` bound to the original implementation. **`guest.update(...)` bypasses this guard today.** `save` is separately overridden, so the write still fails at the end — but it fails silently rather than at the guard, and only by luck.

So the mechanical rename has a real trap: rename the 14 callers to `update` while leaving the definition alone and every renamed path routes around the guard.

**Rename the definition too, and keep the old name as an alias:**

```ruby
def update(attrs = {})
  false
end
alias update_attributes update
```

That closes the existing hole rather than opening a new one, keeps any downstream caller of `update_attributes` working, and leaves criterion 4's grep matching exactly one line — the alias — which is the "kept deliberately" case the criterion already anticipates. It is a behaviour change; it goes in its own commit with this reasoning in the message, not folded into a 14-site rename. See [D3](#d3--guestuserupdate_attributes-becomes-an-alias).

### 1.9 `belongs_to` is 29 sites as claimed — plus a 30th, one hop downstream

24 in `app/models/cms/` and 5 in `lib/cms/behaviors/` (`versioning.rb:115`, `dynamic_attributes.rb:168`, `categorizing.rb:16`, `userstamping.rb:16` and `:17`). The other four `belongs_to` hits in `behaviors/` are the `belongs_to_category` macro name in `categorizing.rb:8-12`, not declarations. The doc's count is right.

**The 30th is [`lib/templates/active_record/model/model.rb:4`](../../lib/templates/active_record/model/model.rb#L4)** — a generator template that emits a bare `belongs_to :<%= attribute.name %>` into every model scaffolded in every downstream project. Same failure mode, deferred by one `rails generate`. The generator has no way to know whether nil is legitimate, so the template can't just gain `optional: true`; flag it and hand it to the 5.0 bump, where the generated code's target Rails version is settled.

### 1.10 Two of the doc's four "near-certain" `optional: true` candidates are already validated as required

The doc names *"all polymorphic associations (`SectionNode#node`, `Connector#connectable`, `Attachment#attachable`, `Tagging#taggable`), `Category#parent`, `Task#assigned_by` / `#assigned_to`, and userstamping's pair"* as near-certain. Two are contradicted by validations already in the models:

| Association | Existing validation | Verdict |
|---|---|---|
| `Connector#connectable` | [`connector.rb:44`](../../app/models/cms/connector.rb#L44) — `validates_presence_of :page_id, :page_version, :connectable_id, :connectable_type, :container` | **Required.** Leave alone. Also settles `Connector#page`. |
| `Task#assigned_by`, `#assigned_to`, `#page` | [`task.rb:27-29`](../../app/models/cms/task.rb#L27) — all three have `validates_presence_of … :message => "is required"` | **Required.** Leave all three alone. |
| `Category#category_type` | [`category.rb:12`](../../app/models/cms/category.rb#L12) — `validates_presence_of :category_type_id` | **Required.** Leave alone. |
| `Category#parent` | none | **`optional: true`** — self-referential, every root has a nil parent |
| `Attachment#attachable` | [`attachment.rb:23`](../../app/models/cms/attachment.rb#L23) validates `attachable_type` but **not** `attachable_id` | **Needs a decision.** `belongs_to` required-by-default validates the *loaded object*, so type-without-id fails it. Not resolvable by inspection. |

**And the database will not help.** `test/dummy/db/schema.rb` has **no `null: false` on any foreign-key column** in `cms_categories`, `cms_taggings`, `cms_attachments`, `cms_connectors`, `cms_section_nodes`, `cms_groups`, `cms_form_fields` or `cms_form_entries`. The schema is uniformly permissive, so it carries zero signal about intent.

That leaves exactly two evidence sources for the remaining sites: an existing presence validation, or a test run with the flag forced on. Which is the next finding.

### 1.11 Criterion 2 is not verifiable inside this phase's own scope

`belongs_to_required_by_default` is off on 4.2 and off on 5.0 for an engine (`load_defaults` appears nowhere in the repo, and per the phase doc's own §0.3 argument, the flag is the host application's to set). So **adding `optional: true` to 29 associations changes nothing observable on either bundle**, and removing it would also change nothing. The whole audit is unfalsifiable by the suite as it stands.

Criterion 2 half-acknowledges this — it asks that each association *"either carries `optional:` or is covered by a test asserting it is required (see Phase 4)"*. The test it points at does not exist yet.

This is the same structural situation Phase 2 hit with its criterion 3, and it takes the same resolution: **borrow the forced-flag test from Phase 4 as a declared prerequisite.** It is one `setup` block that flips `ActiveRecord::Base.belongs_to_required_by_default = true` around a model-instantiation sweep, and without it the largest work item in this phase ships unverified. See [D2](#d2--borrowing-the-forced-flag-test-from-phase-4).

### 1.12 `responders` must be declared without a version constraint

Currently transitive via devise, and the two locks disagree: `Gemfile.lock:258` has **2.4.1**, `Gemfile.next.lock:267` has **3.0.1**. responders 3.0 requires `railties >= 5.0`, so any constraint tight enough to be useful excludes one bundle. Six sites depend on it — `respond_with` at `content_controller.rb:79`, `page_components_controller.rb:14` and `:16`, and class-level `respond_to` at `content_controller.rb:3`, `inline_content_controller.rb:3`, `page_components_controller.rb:4`.

`s.add_dependency "responders"`, unconstrained, matches what both locks already resolve and moves neither. (If a bound is ever needed, the gemspec already carries a `NEXT_BOOT` conditional for four gems — and criterion 14's `NextRails` ban is scoped to `app/` and `lib/`, so the gemspec is not covered by it. Not needed here.)

### 1.13 `_filter` is 36 live sites, two of which are the deletions from 1.3

`grep -c` reports 37 lines across 17 files. One of those is a comment with two occurrences — [`lib/cms/acts/content_page.rb:73`](../../lib/cms/acts/content_page.rb#L73), *"Hash of options that will be passed to the before_filter call. See before_filter for valid options."* So **36 live declarations**: 32 `before_filter`, 2 `after_filter`, 2 `skip_before_filter`.

The two `skip_before_filter` are precisely the orphans deleted in stage A. **Stage D therefore renames 34 sites, not 37**, plus the one comment.

Worth knowing before you start: the codebase already mixes both spellings — 9 `_action` calls exist, and [`base_controller.rb:3-5`](../../app/controllers/cms/base_controller.rb#L3) uses `before_filter`, `before_action` and `before_filter` on three consecutive lines. There is no ordering hazard in that (they are aliases into one chain), but it means "does this file use filters?" is not answerable by grepping for one spelling.

Four further sites live in `test/`; they are outside every exit criterion's scope and outside this phase.

---

## 2. Execution order

| Stage | Work item | Produces | Size |
|---|---|---|---|
| **A** | *new* ([1.3](#13-the-rails-5-load-error-is-a-deletion-and-it-is-the-highest-leverage-change-in-the-phase)) | Two orphan `skip_before_filter` lines deleted; a Rails 5 functional suite that loads | **XS, do first** |
| **A′** | — | Re-measure both bundles. The residue is what actually scopes C. | S |
| **B** | *prereq* ([1.11](#111-criterion-2-is-not-verifiable-inside-this-phases-own-scope)) | The forced-flag test borrowed from Phase 4 — the oracle for stage C | S |
| **C** | 3.1 | The `belongs_to` audit, 29 sites, verified against B | **L — the only stage requiring judgement** |
| **D** | 3.1 | `deliver_now` ×1; `responders` in the gemspec | S |
| **E** | 3.2 / 3.3 / 3.4 | `_filter`→`_action` ×34; `update_attributes`→`update` ×14 + the guard; `render text:` ×4; `.uniq`→`.distinct` ×1; `HashWithIndifferentAccess` ×2 | M |
| **F** | 3.4 | `to_version400.rb` deleted; the two non-deletions recorded | XS |
| **G** | exit | Both bundles measured; branch-coverage floor set; `next-rails` green; report | S |

**A is first for the same reason Phase 2's stage A was**: it is a load error, so nothing downstream of it is measurable. Two deleted lines are expected to take the Rails 5 functional suite from "does not load" to a readable number, and to move most of the 148 cucumber failures. **Do not scope stage C or the contingencies until A′ has run** — the four other defects in Phase 2's §5 (`StaleObjectError` ×2, `PublishableTestCase#test_publish_on_save`, `PortletTest#test_.blacklist`, and the `ckeditor-jquery` asset resolution) are currently measured *behind* a load error, and some of them may be artefacts of it.

**B before C** because C is 29 judgement calls with no oracle otherwise ([1.10](#110-two-of-the-docs-four-near-certain-optional-true-candidates-are-already-validated-as-required), [1.11](#111-criterion-2-is-not-verifiable-inside-this-phases-own-scope)).

**D before E** because D is the last of the 5.0-breaking set; once it lands, everything remaining is a 5.1-or-later concern and the phase can be cut short without leaving the bump blocked.

**After every stage: the 4.2 suite must still be green at 78.35% with cucumber 154/154.** Same rule as Phase 2, same reason — checking once at the end tells you a test was lost without telling you which stage lost it.

**Two operational notes carried from Phase 2's report, both of which will bite otherwise:**

- Clear `coverage/.resultset.json` before any coverage number you intend to quote. It is shared across bundles and suites with a 3600s merge timeout, and stale entries silently shift the merged percentage.
- Switching bundles leaves the test database in a state the other rejects. After a 4.2 run, the next bundle aborts at `db:drop` with `ActiveRecord::NoEnvironmentInSchemaError`; clear it with `BUNDLE_GEMFILE=Gemfile.next bundle exec rake app:db:environment:set`.

---

## 3. Stage detail

### A — The orphan skips (new work item 3.0)

Delete two lines:

- [`app/controllers/cms/content_controller.rb:11`](../../app/controllers/cms/content_controller.rb#L11) — `skip_before_filter :redirect_to_cms_site`
- [`app/controllers/cms/portlet_controller.rb:4`](../../app/controllers/cms/portlet_controller.rb#L4) — same line

Leave a comment where each was, naming the reason, so the next reader does not "restore" them:

```ruby
# There is deliberately no skip of :redirect_to_cms_site here. That callback is
# registered only on Cms::BaseController (base_controller.rb:3), which is a
# sibling of this class, not an ancestor -- so there has never been anything to
# skip. 4.2's skip_callback silently deleted nil; 5.0 raises ArgumentError.
```

Do **not** touch the three `skip_before_action` calls in [`base_controller.rb:15-17`](../../app/controllers/cms/base_controller.rb#L15). Those are inside `allow_guests_to`, they run against a chain that genuinely has all three callbacks, and they are already spelled the modern way.

Commit alone.

### A′ — Re-measure, then rescope

```bash
rm -f coverage/.resultset.json coverage/.last_run.json
bundle exec rake                                     # 4.2: expect 996 / 0F / 0E, cucumber 154/154, 78.35%
BUNDLE_GEMFILE=Gemfile.next bundle exec rake app:db:environment:set
BUNDLE_GEMFILE=Gemfile.next bundle exec rake         # 5.0: the number that scopes the rest
```

Record the Rails 5 unit and cucumber figures in the report before doing anything else. Compare them against Phase 2's §5 list of five defects and write down which of the four remaining ones survived the load error — that list, not the phase document, is what stage G has to close.

### B — Borrow the forced-flag test from Phase 4

One test, in `test/unit/` — enough to make stage C falsifiable and no more:

```ruby
# belongs_to_required_by_default is the host application's flag, not the engine's
# (there is no load_defaults in this repo), so nothing in either bundle exercises
# required-by-default against these models. This forces it on for the duration of
# one sweep, which is the only oracle the belongs_to audit has. Phase 4 owns the
# permanent version of this; borrowed here per D2.
```

It flips `ActiveRecord::Base.belongs_to_required_by_default = true`, instantiates each of the 24 models plus one consumer of each of the 5 behaviors with its associations unset, and asserts validity matches the intended verdict. Restore the flag in `teardown` — leaking it turns every later test in the process into a different test.

It must pass on **both** bundles. If it can only be made to pass on one, that is a finding about the model, not about the test.

### C — The `belongs_to` audit (3.1)

29 sites. Not a find-and-replace; the doc says so and [1.10](#110-two-of-the-docs-four-near-certain-optional-true-candidates-are-already-validated-as-required) shows why.

**Decide each site from evidence, in this order:**

1. **An existing `validates_presence_of` on the FK ⇒ required. Leave alone.** This settles `Connector#page`, `Connector#connectable`, `Task#assigned_by`, `Task#assigned_to`, `Task#page`, `Category#category_type` — six sites, six of them named or implied as optional candidates by the doc.
2. **Self-referential or polymorphic with no presence validation ⇒ almost certainly `optional: true`.** `Category#parent` is the clearest: every root category has a nil parent, so required-by-default breaks the category tree outright.
3. **Everything else ⇒ the stage-B test decides.** The schema does not, because nothing is `null: false`.

**The five behavior-injected sites carry the blast radius** and are worth more care than the 24 model sites combined — they apply to every model using the behavior, in this engine *and in every downstream project*:

| Site | Association | Note |
|---|---|---|
| [`userstamping.rb:16`](../../lib/cms/behaviors/userstamping.rb#L16), `:17` | `created_by`, `updated_by` | Nil for anything created outside a request — seeds, rake tasks, migrations. `optional: true`. |
| [`categorizing.rb:16`](../../lib/cms/behaviors/categorizing.rb#L16) | `category` | Categorising is opt-in per instance; nil is the normal state. |
| [`versioning.rb:115`](../../lib/cms/behaviors/versioning.rb#L115) | version → parent | Declared dynamically via `version_class.belongs_to(...)`, so the `optional:` goes into that call's options hash, not a literal. Grep for `optional:` will not find it in the shape criterion 2 expects — note it in the report. |
| [`dynamic_attributes.rb:168`](../../lib/cms/behaviors/dynamic_attributes.rb#L168) | `base_class` | Also a dynamic declaration. |

**Also flag, do not fix:** [`lib/templates/active_record/model/model.rb:4`](../../lib/templates/active_record/model/model.rb#L4) ([1.9](#19-belongs_to-is-29-sites-as-claimed--plus-a-30th-one-hop-downstream)). The template cannot know whether nil is legitimate for a generated attribute; the decision belongs with whoever settles what Rails version generated code targets, which is [Phase 5](phase-5-the-5.0-bump.md).

Commit the 24 model sites and the 5 behavior sites separately. The behavior sites are the ones a reviewer needs to look at properly.

### D — The rest of the 5.0-breaking set (3.1)

**`deliver` → `deliver_now`, one site.** [`email_message.rb:58`](../../app/models/cms/email_message.rb#L58) only. Leave `:15` (`def self.deliver!`) and `:18` (`m.deliver!`) exactly as they are — [1.4](#14-email_messagerb18-is-not-a-mailer-call-and-renaming-it-would-break-the-model).

**`responders` in the gemspec, unconstrained** — [1.12](#112-responders-must-be-declared-without-a-version-constraint). Add near the other `add_dependency` lines with a one-line comment saying it is currently transitive via devise and that the six `respond_with`/`respond_to` sites should not depend on that. Re-run `bundle install` (`bundle lock` is enough) on **both** Gemfiles and confirm the locks do not move — if either does, the constraint was wrong.

### E — The renames (3.2 / 3.3 / 3.4)

Five independent changes; one commit each, so a bisect lands on one of them.

**`*_filter` → `*_action`, 34 sites across 17 files** ([1.13](#113-_filter-is-36-live-sites-two-of-which-are-the-deletions-from-13)). Pure rename; identical behaviour on both versions. Update the comment at `content_page.rb:73` too. Failure mode on 5.1 is a boot-time `NoMethodError`, so no test is needed — but the 4.2 suite still has to be green afterwards, because a typo in a callback name is *also* a boot-time failure.

**`update_attributes` → `update`, 14 call sites** ([1.8](#18-update_attributes-is-14-calls-and-guest_userrb-is-a-security-guard-the-rename-would-disarm)): 6 in models (`page_component.rb:28`, `email_message.rb:59`, `page.rb:220`, `:243`, `:258`, `task.rb:34`), 4 in controllers (`content_block_controller.rb:267`, `inline_content_controller.rb:7`, `links_controller.rb:38`, `page_route_options_controller.rb:22`), 4 in behaviors (`publishing.rb:132`, `soft_deleting.rb:73`, `:75`, `connecting.rb:119`). The comment at `dynamic_attributes.rb:231` mentions `ActiveRecord::Persistence#update_attributes` by name and is describing Rails' API, not this codebase's — update it or leave it, but do not let it fail criterion 4 by accident.

**The `GuestUser` guard, separately** ([D3](#d3--guestuserupdate_attributes-becomes-an-alias)) — its own commit, with the reasoning in the message.

**`render text:` → `plain:` ×2 and `html:` ×2** ([1.6](#16-two-of-the-four-render-text-sites-are-cucumber-covered-and-they-render-html)). The two `pretend_controller` sites need `.html_safe`; verify with cucumber, not with the unit suite.

**`.uniq` → `.distinct`, one site** ([1.5](#15-uniq-measures-four-sites-and-the-one-that-must-change-has-a-latent-bug-in-it)). Leave the other three. Add a `# TODO(Phase 4)` naming the union-dedupe question so it does not get lost.

**`HashWithIndifferentAccess` → `ActiveSupport::HashWithIndifferentAccess`, 2 sites.** `page_component.rb:10` (covered) and `portlet.rb:228` (uncovered). Trivial, and the removal version is unverified, so qualifying both now retires the tracking rather than the risk.

### F — Dead code (3.4)

**Delete** `lib/cms/commands/to_version400.rb` ([1.7](#17-two-of-the-three-dead-code-deletions-are-not-dead)).

**Do not delete** `app/portlets/deprecated_placeholder.rb` or `lib/cms/behaviors/namespacing.rb`. Add a comment to each saying why, so this does not get re-litigated at the next hop:

- `deprecated_placeholder.rb` — named by `db/migrate/20130327184912_browsercms400.rb:76`; downstream rows point at it.
- `namespacing.rb` — the empty module satisfies `behaviors.rb:30`'s glob-and-constantize, and the file also carries the public `Cms.table_prefix=` deprecation.

`lib/cms/form_builder/deprecated_inputs.rb` stays; `features/content_blocks/deprecated_form_inputs.feature` is its contract. The doc already says so.

Optional, from Phase 2's handoff: `Cms::IntegrationTestHelper` (`test/test_helper.rb`) is defined, included nowhere, and asserts `403` immediately after a successful login. It is test-side and outside every criterion here — delete it if the phase has room, defer it if not.

### G — Exit

1. Clear the resultset. Full run on both bundles. Cucumber on both.
2. **Set the branch-coverage floor.** Phase 2 measured 70.79% and reported it without gating. Now that a stage-A-through-F diff has moved through, take a fresh reading and set `COVERAGE_MINIMUM_BRANCH` in [`core_tasks.rake`](../../lib/tasks/core_tasks.rake) at the measured value. Phase 2's report asks for this and it is cheap here.
3. Run every criterion grep from [§7](#7-exit-criteria-traceability) and paste the output into the report — including the ones that pass already, so the record shows they were checked and not assumed.
4. **The `next-rails` job should now be green.** If it is not, [§6](#6-contingencies) says what to do; do not merge over it silently, because the whole argument for making it gating in Phase 2 was that a permanently-red job hides real regressions.
5. Deploy to production on 4.2 (criterion 15) and write `phase-3-report.md`.

---

## 4. Decisions

### D1 — The migration item leaves the phase

Per [1.2](#12-the-migration-item-cannot-land-in-this-phase--and-does-not-break-at-50): `ActiveRecord::Migration[4.2]` does not exist on 4.2, and 5.0 does not need it. Keeping it would require the phase's first `NextRails` branch, which criterion 14 exists to forbid. Moved to Phase 5 / the 5.1 hop; criterion 12 struck. **Needs a human to confirm the deferral**, since it changes a phase document.

### D2 — Borrowing the forced-flag test from Phase 4

Per [1.11](#111-criterion-2-is-not-verifiable-inside-this-phases-own-scope). Same shape as Phase 2's [D1](phase-2-implementation-plan.md#d1--borrowing-two-fixes-from-phase-3), and the same justification: the alternative is shipping the phase's largest work item with no oracle at all. Phase 4 keeps ownership of the permanent version and of everything else in its scope. The README already notes Phases 3 and 4 can run in parallel, so this is a sequencing detail between them rather than a scope transfer.

Recorded as a deliberate deviation. The phase doc's "no new tests" exclusion is written as *"except where a Tier C fix has a behavioural choice in it"* — 29 nil-legitimacy judgements is that, several times over.

### D3 — `GuestUser#update_attributes` becomes an alias

Per [1.8](#18-update_attributes-is-14-calls-and-guest_userrb-is-a-security-guard-the-rename-would-disarm). Renaming the definition to `update` and aliasing the old name is the only option that does not either leave the guard bypassable through 14 renamed paths or break downstream callers.

It closes a hole that is open today (`guest.update(...)` reaches `ActiveRecord::Persistence#update` right now), which makes it a behaviour change in a phase whose contract is "no behaviour changes." **Flagging it rather than deciding it.** The alternative — leave `update_attributes` as the only definition and exclude `guest_user.rb` from the rename — preserves the phase's contract exactly and leaves a known hole in place. That trade is a human's to make.

While in the file: `def save(perform_validation=true)` at `:52` is the same class of signature-override bug as the `create_or_update` arity Phase 2 fixed. It is not currently breaking — 5.0's `save` is `save(*args)` and a keyword hash lands harmlessly in the positional slot — but it will not survive later hops. Note it; do not fix it here.

### D4 — `namespacing.rb` stays

Per [1.7](#17-two-of-the-three-dead-code-deletions-are-not-dead). Relocating `Cms.table_prefix=` to `lib/browsercms.rb` and deleting the rest is the tidier end state and is maybe six lines — but it moves a public API's definition site in a phase that is supposed to contain nothing but no-op renames, for no upgrade benefit. Leave the file, comment it, revisit when the 6.0 autoloading work touches `behaviors.rb`'s glob anyway.

### D5 — Scope of the `_filter` rename

`test/` has four `_filter` sites. They are outside criterion 3's grep (`app/ lib/`) and outside this phase. They break at 5.1 exactly like the production ones, so they will be picked up by the 5.1 hop's detection run. Not doing them here keeps stage E's commit reviewable as one mechanical change to one tree.

---

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Stage A does not produce the expected improvement**, and the Rails 5 functional suite stays down for a different reason. | A′ exists precisely to find this out in one step. The two lines are provably no-ops on 4.2, so stage A cannot regress the default bundle regardless. |
| R2 | **The `belongs_to` audit gets one wrong** — an association marked optional that a host app depends on being required, or vice versa. Nothing in either bundle detects it. | Stage B is the whole mitigation. Where B cannot decide, prefer `optional: true`: a wrongly-optional association fails later and loudly at the call site; a wrongly-required one fails immediately and everywhere for every host app on `load_defaults 5.0`. |
| R3 | **The behavior-injected `belongs_to` changes break downstream projects** that this repo's suite cannot see. Five declarations reach every model using the behavior. | These four sites get their own commit and their own reviewer. Two are dynamic declarations that grep will not find later ([C](#c--the-belongs_to-audit-31)) — say so in the report. |
| R4 | **The `GuestUser` change is a real behaviour change** in a no-behaviour-change phase. | [D3](#d3--guestuserupdate_attributes-becomes-an-alias) puts the decision in front of a human instead of resolving it silently. Own commit either way. |
| R5 | **`render html:` without `html_safe`** escapes the markup, changing the two cucumber-covered responses in a way `plain:` would not have. | The instruction in [E](#e--the-renames-32--33--34) is explicit, and `acts_as_content_page.feature` asserts on the rendered content. Run cucumber, not just the unit suite, after that commit. |
| R6 | **Coverage moves and nobody can say why.** 34 renamed callbacks and 14 renamed calls do not change line counts, but the deleted file and the deleted skip lines do. | Same discipline as Phase 2's stage F: measure on a cleared resultset, immediately before and after the commits that delete code, so an instrument change is distinguishable from a lost test. |
| R7 | **`responders` in the gemspec moves a lock.** | Check both locks after `bundle lock`. If either moves, the constraint was wrong — remove it rather than accepting the drift ([1.12](#112-responders-must-be-declared-without-a-version-constraint)). |

---

## 6. Contingencies

**If stage A′ shows Rails 5 still substantially red**, the four defects from Phase 2's §5 are the next thing to read, and they are not all Phase 3 work:

- `StaleObjectError` on `Cms::Page` ×2 and `PublishableTestCase#test_publish_on_save` are plausibly downstream of the `create_or_update` arity change interacting with optimistic locking — application behaviour, in scope, but they need diagnosis before they can be scoped.
- `PortletTest#test_.blacklist` is one expectation diff. Small.
- **`couldn't find file 'ckeditor-jquery'`** is asset-pipeline resolution under 5.0, not a code fix, and it accounted for 132 of the 148 cucumber failures. It is a gem-and-pipeline problem in the shape of [Phase 1](phase-1-gem-report.md)'s work. **If it is still there after stage A, it is the thing standing between this phase and a green `next-rails` job, and it does not belong to any of this phase's 89 edits.** Scope it as its own item rather than letting it hold the phase open.

**`use_route`** ([`test/support/engine_controller_hacks.rb`](../../test/support/engine_controller_hacks.rb), Phase 2 §5) is removed in 5.0 and now arrives at controllers as an ordinary request parameter. Phase 2 measured that the obvious replacement produces 16 `UrlGenerationError`s and left the finding in the module's comment. It is test-harness work, it needs a per-test-class decision about engine versus application route sets, and it has no backwards-compatible form. **Not this phase.** It will surface in stage A′; expect it and do not chase it.

**If the phase has to be cut short**, stages A through D are the part that unblocks the bump. E and F break at 5.1 and 6.0 and can slip to [Phase 6](phase-6-subsequent-hops.md) without blocking anything — at the cost the phase document names: debugging them simultaneously with a version change.

---

## 7. Exit criteria traceability

| # | Criterion | Stage | Verification | Status now |
|---|---|---|---|---|
| 1 | Suite green on both Gemfiles, coverage ≥ Phase 2 | G | CI both jobs | 4.2 green at 78.35%; 5.0 red |
| 2 | All 29 `belongs_to` audited | B, C | Stage B's forced-flag test, plus the two dynamic declarations named in the report | not started |
| 3 | No `*_filter` callbacks | E | `grep -rnE "\b(before\|after\|around\|skip_before\|skip_after)_filter\b" app/ lib/` | 37 lines (36 live + 1 comment) |
| 4 | No `update_attributes` calls | E | `grep -rn "update_attributes" app/ lib/` | 16 hits = 14 calls + 1 definition + 1 comment. Expect 1–2 survivors by design ([D3](#d3--guestuserupdate_attributes-becomes-an-alias)) |
| 5 | No `render text:` | E | `grep -rnE "render\s+(:text\s*=>\|text:)" app/ lib/` | 4 |
| 6 | No `.uniq` on a Relation | E | `grep -rn "\.uniq" app/controllers/ app/models/` reviewed | 4 hits, 3 are Arrays and stay ([1.5](#15-uniq-measures-four-sites-and-the-one-that-must-change-has-a-latent-bug-in-it)) |
| 7 | No `HTML::FullSanitizer` | — | `grep -rn "HTML::FullSanitizer" app/ lib/ test/ spec/` | ✅ **already passes** (Phase 2) |
| 8 | No bare mailer `.deliver` | D | **Amended.** The doc's grep excludes `def self.deliver` but not `m.deliver!`, which is a model method, not a mailer ([1.4](#14-email_messagerb18-is-not-a-mailer-call-and-renaming-it-would-break-the-model)). Expect two survivors at `email_message.rb:15` and `:18`; both are correct | 3 hits, 1 to change |
| 9 | No `File.exists?` | — | `grep -rn "File.exists?" app/ lib/` | ✅ **already passes** (Phase 0, `6da1d60d`) |
| 10 | No unqualified `HashWithIndifferentAccess` | E | `grep -rnE "(^\|[^:A-Za-z])HashWithIndifferentAccess" app/ lib/` | 2 |
| 11 | `responders` in the gemspec | D | `grep -n responders browsercms.gemspec` | 0 |
| 12 | ~~Migrations version-qualified~~ | — | **Struck.** Not backwards-compatible and not required at 5.0 — [1.2](#12-the-migration-item-cannot-land-in-this-phase--and-does-not-break-at-50), [D1](#d1--the-migration-item-leaves-the-phase). Moved to Phase 5 / the 5.1 hop | n/a |
| 13 | `find_by_*` untouched | all | `git diff` shows no change to `find_by_login`, `find_by_path`, `find_by_code`, `find_by_from_path` | trivially true |
| 14 | Zero `NextRails` branches | all | `grep -rn "NextRails" app/ lib/` | ✅ 0 today — **the phase's definition of correctness. Keep it 0.** |
| 15 | Deployed to production on 4.2 | G | Deployed and stable | not started |

**Two criteria pass before the phase begins** (7 and 9), **one is struck** (12), and **one cannot be verified without borrowed work** (2, via [D2](#d2--borrowing-the-forced-flag-test-from-phase-4)).

**Add a sixteenth, because it is the phase's actual purpose and nothing above measures it:**

| # | Criterion | Verification |
|---|---|---|
| **16** | **The `next-rails` CI job is green** | It was made gating in Phase 2 with the explicit statement that *"CI is red on every PR until Phase 3 lands."* Turning that red green is what this phase is for, and criterion 1's "suite green on both Gemfiles" is the same claim stated less directly. If the `ckeditor-jquery` asset problem ([§6](#6-contingencies)) is what stands in the way, say so explicitly in the report and scope it — do not let it quietly redefine "done." |
