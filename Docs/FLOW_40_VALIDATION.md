# Flow 4.0 validation

## Implementation

The shipped text path is now Whisper transcription → one GPT-OSS formatting request → insertion. GPT-OSS returns plain text. All original recognition text reaches the formatter unchanged; all returned formatter text reaches insertion without local linguistic scoring, correction, list rendering or quote processing.

Removed production modules: DictationIntelligence (vocabulary replacement and preservation guard), LanguageMemory, PhraseSlipEngine, QuotationEngine, TerminologyPacks, TranscriptCleanup, TranscriptLearning and UseCaseDetection. Removed SQLite target/dependency, learning controls, vocabulary mappings and use-case settings. Removed Qwen fallback. Basic HTTP authentication, cancellation, malformed/truncated-response checks, recording/clipboard/destination safety and raw-transcript outage delivery remain ordinary app infrastructure.

One multilingual system prompt handles language/script preservation, clear recognition repairs, tone, content, punctuation, paragraphs, lists, steps, direct quotes, UI-label quotes and programming terminology. Custom instructions remain optional. No examples are production word substitutions. Verbatim/formatting-off bypasses GPT-OSS without local edits. A first-launch preference migration selects automatic language recognition; other saved recording, shortcut, history and appearance settings remain.

App identity is unchanged. Microphone, Accessibility, Input Monitoring, shortcut, popup, insertion and continuous recorder implementations were not edited. The existing LanguageMemory directory is preserved but no longer accessed. API keys and permissions were not deleted or reset. Packaging does not replace the installed app.

## Validation observations

- Native tests cover the new direct plain-text path, ignored legacy intelligence fields, mixed-language request content, and existing cancellation, archive, history, clipboard ownership, destination and popup behavior. Removed engine tests were removed with their engines; remaining recording/archive tests were retained separately.
- `QA/flow40-cases.json` contains held-out Hindi, English, Marathi, three-language, Bengali, shopping, independent errands, ordered steps, counted requirements, programming, direct/UI quotes, informal pronouns and meeting cases.
- `QA/flow40-initial-live-results.json` records the first live run. Storage formatting returned HTTP 200 and kept the required mixed-script content. Errands returned HTTP 200 but incorrectly added closing deferral as a fifth bullet and introduced a hyphen in “driving license.” This prompted a general prompt clarification: closing completion/deferral comments stay prose; ordinary words do not acquire decorative hyphens.
- Subsequent initial-run requests hit GPT-OSS's daily token quota (HTTP 429). These are failures/blocked coverage, not passes. The compact revised prompt is evaluated separately, without a different model or API key.
- Release test/build logs, final text observations and speech smoke results are recorded alongside this report. Live synthetic speech is not evidence of natural-speaker accuracy. No 100% accuracy claim is made.

## Final release evidence

- Native release: **93 tests in 11 suites passed**; warnings-as-errors arm64 build passed. The smaller test count reflects removal of obsolete intelligence tests, not a claim of equal feature coverage.
- Current compact prompt: `QA/flow40-recheck-results.json` records **1/4 passed** (Hindi-Marathi-English in one input). The other three requests returned **429** without text, so the revised errands formatting, Marathi steps and exact quotes remain unverified live.
- Earlier prompt: the storage case passed, the errands case failed, and remaining first-run requests were quota-blocked. The initial successful storage output is not a fresh pass for the subsequently revised prompt.
- Speech smoke: four reused synthetic English/Hindi WAV files through automatic recognition returned **Whisper 200 for all four**. GPT-OSS returned **429 for all four**. The QA diagnostic retained each raw transcript exactly, mirroring the application's separately tested outage-delivery behavior. This establishes API recognition connectivity, not perfect acoustic accuracy or completed formatting.
- Packaged app `--clipboard-check`: private pasteboard multiple items/all formats, concurrent copy and empty restoration passed. This does not exercise a real editor or the user's clipboard.
- Bundle self-check: version 4.0.0, arm64, in.vardaan.flow identity, microphone usage text and user guide present. Signature and mounted DMG checks are performed on the final package.

## Limits

Prompt-only editing may repair or introduce errors. Formatting is model-driven and can vary. The user's original audio behind the storage example was unavailable, so checking its text cannot prove acoustic recognition accuracy. Real Fn presses, real microphone capture, installed permission status and every editor were not newly checked in this pipeline release. Existing insertion and popup validation describes earlier separately verified behavior. Real multi-hour recordings remain unverified.
