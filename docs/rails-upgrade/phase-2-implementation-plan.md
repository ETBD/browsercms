# Phase 2 — Implementation Plan

**Implements:** [`phase-2-harness-migration.md`](phase-2-harness-migration.md)
**Entry condition:** Phase 1 complete — `Gemfile.next` resolves to 5.0.7.2 and boots; the 4.2 bundle is green at 75.82% ([`phase-1-gem-report.md`](phase-1-gem-report.md)).
**Rails at the end of this phase:** `Gemfile` still 4.2.11.3 and still green. The suite runs *and passes* on `Gemfile.next`, and its CI job stops being allowed to fail. *(Outcome: the first half held; the suite runs on `Gemfile.next` but does not yet pass. See the status block below.)*

Same shape as the [Phase 0](phase-0-implementation-plan.md) and [Phase 1](phase-1-implementation-plan.md) plans: findings first, then an ordered work stream, then the decisions that need a human.

> ### Status: applied — 11 of 12 exit criteria met
> **All seven stages have been implemented.** The 4.2 suite is green at exit 0 with
> 996 tests and cucumber 154/154; on Rails 5 the unit suite went from 323 errors to 3
> and cucumber from "does not load" to 154 scenarios collected.
>
> **Criterion 3 is not met and could not have been** — five *application* defects
> remain on Rails 5, and no harness work reaches them ([1.4](#14-exit-criterion-3-is-unreachable-inside-this-phases-own-scope)
> said as much before any code was written). The `next-rails` CI job was made gating
> anyway, deliberately, so it is **red until Phase 3 lands**.
>
> **This document is the plan as it was written, and it was wrong in six places** —
> two of which broke the 4.2 suite before being caught. Do not read the sections below
> as a description of what was built. In particular:
> [B.2](#b2--requires-and-constants)'s instruction to drop `require 'minitest/unit'`
> is unimplementable as stated; [B.3](#b3--static-attributes-50-sites-reviewed-not-sedd)
> undercounts by two and misses factory_bot 5's association-strategy change;
> [C](#c--controller-test-api-22) does not know that `EngineControllerHacks` exists,
> which is why the shim did not fire on the first attempt; and stage
> [E](#e--cucumber-stack-and-housekeeping-24--25) misses that Rails 5.0 removed
> `Kernel#silence_stream`, which was the single thing stopping cucumber from loading.
>
> **[`phase-2-harness-report.md`](phase-2-harness-report.md) is the record** — the
> measurements, the six corrections, and the five remaining defects by name.

---

## 1. Pre-flight findings

Measured against the working tree at `29b7f92e`, with a confirming full run of the 4.2 bundle first: **exit 0, cucumber 154/154, coverage 75.82%** — identical to the Phase 0 baseline, so everything below is measured from a known-good starting point.

The phase document's [re-scope note](phase-2-harness-migration.md) already retired the Poltergeist migration and the forced-gem-bump list. Four further findings change work items rather than just shrinking them.

### 1.1 The phase doc's central claim about controller tests is wrong

Work item 2.2 says: *"**Rails 4.2 accepts the keyword form**, so this is a safe pre-emptive change with no dual-boot conditional."*

**It does not.** [`actionpack-4.2.11.3/lib/action_controller/test_case.rb:595-602`](../../vendor/bundle/gems/actionpack-4.2.11.3/lib/action_controller/test_case.rb#L595):

```ruby
def process(action, http_method = 'GET', *args)
  ...
  parameters, session, flash = args
```

Three positional slots and no keyword handling anywhere in the file. On 4.2, `get :show, params: {id: 5}` sets `params[:params][:id]` — the controller never sees `:id`, and the test fails in a way that looks like an application bug.

**And the inverse is also true, which is the more useful half.** Rails 5.0 still accepts the *positional* form, via [`actionpack-5.0.7.2/lib/action_controller/test_case.rb:641-663`](../../vendor/bundle/gems/actionpack-5.0.7.2/lib/action_controller/test_case.rb#L641):

```ruby
def process_with_kwargs(http_method, action, *args)
  if kwarg_request?(args)
    ...
  else
    non_kwarg_request_warning if args.any?
```

So the honest version of the compatibility table is:

| Form | 4.2.11.3 | 5.0.7.2 | 5.1+ |
|---|---|---|---|
| `get :show, id: 5` | ✅ only this | ⚠️ deprecated | ❌ removed |
| `get :show, params: {id: 5}` | ❌ silently wrong | ✅ | ✅ only this |

**Two consequences.** First, the 89 conversions are **not required by this hop at all** — they are the first blocker of hop 2 (5.1), alongside `cucumber-rails`. Second, doing them now cannot be unconditional, because no single form works on both versions.

Resolution in [2.2](#c--controller-test-api-22).

### 1.2 `serve_static_assets` has no cross-version replacement — but it has a better fix

Work item 2.3 says rename it to `config.public_file_server.enabled`. That key **does not exist on Rails 4.2**:

| Rails | Key | Framework default |
|---|---|---|
| 4.1 and earlier | `serve_static_assets` | — |
| **4.2.11.3** | `serve_static_files` (`serve_static_assets` is a deprecated alias) | `true` — [`configuration.rb:30`](../../vendor/bundle/gems/railties-4.2.11.3/lib/rails/application/configuration.rb#L30) |
| **5.0.7.2** | `public_file_server.enabled` (both older names removed) | `true` — [`configuration.rb:33`](../../vendor/bundle/gems/railties-5.0.7.2/lib/rails/application/configuration.rb#L33) |

The rename as written would need a version conditional. But **both frameworks already default it to `true`**, and both dummy-app sites set it to `true` — so they set the default and can simply be **deleted**. No conditional, no behaviour change on either version. The doc reached for a rename where a deletion is available.

Same file, one the doc misses: `test/dummy/config/environments/test.rb:12` sets `config.static_cache_control`, which 5.0 deprecates in favour of `public_file_server.headers` and which likewise has no 4.2 equivalent under the new name. Delete it too — a `max-age` header on static assets in the *test* environment buys nothing.

### 1.3 The site counts, re-measured

| Item | Doc says | Measured | Note |
|---|---|---|---|
| positional controller calls | 88 | **89 live, in 9 files**, + 2 in comments | Comments are `pages_controller_test.rb:207,210`. The doc's grep counted them and missed one live site. |
| positional *integration* calls | not mentioned | **1** — [`test/test_helper.rb:209`](../../test/test_helper.rb#L209) | In `Cms::IntegrationTestHelper`, which is **defined and never included anywhere**. Dead code that the doc's `test/`-wide grep pattern could not match. See [D3](#d3--cmsintegrationtesthelper). |
| `mocha` call sites to migrate | 109 | **1 require line each** in `test/test_helper.rb:13` and `spec/minitest_helper.rb:8` | Already corrected by Phase 1. The 109 is the `expects`/`stubs`/`mock` API surface, which survives the rename untouched. |
| `factory_girl` references | 42 | **60**, in 14 code files (+ 3 planning docs, 3 lockfiles) | |
| `assert_template` / `assigns` | 19 / 11 | **19 / 11** ✅ | |
| `Devise::TestHelpers` | 1 | **1** ✅ | |
| `@javascript` tags / Capybara drivers | 0 / commented out | **0 / commented out** ✅ | Confirmed again; nothing to migrate. |

### 1.4 Exit criterion 3 is unreachable inside this phase's own scope

Criterion 3 asks for a green suite on `Gemfile.next`. Phase 1 measured 754 unit tests → 2 failures, 323 errors there, and **322 of those 325 are two application fixes that belong to [Phase 3](phase-3-backwards-compatible-fixes.md)**:

- 320 × `ArgumentError` from the `create_or_update` arity at [`versioning.rb:230`](../../lib/cms/behaviors/versioning.rb#L230)
- 2 × `NameError: uninitialized constant HTML` from [`content_filter.rb:12`](../../lib/cms/content_filter.rb#L12)

No amount of harness work moves those. Phase 2's "explicitly not in this phase" says *"No application code changes beyond what the harness needs to boot"* — but the harness already boots; what it lacks is a **readable result**, and 320 identical errors are not one. Phase 3's own header agrees: *"Do the arity fix first and re-measure before scoping the rest of this phase."*

**Resolution: land those two fixes first, as a declared prerequisite, and say so.** Both are backwards-compatible, both are two lines, and Phase 3 keeps ownership of the other ~94 changes. This is recorded as a deliberate deviation, not an oversight — see [D1](#d1--borrowing-two-fixes-from-phase-3).

### 1.5 The simplecov bump is a change to the measuring instrument

Work item 2.1 asks for a simplecov bump with branch coverage enabled. Exit criterion 1 asks that coverage still read the Phase 0 baseline. **These interact**: simplecov 0.12 → 0.22 changes how lines are counted and rewrites `.resultset.json` / `.last_run.json`, so the reported percentage can move without a single test being lost.

Worse, it breaks the gate outright. [`coverage:check`](../../lib/tasks/core_tasks.rake#L43) reads `result.covered_percent`; from simplecov 0.18 that key is gone, replaced by `result.line` (and `result.branch` once branch coverage is on). Left alone, the gate would `KeyError` rather than fail-open — loud, at least, but still broken.

So this bump goes **last and alone**, in its own commit, with the coverage number measured immediately before and after. That is the only sequence in which criterion 1 stays interpretable: a change in the number across a commit that touches nothing but the coverage tool is an instrument change; a change across a commit that touches tests is a lost test.

---

## 2. Execution order

| Stage | Work item | Produces | Size |
|---|---|---|---|
| **A** | *prereq* ([1.4](#14-exit-criterion-3-is-unreachable-inside-this-phases-own-scope)) | The two Phase-3 fixes; a re-measured Rails 5 error count that is worth reading | S |
| **B** | 2.1 | `factory_bot`, `mocha/minitest`, `minitest/unit` gone | M |
| **C** | 2.2 | `rails-controller-testing`; 89+1 calls in keyword form; a 4.2-only kwargs shim; Devise | **L** |
| **D** | 2.3 | Dummy-app config keys that exist on both versions | S |
| **E** | 2.4 / 2.5 | `poltergeist` deleted; housekeeping verified | S |
| **F** | 2.1 (coverage) | simplecov bumped, branch coverage on, gate fixed — **alone** | M |
| **G** | exit | Both bundles measured; `next-rails` job made gating; report written | S |

Order is by signal, not by size. A is first because nothing after it is readable without it. F is last for the reason in [1.5](#15-the-simplecov-bump-is-a-change-to-the-measuring-instrument). C is the only stage with real risk in it.

**After every stage: the 4.2 suite must still be green at 75.82%.** That is the whole point of criterion 1, and checking it once at the end would tell you a test was lost without telling you which stage lost it.

---

## 3. Stage detail

### A — Borrowed prerequisites

#### A.1 — The two fixes

Three edits, given in full. Each carries a comment naming the Phase 1 finding it closes, because the next person to read `create_or_update(*args, &block)` will otherwise see an unused splat and delete it.

**[`lib/cms/behaviors/versioning.rb:230`](../../lib/cms/behaviors/versioning.rb#L230)** — signature only; the body is unchanged. The bare `super` at line 249 is a zsuper, so it forwards the new arguments implicitly and needs no edit.

```ruby
        # 3. If new record, its version is set to 1, and its published if needed.
        #
        # Rails 4.2 declares `def create_or_update` (persistence.rb:502) and Rails 5.0
        # declares `def create_or_update(*args, &block)` (persistence.rb:546). Accept and
        # forward whatever the framework passes: on 4.2 nothing is passed, so *args is
        # empty and this behaves exactly as the zero-arity version did. Without it, every
        # save on Rails 5 raises ArgumentError -- 320 of the 323 unit errors Phase 1
        # measured. See docs/rails-upgrade/phase-1-gem-report.md, P1-2.
        def create_or_update(*args, &block)
```

**[`lib/cms/content_filter.rb:12`](../../lib/cms/content_filter.rb#L12)**:

```ruby
          # Rails::Html::FullSanitizer, not HTML::FullSanitizer: the latter comes from
          # rails-deprecated_sanitizer, which is in the bundle only because
          # rails-dom-testing 1.x depends on it -- and 1.x caps activesupport < 5.0. On
          # Rails 5 it leaves the bundle and this line raises NameError. Both classes are
          # rails-html-sanitizer's and produce identical output on 4.2, verified across
          # nil/empty/non-string input. See phase-1-gem-report.md, P1-3.
          c[key] = Rails::Html::FullSanitizer.new.sanitize(c[key]).strip
```

**[`test/functional/cms/inline_controller_test.rb:7`](../../test/functional/cms/inline_controller_test.rb#L7)** — asserts against the doomed constant directly:

```ruby
      assert_equal "Remove", Rails::Html::FullSanitizer.new.sanitize("<p>Remove</p>")
```

#### A.2 — Re-measure, then rescope

```bash
bundle exec rake units                                  # expect: green, unchanged
BUNDLE_GEMFILE=Gemfile.next bundle exec rake units      # the number that matters
```

Record failures **and** errors for the 5.0 run in the report's scratch section. **Everything after this point is scoped against that number, not against Phase 1's 323.** If the residue is small and harness-shaped, stages B–F are the whole job. If it is large and application-shaped, that is a [contingency](#6-contingencies), not a surprise to absorb quietly.

Commit A on its own. It is the only stage that touches `lib/`, and keeping it separable is what makes it cheap to hand back to Phase 3 if the borrowing turns out to be a mistake.

### B — Gem renames and requires (2.1)

#### B.0 — Settle the DSL question before touching 50 lines

Every factory in this repo uses the **block-argument** DSL — `factory :root_section, :class => Cms::Section do |m| … end`, with attributes hung off `m`. factory_bot 5 definitely removed *static attributes*; whether it still yields a `DefinitionProxy` to a block argument is a separate question, and the answer changes stage B from a 50-line edit to a rewrite of both factory files.

`factory_bot` is not installed anywhere on the build machine — not in `vendor/bundle`, not in `vendor/cache`, not in any gem path — so the answer cannot be read off disk. **Measure it first, do not assume it**:

```bash
BUNDLE_GEMFILE=Gemfile.next bundle exec ruby -e '
  require "factory_bot"
  FactoryBot.define { factory(:probe, class: Hash) { |m| m.foo { 1 } } }
  puts "block-arg DSL: OK"
'
```

If it raises, stage B grows a step — convert both files to the bare-block form (`factory :root_section, class: Cms::Section do name { "My Site" } end`) — and that is worth its own commit ahead of the attribute change, so the two edits can be reviewed apart.

#### B.1 — Gemfile

Both Gemfiles are byte-identical (`diff Gemfile Gemfile.next` is empty; the dual-boot difference is expressed with `next?` inside the file), so every change here lands once and applies to both bundles.

- [ ] `gem 'factory_girl_rails'` → `gem 'factory_bot_rails', '~> 5.2'`. factory_bot 5.2.0 requires `activesupport >= 4.2.0` and Ruby >= 2.3 — resolves on 4.2/Ruby 2.7.8 and on 5.0 alike.
- [ ] `gem 'mocha', require: false` → `gem 'mocha', '~> 1.16', require: false` ([D4](#d4--mocha-1x-vs-2x)).
- [ ] Re-resolve **both** lockfiles and diff them. Anything that moves other than `factory_girl*` → `factory_bot*` and `mocha` is a resolver side-effect and needs an explanation before it is committed — the default lockfile drifting is what invalidates the Phase 0 baseline.

#### B.2 — Requires and constants

`FactoryGirl` → `FactoryBot`, `require 'factory_girl'` → `require 'factory_bot'`. Measured inventory — **60 references in 14 code files**, of which the ones that are more than a token swap:

| Site | Change |
|---|---|
| [`test/test_helper.rb:24`](../../test/test_helper.rb#L24), [`features/support/env.rb:8`](../../features/support/env.rb#L8) | `require 'factory_girl'` → `'factory_bot'` |
| [`test/test_helper.rb:52`](../../test/test_helper.rb#L52), [`test/minitest_helper.rb:34`](../../test/minitest_helper.rb#L34), [`spec/minitest_helper.rb:24`](../../spec/minitest_helper.rb#L24) | `include FactoryGirl::Syntax::Methods` → `FactoryBot::` |
| [`features/support/env.rb:12`](../../features/support/env.rb#L12) | `World(FactoryGirl::Syntax::Methods)` → `FactoryBot::` |
| [`features/support/env.rb:9`](../../features/support/env.rb#L9) | commented `factory_girl/step_definitions` — rename it too, or criterion 4's grep fails on a comment |
| The other 8 files | plain `FactoryGirl.create/build/attributes_for` → `FactoryBot.` |

Criterion 4's grep is repo-wide and excludes only `vendor/` and `.git/`, so **comments and planning docs count**. The three planning docs and the lockfile entries are in scope for the grep even though they are not code; note them in the report rather than being surprised at stage G.

- [ ] `require 'mocha/setup'` ([`test/test_helper.rb:13`](../../test/test_helper.rb#L13)) and `require "mocha/mini_test"` ([`spec/minitest_helper.rb:8`](../../spec/minitest_helper.rb#L8)) → `require 'mocha/minitest'`. Available from mocha 1.5.0; the 109 `expects`/`stubs`/`mock` call sites are untouched by the rename.
- [ ] Drop `require 'minitest/unit'` from [`test/test_helper.rb:9`](../../test/test_helper.rb#L9), [`test/minitest_helper.rb:6`](../../test/minitest_helper.rb#L6), [`spec/minitest_helper.rb:7`](../../spec/minitest_helper.rb#L7). **Three files, not the two the phase doc names.**

#### B.3 — Static attributes: 50 sites, reviewed not sed'd

factory_bot 5 removed static attributes, so `m.name "My Site"` must become `m.name { "My Site" }`. Measured: **35 in [`factories.rb`](../../test/factories/factories.rb), 15 in [`attachable_factories.rb`](../../test/factories/attachable_factories.rb)**.

What must **not** be touched, because it is not a static attribute: `m.association …`, `m.sequence(…) { }`, `m.after(:build)` / `after(:create)`, anything already in block form, the `transient do … end` wrapper itself, and the `acts_as_content_block` / `has_attachment` class-body macros at the top of `attachable_factories.rb`. A naive regex hits all of them.

Three sites need more than braces round the value:

- [`factories.rb:134`](../../test/factories/factories.rb#L134) — `m.body %q{<html>…}` spans 11 lines. The brace form nests `%q{}` inside `{}`; balanced, but check it renders.
- [`factories.rb:150`](../../test/factories/factories.rb#L150) — `m.name p`, where `p` is the block parameter of the enclosing `Cms::Authoring::PERMISSIONS.each do |p|`. `m.name { p }` closes over a per-iteration binding, so each permission factory still gets its own name — but inside the block `self` is the evaluator, and `p` is only a local rather than `Kernel#p` because the local is in lexical scope. It is worth a comment saying so.
- [`factories.rb:252`](../../test/factories/factories.rb#L252) — `page_path "/random"` sits **inside** `transient do`. Transient declarations are declarations too and take the same change; being one indent deeper is the reason a per-file skim misses it.

- [ ] All 50 converted, reviewed individually.
- [ ] `grep -nE '^\s+[a-z_.]+ +[^{|]' test/factories/*.rb` returns only `association`, `sequence`, `after` and the class-body macros.

#### B.4 — Verify

```bash
bundle exec rake                                        # 4.2: green, 75.82%
BUNDLE_GEMFILE=Gemfile.next bundle exec rake units      # 5.0: no worse than A.2
```

A factory whose value silently changed shows up as a 4.2 failure here, in the commit that caused it. That is the whole reason stage B is verified on 4.2 rather than waved through to stage G.

### C — Controller test API (2.2)

Given [1.1](#11-the-phase-docs-central-claim-about-controller-tests-is-wrong), there are three ways to satisfy criteria 2, 3 and 5 at once, and only one of them is any good:

| Option | Verdict |
|---|---|
| Convert to keyword form unconditionally | **Breaks the 4.2 suite.** Not viable. |
| Leave positional, defer to hop 2 | Green on both, but criterion 5 fails and the 5.0 job carries 89 deprecation warnings through Phases 3–5 — polluting exactly the signal those phases read. |
| **Convert to keyword form + a 4.2-only shim in `test_helper.rb`** | ✅ One version-guarded block instead of 89 conditionals. Deleted by Phase 5 when 4.2 goes away. |

Take the third. The shim translates `params:` / `session:` / `flash:` back into 4.2's three positional slots, and raises on any keyword 4.2 cannot express (`xhr:`, `as:`, `format:` — none of which is used today; verified zero `xhr`/`xml_http_request` sites in the repo) rather than silently dropping it. It sits beside the `MonitorMixin`/`recycle!` patch already in that file and is guarded the same way, on `Rails::VERSION`.

#### C.1 — The shim

Goes in [`test/test_helper.rb`](../../test/test_helper.rb) beside the existing `MonitorMixin`/`recycle!` patch, guarded the same way and announcing itself the same way — stage E's checklist reads that output rather than assuming.

```ruby
# Rails 4.2's ActionController::TestCase#process has three positional slots and
# no keyword handling: `def process(action, http_method = 'GET', *args)` then
# `parameters, session, flash = args` (actionpack-4.2.11.3 test_case.rb:595).
# So `get :show, params: {id: 5}` arrives as params[:params][:id] and the
# controller never sees :id -- a silently wrong answer, not an error. Rails 5.0
# accepts both forms; 5.1 accepts only the keyword form. No single form works on
# both, so the call sites are written the 5.x way and translated back here, once,
# for the 4.2 bundle only. Delete this whole block in Phase 5.
if Gem::Version.new(Rails.version) < Gem::Version.new('5.0.0')
  module KeywordControllerArgs
    TRANSLATABLE = [:params, :session, :flash].freeze

    # 4.2 has no positional slot for any of these. Zero call sites use one today
    # (no xhr / xml_http_request / as: / format: anywhere in test/functional).
    # Raise rather than drop: a dropped keyword is a test that passes for the
    # wrong reason, which is the one failure mode this shim must not have.
    UNTRANSLATABLE = [:xhr, :as, :format, :body, :env, :headers].freeze

    def process(action, http_method = 'GET', *args)
      kwargs = args.first
      keyword_form = args.length == 1 && kwargs.is_a?(Hash) && kwargs.any? &&
        kwargs.keys.all? { |k| TRANSLATABLE.include?(k) || UNTRANSLATABLE.include?(k) }
      return super unless keyword_form

      unsupported = kwargs.keys & UNTRANSLATABLE
      unless unsupported.empty?
        raise ArgumentError, "Rails 4.2 cannot express #{unsupported.inspect} in a " \
                             "controller test. Rewrite the call, or extend the shim " \
                             "in test/test_helper.rb -- do not drop the keyword."
      end

      super(action, http_method, kwargs[:params], kwargs[:session], kwargs[:flash])
    end
  end

  ActionController::TestCase.prepend(KeywordControllerArgs)
  puts 'Translating keyword controller-test args back to Rails 4.2 positional form'
end
```

Two things to verify rather than assume, both one-liners:

- [ ] `prepend` on the class really does intercept. `process` is defined in `ActionController::TestCase::Behavior`, an *included* module, so a module prepended to the class sits ahead of it — check with `ActionController::TestCase.ancestors.take(3)` rather than trusting the ancestry rule.
- [ ] The verb methods route through `process`. 4.2 defines `get`/`post`/… as thin wrappers over it, which is why one interception covers all 89 sites; confirm before converting any of them.

#### C.2 — The 89 call sites

**91 grep hits, 89 live, 9 files** — the two non-live are comments at [`pages_controller_test.rb:207,210`](../../test/functional/cms/pages_controller_test.rb#L207).

| File | Sites |
|---|---|
| `test/functional/cms/pages_controller_test.rb` | 27 (25 live) |
| `test/functional/cms/sections_controller_test.rb` | 18 |
| `test/functional/cms/content_controller_test.rb` | 16 |
| `test/functional/cms/links_controller_test.rb` | 10 |
| `test/functional/cms/html_blocks_controller_test.rb` | 9 |
| `test/functional/cms/tasks_controller_test.rb` | 4 |
| `test/functional/cms/content_block_controller_test.rb` | 3 |
| `test/functional/cms/file_blocks_controller_test.rb` | 3 |
| `test/dummy/test/controllers/design_controller_test.rb` | 1 |

Every one is the simple shape — a single trailing hash, no second or third positional argument. Verified: **no call site passes session or flash positionally**, and none uses `format:`. So the conversion is uniformly `get :edit, :id => @page.id` → `get :edit, params: {:id => @page.id}`, including the multi-key ones (`put :update, :id => …, :page => {…}` → `params: {:id => …, :page => {…}}` — one params hash, not two).

The dummy-app file is easy to miss: it is under `test/dummy/`, it is reached only through the `test:orphans` task Phase 0 added, and criterion 5's grep does cover it.

- [ ] 89 conversions, 9 files.
- [ ] Convert the two comments as well — they are prose, but leaving them means the next person greps and finds "remaining" sites.

#### C.3 — `rails-controller-testing`

For the 19 `assert_template` and 11 `assigns` sites. **Must be `next?`-conditional**: 1.0.5 requires `actionpack >= 5.0.1.rc1` and cannot enter the 4.2 bundle — where both APIs are built into the framework and need no gem.

```ruby
# 4.2 has assert_template and assigns built in; 5.0 extracted them. The gem
# cannot resolve on 4.2 (it needs actionpack >= 5.0.1.rc1), so this is one of
# the few places a next? branch is not a smell -- it is the only expressible
# form. Criterion 12 is about test *code*, not the Gemfile.
gem 'rails-controller-testing' if next?
```

Note the interaction with criterion 12: the criterion greps `test/` and `spec/` for `NextRails`, and this branch is in the `Gemfile`, so it does not trip. That is the right outcome and worth saying out loud, because the alternative reading — "no version branches anywhere" — would make criterion 7 unsatisfiable.

#### C.4 — Devise

- [ ] `Devise::TestHelpers` → `Devise::Test::ControllerHelpers` at [`test_helper.rb:202`](../../test/test_helper.rb#L202). Devise 4.9.4 is already in both bundles and the new name works on 4.2, so this one *is* unconditional — the only item in stage C that is.

#### C.5 — Verify

```bash
bundle exec rake                                        # 4.2 green, through the shim
BUNDLE_GEMFILE=Gemfile.next bundle exec rake units test:functionals
```

Stage C is the only stage where 4.2 green and 5.0 green mean genuinely different things: on 4.2 it proves the shim translates correctly, on 5.0 it proves the call sites are right natively. Both are needed; neither substitutes for the other. Run the functionals on 5.0 here even though the full-suite check waits for stage G — the functionals *are* what stage C changed.

### D — Dummy app config (2.3)

- [ ] Delete `config.serve_static_assets = true` from [`test/dummy/config/environments/test.rb:11`](../../test/dummy/config/environments/test.rb#L11) and [`production.rb:20`](../../test/dummy/config/environments/production.rb#L20) — both set the framework default on both versions ([1.2](#12-serve_static_assets-has-no-cross-version-replacement--but-it-has-a-better-fix)).
- [ ] Delete `config.static_cache_control` from [`test.rb:12`](../../test/dummy/config/environments/test.rb#L12).
- [ ] Boot the dummy app under both Gemfiles and **read the deprecation output**, which is the actual point of this stage:

```bash
for gf in Gemfile Gemfile.next; do
  echo "== $gf"
  BUNDLE_GEMFILE=$gf bundle exec ruby -e 'require "./test/dummy/config/environment"; puts Rails.version' 2>&1 \
    | grep -i "deprecat\|renamed\|unknown"
done
```

The `production.rb` deletion deserves a second look before it goes in: that file's comment says the dummy app runs in "faux production mode", so it is the one place where serving static assets is load-bearing rather than incidental. Both frameworks default it to `true`, so deleting the line is still correct — but confirm nothing in the dummy app sets `config.serve_static_files = false` earlier in the chain, or the deletion changes behaviour rather than preserving it.

### E — Cucumber stack and housekeeping (2.4 / 2.5)

- [ ] Delete `gem 'poltergeist'` ([`Gemfile:67`](../../Gemfile#L67)) and `require 'capybara/poltergeist'` ([`features/support/env.rb:16`](../../features/support/env.rb#L16)), plus the two commented driver assignments at [`env.rb:19-20`](../../features/support/env.rb#L19). Nothing selects a driver; P1-7.
- [ ] **Do not** bump `cucumber`, `capybara`, `database_cleaner` or `aruba`. None caps Rails 5 (Phase 1). `cucumber-rails 1.4.5` caps `railties < 5.1` — hop 2's first blocker, and it belongs to the phase that does that hop. See [D2](#d2--deferring-the-cucumber-stack).
- [ ] Run the features on 4.2 straight after the deletion. Criterion 11 is a Cucumber pass rate, and 154/154 is the number to hold — removing a `require` from `env.rb` is exactly the kind of change that is obviously safe and occasionally isn't.

Housekeeping, all three observable rather than assumed:

- [ ] No blanket warning suppression has returned. `grep -rn 'VERBOSE' test/ spec/ features/` — the comment block at [`test_helper.rb:28-32`](../../test/test_helper.rb#L28) explains why, and should still be the only hit.
- [ ] The `recycle!` patch self-disables on 5.0. It prints `Monkeypatch for ActionController::TestResponse no longer needed` on the 5.0 bundle and `Patching ActionController::TestResponse …` on 4.2 — so grep the CI logs of both jobs for the right line, rather than reasoning about the guard.
- [ ] The new shim from [C.1](#c1--the-shim) prints on 4.2 and is silent on 5.0. Same check, same reason.

### F — Coverage (2.1, alone)

Four steps, strictly in this order. The ordering is the whole value of the stage: fixing the gate *before* the bump means the gate is never broken, and measuring before and after on identical code means any movement is attributable to the tool.

**F.1 — Measure before.** `bundle exec rake && cat coverage/.last_run.json`. Commit nothing. This is the number the "after" is compared against, and it must be taken on the tree that stage E left behind, not on the Phase 0 baseline from memory.

**F.2 — Fix the gate, still on simplecov 0.12.** [`coverage:check`](../../lib/tasks/core_tasks.rake#L43) currently does `.fetch('result').fetch('covered_percent')`, and 0.18 removed that key — left alone it would `KeyError` after the bump. Teach it both shapes while the old one is still live, so the commit is verifiable:

```ruby
result = JSON.parse(File.read(path)).fetch('result')

# simplecov < 0.18 wrote {"result": {"covered_percent": 75.82}}. From 0.18 that
# key is gone and the shape is {"result": {"line": 75.82}}, plus "branch" once
# enable_coverage :branch is on. Accept either, so the gate keeps working across
# the bump -- and abort on neither, rather than comparing nil to a Float.
actual = result['line'] || result['covered_percent']
abort "#{path} has no line-coverage key (got #{result.keys.inspect})" if actual.nil?
```

**F.3 — Bump.** `simplecov` → `~> 0.22.0` in both Gemfiles; `enable_coverage :branch` in [`.simplecov`](../../.simplecov). Two things in that file need re-checking against 0.22, because both were written against 0.12's constraints:

- The `merge_timeout 3600` workaround stays — five suites in five processes is still the situation, and 0.22 still defaults to 600s.
- The comment at [`.simplecov:18-22`](../../.simplecov#L18) says block filters are used *because* 0.12's `parse_filter` raises `ArgumentError` on a `Regexp`. 0.22 accepts regexes. The filters work either way, so **do not rewrite them** — but the comment now explains a constraint that no longer binds, and leaving it uncorrected sets a trap for whoever reads it next.

Branch coverage is **reported, not gated**: there is no committed branch baseline, and inventing a floor in the same commit that first measures the number would be gating on something nobody has looked at. Print it and let Phase 3 set the floor.

**F.4 — Measure after, on identical code.** Re-run and diff against F.1. If the line number moved, the instrument moved — record both numbers and the new baseline in the report, and update `COVERAGE_MINIMUM`'s default in the rake task to match. If it moved for any other reason, stage F is wrong and the bump comes back out.

- [ ] Before/after line coverage recorded in the report, with the delta explained.
- [ ] A branch percentage appears in the output (criterion 10).
- [ ] `bundle exec rake coverage:check` passes on the post-bump number.

### G — Exit

- [ ] Full run on both bundles; all 12 criteria checked with the commands in the phase doc, using [§7](#7-exit-criteria-traceability) as the checklist.
- [ ] [`.github/workflows/ci.yml:147`](../../.github/workflows/ci.yml#L147): drop `continue-on-error: true` from the `next-rails` job, and rewrite the comment above it — it currently says the job "becomes gating in Phase 5", which stops being true here. Rename the job from `Rails 5.0 (Gemfile.next, reporting only)` too; a gating job labelled *reporting only* is how a red build gets ignored.
- [ ] The `next-rails` job currently runs `bundle exec rake` under `if: always()`. Once it is gating, `always()` is doing nothing useful and should go with the `continue-on-error`.
- [ ] Write [`phase-2-harness-report.md`](phase-2-harness-report.md); update the [README](README.md) status table.

The `Assert the bundle really is Rails 5.0` step stays exactly as it is. It is the thing that would catch dual-boot silently falling back to 4.2 and reporting a green Rails 5 job — a failure mode that becomes considerably more expensive the moment the job is gating.

---

## 4. Decisions

### D1 — Borrowing two fixes from Phase 3

**Decision: take them.** Criterion 3 cannot pass without them, and Phase 3's header explicitly asks for the arity fix first. The alternative — declaring Phase 2 done with criterion 3 unmet — trades a documented two-line deviation for an unmet contract, which is the worse of the two. Phase 3 keeps the remaining ~94 changes; its exit criteria 1 and 7 already cover both borrowed items, so nothing goes untracked.

### D2 — Deferring the cucumber stack

**Decision: defer everything except deleting `poltergeist`.** Phase 1 measured that none of `cucumber`, `capybara`, `database_cleaner` or `aruba` caps Rails 5. Bumping four test gems inside a phase whose success metric is "coverage did not move" adds risk to the one number this phase is judged on, for no Rails-5 benefit. `cucumber-rails`'s `< 5.1` cap is real and is hop 2's problem.

The counter-argument is that hop 2 then carries both `cucumber-rails` **and** 89 controller calls. Stage C removes the second half of that, which is most of why it is worth doing now.

### D3 — `Cms::IntegrationTestHelper`

Defined at [`test_helper.rb:205`](../../test/test_helper.rb#L205), included nowhere, and its `login_as` asserts `assert_response 403` immediately after a successful login — it could not have passed in years. **Decision: convert it to keyword form and leave it in place.** Deleting dead code is the right end state but this phase is a port, and "no tests were lost" is much easier to defend if nothing was deleted. Flag it for Phase 3's dead-code item.

**Correction to an earlier draft of this decision:** it said "criterion 5 covers it." It does not. Criterion 5's grep requires a symbol action — `:[a-z_]+` — and the call is `post login_url, :login => …`, a method call. The site is invisible to the criterion, which is why [1.3](#13-the-site-counts-re-measured) had to find it by hand. Converting it is therefore a judgement call, not a requirement, and it comes with a caveat: **the [C.1](#c1--the-shim) shim does not cover it.** The shim prepends to `ActionController::TestCase`; integration tests go through `ActionDispatch::IntegrationTest#process`, which has a different signature (`process(method, path, parameters, headers_or_env)`). Writing a second shim for one call site in dead code is not worth it. Convert the call and add a comment saying it is unshimmed and would break on 4.2 if this module were ever revived.

### D4 — mocha 1.x vs 2.x

**Decision: `~> 1.16`.** `mocha/minitest` exists from 1.5.0, so 1.x satisfies the work item in full. Mocha 2.0 removes the legacy entry points *and* changes `any_instance` and configuration behaviour across 109 call sites. That is a modernisation with no Rails deadline — the same category Phase 1 put `factory_girl` and `capybara` in — and it does not belong in a phase measured on coverage stability.

---

## 5. Risks

| Risk | Mitigation |
|---|---|
| The kwargs shim silently mistranslates a call and a test passes for the wrong reason | The shim raises on anything it cannot express rather than dropping it. 4.2 stays green through stage C, so any mistranslation shows up as a failure in the same commit that caused it. |
| factory_bot 5's static-attribute removal changes a factory's value rather than erroring | Reviewed per line; `association`/`sequence`/`after` deliberately excluded. 4.2 green after stage B is the check. |
| simplecov's number moves and looks like lost coverage | Stage F is isolated and measured before/after on identical code ([1.5](#15-the-simplecov-bump-is-a-change-to-the-measuring-instrument)). |
| Rails 5 reveals failures underneath the 322 borrowed-fix errors that this phase cannot fix | Then criterion 3 fails on application behaviour, not harness. Report the residue and hand it to Phase 3 rather than papering over it with a `next?` branch — criterion 12 exists for exactly this temptation. |
| factory_bot 5 has dropped the block-argument DSL as well as static attributes, turning a 50-line edit into a rewrite of both factory files | [B.0](#b0--settle-the-dsl-question-before-touching-50-lines) measures this before any editing, and splits the conversion into its own commit if the answer is bad. |
| The two lockfiles drift on gems nobody asked to move when stage B re-resolves | [B.1](#b1--gemfile) diffs both lockfiles and requires an explanation for anything beyond `factory_bot` and `mocha`. Silent drift in the *default* lock is what invalidates the 75.82% everything is measured against. |

---

## 6. Contingencies

| If | Then |
|---|---|
| A.2's re-measured Rails 5 error count is still large and application-shaped | **Stop and re-scope before stage B.** Phase 2 cannot fix application behaviour without becoming Phase 3. Report the residue, get a decision on whether criterion 3 moves to Phase 3, and do not quietly absorb the work — [D1](#d1--borrowing-two-fixes-from-phase-3) borrowed two fixes on the strength of them being two lines each, and that argument does not extend. |
| The 4.2 suite goes red after any stage | Fix it inside that stage or revert that stage. Do not carry a red 4.2 suite forward "to fix at G" — criterion 1 is the phase's only real safety net, and it only works if it is checked per stage. |
| The kwargs shim cannot be made to intercept cleanly (`prepend` does not win, or `process` is bypassed) | Fall back to option 2 from [C](#c--controller-test-api-22): leave the call sites positional and defer all of stage C to hop 2. Criterion 5 then fails, and that is the honest outcome — a shim that works for 85 of 89 sites is worse than no shim. |
| factory_bot 5.2 will not resolve on the 4.2 bundle | Pin `factory_bot_rails` per-bundle with `next?` and record it as a dual-boot conditional in the report. This would be the first Gemfile branch this phase adds beyond `rails-controller-testing`, so it needs saying out loud rather than slipping in. |
| Coverage moves in stage F and the cause is not obviously the instrument | Revert F and land the rest of the phase without it. Criteria 1 and 3 are the phase; criterion 10 is not worth trading either of them for, and simplecov can be bumped in any later phase at no extra cost. |
| The Cucumber pass rate drops after the poltergeist deletion | Revert the `env.rb` edit, keep the Gemfile deletion, and record that the `require` had a side-effect nobody expected. Criterion 11 outranks tidiness. |
| Criterion 3 is met only because the 5.0 job is running fewer tests than the 4.2 job | That is not criterion 3 being met. Compare test *counts* between the two jobs, not just exit codes — a suite that green-lights by collecting nothing is the exact failure this phase exists to prevent. |

---

## 7. Exit criteria traceability

| # | Criterion | Stage | Verification |
|---|---|---|---|
| 1 | Coverage still reads the Phase 0 baseline on 4.2 | every stage; F | `bundle exec rake coverage:check` after each stage; F.1/F.4 before-and-after |
| 2 | Suite green on the default Gemfile | every stage | `bundle exec rake` exits 0 |
| 3 | Suite green on `Gemfile.next`, no longer allow-failure | A, G | `BUNDLE_GEMFILE=Gemfile.next bundle exec rake` green in CI; `continue-on-error` gone |
| 4 | Zero `factory_girl` references | B.2 | `grep -rn "factory_girl\|FactoryGirl" . --exclude-dir=vendor --exclude-dir=.git` — **includes comments, planning docs and lockfiles** |
| 5 | Zero positional controller-test calls | C.2 | The phase doc's anchored grep over `test/` and `spec/`. Does **not** reach the integration site — see [D3](#d3--cmsintegrationtesthelper) |
| 6 | No `mocha/setup`, `mocha/mini_test` or `minitest/unit` requires | B.2 | `grep -rn "mocha/setup\|mocha/mini_test\|minitest/unit" test/ spec/` — three files, not two |
| 7 | `rails-controller-testing` declared; 19 + 11 sites pass | C.3 | Gem present in the next bundle only; those tests green on `Gemfile.next` |
| 8 | No `Devise::TestHelpers` | C.4 | `grep -rn "Devise::TestHelpers" test/ spec/` |
| 9 | No `serve_static_assets` | D | `grep -rn "serve_static_assets" test/ config/` |
| 10 | Branch coverage enabled and reported | F.3 | A branch percentage in the run output; **reported, not gated** |
| 11 | Cucumber pass rate ≥ Phase 0 baseline | E | 154/154, compared against `phase-0-baseline.md` |
| 12 | No `NextRails.next?` branch added to make the suite pass | C.3 | `grep -rn "NextRails" test/ spec/` empty. The two branches this phase adds are both in the `Gemfile`, which the criterion does not grep — deliberately, see [C.3](#c3--rails-controller-testing) |

**A note on criteria 3 and 5 versus what this phase can honestly claim.** Criterion 3 is inherited, not earned: it passes because [D1](#d1--borrowing-two-fixes-from-phase-3) borrowed two Phase 3 fixes, and if the A.2 residue turns out to be non-trivial it will not pass at all. Criterion 5, meanwhile, is satisfied by conversions this hop does not need — the 89 sites are hop 2's blocker, not 5.0's ([1.1](#11-the-phase-docs-central-claim-about-controller-tests-is-wrong)). Both are worth doing here for the reasons given. Neither should be reported as though this phase discovered a clean bill of health; the report should say which criteria were met by this phase's own work and which were met by borrowing forward or paying down early.
