# Flow 3.0 validation

## What changed

The previous list prompt favored announced counts and explicit enumeration. Its exact-token guard also rejected useful common-word spelling repairs and could discard all layout. Flow 3.0 separates source-based list layout from bounded spelling correction.

GPT-OSS identifies complete items across arbitrary topics and supplies exact original source spans. Swift checks that spans exist, are unique, ordered, non-overlapping and aligned to word boundaries, then renders the original clauses. Introductory and closing text stays present. If the model duplicates, paraphrases or omits words, valid source spans can still recover the list. No example task, brand or phrase is used as a production replacement rule.

Spelling proposals are separately declared. Local validation requires model confidence of at least 0.9, a bounded Unicode edit distance, unchanged script, one source occurrence and a small overall correction budget. It protects grammatical meaning words, quantities, identifiers, capitalized words, quotations, approved vocabulary and starter programming names. Rejected token changes can be restored without discarding valid punctuation or layout. This is conservative validation, not proof of semantic equivalence: model confidence and spelling resemblance do not establish what an audio recording said. Ambiguous/severely garbled words may remain unchanged. Model proposals are never added to the user's approved phrase database.

Confirmed transcript learning is a separate local path. It aligns any human-corrected pair with a Unicode-token longest-common-subsequence algorithm. Only isolated, similar word changes with at least two matching context words can become contextual rules; rewritten spans, quantities, identifiers, protected grammar and competing existing rules are excluded. The History page previews extracted corrections before the user approves them. Lessons are bounded to 600-word windows; recording length is unaffected. The user's supplied Wispr comparison was explicitly confirmed by the user and taught two contextual word corrections. These are private user data, not hardcoded production substitutions. Unseen-context automatic Hindi repair remains a separate test and must not be conflated with personalized success.

Full Whisper large-v3 is the default when no recognition choice is saved. Existing explicit Fast/Turbo preferences are preserved. Raw/Verbatim mode still bypasses AI cleanup. The raw transcript remains available separately from the final result.

The primary text model remains GPT-OSS 120B. A rate-limit response permits one alternate Qwen 3.8 27B request to the same fixed Groq text endpoint with the same key. The alternate uses a compact prompt, disabled reasoning and an 896-token output limit; both responses go through the same local validation. Authentication failures and uncertain network errors do not trigger this fallback. The account's observed GPT-OSS daily token cap and Qwen per-minute cap motivated this path. Catalogue availability is not inference quota. Malformed/truncated cleanup returns the complete source, potentially without useful formatting.

Live output exposed equivalent transport labels: `bulleted`/`unordered` are accepted as bullets, `ordered` as numbered, and correction kind `spelling` as orthographic. Unknown list styles and grammar/translation repairs remain rejected; source validation and the correction budget still apply. A nonnumeric confidence is rejected. Ordinary sessions now also deliver the complete recognized transcript if optional cleanup throws, with a notice. Cancellation is propagated and prevents insertion. This is distinct from reporting an API success; the inference probes and QA logs keep actual HTTP failures.

The Settings recording path includes the 2.5.2 fix: recording inside Flow previews the result locally and never writes into settings fields. Permission, insertion, microphone and shortcut service implementations were not changed for 3.0. The installed app and existing macOS grants are not reset by building this release. Installing this ad hoc signed binary may still require renewed macOS permission grants.

## Evidence

- `Tests/FlowCoreTests/Flow30Tests.swift`: source-based recovery, general implied lists, bounded English/Hindi spelling repairs, rejection of pronoun/quantity changes, protected names and quotes, duplicates, malformed responses, dropped/invented clauses, translations and technical mutations.
- `Tests/FlowCoreTests/TranscriptLearningTests.swift`: held-out English/Hindi transcript lessons across topics, context mismatch protection, 100 repeated deterministic applications, rejected rewrites, and persistence/conflict preservation. Temporary databases isolate these tests from personal memory.
- `QA/flow30-cases.json`: live cases include the user's four-task example, Hindi-English errands, travel, research, shopping, counted concepts, spelling errors, informal tone, quantities, unseen names, programming terms, narration, alternatives, compound actions and button/direct quotations.
- `QA/flow30-release-final-results.json`: expanded production-path outputs, model candidates, HTTP statuses, latency and case-specific checks. `QA/flow30-final-regression-results.json`, `QA/flow30-spelling-recheck-results.json` and `QA/flow30-outage-recheck-results.json` record later fixes/rechecks. Tests check more than whether the endpoint returns 200. These are text-pipeline tests, not acoustic accuracy measurements. Earlier result files are retained as failed/intermediate experiments.
- `QA/flow30-personalized-targets.json`: three actual rate-limit/fallback checks passed. The two Hindi spelling cases used the user's human-confirmed contextual rules; the Hindi-English task-list case tested source-based rendering. These do not prove unseen Hindi spelling correction.
- `QA/flow30-speech/recheck-results.json`: 18 reused synthetic Hindi/English recordings through actual transcription and cleanup endpoints, with automatic recognition language and automatic use-case selection. Normal, fast and attenuated speech are separate cases. Synthetic voices do not substitute for the user's natural mixed-language recordings. `results.json` is the earlier explicit-language run.
- `release/release-tests.log` and `release/release-build.log`: native suite and release build evidence.

An intermediate 20-case production run passed 17 cases. It exposed two counted-list classification failures and a prohibited-alternative sentence incorrectly treated as a second task. These failures prompted general count-priority and single-action-with-constraint instructions, followed by a fresh expanded run. Final measured counts are recorded below after that run. Historical 2.5 reports describe older builds and should not be treated as current 3.0 results.

## Measured results on 11 October 2026

| Check | Observed result | Practical limit |
| --- | --- | --- |
| Native release suite | 116 tests in 12 suites passed | Mocked capture/insertion and storage simulations are not real microphone sessions. |
| Expanded live text run | 22/24 passed; 20 cases used Qwen after GPT-OSS quota responses | Two failures remained in that run: research task classification and nonnumeric spelling confidence. Median text-stage latency was 0.70 s, maximum 2.44 s; this excludes microphone capture/STT. |
| Six targeted text regressions | Four passed initially; spelling kind alias and a real HTTP 503 failed | After fixing the alias, spelling passed a fresh 1/1 live recheck. The lecture case passed its separate 1/1 recheck. All six have a passing later observation, across separate runs, not one fresh 6/6 run. |
| Latest synthetic audio | 18/18 completed recognition and cleanup; every speech request returned 200 | Text requests often included primary 429 followed by fallback 200. Synthetic speech cannot establish natural-speaker accuracy. |
| English synthetic recognition | 6/9 had zero normalized word errors; mean WER 2.38% | All three meeting cases rendered spoken "ten" as "10", counted as a token error by this metric. |
| Hindi synthetic recognition | 6/9 had zero normalized word errors; mean WER 8.73% | Shopping cases still misrecognized words. Full Whisper did not make these perfect. |
| Strict raw/final word identity | 16/18 synthetic cases passed | The other two changed only the declared spelling चाबल to चावल, keeping the remaining words. Their output still contained other unresolved recognition errors. |
| Text-service outage delivery | Simulated 503, rate limit, network failure and timeout each delivered the complete recognized source exactly once | Real cross-application delivery on this new bundle remains unverified. API failures are still reported as failures in inference probes. |

Main-model count classification was inconsistent in an earlier run. Later count-pattern guidance is present in the release, but the exhausted primary daily quota prevented a complete fresh primary-only benchmark. Successful fallback counts must not be represented as proof of primary-only classification. The two personalized Hindi repair successes depend on human-confirmed local rules, not an independently demonstrated repair of every unfamiliar Hindi phrase.

## Remaining validation limits

No claim of 100% speech recognition is made. The original recording behind the user's Wispr comparison is unavailable; the competing outputs cannot be acoustically compared from text alone. Long real-time microphone sessions, physical Fn shortcuts, insertion across every destination and all Indian-language accents require real hardware/user recordings. Passing synthetic audio or mocked session tests does not establish those results. Shouting-based uppercase remains unimplemented; volume alone cannot safely establish shouting intent.
