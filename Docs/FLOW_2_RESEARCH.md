# Flow 2.0 research and formatting decisions

Research completed 10 October 2026 before implementation.

## What the supplied comparison shows

The website example already contains the introduction and all three items. The missing step is recognizing “three things” as enumeration and placing frontend, backend and database on separate numbered lines. Adding information or rewriting the introduction is unnecessary. The Hindi example should retain its question mark and final danda. Mixed Hindi and English needs brand names, quantities and English words preserved instead of transliterated arbitrarily. Neither supplied Marathi transcript is reliable enough to reconstruct the original sentence without its audio.

## Findings from primary sources

[Wispr Smart Formatting](https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack) documents sequence cues for lists, spoken punctuation, line breaks and corrections. Its cleanup distinguishes correction phrases from meaningful uses of the same word. Flow 2.0 implements these behaviors through a constrained dictation-editing prompt and examples. Wispr's exact production system prompt is not publicly established by these sources; this implementation is original.

[Wispr multilingual research](https://wisprflow.ai/research/supporting-languages) describes choosing transcription engines for particular languages, training formatters from corrections, and using accent-aware processing. Its claimed accuracy gains are vendor-reported internal results, not a benchmark of this app. A formatting prompt alone cannot reproduce a separately trained speech recognition system.

[Wispr language guidance](https://docs.wisprflow.ai/articles/3191899797) recommends selecting the intended language when detection is wrong. This supports a dedicated Marathi selection rather than silently forcing all mixed Hindi/English speech into Marathi.

[Groq speech documentation](https://console.groq.com/docs/speech-to-text) provides Turbo and full Whisper v3, accepts language hints, and describes vocabulary prompting as context/style guidance. Flow 2.0 keeps Turbo for Automatic and uses full v3 with `mr` when Marathi is selected. This is an accuracy-oriented option, not proof that every Marathi utterance will improve.

[Apple Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) provides native glass surfaces and containers. The recording card uses these APIs on macOS 26, system material on older supported releases, and an opaque accessible fallback with Reduce Transparency.

## Natural wording rules

The editor keeps the speaker's vocabulary, contractions, register and intent. It removes only meaningless hesitation, resolves explicit corrections, organizes clear enumerations, and keeps casual requests in prose. It does not add corporate vocabulary, generic enthusiasm, greetings, headings, conclusions, Markdown emphasis or explanations. Words actually dictated are preserved even when they are common in generated writing.

An em dash is a punctuation choice, not reliable evidence of AI authorship. The user's preference is enforced both in the prompt and after generation. Narrow nonbreaking spaces are normalized to ordinary spaces. No claim of guaranteed human authorship or reliable AI-detector evasion is made.

## Verification boundaries

The live formatting suite sends known text inputs through the actual GPT-OSS client. It checks list structure, corrections, natural prose, names, quantities, scripts, punctuation and preservation of uncertain Marathi wording. Passing these tests measures formatting for those examples; it does not measure recognition from the user's voice. Real Marathi accuracy needs representative recordings and reference transcripts. The original audio was not provided.

The complete production instructions are in Sources/FlowCore/DictationFormatting.swift. Reproducible inputs and live outputs are in QA/formatting-cases.json and QA/formatting-results.json. Run Scripts/evaluate-formatting.py with a configured local key to repeat the evaluation. Rate limits are reported separately from formatting quality.
