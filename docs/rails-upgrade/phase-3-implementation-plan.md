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
>
> **Three items were added after this plan's first draft**, from a second reading of
> Phase 2's residue. Two of them are the Rails 5 asset chain
> ([1.14](#114-ckeditor_rails-434-is-rails-4-only-at-runtime-and-no-declaration-says-so),
> [1.15](#115-sprockets-rails-3-requires-every-referenced-asset-to-be-declared)) — **132
> of the 148 cucumber failures, and the last thing standing between this phase and
> criterion 16.** The first draft named the symptom in a contingency and said "scope it
> as its own item"; **stage D′** is that item. The third is a second signature override
> of exactly the kind Phase 2 fixed
> ([1.16](#116-save-is-the-same-signature-override-that-p1-2-was)). None of the three is
> a mechanical rename and the first is not strictly backwards-compatible, so all three
> are argued in [D6](#d6--how-far-to-move-ckeditor_rails),
> [D7](#d7--how-to-satisfy-sprockets-rails-3) and
> [D8](#d8--the-save-override-forwards-and-that-changes-behaviour).

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

### 1.14 `ckeditor_rails` 4.3.4 is Rails-4-only at runtime, and no declaration says so

Phase 2's report lists `couldn't find file 'ckeditor-jquery'` among five remaining defects and attributes **132 of the 148 cucumber failures** to it. It is not in the phase document's work items, and this plan's first draft said only *"scope it as its own item rather than letting it hold the phase open."* This is that item.

The cause is a `case` statement in the gem's entry point — [`ckeditor_rails-4.3.4/lib/ckeditor-rails.rb`](../../vendor/bundle/gems/ckeditor_rails-4.3.4/lib/ckeditor-rails.rb):

```ruby
module Ckeditor
  module Rails
    case ::Rails.version.to_s
    when /^4/       then require 'ckeditor-rails/engine'
    when /^3\.[12]/ then require 'ckeditor-rails/engine3'
    when /^3\.[0]/  then require 'ckeditor-rails/railtie'
    end
  end
end
```

On Rails 5 **no branch matches**, so `Ckeditor::Rails::Engine` — the `::Rails::Engine` subclass declared in `lib/ckeditor-rails/engine.rb` — is never defined. That class is the only thing that puts the gem's directories on the asset load path, and the file the CMS layout needs is at `lib/assets/javascripts/ckeditor-jquery.js`, under the engine's default `lib/assets` path. With no engine, that directory is invisible to sprockets, and `//= require ckeditor-jquery` at [`app/assets/javascripts/bcms/ckeditor.js:5`](../../app/assets/javascripts/bcms/ckeditor.js#L5) cannot resolve. Every page that renders the CMS layout then raises `ActionView::Template::Error`.

**No instrument in Phase 1 or Phase 2 could have caught this.** [`browsercms.gemspec:51`](../../browsercms.gemspec#L51) declares `ckeditor_rails ~> 4.3.0` with no Rails constraint, and Phase 1's offline scan reads declared requirements — there are none to read. `bundle_report` searches for newer *compatible* versions, and 4.3.4 is compatible by every declaration it makes. Phase 1's boot smoke test booted; it just never rendered a view. Both locks resolve 4.3.4 today ([`Gemfile.lock:93`](../../Gemfile.lock#L93), [`Gemfile.next.lock:97`](../../Gemfile.next.lock#L97)). The lesson is `panoramic`'s, from the opposite direction: **a declared requirement is not a compatibility claim, and a boot is not a render.**

The gem's `when` clause widens to `/^[45]/` at **4.5.10** and to `/^[4567]/` by 4.17.0. Only 4.3.4 is vendored here, so confirm the exact first-working release against rubygems at implementation time rather than trusting that number.

**The catch is that this gem's version *is* CKEditor's version.** 4.3.4 → 4.5.10 moves the bundled editor two minor versions; 4.16+ also changes the default skin from `moono` to `moono-lisa`. This is the WYSIWYG editor in a CMS, and the cucumber suite has **zero `@javascript` scenarios** — so no test in this repository can tell you the editor still works after the bump. See [D6](#d6--how-far-to-move-ckeditor_rails).

### 1.15 sprockets-rails 3 requires every referenced asset to be declared

This one is in no phase document at all, and it is the next failure sitting *behind* [1.14](#114-ckeditor_rails-434-is-rails-4-only-at-runtime-and-no-declaration-says-so).

The two locks differ: [`Gemfile.lock:291`](../../Gemfile.lock#L291) has **sprockets-rails 2.3.3**, [`Gemfile.next.lock:301`](../../Gemfile.next.lock#L301) has **3.2.2**. Version 3 raises `Sprockets::Rails::Helper::AssetNotPrecompiled` for any asset referenced through `image_tag` / `asset_path` that is not reachable from `config.assets.precompile` or an `app/assets/config/manifest.js`. This engine has neither for images: [`lib/cms/engine.rb:122-133`](../../lib/cms/engine.rb#L122) lists eight named JS/CSS files plus `jquery`, and `app/assets/config/` does not exist in this repository.

The first asset that trips it is `cms/logo.png`, from [`app/views/layouts/cms/_main_menu.html.erb:5`](../../app/views/layouts/cms/_main_menu.html.erb#L5):

```erb
<%= link_to image_tag('cms/logo.png', class: 'main-logo'), "/" %>
```

The file is real and on disk. It is simply undeclared, which 2.3.3 tolerated and 3.2.2 does not.

**It is the first, not the only one.** This is the single item in the phase with no measured upper bound: fix, re-run, read the next asset name, repeat. Budget stage D′ accordingly and re-scope out loud if it goes deep, rather than absorbing it silently. [D7](#d7--how-to-satisfy-sprockets-rails-3) picks the exit that closes the whole class instead of the instances — and whichever is chosen, **it belongs in the engine, not in `test/dummy/`.** A consuming application hits exactly this wall at [Phase 5](phase-5-the-5.0-bump.md), and a dummy-app fix does not travel to it.

### 1.16 `save!` is the same signature override that P1-2 was

[`lib/cms/behaviors/versioning.rb:271`](../../lib/cms/behaviors/versioning.rb#L271), in `Versioning::InstanceMethods`:

```ruby
def save!(perform_validations=true)
  save(:validate => perform_validations) || raise(ActiveRecord::RecordNotSaved.new(errors.full_messages))
end
```

Nothing in Rails calls `save!` with a positional boolean. Both frameworks call it with an **options hash**, from the collection-association insert path:

| | Framework call site | Signature it is calling into |
|---|---|---|
| 4.2 | [`has_many_association.rb:39`](../../vendor/bundle/gems/activerecord-4.2.11.3/lib/active_record/associations/has_many_association.rb#L39) — `record.save!(:validate => validate)` | `validations.rb:42` — `save!(options={})` |
| 5.0 | [`collection_association.rb:510`](../../vendor/bundle/gems/activerecord-5.0.7.2/lib/active_record/associations/collection_association.rb#L510) — `record.save!(validate: validate, &block)` | `persistence.rb:159` — `save!(*args, &block)` |

Two consequences, one per bundle:

- **On both**, `perform_validations` is bound to `{validate: false}` — a Hash, and therefore truthy — so the override calls `save(validate: true)` and validations run in precisely the path where the framework asked for them to be skipped. Silently wrong on 4.2 today.
- **On 5.0 additionally, the block is dropped.** `collection_association.rb:501` passes `{ @_was_loaded = loaded? }` into `insert_record`, and 5.0's `save!(*args, &block)` forwards it to `create_or_update(*args, &block)`, which yields it after the insert. Phase 2 taught `create_or_update` to accept and forward that block ([P1-2](phase-1-gem-report.md#open-items)); this override sits *above* it in the chain and throws the block away before it ever gets there.

So it is the same defect Phase 2 fixed, one method up — and the Phase 2 fix is what makes the gap reachable. It does not raise, which is why nothing has caught it. The remedy has the same shape as P1-2's, and it is a behaviour change: [D8](#d8--the-save-override-forwards-and-that-changes-behaviour).

Distinguish it from the sibling already flagged in [D3](#d3--guestuserupdate_attributes-becomes-an-alias): [`guest_user.rb:52`](../../app/models/cms/guest_user.rb#L52)'s `def save(perform_validation=true)` returns `false` unconditionally, so its arity genuinely does not matter. That one is a guard. This one is not.

---

## 2. Execution order

| Stage | Work item | Produces | Size |
|---|---|---|---|
| **A** | *new* ([1.3](#13-the-rails-5-load-error-is-a-deletion-and-it-is-the-highest-leverage-change-in-the-phase)) | Two orphan `skip_before_filter` lines deleted; a Rails 5 functional suite that loads | **XS, do first** |
| **A′** | — | Re-measure both bundles. The residue is what actually scopes C. | S |
| **B** | *prereq* ([1.11](#111-criterion-2-is-not-verifiable-inside-this-phases-own-scope)) | The forced-flag test borrowed from Phase 4 — the oracle for stage C | S |
| **C** | 3.1 | The `belongs_to` audit, 29 sites, verified against B | **L — the only stage requiring judgement** |
| **D** | 3.1 | `deliver_now` ×1; `responders` in the gemspec; the `save!` override forwards ([1.16](#116-save-is-the-same-signature-override-that-p1-2-was)) | S |
| **D′** | *new* 3.5 ([1.14](#114-ckeditor_rails-434-is-rails-4-only-at-runtime-and-no-declaration-says-so), [1.15](#115-sprockets-rails-3-requires-every-referenced-asset-to-be-declared)) | `ckeditor_rails` on a release that loads under Rails 5; the engine's images declared to sprockets 3; a cucumber number that means something | **M, with an unbounded tail** |
| **E** | 3.2 / 3.3 / 3.4 | `_filter`→`_action` ×34; `update_attributes`→`update` ×14 + the guard; `render text:` ×4; `.uniq`→`.distinct` ×1; `HashWithIndifferentAccess` ×2 | M |
| **F** | 3.4 | `to_version400.rb` deleted; the two non-deletions recorded | XS |
| **G** | exit | Both bundles measured; branch-coverage floor set; `next-rails` green; report | S |

**A is first for the same reason Phase 2's stage A was**: it is a load error, so nothing downstream of it is measurable. Two deleted lines are expected to take the Rails 5 functional suite from "does not load" to a readable number, and to move most of the 148 cucumber failures. **Do not scope stage C or the contingencies until A′ has run** — the four other defects in Phase 2's §5 (`StaleObjectError` ×2, `PublishableTestCase#test_publish_on_save`, `PortletTest#test_.blacklist`, and the `ckeditor-jquery` asset resolution) are currently measured *behind* a load error, and some of them may be artefacts of it.

**B before C** because C is 29 judgement calls with no oracle otherwise ([1.10](#110-two-of-the-docs-four-near-certain-optional-true-candidates-are-already-validated-as-required), [1.11](#111-criterion-2-is-not-verifiable-inside-this-phases-own-scope)).

**D and D′ are the last of the 5.0-breaking set**; once they land, everything remaining is a 5.1-or-later concern and the phase can be cut short without leaving the bump blocked.

**D′ is placed here rather than earlier** because nothing in B or C depends on it — but **pull it forward ahead of B if A′'s cucumber number is still dominated by the asset error**, which is the likely outcome: [1.14](#114-ckeditor_rails-434-is-rails-4-only-at-runtime-and-no-declaration-says-so) alone is 132 of 148 failures. Until it clears, cucumber cannot tell you anything about the other four defects in Phase 2's §5, and stage G has to close them.

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

**The `save!` override forwards** — [1.16](#116-save-is-the-same-signature-override-that-p1-2-was), decided by [D8](#d8--the-save-override-forwards-and-that-changes-behaviour). Own commit; it is the only change in stage D that alters behaviour. [`versioning.rb:271`](../../lib/cms/behaviors/versioning.rb#L271) takes the same shape Phase 2 gave `create_or_update` one method below it, with a comment that names the call sites so the splat does not read as unused:

```ruby
        # Rails never calls save! with a positional boolean. 4.2 calls it as
        # save!(:validate => x) (has_many_association.rb:39) and 5.0 as
        # save!(validate: x, &block) (collection_association.rb:510) -- so the old
        # `perform_validations` parameter was being handed a truthy Hash, and on 5.0 the
        # block that create_or_update yields after insert was being dropped here before
        # it could reach the (*args, &block) signature Phase 2 gave that method. Same
        # defect as P1-2, one method up. See docs/rails-upgrade/phase-1-gem-report.md.
        def save!(*args, &block)
          save(*args, &block) || raise(ActiveRecord::RecordNotSaved.new(errors.full_messages))
        end
```

`save` with no arguments already defaults to validating, so a bare `record.save!` is unchanged. The behaviour that *does* change is the autosave path, where validations will now correctly be skipped — run the full suite on **both** bundles after this commit and read the diff in failures carefully, because a test that was passing on accidental validation will surface here and that is the fix working, not the fix breaking.

### D′ — The Rails 5 asset chain (new work item 3.5)

Two changes, in this order, because the second is invisible until the first lands. **Neither is a code fix and neither is a rename** — this is the one stage whose work the phase document's "backwards-compatible mechanical change" contract does not describe. Do not start it until [D6](#d6--how-far-to-move-ckeditor_rails) and [D7](#d7--how-to-satisfy-sprockets-rails-3) are answered.

#### D′.1 — `ckeditor_rails` onto a release that loads under Rails 5

The constraint is at [`browsercms.gemspec:51`](../../browsercms.gemspec#L51), and the gemspec already carries the `NEXT_BOOT` pattern for three other gems ([`:45`](../../browsercms.gemspec#L45), [`:54`](../../browsercms.gemspec#L54), [`:62`](../../browsercms.gemspec#L62)), so whichever way [D6](#d6--how-far-to-move-ckeditor_rails) goes there is a shape to follow:

```ruby
  # 4.3.4 dispatches its Railtie on `case ::Rails.version` and has no Rails 5 branch, so
  # under 5.0 the gem defines no Rails::Engine at all, its lib/assets never joins the
  # asset load path, and `//= require ckeditor-jquery` (bcms/ckeditor.js:5) cannot
  # resolve -- which takes down every page rendering the CMS layout. The version tracks
  # CKEditor itself, so this is an editor upgrade as well as a gem bump. See D6.
  s.add_dependency("ckeditor_rails", NEXT_BOOT ? "~> 4.5" : "~> 4.3.0")
```

- [ ] `couldn't find file 'ckeditor-jquery'` gone from the Rails 5 functional and cucumber logs
- [ ] `Gemfile.lock` unchanged — inspect the diff; this must not move the 4.2 bundle
- [ ] **Open the editor by hand on Rails 5 and edit a block.** Zero `@javascript` scenarios means no test here can do it for you ([1.14](#114-ckeditor_rails-434-is-rails-4-only-at-runtime-and-no-declaration-says-so))

#### D′.2 — Declare the engine's assets to sprockets 3

[1.15](#115-sprockets-rails-3-requires-every-referenced-asset-to-be-declared), decided by [D7](#d7--how-to-satisfy-sprockets-rails-3). Iterate: run, read the raised asset name, declare it, run again. `cms/logo.png` is the first and will not be the last.

Wherever the declaration goes, it goes in **the engine** — [`lib/cms/engine.rb`](../../lib/cms/engine.rb) or a new `app/assets/config/manifest.js` — and **not** in `test/dummy/`. A dummy-app fix turns this phase's suite green and leaves every consuming application to hit the identical wall at [Phase 5](phase-5-the-5.0-bump.md), where it is far more expensive to diagnose.

- [ ] No `AssetNotPrecompiled` and no `couldn't find file` in the Rails 5 logs
- [ ] The declaration is in the engine — `git diff` for this stage shows nothing under `test/dummy/`
- [ ] 4.2 still green at 78.35% with cucumber 154/154. sprockets-rails 2.3.3 does not enforce the declaration, so it must be a no-op on the default bundle

#### D′.3 — Read the cucumber number

This is the first point in the phase at which the Rails 5 cucumber figure means anything. Record it in the report against Phase 0's baseline (154/154, default profile) and against the four remaining defects from Phase 2's §5 — some of those have been sitting behind *this* stage rather than behind stage A, and A′ could not have told them apart.

If the sprockets iteration goes deeper than a handful of assets, **stop and re-scope out loud** ([§6](#6-contingencies)). It is the only item in the phase with no measured upper bound, and it is a better contingency than a surprise.

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

### D6 — How far to move `ckeditor_rails`

Per [1.14](#114-ckeditor_rails-434-is-rails-4-only-at-runtime-and-no-declaration-says-so). The gem's version *is* CKEditor's version, so this is an editor upgrade wearing a dependency bump's clothes, and no test in this repository can see the difference.

**(a)** `NEXT_BOOT ? "~> 4.5" : "~> 4.3.0"` — the next bundle gets a modern editor, 4.2 is untouched. The two bundles then run two different WYSIWYG editors, which is a real divergence in the thing users actually touch.
**(b)** `"~> 4.5"` unconditionally — both bundles get the same editor, so anything the upgrade breaks in the CMS UI is caught by the 4.2 suite as well, which is the suite that is currently green. Costs a change to a bundle Phase 0 baselined, and moves `Gemfile.lock`.
**(c)** Pin the oldest release that works on Rails 5 (reported as 4.5.10) for the next bundle — the smallest possible editor jump, and it keeps the `moono` default skin that 4.16+ replaces with `moono-lisa`.

**Recommendation: (c) now, (b) at [Phase 5](phase-5-the-5.0-bump.md).** A default-skin change is a visible, user-facing difference in a CMS's editor; taking it during an upgrade means a UI regression and a Rails regression land in the same commit and get diagnosed as each other. Whichever is chosen, the by-hand editor check in D′.1 is not optional — it is the only oracle that exists.

**This needs a human** for the same reason [D1](#d1--the-migration-item-leaves-the-phase) does: it changes what the phase document says the phase contains, and it is the phase's first gem bump.

### D7 — How to satisfy sprockets-rails 3

Per [1.15](#115-sprockets-rails-3-requires-every-referenced-asset-to-be-declared).

**(a)** Add `app/assets/config/manifest.js` to the engine with `link_tree ../images` — the Rails 5+ idiom, declares the whole class at once, and it is what the engine needs at every subsequent hop anyway.
**(b)** Extend `config.assets.precompile` in [`lib/cms/engine.rb:122`](../../lib/cms/engine.rb#L122) — consistent with the eight entries already there, and it grows by one line per asset discovered.
**(c)** Set `config.assets.check_precompiled_asset = false` in the dummy app's `test.rb` — makes the suite pass today and guarantees the same failure reappears inside a consuming application at Phase 5.

**Recommendation: (a).** It is the destination, it is one file, and it fixes the class rather than the instances — which also bounds the one unbounded item in this phase. **(c) is the trap**: it converts a loud test failure into a silent production one, which is exactly the failure mode [`RAILS_UPGRADE_TEST_PRIORITY.md`](../../RAILS_UPGRADE_TEST_PRIORITY.md) ranks the whole plan by. (b) works and is more in keeping with the file, but it books another discovery round at every later hop.

### D8 — The `save!` override forwards, and that changes behaviour

Per [1.16](#116-save-is-the-same-signature-override-that-p1-2-was). Taking `(*args, &block)` and forwarding is the only signature that matches what both frameworks actually call, and it is what Phase 2 already did to `create_or_update` directly beneath it.

But it is a **behaviour change in a phase whose contract is that there are none**: autosaved children of a versioned record are validated today, in a path where Rails asked for `validate: false`, and after the fix they will not be. If any test depends on that accidental validation it will go red, and the red will be correct.

**Flagging rather than deciding.** The alternative is to leave it, note it beside the `guest_user.rb:52` sibling already recorded in [D3](#d3--guestuserupdate_attributes-becomes-an-alias), and hand both to [Phase 4](phase-4-characterization-tests.md) to characterise before either is touched — which is the more conservative reading of this phase's contract, and defensible. What is *not* defensible is leaving it undocumented: it is a live defect on the bundle that is in production today, not a Rails 5 concern.

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
| R8 | **The `ckeditor_rails` bump breaks the CMS editor** and nothing notices. Zero `@javascript` scenarios means the suite cannot see a WYSIWYG regression; a green cucumber run proves the *asset resolves*, not that the editor works. | [D6](#d6--how-far-to-move-ckeditor_rails)'s recommendation minimises the editor jump, and D′.1 requires a by-hand check. If (b) is chosen instead, the 4.2 suite becomes a second detector — which is the main argument for it. |
| R9 | **The sprockets chain is deeper than a handful of assets** and stage D′ becomes the phase. It has no measured upper bound; only the first failure has been observed. | [D7](#d7--how-to-satisfy-sprockets-rails-3)(a) closes the whole class in one file rather than one asset at a time. If it still runs long, [§6](#6-contingencies) says to re-scope out loud rather than absorb it — the phase can ship A–D and hand D′ on. |

---

## 6. Contingencies

**If stage A′ shows Rails 5 still substantially red**, the four defects from Phase 2's §5 are the next thing to read, and they are not all Phase 3 work:

- `StaleObjectError` on `Cms::Page` ×2 and `PublishableTestCase#test_publish_on_save` are plausibly downstream of the `create_or_update` arity change interacting with optimistic locking — application behaviour, in scope, but they need diagnosis before they can be scoped.
- `PortletTest#test_.blacklist` is one expectation diff. Small.
- **`couldn't find file 'ckeditor-jquery'` is now scoped** — it is [1.14](#114-ckeditor_rails-434-is-rails-4-only-at-runtime-and-no-declaration-says-so), it is a gem bump rather than a code fix, and it owns **stage D′** together with the sprockets-rails 3 problem sitting behind it ([1.15](#115-sprockets-rails-3-requires-every-referenced-asset-to-be-declared)). It accounted for 132 of the 148 cucumber failures, so **expect A′'s cucumber number to still be dominated by it**; that is not evidence stage A failed. Read the functional suite, not cucumber, to judge stage A.

**If stage D′ runs long**, it is still this phase's — the `next-rails` job cannot go green without it, and criterion 16 is the phase's purpose. But it is the one item here with no measured upper bound, so re-scope out loud rather than letting it hold the phase open silently. A–D unblock the bump on their own; D′ can be handed to [Phase 5](phase-5-the-5.0-bump.md) with an honest gap recorded, at the cost of leaving the CI job red and Phase 2's gating decision looking wrong.

**`use_route`** ([`test/support/engine_controller_hacks.rb`](../../test/support/engine_controller_hacks.rb), Phase 2 §5) is removed in 5.0 and now arrives at controllers as an ordinary request parameter. Phase 2 measured that the obvious replacement produces 16 `UrlGenerationError`s and left the finding in the module's comment. It is test-harness work, it needs a per-test-class decision about engine versus application route sets, and it has no backwards-compatible form. **Not this phase.** It will surface in stage A′; expect it and do not chase it.

**If the phase has to be cut short**, stages A through D′ are the part that unblocks the bump. E and F break at 5.1 and 6.0 and can slip to [Phase 6](phase-6-subsequent-hops.md) without blocking anything — at the cost the phase document names: debugging them simultaneously with a version change.

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

**Add two more.** The first is the phase's actual purpose and nothing above measures it; the second is what now stands in the first's way, and it has a failure mode that passes silently.

| # | Criterion | Stage | Verification |
|---|---|---|---|
| **16** | **The `next-rails` CI job is green** | G | It was made gating in Phase 2 with the explicit statement that *"CI is red on every PR until Phase 3 lands."* Turning that red green is what this phase is for, and criterion 1's "suite green on both Gemfiles" is the same claim stated less directly. The `ckeditor-jquery` asset problem is no longer an excuse for missing it — it is scoped as stage D′ |
| **17** | **The Rails 5 asset chain is clear, and the fix is in the engine** | D′ | Two halves. First: no `couldn't find file` and no `AssetNotPrecompiled` in the `Gemfile.next` functional and cucumber logs. Second, and the one that can pass wrongly: `git diff` for stage D′ touches [`lib/cms/engine.rb`](../../lib/cms/engine.rb), `app/assets/config/manifest.js` or [`browsercms.gemspec`](../../browsercms.gemspec) and **nothing under `test/dummy/`** — a dummy-app fix satisfies the first half and hands every consuming application the same failure at [Phase 5](phase-5-the-5.0-bump.md) ([D7](#d7--how-to-satisfy-sprockets-rails-3)) |

Neither is a grep over `app/` and `lib/`, and criterion 14 is not endangered by either: the `NEXT_BOOT` conditional D′.1 needs lives in the gemspec, which [1.12](#112-responders-must-be-declared-without-a-version-constraint) already establishes is outside criterion 14's scope.
