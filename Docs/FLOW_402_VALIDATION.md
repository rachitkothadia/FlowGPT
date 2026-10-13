# Flow 4.0.2: general script selection and complete lists

The single GPT-OSS system prompt now explicitly asks for contextual analysis of EVERY word and multiword phrase, across unfamiliar vocabulary/topics. English speech uses standard Latin spelling; Hindi/Marathi stays Devanagari; other languages retain their native scripts. This is model-driven transliteration/spelling selection, not translation. No local dictionary, classifier, NLP history, prediction or validator is introduced. Existing discourse-marker examples illustrate a general rule and are explicitly non-exhaustive.

Bullets, continuously numbered enumerations/steps, punctuation, paragraphs and quotes remain. Numbering must continue through every actual item, without a fixed item-count cap or substitution of an ellipsis/summary for later items. Explicit arrows or concise directional flows can use →, ← and ↔, without discarding full explanations or inventing relationships. Introductions and completion/deferral commentary remain outside lists.

Literal infinite output is impossible: each request has a finite service/input/output limit. Flow has no separate 3-, 4-, 10- or 20-item limit. Its existing output budget scales with input up to 8192 completion tokens; truncated responses are rejected and ordinary sessions deliver the raw transcript with a formatting-unavailable notice. Continuous recordings are segmented and have their separately documented constraints.

Recording, permission, shortcut, popup, insertion, key and history implementations are unchanged. This release updates the system prompt and package/version only, plus developer tests/reports. It is not installed automatically.

## Validation

- Native transport tests pass 200 numbered items and 40 mixed-script bullet/arrow lines through the actual formatter client without local clipping or rewriting. Those responses are mocked and cannot demonstrate model accuracy.
- `QA/flow402-cases.json` covers unfamiliar English phonetic spellings inside Hindi/Marathi, an English phrase, native vocabulary preservation, twelve numbered items, ten ordered tasks, ten bullets, arrows and punctuation. These are evaluation inputs, not production replacement words.
- Live observations are recorded in `QA/flow402-live-results.json`. A successful HTTP response is evaluated for actual required words, native terms, item counts, numbering and arrows. Quota/network failures are not passes.
- Existing flow and archive tests cover cancellation, raw-transcript outage delivery, clipboard ownership, insertion targeting and history. These software checks do not establish real microphone accuracy, a physically infinite list or reliable recognition of every word.

## Release observations

- **95 native tests in 12 suites passed**; arm64 release build with warnings-as-errors passed. The 200-numbered-item and 40-bullet/arrow observations use mocked model responses and demonstrate absence of app-side clipping only.
- Live production run: **1/5 passed**. The 12-item enumeration returned **GPT-OSS HTTP 200**, with all twelve English phonetic spellings converted to Latin and every consecutive number 1–12 present. Hindi introduction and closing commentary remained Hindi and outside the list. No previous storage/example words were required to trigger conversion.
- Actual items were notebook, charger, umbrella, detergent, envelope, towel, adapter, headphones, calendar, stapler, soap and bottle. These appear solely in developer evaluation input/output, not in production prompt substitutions or a word dictionary.
- Other live cases returned **429 daily quota failures** without text. Unfamiliar multiword Hindi/Marathi-English passages, live arrows/punctuation, ten bullets and ten ordered errands therefore remain unverified for this prompt. No failure is reclassified as a pass.
- Developer QA whitespace normalization and optional case-insensitive comparisons affect assertions only; model output and production requests remain unchanged. Required technical-case assertions in older cases remain case-sensitive by default.
- The package preserves the two-model prompt-only pipeline and existing app services. DMG integrity, mounted signature/self-check, executable and packaged report comparisons are performed on the final 4.0.2 installer. Building/package verification does not replace the installed app or reset grants.
