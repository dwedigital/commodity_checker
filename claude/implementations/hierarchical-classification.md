# Hierarchical Commodity-Code Classification

**Date:** 2026-09-22
**Feature:** Replace the single-shot commodity-code suggester with a retrieve-then-walk pipeline that walks the real UK Trade Tariff tree to a declarable 10-digit leaf.

## Overview

`LlmCommoditySuggester#suggest(description)` used to do one thing: search the UK
Trade Tariff API with the whole scraped description, hand Claude whatever came
back, and ask it for a code in a single call. Measured against 32 UK Advance
Tariff Rulings (10-digit ground truth), that approach got the chapter right 81%
of the time but the full 10-digit code only 9%, invented UK suffixes (14/32
codes did not exist or were not declarable), and the true 8-digit code was in
the candidate list only 6% of the time — so Claude was classifying from memory.

The rebuild keeps the public contract of `#suggest` identical but changes the
internals to a **retrieve-then-walk** pipeline:

1. **Analyze** — one Claude call turns the raw description into structured facts:
   a plain product summary, 2-4 short "customs officer" search phrases, salient
   attributes, numeric facts, and the 1-3 most likely chapters.
2. **Retrieve** — each short phrase is searched directly against the tariff
   (with the noisy word-by-word fallback OFF), and the resulting headings are
   unioned with the headings of the candidate chapters into an ordered
   shortlist.
3. **Walk** — a chooser picks a heading, then descends the *real* commodity tree
   node by node (the model only ever chooses among codes that actually exist)
   until it reaches a declarable 10-digit leaf, which is then validated.

The old behaviour is preserved as `LegacyCommoditySuggester` and reachable with
`TARIFFIK_PIPELINE=legacy`, so the eval can compare the two head to head.

## Design Decisions

- **Walk real codes, never invent them.** The single biggest failure of the old
  suggester was inventing UK 10-digit suffixes. The walker only ever offers the
  model codes that exist in the tariff (`Classification::ClaudeChooser` bakes the
  option keys into the JSON-schema `enum`, so an invalid key is impossible).
- **Short search phrases, fallback off.** Long scraped descriptions return zero
  fuzzy matches; the old word-by-word fallback then sprayed ~20 HTTP calls of
  noise. The analyzer produces short noun phrases ("electric kettle", "knitted
  polyester t-shirt") that actually hit, and `TariffLookupService#search` gained
  a `fallback:` keyword so the retriever can disable the spray.
- **Analyzer holds the rules, chooser holds the judgement.** GRI framing and the
  awkward canonical rules (pet toys are not chapter 95, kettles are 8516 79, a
  textile shopping bag is 4202 92) live in the analyzer's system prompt. The
  chooser stays a general GRI-guided decision maker so it can be swapped.
- **Swappable chooser behind a fixed contract.** `Classification::Chooser`
  defines `#choose(question:, options:, context:)`. A second implementation
  (`JevChooser`, see `jev-chooser.md`) targets the same contract and is the
  default whenever `TYPESAFE_API_KEY` is set, with `ClaudeChooser` as its
  fallback for numeric-threshold levels; `TARIFFIK_CHOOSER=claude` forces Claude.
- **Confidence is a product of the walk.** Overall confidence is the product of
  the chosen option's confidence at each step, so a shaky decision anywhere in
  the walk drags the whole result down (useful for calibration and triage).
- **Low-confidence heading fallback.** If the chooser is not confident about any
  candidate heading (< 0.35) or there are no candidates, the walker falls back to
  choosing a chapter among all 98, then a heading within it.
- **Everything degrades, nothing raises.** `TariffTree` caches every GET for 24h
  and returns empty/nil on failure; `ProductAnalyzer`, `ClaudeChooser` and
  `LlmCommoditySuggester` all rescue and return nil. A flaky tariff API or Claude
  error yields "no suggestion", never a crash.
- **Structured outputs.** Both Claude calls use `output_config` with a
  `json_schema` and adaptive thinking, so the response text is guaranteed-valid
  JSON for the schema (the text block is selected explicitly, since adaptive
  thinking can prepend a thinking block).

## Database Changes

None. The pipeline returns the same `#suggest` hash shape the callers already
persist; no schema or migration changes.

## New Files Created

### Services (`app/services/classification/`, namespace `Classification::`)

| File | Purpose |
|------|---------|
| `tariff_tree.rb` | Read-only UK Trade Tariff API v2 client: `chapters`, `headings_for_chapter`, `tree_for_heading` (nested by `number_indents`, node identity `item_id/suffix`), `chapter_note`. 24h cached GETs, one retry, never raises. |
| `product_analyzer.rb` | One Claude call → `{ product_summary, search_phrases, attributes, numeric_facts, candidate_chapters }` via structured output. Holds the GRI + canonical-rule system prompt. |
| `candidate_retriever.rb` | Runs each short search phrase (fallback off) + candidate-chapter headings → ordered, de-duplicated shortlist of `{ code, description, source }`. |
| `chooser.rb` | The `Classification::Chooser` interface (contract shared with `JevChooser`). |
| `claude_chooser.rb` | Claude-backed chooser; option keys baked into the schema enum; low effort for `:node`, medium for `:chapter`/`:heading`. |
| `choosers.rb` | `Classification::Choosers.default` — `JevChooser` (with Claude fallback) when `TYPESAFE_API_KEY` is set, else `ClaudeChooser`; `TARIFFIK_CHOOSER=claude` forces Claude. |
| `tree_walker.rb` | Walks candidates → declarable leaf; heading step with chapter fallback; node steps capped at depth 12; validates + enriches; builds reasoning/steps. |
| `anthropic_client.rb` | Shared Anthropic client + API-key mixin. |
| `token_meter.rb` | Optional thread-local Claude token/call accounting (used only by the eval). |

### Other

| File | Purpose |
|------|---------|
| `app/services/legacy_commodity_suggester.rb` | The old single-shot suggester, moved verbatim; used when `TARIFFIK_PIPELINE=legacy`. |
| `lib/tasks/eval.rake` | `bin/rails "eval:rulings"` — sequential accuracy eval with depth accuracy, calibration table, latency, tokens; writes per-item JSON incl. walk steps. |
| `test/services/classification/tariff_tree_test.rb` | Tree building (indent nesting, suffix 10/80 identity), empty-heading leaf, failure handling, caching. |
| `test/services/classification/candidate_retriever_test.rb` | Union/ordering, fallback-off on short phrases. |
| `test/services/classification/tree_walker_test.rb` | Walk to a declarable leaf, low-confidence chapter fallback, depth cap, nil on undecided. |
| `test/services/classification/claude_chooser_test.rb` | Enum contains all option keys, nil on API error, off-list key rejected. |

## Modified Files

| File | Change |
|------|--------|
| `app/services/llm_commodity_suggester.rb` | Rewritten as the pipeline entry point (analyze → retrieve → walk); delegates to `LegacyCommoditySuggester` when `TARIFFIK_PIPELINE=legacy`. Same `#suggest` contract; collaborators injectable for tests. |
| `app/services/tariff_lookup_service.rb` | `search` gained a `fallback:` keyword (default true) so the retriever can send short phrases without triggering the word-by-word fallback. |
| `test/services/llm_commodity_suggester_test.rb` | Reworked to pin the public contract against the new pipeline (blank → nil, all keys present, validated true/false, nil on failure) + legacy delegation. |
| `test/support/llm_mock_helper.rb` | Added `stub_suggester` (stubs `LlmCommoditySuggester.new` with a canned result) for the API/MCP/extension layer tests, which no longer stub raw single-shot Claude HTTP. |
| `test/controllers/api/v1/extension_controller_test.rb`, `test/controllers/api/v1/commodity_codes_controller_test.rb`, `test/controllers/mcp/server_controller_test.rb` | Lookup tests repointed from `stub_commodity_suggestion` (old single-shot HTTP) to `stub_suggester`; assertions unchanged. |
| `CLAUDE.md` | Updated "Commodity Code Flow" diagram, "Modifying commodity code suggestions", and the important-files table. |
| `test/eval/baseline_eval.rb` | Deleted; superseded by `lib/tasks/eval.rake` (the JSON set and baseline results file are kept). |

## Routes

None.

## Data Flow

```
LlmCommoditySuggester#suggest(description)
        │  (blank? → nil;  TARIFFIK_PIPELINE=legacy → LegacyCommoditySuggester)
        ▼
Classification::ProductAnalyzer#analyze         [1 Claude call, structured JSON]
        │  → { product_summary, search_phrases[2-4], attributes,
        │      numeric_facts, candidate_chapters[1-3] }
        ▼
Classification::CandidateRetriever#retrieve
        │  for each phrase: TariffLookupService#search(phrase, fallback: false)
        │      → heading = code[0,4]
        │  ∪ TariffTree#headings_for_chapter(candidate_chapters)
        │  → ordered, de-duped [{ code:"6109", description:, source::search|:chapter }]
        ▼
Classification::TreeWalker#walk
        │  heading step:  Chooser#choose(level: :heading, candidate headings)
        │     └─ conf < 0.35 or no candidates → choose chapter (98) → heading
        │  node steps:    TariffTree#tree_for_heading → descend children,
        │     Chooser#choose(level: :node) until chosen node is declarable
        │     (depth-capped at 12; empty heading → "<heading>000000")
        │  validate:      TariffLookupService#get_commodity(code) → validated,
        │                 official_description, duty_rate; category = chapter desc
        ▼
{ commodity_code (10 digits), confidence (product of steps), reasoning,
  category, validated, official_description, duty_rate, path, steps }
```

Node identity in the tree is `"<item_id>/<producline_suffix>"`, because the same
`goods_nomenclature_item_id` can appear as a suffix-10 grouping line and a
suffix-80 declarable line (e.g. heading 2204: `2204101100/10` "PDO" →
`2204101100/80` "Champagne"). Parents are assigned from the flat, ordered
commodity list by `number_indents` (nearest preceding smaller indent).

## Testing / Verification

Commands run and their real results:

- `bin/rails test` — **458 runs, 1144 assertions, 0 failures, 0 errors**.
- `TARIFFIK_PIPELINE=legacy bin/rails "eval:rulings"` — harness sanity check, 32
  Sonnet calls. Reproduces the baseline closely (2-digit 81%, 8-digit 19%,
  10-digit 6%, 17 unvalidated), confirming the harness.
- `bin/rails "eval:rulings"` — new pipeline, Claude chooser, 32 rulings (149
  Claude calls, 4.7/lookup).
- One real end-to-end lookup:
  `LlmCommoditySuggester.new.suggest("Sony WH-1000XM5 wireless noise cancelling
  over-ear headphones …")` → `8518300090` (headphones/earphones, "Other"),
  `validated: true`, confidence 0.94, walk 8518 → 8518 30 → "Other". Correct.

### Eval results (32 UK Advance Tariff Rulings)

| Depth | Legacy (single-shot) | Pipeline (retrieve-then-walk) |
|-------|---------------------|-------------------------------|
| 2-digit (chapter) | 81% | **94%** |
| 4-digit (heading) | 63% | **69%** |
| 6-digit | 50% | **63%** |
| 8-digit | 19% | **56%** |
| 10-digit (full) | 6% | **56%** |
| Unvalidated / invented codes | 17 | **0** |
| No suggestion | 1 | **0** |
| Median latency | ~14s | ~20s |
| Claude calls / lookup | 1 | 4.7 |

The pipeline never returns a code that is not a real, declarable commodity (0
unvalidated vs 17), which is the point of walking the tree instead of asking for
a code. 10-digit accuracy went from 6% to 56%.

Pipeline calibration (confidence bucket → n, 10-digit acc, 8-digit acc):

| Bucket | n | 10-digit | 8-digit |
|--------|---|----------|---------|
| 0.0-0.5 | 12 | 42% | 42% |
| 0.5-0.7 | 6 | 67% | 67% |
| 0.7-0.9 | 12 | 58% | 58% |
| 0.9-1.0 | 2 | 100% | 100% |

Confidence (the product of per-step confidences) separates right from wrong at
the extremes (0.9-1.0 → 100%, and mean confidence when right 0.65 vs 0.49 when
wrong), but the 0.0-0.5 bucket still lands 42% correct — the product understates
confidence on longer walks. Of the 14 remaining misses, most are heading-level
errors that then cascade (e.g. a dog toy walked into 9503 "toys" instead of 6307;
a novelty sink into 3922 instead of 3926; a fitness-console LCD into 8528 instead
of 8537). Better candidate retrieval or a stronger chooser at the heading step is
the main lever left. Full per-item results with walk steps are written to
`test/eval/results/`.

## Limitations & Future Improvements

- **Cost and latency.** The pipeline makes several Claude calls per lookup
  (analyzer + one per walk step, typically ~4-6) versus one for the old
  suggester, so it is slower and more expensive per lookup. The walk is
  sequential by necessity (each step depends on the last).
- **Node-level judgement is the chooser's.** Canonical rules live in the analyzer
  prompt, but the actual heading/node choices are the chooser's. Subtle
  distinctions (e.g. a kettle as an "other domestic electrothermic appliance"
  8516 79 vs a "water heater/immersion heater" 8516 10) can still go wrong at a
  node step; a `JevChooser` or richer node context is the lever to improve this.
- **Tariff API dependence.** Accuracy depends on the short-phrase search
  surfacing the right heading (or the chapter fallback recovering it) and on the
  tree endpoints being available. The 24h cache and single retry soften
  transient failures but a sustained outage yields "no suggestion".
- **Eval sets.** The 32-item set is contaminated: four analyzer-prompt rules
  were written from its misses, so quote the 88-item set
  (`test/eval/rulings_eval_set_large.json`, 28 chapters, 56 rulings unseen by
  any prompt). On it the Claude chooser scores 78% chapter / 64% heading / 50%
  8-digit / 45% 10-digit with 0 invalid codes (legacy: 6% at 10 digits); the Jev
  chooser matches it at 45% with half the latency. 31 of the 47 Claude misses go
  wrong at the heading step, so heading selection (section notes in context,
  walking the top two candidate headings) is the next lever. Never tune prompts
  on the set you report.
