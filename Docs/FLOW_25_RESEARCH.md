# Flow 2.5 research and implementation decisions

10 October 2026. Sources inform design, not a claim of equivalent Wispr accuracy.

## Real uses and survey boundaries

[Wispr use cases](https://wisprflow.ai/use-cases) documents email, text messages, ideas, developer tools and meeting notes. Its [product site](https://wisprflow.ai/) lists email/chat, Notion, terminal/code editors and AI tools. These support tests for communication, notes, study, programming and workplace dictation. Shopping, recipes, travel, customer support, finance, real estate, healthcare notes, legal notes, research and personal journals extend that test matrix based on the user's needs; this is not a statistically representative sector survey.

Community reports include [mixed-language boundaries](https://www.reddit.com/r/productivity/comments/1ssk0ys/wispr_flow_alternatives_for_multilingual_users/), [language-switch translation](https://www.reddit.com/r/WisprFlow/comments/1ufmx15/wisprflow_is_now_live_translating_me_when_i/) and [keyboard/shortcut conflicts](https://www.reddit.com/r/WisprFlow/comments/1seahqg/wispr_flow_with_multiple_language_keyboards/). These are qualitative anecdotes with selection bias. They motivated preservation checks and mixed-script testing; they do not establish population accuracy or usage percentages. Quora searches did not yield reliable survey evidence, so no Quora statistics are asserted.

## Speech recognition and language limits

[Groq speech documentation](https://console.groq.com/docs/speech-to-text) supports Whisper Turbo/full v3 and vocabulary prompts. [Whisper's official tokenizer](https://github.com/openai/whisper/blob/main/whisper/tokenizer.py) supplies the valid language tokens. Flow covers the 22 scheduled Indian languages in its catalog but never sends unsupported tokens. Fourteen have dedicated tokens; eight do not. A text formatter preserving an Odia or Meitei script is not evidence of correct speech recognition in that language.

[Wispr multilingual research](https://wisprflow.ai/research/supporting-languages) describes an ensemble of recognition models. A single Whisper API plus prompt cannot reproduce that acoustic system. [Language settings](https://docs.wisprflow.ai/articles/3191899797) distinguish preferred languages and Hinglish. Flow preserves mixed native scripts and English terms; it does not force all native language text into Latin transliteration.

## Our intelligence layer

Unicode tokenization, approved contextual corrections, SQLite phrase counts, technical packs, quotation rules and a strict preservation guard are local Swift components. The guard rejects word changes, lost negation, reordered content and modified technical symbols/numbers, reverting to the corrected baseline. The two remote stages remain transcription and optional punctuation/layout generation. No new acoustic, phonetic or semantic recognition model is claimed.

The six NLP perspectives inform evaluation: sound quality/rate for phonetics and phonology; inflections and informal pronouns for morphology; names/ingredients/jargon for vocabulary; order/lists/quotes for syntax; numbers/negation/substitutions for semantics; familiarity and direct speech for pragmatics. This does not mean six independently trained engines exist. Exact correction rules and phrase matching are deterministic. The phrase matcher requires repeated human approvals, exact unchanged context, a unique one-character substitution and no accepted competing wording; it remains fallible and can be disabled.

## Long capture and insertion

[Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/scstreamoutput) supplies computer-audio callbacks; microphone capture uses AVAudioEngine. Durable PCM segments and a serialized recovery queue separate recording from API latency. File-based transcription is incremental, not a streaming recognition socket. [Groq quotas](https://console.groq.com/docs/rate-limits) can prevent ten hours of immediate cloud transcription even if local capture continues.

Automatic insertion uses existing captured-target/secure-field checks, Accessibility writes and Unicode events. The user requested no clipboard interaction; this is a different compatibility tradeoff from Command-V. Real app compatibility must be tested separately from fake insertion tests.

## Design

The floating strip is 150 by 30 points with a microphone and waveform, no text card or visible border. It uses native SwiftUI/AppKit. The user explicitly asked for a small dark strip; the earlier large glass completion card is removed. Errors are retained in settings/results and indicated by the mic tint/accessible description. Screaming does not automatically create uppercase text: loudness is also affected by distance, microphone gain and noise.
