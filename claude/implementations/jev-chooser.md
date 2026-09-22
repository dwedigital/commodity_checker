# Jev Chooser (TypeSafe AI) Implementation

**Date:** 2026-09-22
**Feature:** An alternative decision maker for the classification pipeline, backed by TypeSafe AI's "Jev" decision model instead of a Claude call per step.

## Overview

The retrieve-then-walk classification pipeline (`Classification::*`) asks a
*chooser* at each step of the tariff tree: given a product, a question, and a
fixed set of options, pick one. The default chooser is `ClaudeChooser` (one
Claude call per decision). This adds a second chooser, `Classification::JevChooser`,
backed by Jev.

Jev is a decision model, not a text generator. You send a `state` (free text or
a JSON object) plus one or more typed `questions`, and it returns typed answers
with calibrated probabilities and no prose. For a single-branch tariff decision
that maps to one `choice` question whose `criteria` list the options, which is a
better shape than asking a chat model to emit JSON: the answer is always one of
the keys on offer, and the confidence is calibrated rather than self-reported.

It is the default chooser whenever `TYPESAFE_API_KEY` is set:
`Classification::Choosers.default` builds `JevChooser.new(fallback: ClaudeChooser.new)`,
so numeric-threshold levels still go to Claude. Set `TARIFFIK_CHOOSER=claude` to
force Claude. The key is loaded from `.env` by dotenv in development and test,
and from Kamal secrets in production (`config/deploy.production.yml` lists it
under `env.secret`; the value lives in `.kamal/secrets.production`, gitignored).

## API shape

REST: `POST https://api.typesafe.ai/v1/systemone`, header
`Authorization: Bearer <TYPESAFE_API_KEY>`, JSON body `{ model, state, questions }`.

Request (a `choice` question plus a yes/no `noul`):

```json
{
  "model": "jev-latest",
  "state": {
    "product": "Football tops ... It is knitted. It is made from polyester.",
    "classified_so_far": "Chapter 61 ... > Heading 6109 T-shirts, singlets and other vests"
  },
  "questions": {
    "leaf": {
      "type": "choice",
      "instructions": "Which commodity line under heading 6109 classifies `product`? Choose by textile material.",
      "criteria": {
        "6109100010": "Of cotton > T-shirts",
        "6109902000": "Of other textile materials > Of wool or fine animal hair or man-made fibres"
      }
    },
    "knitted": { "type": "noul", "instructions": "Is `product` knitted or crocheted?" }
  }
}
```

Response:

```json
{
  "model": "jev-1.13.0",
  "answers": {
    "leaf": { "type": "choice", "choice": "6109902000", "confidence": 0.99,
              "probabilities": { "6109902000": 0.99, "6109909000": 0.01 } },
    "knitted": { "type": "noul", "noul": 0.93 }
  },
  "usage": { "input_tokens": 605, "output_tokens": 126 }
}
```

Question types:

- `choice` takes `criteria` as an object of `key => description` (there is no
  `options` field) and returns `choice`, `confidence` and a `probabilities` map.
- `noul` returns a single calibrated probability (0..1).
- `score` takes `criteria` as an ordered array of 2 to 10 level descriptions and
  returns `score`, `legend`, `probabilities` and `confidence`.

Validation errors come back as HTTP 422 with a FastAPI-style body:
`{"detail":[{"type":"missing","loc":[...],"msg":"Field required"}]}`.

## The chooser contract

`Classification::JevChooser` implements the shared `Classification::Chooser`
interface (the same one `ClaudeChooser` implements), which the `TreeWalker`
calls at each step:

```ruby
# question: String
# options:  Array of { key: String, label: String }   # key = node id, label = description incl. path context
# context:  { product: String, path: Array<String>, level: Symbol (:chapter | :heading | :node), chapter_note: String|nil }
# returns:  { key:, confidence:, probabilities: { key => Float }, reasoning: String|nil, chooser: String } or nil
def choose(question:, options:, context:)
```

`JevChooser` maps the step to one `choice` question:

- `state = { product: context[:product], classified_so_far: context[:path].join(" > ") }`
- `criteria` maps each option `key` to its `label`. Labels must be unique and
  non-empty, so a blank label falls back to the key and a label shared by two
  options is suffixed with the key (`"T-shirts (6109_a)"`).
- The answer maps straight back: `key = answers[qid]["choice"]`,
  `confidence = answers[qid]["confidence"]`, `probabilities = answers[qid]["probabilities"]`,
  `reasoning = "jev p=<confidence>"`, `chooser = "jev"`.

The chooser never raises; it returns `nil` on any failure (no key, empty options,
client failure), and the walker falls back.

## Numeric routing

Jev's own documentation lists numeric comparison as a weakness (it cannot
reliably count or do arithmetic, and struggles with dates, measurements and
numeric thresholds). Several tariff branches are exactly that: "weighing not more
than 200 g/m2", "of a power exceeding 750 W", "of a capacity not exceeding 50 l".

`JevChooser.numeric_level?(options)` returns true when any option label reads as a
numeric-threshold branch: a number followed by a unit or `%`, the words
`exceeding` / `not exceeding` / `more than` / `less than` / `of a weight` /
`of a capacity` / `of a power`, or a comparison operator (`<`, `>`, `≤`, `≥`).
ASCII `<` and `>` only count when next to a digit, so a " > " path separator
inside a label is not mistaken for a comparison.

On a numeric level:

- with a `fallback:` chooser, the whole decision is delegated to it and the
  result is tagged `chooser: "claude(numeric)"`.
- without a fallback, Jev is still asked, but `reasoning` carries the caveat so
  the answer is not trusted blindly.

`Classification::Choosers.default` constructs `JevChooser.new` with no fallback,
so out of the box numeric levels go to Jev with the caveat. To route numeric
levels to Claude, construct `JevChooser.new(fallback: Classification::ClaudeChooser.new)`
(see Limitations).

## Limits

- `choice` supports at most 255 options; `JevChooser` returns `nil` above that so
  the walker falls back.
- Token budget is roughly 64k per request across state plus questions, and the
  state plus the longest single question must fit roughly 32k.
- Rate limit is 1,200 requests/min (early access, dynamic).
- Client timeout defaults to 8s, with one retry on a timeout, 429 or 5xx and a
  short backoff.

## Hosting and data caveat

TypeSafe AI is hosted on the US West Coast only; there is no EU region on offer.
Only product descriptions and tariff option text are sent to Jev (the `state` is
the analysis summary plus attributes and the original product description, and
the `questions` are tariff line descriptions). No personal data, candidate data
or account data is sent. This is worth keeping in view given the project's
preference for EU data regions, and it should be revisited if Jev is ever used
for anything beyond classifying product descriptions.

## Design Decisions

- **One `choice` question per step.** Matches the walker's one-decision-at-a-time
  shape and keeps Jev's answer constrained to the keys on offer.
- **Fail soft, never raise.** Both the client and the chooser log and return
  `nil` on any failure, so a Jev outage degrades to the walker's fallback rather
  than breaking a lookup.
- **Numeric hand-off is opt-in.** The registry builds `JevChooser` with no
  fallback, so enabling Jev does not silently require a Claude client. Numeric
  fallback is wired only when a caller passes `fallback:`.
- **No new dependencies.** Uses the existing `faraday` gem, same as
  `TariffLookupService` and `ScrapeDoClient`.

## Database Changes

None.

## New Files Created

| File | Purpose |
|------|---------|
| `app/services/jev_client.rb` | Faraday client for `POST /v1/systemone`: `evaluate(state:, questions:)`, `configured?`, and `choice` / `noul` / `score` question builders. Fails soft, one retry, logs `[jev]` usage. |
| `app/services/classification/jev_chooser.rb` | `Classification::Chooser` implementation backed by Jev, with `numeric_level?` routing and label de-duplication. |
| `test/services/jev_client_test.rb` | WebMock unit tests: request shape, response mapping, 422/500/timeout/connection handling, retry, builders, `configured?`. |
| `test/services/classification/jev_chooser_test.rb` | Unit tests with a fake client and fake fallback: mapping, criteria/state building, dedup, >255 options, numeric routing, `numeric_level?`. |
| `script/jev_smoke.rb` | Live smoke test (`bin/rails runner script/jev_smoke.rb`) covering a leaf choice + noul, a 20-option heading choice, and numeric routing. |
| `claude/implementations/jev-chooser.md` | This document. |

## Modified Files

| File | Change |
|------|--------|
| `app/services/classification/choosers.rb` | Jev is the default when `TYPESAFE_API_KEY` is set, built with `ClaudeChooser` as the numeric fallback; `TARIFFIK_CHOOSER=claude` forces Claude. |
| `test/services/classification/choosers_test.rb` | New: selector behaviour with/without the key and with the override. |
| `config/deploy.production.yml` | `TYPESAFE_API_KEY` added to `env.secret`. |
| `.env.example` | Placeholder + comment for the key. |

## Routes

None.

## Data Flow

```
TreeWalker (one decision)
   │  choose(question:, options:, context:)
   ▼
Classification::JevChooser
   │  numeric_level?(options)?
   ├─ yes + fallback ─► fallback.choose(...)  ─►  { ..., chooser: "claude(numeric)" }
   │
   └─ no  (or numeric without a fallback)
          │  state    = { product:, classified_so_far: path.join(" > ") }
          │  questions = { "choice" => JevClient.choice(instructions: question, criteria: key=>label) }
          ▼
      JevClient#evaluate ──► POST https://api.typesafe.ai/v1/systemone ──► { answers, usage, model }
          ▼
      { key: answers.choice.choice, confidence:, probabilities:, reasoning: "jev p=...", chooser: "jev" }
```

## Testing / Verification

```bash
# Unit tests (WebMock; no live calls)
bin/rails test test/services/jev_client_test.rb test/services/classification/jev_chooser_test.rb

# Live smoke test (real TypeSafe API; prints answers, latency, input tokens)
bin/rails runner script/jev_smoke.rb
```

The client tests raise `Faraday::TimeoutError` explicitly rather than using
WebMock's `#to_timeout`, which maps to `Faraday::ConnectionFailed` in this
adapter version; a real socket timeout raises `Faraday::TimeoutError`, which is
the branch under test.

## Enabling and comparing

```bash
# Jev is the default when TYPESAFE_API_KEY is set. Force Claude with:
TARIFFIK_CHOOSER=claude bin/rails runner '...'

# Compare choosers on the 88-ruling set (sequential on purpose)
EVAL_FILE=test/eval/rulings_eval_set_large.json bin/rails "eval:rulings"
TARIFFIK_CHOOSER=claude EVAL_FILE=test/eval/rulings_eval_set_large.json bin/rails "eval:rulings"
```

Results on 22 Sep 2026 (`test/eval/results/pipeline-{jev,claude}-88.json`):

| | Claude chooser | Jev chooser |
|---|---|---|
| Heading correct | 64% | 59% |
| 8-digit correct | 50% | 49% |
| 10-digit correct | 45% | 45% |
| Median latency | 16.9 s | 9.2 s |
| Claude calls per lookup | 5.0 | 1.9 |

257 of 335 tree decisions went to Jev; 77 numeric-threshold levels went to
Claude. Scoring only decisions taken while still on the correct path, Claude's
self-reported confidence rose monotonically with accuracy (27%, 48%, 77%, 93%)
while Jev's top bucket (p >= 0.97) was right 72% of the time, so on this task
Jev's probabilities were not better calibrated than Claude's. Jev was chosen as
the default for latency and cost at equal accuracy.

## Limitations & Future Improvements

- **Calibration not yet proven on this task.** Jev's per-step probabilities
  did not beat Claude's self-reported confidence on the 88-ruling set (see
  above); the end-to-end confidence shown to users is still the product of
  per-step values and should be re-checked as the eval set grows.
- **`score` questions are unused.** The client exposes a `score` builder, but the
  walker only asks single `choice` questions today. A `score` question could
  drive confidence-banded behaviour later.
- **No token metering integration.** `ClaudeChooser` records Claude tokens via
  `Classification::TokenMeter`; the Jev client logs `input_tokens` at info level
  but does not feed the meter, since the meter is Claude-token specific.
- **US-only hosting.** No EU region (see the hosting caveat).
