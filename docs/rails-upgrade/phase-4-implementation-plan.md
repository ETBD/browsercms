# Phase 4 — Implementation Plan

**Implements:** [`phase-4-characterization-tests.md`](phase-4-characterization-tests.md)
**Exit criteria:** all **14** live in [`phase-4-characterization-tests.md` § Exit criteria](phase-4-characterization-tests.md#exit-criteria), not in this file. This plan references them by number throughout; [§7](#7-exit-criteria-traceability) maps each to the stage that meets it.
**Entry condition:** Phase 3 complete at 14 of 14 criteria ([report](phase-3-report.md)) — `Gemfile` green at 1007 tests, 0F/0E, cucumber 154/154, line **78.37%** / branch **70.83%**; `Gemfile.next` at **10** failures across unit, functional and cucumber, and the `next-rails` job gating and red.
**Rails at the end of this phase:** `Gemfile` still 4.2.11.3 and green. `Gemfile.next` **green** — this is the phase where the `next-rails` job stops being red, and unlike Phase 3 that claim is scoped to work this phase actually owns.

Same shape as the [Phase 0](phase-0-implementation-plan.md), [Phase 1](phase-1-implementation-plan.md), [Phase 2](phase-2-implementation-plan.md) and [Phase 3](phase-3-implementation-plan.md) plans: findings first, then an ordered work stream, then the decisions that need a human.

**Local prerequisites, established during planning:** both bundles install clean under Ruby 2.7.8 / Bundler 1.17.3 with no lockfile drift (`BUNDLE_FROZEN=true bundle install`, and the same with `BUNDLE_GEMFILE=Gemfile.next`), Postgres is reachable on the socket `test/dummy/config/database.yml` expects, and the dual-boot assertion reports `Booted Rails 5.0.7.2`.

> ### Read this first
>
> Four things moved before any code was written, and two of them change what the phase is:
>
> 1. **Work item 4.1 is largely already built.** Phase 3's stage-B audit test is a 224-line, 9-test enumeration of all 29 `belongs_to` declarations, and its own closing comment says *"Phase 4 owns the permanent version of this."* What remains is one missing assertion and a criterion that needs rewriting — not a day of work. ([1.1](#11-work-item-41-is-substantially-already-built), [1.4](#14-one-declaration-has-no-assertion-and-it-is-a-dynamic-one))
> 2. **Criterion 3 cannot be met as written, and criteria 3 and 11 contradict each other.** Forcing `belongs_to_required_by_default` on is a no-op on 5.0 in the shape the phase document imagines, and raises `NoMethodError` on 4.2. Phase 3 measured this and the finding never made it back into the phase file. ([1.2](#12-criterion-3-rests-on-a-misreading-and-phase-3-already-measured-it))
> 3. **B1 — the item ranked first in the whole analysis — has a wrong premise, and the correction makes it much worse.** `ColumnDumper` was *not* removed at 5.0. The patch does not evaporate; it **wins**, with the wrong arity, against a caller that passes one argument. **Measured end to end: on the 5.0 bundle the schema dumper emits 0 of 74 tables and exits successfully.** The 4.2 control emits 73. This is not a latent risk — it is a live, total, silent failure, and it has already happened once in this repo. ([1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50), [1.6](#16-criterion-8s-guard-would-not-have-caught-15))
> 4. **One of the three "singletons" in Phase 3's residue is a nine-site class**, and the failing test is a truthiness bug rather than the cast bug it was filed as. ([1.9](#19-the-tasks_controller-failure-is-one-of-nine-sites-and-it-is-a-truthiness-bug))
>
> The net effect is that **the phase is not smaller, it is differently shaped**: less `belongs_to` work than planned, considerably more schema-dumper work, and one work item (4.0) that arrived from Phase 3 and carries the red CI job.

---

## 1. Pre-flight findings

Every measurement below was taken against this tree. Gem source references are to the installed gems (`/Users/…/gems/2.7.0/gems/`), because `vendor/bundle` is not present locally — paths in the older plans point there and no longer resolve.

### 1.1 Work item 4.1 is substantially already built

[`test/unit/belongs_to_optionality_test.rb`](../../test/unit/belongs_to_optionality_test.rb) is 224 lines and nine tests, added by Phase 3's stage B. It already does what 4.1 asks for, by a better mechanism than 4.1 proposes:

| 4.1 asks for | The audit test already does |
|---|---|
| "For each of the **29** declarations, one test that either asserts required or asserts saves-without-it" | A verdict table (`AUDIT` + `BEHAVIOR_AUDIT`) with one entry per site, and **six** invariant tests over it — every site has a verdict, every verdict names a live association, `:required` sites are backed by a presence validation *and* left bare, `:optional` sites carry `required: false` *and* are not contradicted by a presence validation |
| "Pay particular attention to the 5 injected by behaviors" | `test "userstamping and categorizing inject required: false everywhere they apply"` checks them **where they land** — `Cms::Page`, `Cms::HtmlBlock`, `Cms::Section` — not just on the behavior module |
| — | A both-bundles probe: `test "required: false adds no presence validation on either bundle"` |

The counts reconcile: `AUDIT` holds 24 entries (7 `:required`, 17 `:optional`), `BEHAVIOR_AUDIT` holds 3, and two more are declared dynamically — 29. The 7 bare plus 22 carrying `required: false` matches the [Phase 3 report's](phase-3-report.md) criterion-2 row exactly.

**What is actually left of 4.1** is [1.4](#14-one-declaration-has-no-assertion-and-it-is-a-dynamic-one) and the criterion rewrites in [1.2](#12-criterion-3-rests-on-a-misreading-and-phase-3-already-measured-it) and [1.3](#13-criterion-4s-literal-check-does-not-match-the-audit-tests-design). Budget hours, not the day the phase file implies.

### 1.2 Criterion 3 rests on a misreading, and Phase 3 already measured it

Criterion 3: *"`belongs_to_required_by_default = true` is set in the test environment — without this, criterion 4 is meaningless."* Work item 4.1 opens with the same instruction in bold.

The reasoning behind it is wrong, and the audit test's header comment documents why in detail. The flag is read inside `ActiveRecord::Associations::Builder::BelongsTo.define_validations` (`activerecord-5.0.7.2/lib/active_record/associations/builder/belongs_to.rb:122`) and its entire effect is one line — `model.validates_presence_of reflection.name, message: :required`. That runs when `belongs_to` is **called**, at class-definition time. So:

- Setting the flag in a `setup` block cannot retroactively add validations to associations already defined. **It is a no-op even on 5.0.**
- The accessor does not exist on 4.2 at all — it arrives at `activerecord-5.0.7.2/lib/active_record/core.rb:117` — so touching it **raises `NoMethodError` on the production bundle.**

Setting it in `test/dummy/config/environments/test.rb` *would* take effect on 5.0, because that runs before models autoload. But it still raises on 4.2, so it needs a version guard — and the guard would live under `test/`, which **criterion 11 forbids** (`grep -rn "NextRails" test/ spec/` stays empty). **Criteria 3 and 11 cannot both be satisfied.** [D1](#d1--criterion-3-is-replaced-by-the-audit-tests-invariant) resolves it.

Verified absent: `grep -rn "belongs_to_required_by_default" test/ spec/ lib/ config` returns **one hit, a comment** in the audit test.

### 1.3 Criterion 4's literal check does not match the audit test's design

Criterion 4: *"A test file enumerates them; the count in the test matches 29."*

The audit test enumerates by **reflection** over 15 named classes plus three behavior-injected names, which is strictly better — it catches a `belongs_to` added tomorrow, which a hardcoded list of 29 would not. But no literal `29` appears anywhere in it, so the criterion's stated check fails against a test that over-satisfies its intent. Either add a count assertion as a tripwire or amend the criterion; [D2](#d2--criterion-4-gets-a-count-tripwire-rather-than-a-rewrite) picks the former, because the count is genuinely useful as a review anchor.

### 1.4 One declaration has no assertion, and it is a dynamic one

Two of the 29 are declared dynamically, which is why `grep` cannot audit them:

- `lib/cms/behaviors/versioning.rb:115` — version → parent. **Asserted**, through `Cms::HtmlBlock::Version.reflect_on_association(:html_block)`.
- `lib/cms/behaviors/dynamic_attributes.rb:168` — `base_class`. **Not asserted anywhere.**

The audit test's comment names both as needing reflection-based assertions and then only writes one. This is the single concrete gap in 4.1, and it is the more dangerous of the two to leave: `dynamic_attributes` is applied per-model by consumers, so a downstream project on `load_defaults 5.0` is the one that finds out.

### 1.5 B1 is an arity collision, not a vanishing monkeypatch, and it is live on 5.0

This is the most consequential finding in the phase and it inverts the item's stated failure mode.

[`RAILS_UPGRADE_TEST_PRIORITY.md` §3 B1](../../RAILS_UPGRADE_TEST_PRIORITY.md) ranks [`lib/cms/extensions/active_record/connection_adapters/abstract/schema_dumper.rb`](../../lib/cms/extensions/active_record/connection_adapters/abstract/schema_dumper.rb) first in the whole analysis, on this reasoning:

> *"`ColumnDumper` was folded into `SchemaDumper` in the Rails 5.1–6.0 range… when the target module no longer exists, `module ActiveRecord::ConnectionAdapters::ColumnDumper` does not fail. It silently defines a brand-new, empty module that nothing includes. The patch evaporates."*

The ranking is right. The mechanism is wrong. Measured:

| | 4.2.11.3 | 5.0.7.2 |
|---|---|---|
| `ColumnDumper` exists | ✅ `abstract/schema_dumper.rb:8` | ✅ **still `abstract/schema_dumper.rb:8`** |
| Included by the adapter | ✅ `abstract_adapter.rb:73` | ✅ **still, `abstract_adapter.rb:71`** |
| `def column_spec` | `(column, types)` — arity **2** | `(column)` — arity **1** |
| `def prepare_column_options` | arity **2** | arity **1** |
| Caller | — | `schema_dumper.rb:140` — `@connection.column_spec(column)` |

So the module is not gone at 5.0 and the patch does not evaporate. It does the opposite: **it wins, and it wins with the wrong signature.** Measured on both load orders (patch-then-adapter, and adapter-then-patch), on 5.0:

```
column_spec now defined at: …/browsercms/lib/cms/extensions/…/schema_dumper.rb
arity: 2
```

and simulating the real call from `schema_dumper.rb:140` against an object including the module:

```
ArgumentError: wrong number of arguments (given 1, expected 2)
```

Two things close the escape hatches:

- **`PostgreSQL::ColumnDumper` does not shadow it.** `activerecord-5.0.7.2/lib/active_record/connection_adapters/postgresql/schema_dumper.rb` defines `column_spec_for_primary_key`, `prepare_column_options`, `migration_keys`, `default_primary_key?`, `schema_type` and `schema_expression` — **not `column_spec`**. So the abstract module's method, i.e. the patch's, is what the PG adapter calls.
- **Loading is unconditional.** [`lib/cms/extensions.rb`](../../lib/cms/extensions.rb) is `Dir[…/extensions/**/*.rb].each { |f| require f }`. There is no version guard and no opt-out on either bundle.

#### Confirmed end to end

Both bundles were installed and the real dumper run against the live `browsercms_test` database (74 tables), output captured to a `StringIO` so `db/schema.rb` was never touched:

| | 4.2.11.3 (control) | 5.0.7.2 |
|---|---|---|
| Tables in the database | 74 | 74 |
| `create_table` statements emitted | **73** | **0** |
| Tables reported as undumpable | 0 | **72** |
| `published` / `deleted` / `archived` columns dumped | **123** | **0** |
| Process outcome | success | **success** |

In the booted 5.0 app the live `PostgreSQLAdapter` resolves `column_spec` to the patch (`arity: 2`, `source_location` = the patch file), and every table fails the same way:

```
# Could not dump table "catalogs" because of following ArgumentError
#   wrong number of arguments (given 1, expected 2)
```

**And nothing raises.** `ActiveRecord::SchemaDumper#table` (`activerecord-5.0.7.2/lib/active_record/schema_dumper.rb:102-104`) wraps the per-table body in `begin … rescue => e` and writes the exception into the stream **as a comment**. So `rake db:migrate` on the 5.0 bundle exits 0 and writes a syntactically valid `schema.rb` in which all 74 tables are commented out.

This is worse than B1 predicted in every dimension: not partial but **total**, not loud but **silent**, and not future but **now**.

#### This resolves the §9 contradiction rather than standing against it

[`phase-3-report.md` §9](phase-3-report.md) records that `app:test:prepare` rewrote `test/dummy/db/schema.rb` during Phase 3, "dropping ~500 lines of dynamically-created test tables and reformatting it in 5.0's style," and that it was reverted. That was not a formatting difference. **That was this bug**, observed as a cosmetic artifact and filed as one. The file was reverted, so no damage persisted — but the detection was luck, and the note that came out of it ("watch `schema.rb` before every commit") treats the symptom.

So the two observations agree, and B1 is confirmed as the correct top-ranked item in the analysis — for a mechanism nobody had identified.

### 1.6 Criterion 8's guard would not have caught 1.5

Criterion 8: *"A guard test fails if `ColumnDumper` is undefined at load time. Temporarily rename the constant in the patch file; the guard test must go red."*

`ColumnDumper` **is** defined at 5.0. A guard that asserts the constant exists passes on both bundles while the dumper is broken on one of them. The criterion tests for the failure mode B1 predicted rather than the one that is actually present.

B1's own prescription is better than the criterion derived from it: *"Assert on the dumped output, not on `column_spec`'s return value — the point is to detect the patch going missing, so the test must exercise the real dumper end to end."* Follow the item, not the criterion. [D3](#d3--what-criterion-8s-guard-must-actually-assert) rewrites it.

⚠️ **And the measurement in [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50) rules out one more test shape that looks sufficient and is not.** Because `SchemaDumper#table` rescues into a comment, the dump **succeeds** while emitting nothing. So a test that asserts "dumping does not raise" passes on the broken bundle, and so does one that asserts the output is non-empty — the 5.0 dump is 234 lines of header and error comments. **The assertion has to be on dumped content**: a `create_table` count, and the boolean-default columns by name.

### 1.7 B3 / criterion 6 is partly done

[`test/unit/schema_statements_test.rb`](../../test/unit/schema_statements_test.rb) already exists with six tests over `create_content_table` / `add_content_column`:

- `:version_foreign_key` silently ignored
- non-versioned blocks create no versions table
- default versioned column created for subclasses
- non-existent models get a default versions table
- `create_content_table` makes two tables
- `add_content_column` adds to both tables

Criterion 6 wants "**every** option combination… and asserts the resulting column set on both the content table and the `_versions` table." What is missing is the `name:` option and a per-combination assertion of the full column set rather than of one column's presence. That is an extension of an existing file, not a new one.

### 1.8 B6's three questions all answer "no" — the audit is already done

B6 asks for an audit before test-writing, and budgets "a day for reading" to answer three questions about [`test/unit/behaviors/versioning_test.rb`](../../test/unit/behaviors/versioning_test.rb). Grepped:

| Question | Assertion present? |
|---|---|
| Does a failed validation produce no new version? | **No** — no assertion in the file mentions `valid` or `invalid` |
| Does `version_comment` reflect *this* save's changes? | **No** — `version_comment` appears in no assertion |
| Does a rolled-back transaction leave no orphan version row? | **No** — neither `transaction` nor `rollback` appears |

All three need writing, so the reading budget can be cut and the item becomes three concrete tests. The 96.91% line coverage on `versioning.rb` is exactly the "tested for the wrong thing" case B6 warns about, now confirmed rather than suspected.

This item also has a live claim behind it: `versioning.rb:206-225` is a comment block documenting an **observed** `save` call order, and Phase 3 changed `save!` in that same file to forward `(*args, &block)` ([Phase 3 §5](phase-3-report.md)). These three tests are the net that change should have had.

### 1.9 The `tasks_controller` failure is one of nine sites, and it is a truthiness bug

[Phase 3 §6](phase-3-report.md) files `Cms::TasksControllerTest#test_complete_no_tasks` as a singleton: *"`PG::InvalidTextRepresentation: invalid input syntax for type integer: \"\"`. Rails 5 stopped coercing `\"\"` to nil on integer casts."* The diagnosis stops one step short.

The test ([`tasks_controller_test.rb:52`](../../test/functional/cms/tasks_controller_test.rb#L52)) does `put :complete, params: {:task_ids => nil}`. The controller ([`tasks_controller.rb:21-23`](../../app/controllers/cms/tasks_controller.rb#L21)):

```ruby
def complete
  if params[:task_ids]
    Task.where(["id in (?)", params[:task_ids]]).each do |t|
```

On 4.2 the nil arrives as `nil` — falsy — and the `else` branch runs. On 5.0 it arrives as `""` — **truthy** — so the `if` branch runs and hands `""` to Postgres as an integer. The cast error is the symptom; **the guard is the defect.** `if params[:task_ids]` asks "was the key present?" when it means "is there a value?"

That pattern is not unique to this controller. Nine sites guard on the truthiness of a params value:

| Site | |
|---|---|
| [`attachments_controller.rb:13`](../../app/controllers/cms/attachments_controller.rb#L13) | `if params[:version]` |
| [`content_block_controller.rb:128`](../../app/controllers/cms/content_block_controller.rb#L128) | `if params[:version]` |
| [`content_block_controller.rb:219`](../../app/controllers/cms/content_block_controller.rb#L219) | `if params[model_form_name]` |
| [`toolbar_controller.rb:14`](../../app/controllers/cms/toolbar_controller.rb#L14) | `if params[:page_id]` |
| [`inline_content_controller.rb:20`](../../app/controllers/cms/inline_content_controller.rb#L20) | `if params[:container]` |
| [`tasks_controller.rb:22`](../../app/controllers/cms/tasks_controller.rb#L22) | `if params[:task_ids]` ← **the one the suite happens to hit** |
| [`pages_controller.rb:74`](../../app/controllers/cms/pages_controller.rb#L74) | `if params[:page_ids]` |
| [`sections_controller.rb:68`](../../app/controllers/cms/sections_controller.rb#L68) | `if params[:section_id]` |
| [`users_controller.rb:15`](../../app/controllers/cms/users_controller.rb#L15) | `unless params[:show_expired]` |

Four of the nine feed the value straight into a finder or an integer column, so they have the same shape as the failing one. **This is a Tier B silent-change item that arrived disguised as a single red test** — which is a good argument for why it belongs in this phase and not in Phase 3.

### 1.10 The missing partial is a real 4.2 bug with a one-line fix

Confirmed on both halves. [`app/views/cms/pages/_main_form.html.erb:2`](../../app/views/cms/pages/_main_form.html.erb#L2):

```erb
<%= render :partial => 'cms/shared/version_conflict_error', :locals => {…} %>
```

`app/views/cms/shared/` exists and holds `access_denied.html.erb`, `error.html.erb`, `error.xml.erb` — **no version-conflict partial**. `find app/views -name "*version_conflict*"` returns exactly two files, both under `app/views/cms/application/`. So the reference is broken on **both** bundles; 4.2 never renders that branch, and 5.0 does only because the update ahead of it fails.

Fixing it will not make the two functional failures pass — it changes what they say. That ordering matters and is easy to get backwards.

### 1.11 No eager-load test exists, and the test environment has eager loading off

`grep -rn "eager_load" test/ spec/ lib/cms/engine.rb` finds only the three dummy-app environment settings, and [`test/dummy/config/environments/test.rb:17`](../../test/dummy/config/environments/test.rb#L17) is `config.eager_load = false`. So 4.2's test must call `Rails.application.eager_load!` explicitly — which is what B10 prescribes anyway.

The surface it defends is larger than the supporting docs state. [`lib/cms/engine.rb:112-116`](../../lib/cms/engine.rb#L112) pushes **9 paths in 5 statements** (the analysis says "6 directories"):

```ruby
ActiveSupport::Dependencies.autoload_paths += %W( #{self.root}/vendor #{self.root}/app/mailers #{self.root}/app/helpers)
ActiveSupport::Dependencies.autoload_paths += %W( #{self.root}/app/controllers #{self.root}/app/models #{self.root}/app/portlets)
ActiveSupport::Dependencies.autoload_paths += %W( #{Rails.root}/app/portlets )
ActiveSupport::Dependencies.autoload_paths += %W( #{Rails.root}/app/presenters )
ActiveSupport::Dependencies.autoload_paths += %W( #{Rails.root}/app/portlets/helpers )
```

Note the last three are `Rails.root`, not `self.root` — **host application** directories, which an engine cannot see the contents of at test time. Zeitwerk has no `autoload_paths` API at all, so all nine statements are 6.0 work; this test is what will size it.

`require_dependency` is confirmed as exactly one site — [`content_types_controller.rb:1`](../../app/controllers/cms/content_types_controller.rb#L1) — and the file is 0% covered, so the eager-load test is also the only thing that will ever load it.

### 1.12 B9's four target sites are confirmed, and two are in files with no test at all

Line numbers re-verified against this tree (Phase 3 moved several):

| Site | Current line | Coverage |
|---|---|---|
| `pages_controller.rb` `strip_visibility_params` | **124-128** (was 126-128) | 3 lines untested |
| `sections_controller.rb` `delete('group_ids')` | **43** | in the 9 missed lines |
| `form_fields_controller.rb` `delete(:form_id)` | **16** | **0% file** |
| `forms_controller.rb` `delete(:new_entry)` | **33** | **0% file** |

`ls test/functional/cms/ | grep -i form` returns **nothing** — there is no functional test file for either Forms controller. Both are 0% because nothing instantiates them, so criterion 7 ("no longer 0%") needs the files created, not extended.

Two of the four sit on an authorization boundary: `strip_visibility_params` is a `before_action` on `:create`/`:update` ([`pages_controller.rb:10`](../../app/controllers/cms/pages_controller.rb#L10)) that removes fields a non-admin must not set, and `sections_controller.rb:43` drops `group_ids` unless `current_user.able_to?(:administrate)`. A `Parameters`-semantics change here fails **open**.

### 1.13 The residue reconciles to ten, and the phase-4 target is therefore ten

Recorded here because Phase 3's report said "nine" in four places and the enumeration said ten; the count has since been corrected in that report. Per-suite, against [§2](phase-3-report.md):

| Suite | Failures | Composition |
|---|---|---|
| unit | 1F / 2E | 2× `StaleObjectError` (cluster) + `test_publish_on_save` |
| functional | 0F / 3E | 2× missing partial (cluster) + `test_complete_no_tasks` |
| cucumber | 4 failed | 2× `manage_images` + 1× `sitemap/pages` (cluster) + `portlets_with_params` |

**7 cluster + 3 singletons = 10**, and the per-suite split matches the measured totals exactly.

---

## 2. Execution order

Stage A first is not the obvious choice — it is not one of the ten failures, and criterion 13 is what the phase is judged on. It goes first because **[1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50) is now a confirmed, live, silent data-corruption bug**: on the 5.0 bundle the schema dumper emits 0 of 74 tables and exits successfully. Every day it stays unfixed is a day someone can run `db:migrate` on `Gemfile.next` and commit an empty schema that looks fine in review.

Stage B does not depend on it — the test database is built from migrations, not from `schema.rb` — so this is a judgement about severity, not sequencing. If you want criterion 13 moving sooner, A.2 alone (the one-line scope fix) can land first and A.3/A.4's tests can trail stage B. **What must not happen is A.2 trailing the phase.**

| Stage | Work item | Why here |
|---|---|---|
| **A** | B1 / criterion 8 | Settles [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50). Until this is known, no 5.0 number is trustworthy |
| **B** | **4.0** | The ten failures. Owns criterion 13 and the red CI job. Longest stage; starts as soon as A clears the ground |
| **C** | 4.2 | The eager-load test. One hour, largest signal-per-hour in the plan, and independent of everything else — do it while B is still being diagnosed |
| **D** | 4.1 | `belongs_to` — close the [1.4](#14-one-declaration-has-no-assertion-and-it-is-a-dynamic-one) gap and land the criterion rewrites. Small |
| **E** | 4.3 | `create_content_table` option matrix. Extends an existing file |
| **F** | 4.4 | `Parameters` on the four uncovered sites. Creates two test files that do not exist |
| **G** | 4.6 | B6's three versioning tests. The audit is already done ([1.8](#18-b6s-three-questions-all-answer-no--the-audit-is-already-done)) |
| **H** | 4.5, 4.7 | Schema-dumper end-to-end assertion (folded into A's fix), B7 `publish!`, B8 `default_scope` |
| **I** | — | Exit: both suites, coverage on a cleared resultset, criteria table |

**Run the 4.2 suite after every stage, not at the end.** Phase 3's deviation 8 is the cautionary tale: a "pure rename" broke three 4.2 tests because they were mocha expectations on the renamed method, and it was only caught because the plan said to re-run. This phase writes tests that assert on framework internals, which is the same category of fragility.

---

## 3. Stage detail

### A — Settle the schema-dumper contradiction and fix B1

**A.1 — ✅ Done during planning. The dumper is broken on 5.0; see [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50).** Result: 0 of 74 tables dumped, 72 reported undumpable in comments, process exits 0. The 4.2 control emits 73 tables and 123 boolean-default columns. `db/schema.rb` was not touched (output captured to a `StringIO`). Both bundles are now installed, and the dual-boot assertion reports `Booted Rails 5.0.7.2`.

Kept below for the record, and because the same commands are how you verify A.2's fix:

```bash
BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test bundle exec rake db:drop db:create:all db:install
BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test bundle exec rake db:migrate   # this dumps
git diff --stat test/dummy/db/schema.rb
```

The outcome was the third of the three this stage was scoped against — *"dump succeeds but the output is short on tables"* — in its most extreme form: short by **all** of them. Treat any 5.0 `schema.rb` produced before A.2 lands as worthless rather than merely suspect.

**The ten failures in stage B are not affected by this.** The test database is built by `db:install` from migrations, not from `schema.rb`, so the schema in the database is correct even though the dumped file is not. A and B are independent; A goes first because it is the larger defect, not because B depends on it.

⚠️ **Do this on a clean tree and revert `test/dummy/db/schema.rb` afterwards.** [Phase 3 §9](phase-3-report.md) warns that the suite rewrites this file; that warning applies double to a stage whose whole purpose is to run the dumper.

**A.2 — Fix the patch.** The patch exists to work around a Ruby 2.7 frozen-string crash in **4.2's** `column_spec`, which mutated option strings in place with `String#insert`. 5.0's implementation already builds a new string (`Hash[prepare_column_options(column).map { |k, v| [k, "#{k}: #{v}"] }]`), so **5.0 does not need the patch at all.** The fix is to stop applying it there. See [D4](#d4--how-to-scope-the-schema-dumper-patch) for the mechanism — it is the one place in this phase where a version branch is arguably correct, and criterion 11 scopes only `test/` and `spec/`.

**A.3 — Write the end-to-end assertion** (criterion 9, and B1's actual prescription). Dump the schema for a content table and assert the output contains `published`, `deleted` and `archived` with their defaults. Assert on the **dumped string**, not on `column_spec`'s return value. This is the test that detects the patch being wrong in either direction, on either bundle.

**A.4 — Write the guard, and prove it guards** (criterion 8, as rewritten by [D3](#d3--what-criterion-8s-guard-must-actually-assert)). Assert the *signature* the patch expects is the signature the framework calls with — not that a constant exists. Then break it deliberately and watch it go red, per the criterion's own instruction, which is the half of criterion 8 that was always right.

- [x] A real 5.0 dump has been run and its outcome written into the report — [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50)
- [ ] `test/dummy/db/schema.rb` is unchanged in `git status`
- [ ] The dumped-output test asserts **content** — a `create_table` count and the boolean-default columns by name — not merely that the dump did not raise
- [ ] It passes on **both** bundles, and has been seen to fail on 5.0 with A.2 reverted
- [ ] The guard has been seen red

### B — The ten Rails 5 failures (work item 4.0)

**Characterize before fixing.** Every one of these is a Rails 5 behaviour difference in application code, so the first question is always "what does 4.2 do here, and is that asserted anywhere?" A fix that greens 5.0 by changing 4.2 behaviour is a regression in what ships — criterion 14 is what catches it.

**B.1 — The cluster (7 of 10). Diagnose the optimistic-locking difference first.** Four masks, one cause: 2× `StaleObjectError` on `Cms::Page` (unit), 2× missing partial (functional), 2× `manage_images` and 1× `sitemap/pages:19` (cucumber). Phase 3 ruled it out against its own `save!` change with a control run, so it is pre-existing. Start at the unit failures — they are the shortest path to the mechanism. Do **not** start at the cucumber scenarios.

⚠️ The `manage_images` failures **read backwards**: [`image_steps.rb:1-9`](../../features/step_definitions/image_steps.rb#L1) has expected and actual reversed (`expect(section_name).to eq(image.parent.name)`). Decoded, they say the update did not take. Fixing the step definitions' argument order is worth doing while here, but is not the failure.

**B.2 — Fix the partial path** ([1.10](#110-the-missing-partial-is-a-real-42-bug-with-a-one-line-fix)). `'cms/shared/version_conflict_error'` → `'cms/application/version_conflict_error'`. Then write a test that renders that branch on **4.2**, where it has never run — that is the characterization, and it is worth having independently of the upgrade. Expect the functional failures to *change message* rather than pass.

**B.3 — The truthiness class** ([1.9](#19-the-tasks_controller-failure-is-one-of-nine-sites-and-it-is-a-truthiness-bug)). Characterize first: what should `complete` do with a blank `task_ids`? The existing test says "redirect to dashboard with `flash[:error]`", which is the 4.2 behaviour and is the answer. Then `if params[:task_ids]` → `if params[:task_ids].present?`. Then **audit the other eight sites** and fix the four that feed a finder or an integer column. See [D5](#d5--how-far-to-take-the-truthiness-audit) for scope.

**B.4 — `PublishableTestCase#test_publish_on_save`.** `Expected false to be truthy`, surviving from Phase 2's §5. Re-read it now that `save!` forwards `(*args, &block)` — Phase 3's one behaviour change lands in this area and may have moved it. Related to stage G; if G's tests are written first this may resolve as a side effect, in which case say so rather than claiming a fix.

**B.5 — `portlets_with_params.feature`.** The portlet renders the page layout instead of its own `"I worked"` content. Least understood of the ten and the least connected to anything else; schedule it last so the others' findings are available.

- [ ] All ten resolved, `next-rails` green
- [ ] Every one has a 4.2-asserting test that passes on the `Gemfile` bundle (criterion 14)
- [ ] The 4.2 suite is still 1007 / 0F / 0E

### C — The eager-load test (work item 4.2)

One test. `Rails.application.eager_load!`, then assert every expected `Cms::` constant resolves. Runs in the default suite, not a manual task (criterion 5).

Given [1.11](#111-no-eager-load-test-exists-and-the-test-environment-has-eager-loading-off), two practical notes:

- The test environment has `eager_load = false`, so call `eager_load!` explicitly rather than flipping the config — flipping it would slow every test in the suite and change what other tests exercise.
- **Expect this to be red the first time.** It has never been run. Three known-suspicious mechanisms are in its path: [`lib/cms/behaviors.rb:32`](../../lib/cms/behaviors.rb#L32) and [`lib/cms/concerns.rb:6`](../../lib/cms/concerns.rb#L6) build class names from filenames with `File.basename(b, ".rb").camelize` then `constantize` at load time, and [`lib/browsercms.rb:36-67`](../../lib/browsercms.rb#L36) does `ActiveRecord::Base.send(:include, …)` at require time. If it is red, **that is the test working** — record what it found, because that output is what scopes the 6.0 hop.

- [ ] `Rails.application.eager_load!` appears in a test that runs in the default suite
- [ ] Green on both bundles, or its findings are written into the report

### D — `belongs_to`: close the gap (work item 4.1)

Small, given [1.1](#11-work-item-41-is-substantially-already-built).

- [ ] **Add the `dynamic_attributes.rb:168` reflection assertion** ([1.4](#14-one-declaration-has-no-assertion-and-it-is-a-dynamic-one)), mirroring the versioning one. This is the only genuinely missing test in the item.
- [ ] **Add the count tripwire** ([D2](#d2--criterion-4-gets-a-count-tripwire-rather-than-a-rewrite)): assert `AUDIT.size + BEHAVIOR_AUDIT.size + 2 == 29`, with a comment saying what the 2 are. Cheap, and it makes criterion 4's stated check literally true.
- [ ] **Rewrite the audit test's closing comment.** It currently says "Phase 4 owns the permanent version of this" — once this stage lands, this *is* the permanent version, and the comment should say so.
- [ ] **Do not** set `belongs_to_required_by_default` anywhere. [D1](#d1--criterion-3-is-replaced-by-the-audit-tests-invariant) is the reasoning; record it in the report so it does not get re-proposed at 5.1.

### E — `create_content_table` option matrix (work item 4.3)

Extend [`test/unit/schema_statements_test.rb`](../../test/unit/schema_statements_test.rb) rather than adding a file ([1.7](#17-b3--criterion-6-is-partly-done)).

- [ ] One test per option combination — `versioned: true/false` × `name: true/false`
- [ ] Each asserts the **full column set** on both the content table and the `_versions` table, not the presence of one column
- [ ] Note in a comment that this DSL is the blast-radius item — every migration in this engine and in every downstream project — so the test's job is to fail at *test* time rather than in someone's deploy

### F — `Parameters` on the four uncovered sites (work item 4.4)

Per [1.12](#112-b9s-four-target-sites-are-confirmed-and-two-are-in-files-with-no-test-at-all), two of the four need a test **file** created.

- [ ] `test/functional/cms/form_fields_controller_test.rb` — new file, covering `:16`
- [ ] `test/functional/cms/forms_controller_test.rb` — new file, covering `:33`
- [ ] `pages_controller.rb:124-128` — `strip_visibility_params`. Assert the stripped keys are absent from the **saved record**, not from the params hash. This is authorization logic; test it as such
- [ ] `sections_controller.rb:43` — assert `group_ids` survives for an administrator and is dropped for a non-administrator. Both directions, or the test proves nothing
- [ ] **Do not** test the six covered sites. `content_controller.rb:72` is hit 153× and `path_helper.rb:33-36` 49× — CI is already the detector and the phase document excludes them explicitly

Criterion 7 wants both Forms controllers off 0%. Check the coverage report, not the test count.

### G — The versioning call-chain tests (work item 4.6)

The audit is done ([1.8](#18-b6s-three-questions-all-answer-no--the-audit-is-already-done)) and all three answers are "no", so this is three tests:

- [ ] A failed validation produces **no** new version row
- [ ] `version_comment` reflects the changes from *this* save
- [ ] A rolled-back transaction leaves **no** orphan version row

Write the audit's outcome down as well as the tests (criterion 10 asks for the three questions answered yes/no in a committed note or in test comments). The answers are all "no" and that is worth stating plainly — it means `versioning.rb`'s 96.91% line coverage was measuring the wrong thing, which is this phase's whole thesis in one example.

These also belong to Phase 3's `save!` change. If B.4 is still open when this stage lands, re-check it here.

### H — The rest of Tier B (work items 4.5, 4.7)

- [ ] **4.5 schema dumper** — folded into [A.3](#a--settle-the-schema-dumper-contradiction-and-fix-b1); nothing separate to do
- [ ] **B7 `publishing.rb`** — assert `publish!` flips `published` in the database for versioned and non-versioned models, read back through a **fresh query**, not the in-memory object. `connection.quote(value, column)`'s two-argument form is deprecated and removed at some later hop; asserting behaviour rather than API shape means the test survives the change
- [ ] **B8 `soft_deleting.rb`** — assert `deleted` records are excluded by default, included under `unscoped`, and that the default scope composes with `where`. The startup `rescue` is Zeitwerk-sensitive; stage C's eager-load test is the other half of this item's defence
- [ ] **B4 Paperclip is out of scope** — the phase document says validation tests only, no replacement. Do not start it here

### I — Exit

- [ ] Full chain on **both** bundles
- [ ] Coverage on a **cleared** `coverage/.resultset.json` — line ≥ 78.37%, branch ≥ 70.83%. Phase 3's floors, and `COVERAGE_MINIMUM_BRANCH` is gating, so a drop fails the build rather than the review
- [ ] `grep -rn "NextRails" test/ spec/` empty (criterion 11)
- [ ] `git status` clean of `test/dummy/db/schema.rb` — check this before **every** commit in this phase, not just at exit
- [ ] Rewrite the [`ci.yml`](../../.github/workflows/ci.yml) `next-rails` comment: it currently explains why the job is red and gating, and that will be wrong once it is green
- [ ] Update [`README.md`](README.md) — Phase 4 status, and Phase 0's criteria 1-2, which unblock the moment this job goes green
- [ ] Write `phase-4-report.md`. It is the record, not this file

---

## 4. Decisions

### D1 — Criterion 3 is replaced by the audit test's invariant

**The problem:** criterion 3 asks for `belongs_to_required_by_default = true` in the test environment. Per [1.2](#12-criterion-3-rests-on-a-misreading-and-phase-3-already-measured-it) it is a no-op in a `setup` block on 5.0, raises `NoMethodError` on 4.2, and the only shape that works — the dummy app's `test.rb` — needs a version guard under `test/`, which criterion 11 forbids.

**Options:** (a) strike it; (b) set it in `test/dummy/config/environments/test.rb` behind a guard and amend criterion 11 to exempt `test/dummy/config/`; (c) replace it with the invariant the audit test already enforces.

**Recommendation: (c).** The criterion's stated purpose is "without this, criterion 4 is meaningless" — it wants criterion 4 to be *falsifiable*. The audit test achieves that a different and better way: every site carries a verdict, and each verdict is checked against the loaded class from both directions, so a wrong verdict fails on both bundles without the flag existing at all. Replace criterion 3 with: *"the audit is falsifiable — adding a `belongs_to` with no verdict fails a test, and contradicting a verdict fails a test."* That is met today and stays met.

(b) is defensible if someone wants the real 5.0 flag exercised, and it would be genuinely stronger. It is also a `test/dummy` config change that only ever runs on one bundle, and Phase 3's criterion 17 exists precisely because `test/dummy` fixes do not travel to consuming applications. **Not worth the exception.** Record the reasoning either way, because this will look like an oversight to the next reader.

### D2 — Criterion 4 gets a count tripwire rather than a rewrite

Criterion 4's "the count in the test matches 29" does not literally hold ([1.3](#13-criterion-4s-literal-check-does-not-match-the-audit-tests-design)). The reflection-based enumeration is better than a hardcoded list and should not be replaced by one. But the criterion's instinct — a reviewer can check one number — is worth keeping, so add the assertion rather than amending the criterion. One line, and it fails loudly if a declaration appears or disappears without the audit being revisited.

### D3 — What criterion 8's guard must actually assert

Per [1.6](#16-criterion-8s-guard-would-not-have-caught-15), "fails if `ColumnDumper` is undefined" tests for a failure mode that is not present. The guard must assert the **contract between the patch and the framework**: that the arity the patch defines is the arity the caller uses. Concretely — assert `ColumnDumper.instance_method(:column_spec).arity` matches what the running Rails version's `SchemaDumper` calls with, and fail with a message naming both.

Keep criterion 8's second half exactly as written. "A guard test that has never been seen to fail is not a guard" is right, and this guard is more worth breaking-and-watching than the original, because it is now guarding something real.

### D4 — How to scope the schema-dumper patch

**Needs a human.** The patch is a Ruby 2.7 frozen-string workaround for 4.2 only ([A.2](#a--settle-the-schema-dumper-contradiction-and-fix-b1)); 5.0's implementation does not have the bug and does not want the override.

**Options:**

| | Approach | Cost |
|---|---|---|
| (a) | Guard the patch on the Rails version — apply only below 5.0 | A version conditional in `lib/`, which reads against the spirit of "no version branches" even though criterion 11 scopes only `test/`/`spec/` |
| (b) | Make the patch signature-compatible with both — `def column_spec(column, types = nil)` and branch internally | One method, no load-time conditional, but the method now has two behaviours and a reader has to know why |
| (c) | Delete the patch and pin Ruby's frozen-string behaviour another way | Smallest surface, but re-opens a bug that was already fixed once, on the bundle that is in production |

**Recommendation: (a),** with the version check on `ActiveRecord::VERSION::MAJOR` rather than `NextRails.next?` — the patch is reacting to the *framework's* implementation, not to which bundle is booting, and those are different questions that happen to coincide right now. Phase 3 set the precedent for a non-`NextRails` conditional when the thing being branched on is not the dual-boot state (the gemspec's `NEXT_BOOT`).

Whichever is chosen: **the patch's comment must say why the branch exists**, or the next upgrader deletes it. And criterion 11's grep must stay empty — none of these options put anything in `test/` or `spec/`.

### D5 — How far to take the truthiness audit

[1.9](#19-the-tasks_controller-failure-is-one-of-nine-sites-and-it-is-a-truthiness-bug) found nine sites; one is red.

**Options:** (a) fix only `tasks_controller.rb:22`; (b) fix all nine; (c) fix the four that feed a finder or an integer column, characterize the rest.

**Recommendation: (c).** (a) leaves eight known instances of a defect that is red in CI today — that is the "known hole vs unknown hole" distinction Phase 0 drew, on the wrong side of it. (b) is a nine-site behaviour change in a phase whose contract is characterization, and five of the nine have no test that would notice a mistake. (c) fixes what can fail the same way and writes the rest down.

**This one deserves a second opinion** — it is a judgement about how much unrelated-but-identical breakage to absorb into a phase, which is the same call Phase 3 made about `GuestUser` and deliberately escalated rather than resolving alone.

### D6 — Does Phase 4 fix the cluster, or only characterize it?

Work item 4.0 says "characterize before fixing", which implies both. Worth stating explicitly, because the cluster is a genuine Rails 5 semantic difference in optimistic locking and the fix might be larger than this phase wants.

**Recommendation: fix it, and hold the line at 4.2 behaviour.** Criterion 13 requires the job green, so characterizing without fixing does not close the phase. But if the fix turns out to require changing what 4.2 does, **stop and escalate** — that is a Phase 5 decision (it is a behaviour change that ships), not a Phase 4 one. Criterion 14 is the tripwire: every fix needs a 4.2-asserting test that passes on the `Gemfile` bundle.

### D7 — ~~What happens if stage A finds the dumper working~~ — resolved

**Struck. Settled by measurement during planning** ([1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50)): the dumper is broken on 5.0, totally and silently. No decision needed.

Kept as a row rather than deleted because its reasoning is what the stage-A test has to encode: *"'it seemed fine' is exactly what that failure looks like from the outside."* That turned out to be literally true — the dump exits 0 and writes a valid file. Any test weaker than an assertion on dumped content reproduces the same blind spot.

---

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| **R1** | 🔴 **`test/dummy/db/schema.rb` gets committed with every table commented out.** Confirmed live in [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50): any `db:migrate` on the 5.0 bundle rewrites the file with 0 of 74 tables and **exits successfully**. It nearly happened once already ([§9](phase-3-report.md)). Committing it would break every developer's database and every downstream CI run, and the commit would look clean | Three layers, because the failure is silent: (1) check `git status` before **every** commit, not at exit; (2) land A.2 early, which removes the cause; (3) A.3's content assertion, which is the only thing that would catch a regression automatically. Until A.2 lands, **do not run `db:migrate` on `Gemfile.next`** — use `db:install`, or capture the dump to a `StringIO` as the planning run did |
| **R2** | **A fix greens 5.0 by changing 4.2.** The cluster is in save/locking, the highest-traffic path in the engine | Criterion 14, and [D6](#d6--does-phase-4-fix-the-cluster-or-only-characterize-it)'s escalation rule. Re-run the 4.2 suite after every stage |
| **R3** | **The eager-load test is red and its findings are large.** It has never been run, and three known-suspicious load-time mechanisms sit in its path | [Stage C](#c--the-eager-load-test-work-item-42) treats red as success. If the findings are big, they are 6.0 scope — record and move on, do not fix Zeitwerk here |
| **R4** | **[D4](#d4--how-to-scope-the-schema-dumper-patch)'s version branch reads as a violation.** A reviewer sees a Rails-version conditional in `lib/` in a phase that forbids version branches | The distinction is real and must be written into the patch's comment: it branches on the *framework's implementation*, not on which bundle is booting. Criterion 11's grep stays empty either way |
| **R5** | **Criterion 14 is unfalsifiable if written loosely.** "Was it characterized first?" is a claim about process, not about the tree | Make it checkable: for each of the ten, name the test and show it passing on the `Gemfile` bundle. A test that only runs on `Gemfile.next` does not satisfy it |
| **R6** | **The two new Forms test files raise coverage and mask a drop elsewhere.** Aggregate coverage can rise while a file regresses | Measure on a cleared resultset, and check the two Forms controllers specifically (criterion 7) rather than reading the aggregate |
| **R7** | **B.2's partial fix is mistaken for a cluster fix.** It changes the functional failures' message without passing them | Stated in [B.2](#b--the-ten-rails-5-failures-work-item-40). Fix the partial *after* the locking diagnosis is understood, not before |

---

## 6. Contingencies

**If the cluster's fix requires changing 4.2 behaviour** — stop, write up the choice, and take it to Phase 5. Criterion 13 goes unmet and the job stays red, which is the same outcome Phase 3 reached honestly. Do not change what ships to turn a CI job green.

**If stage A finds the dumper broken on 5.0 and the fix is not backwards-compatible** — that is a genuine surprise worth escalating rather than absorbing. The patch is a workaround for a bug in a Ruby/Rails combination that is on its way out; "delete it at the 5.0 bump" may beat "branch it now."

**If `portlets_with_params` resists diagnosis** — it is the least-connected of the ten and the only one with no hypothesis attached. Time-box it. If it does not yield, tag it and record the number, the way Phase 0 handled `@cli`: a documented, tagged, counted failure is a known hole. But note that criterion 13 wants the job **green**, so a tagged scenario has to be excluded from the gating profile deliberately and said out loud — not quietly.

**If the eager-load test cannot be made green on either bundle** — it still ships, red or excluded, with its output recorded. Its value is the inventory it produces for the 6.0 hop, and that value does not depend on it passing today.

---

## 7. Exit criteria traceability

Criteria as they stand in [`phase-4-characterization-tests.md`](phase-4-characterization-tests.md) after Phase 3's handoff, with the two amendments this plan proposes marked.

| # | Criterion | Stage | Verification |
|---|---|---|---|
| 1 | Suite green on both Gemfiles | B, I | Both CI jobs |
| 2 | Coverage at or above Phase 2, branch reported | I | Cleared resultset; line ≥ 78.37%, branch ≥ 70.83% |
| 3 | ~~Flag set in the test environment~~ → **audit is falsifiable** | D | [D1](#d1--criterion-3-is-replaced-by-the-audit-tests-invariant). ⚠️ **Amended** — the original cannot be met; see [1.2](#12-criterion-3-rests-on-a-misreading-and-phase-3-already-measured-it) |
| 4 | All 29 have an explicit test; count matches 29 | D | The audit test's six invariants + the count tripwire ([D2](#d2--criterion-4-gets-a-count-tripwire-rather-than-a-rewrite)) |
| 5 | Eager-load test exists and passes | C | `Rails.application.eager_load!` in the default suite |
| 6 | `create_content_table` exercised with every option combination | E | Column sets asserted on both tables, per combination |
| 7 | Four `Parameters` sites tested; both Forms controllers off 0% | F | Coverage report, not test count |
| 8 | Guard test, **proven to guard** | A.4 | [D3](#d3--what-criterion-8s-guard-must-actually-assert). ⚠️ **Amended** — asserts the signature contract, not the constant; see [1.6](#16-criterion-8s-guard-would-not-have-caught-15) |
| 9 | Schema dump asserted end-to-end for boolean-default columns | A.3 | Assert on the dumped **content** — `create_table` count and the named boolean columns. Asserting "does not raise" or "output is non-empty" both pass on the broken bundle ([1.6](#16-criterion-8s-guard-would-not-have-caught-15)) |
| 10 | B6 audit written down, three questions answered | G | Already answered in [1.8](#18-b6s-three-questions-all-answer-no--the-audit-is-already-done) — carry the answers into the report |
| 11 | Every new test is a characterization test | I | `grep -rn "NextRails" test/ spec/` empty |
| 12 | No test written for a loud failure | I | Review: nothing new for `*_filter`, `update_attributes`, `File.exists?` |
| 13 | **The gating `next-rails` job is green** | B | All ten resolved. Arrived from Phase 3 as its criterion 16 |
| 14 | **Each of the ten characterized before it was fixed** | B | Per failure, a named test asserting 4.2 behaviour, passing on the `Gemfile` bundle ([R5](#5-risks)) |

**A note on criteria 3 and 8.** Both are amended by this plan rather than met, and both amendments came out of measurement — 3 from Phase 3's stage-B work, 8 from [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50). That is two of fourteen criteria rewritten before the phase starts, which is worth pausing on: it is the same pattern as Phase 3, where measurement moved four work items and struck one. **The phase documents were written before anything ran, and they are hypotheses.** Amend them in the open, with the evidence attached, and the record stays trustworthy. What must not happen is a criterion being quietly reinterpreted to something achievable.
