# Flow 4.0.1: English script in mixed dictation

The user's mixed Hindi/English dictation left recognizable English words and phrases phonetically written in Devanagari. The installed app was verified as 4.0.0, with formatting enabled, Clean Dictation mode and automatic spoken language. A matching saved history entry had identical raw/final text; that alone cannot distinguish an outage from a model returning unchanged text.

The failure was independently reproduced through the production formatter: GPT-OSS returned HTTP 200 but kept English words in Devanagari. Two additional baseline cases were blocked by daily quota 429. Evidence: QA/flow401-before-results.json.

4.0.1 changes only the formatting system prompt and release documentation/version. Script selection comes first and is reiterated at the end. It covers everyday borrowed English words and complete phrases, not only technical words. Fidelity explicitly preserves spoken meaning, not ASR's phonetic script. Native vocabulary stays native; Marathi is not translated into Hindi. Bullets, numbered steps, tone, punctuation, quotes and completeness requirements remain.

There is no dictionary, local transliteration engine, learned correction, prediction, rewrite validator or extra model. Recording, insertion, permission and shortcut code is unchanged. Keys/preferences/history are not deleted. GPT-OSS outages still deliver raw recognition, so script conversion cannot happen when formatting is unavailable or deliberately bypassed.

Live revised-prompt results are recorded in QA/flow401-after-results.json. HTTP failures are not passes. Software tests verify pipeline delivery; they do not prove language accuracy. The original recording was unavailable, so this is a text-stage reproduction, not a new microphone accuracy benchmark.

## Final evidence

- Final arm64 release build passed with warnings treated as errors; 93 native tests in 11 suites passed.
- The intermediate prompt returned HTTP 200 and converted MacBook/storage/give me some tips/optimise, but left the English opening in Devanagari. This led to a general prompt clarification covering acknowledgements and discourse markers, with non-exhaustive examples. These are model instructions, not local replacement rules.
- The final prompt passed the user's exact sentence: **GPT-OSS HTTP 200, 1/1 case passed**. Actual output:

  Okay, so मेरे MacBook में storage बहुत कम है और मुझे storage निकालना है तो give me some tips कि जिससे मेरा storage optimize हो जाए।

- QA comparisons normalize whitespace and accept both legitimate optimise/optimize spellings. Production output is unchanged. The original intermediate observation is preserved in QA/flow401-intermediate-results.json, including its original strict check failures.
- Additional held-out English-phrase and Marathi cases were quota-blocked during the baseline run. They are not demonstrated passing observations. The final successful check establishes this particular text conversion, not perfect recognition or universal script selection.
- Before success, daily quota responses were preserved. The same saved key and production GPT-OSS formatter were used throughout; no model fallback or key switch.
- The final DMG is in the project root. Mounted bundle signature, self-check and binary byte comparison passed. The installed /Applications/Flow.app was not replaced and remains 4.0.0 until the user installs this release.
