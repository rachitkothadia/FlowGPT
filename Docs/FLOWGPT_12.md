# FlowGPT 1.2

## Formatting

Mac and Windows call the same native C++ UTF-8 formatting engine. This adds no network request. The provider's original text is retained in History before any insertion.

- Clearly introduced enumerations become bullets, regardless of the named products, tools or sector.
- Explicit to-do lists become checkboxes. Spoken sequential labels become numbered lines, retaining the spoken labels too.
- Literal consecutive numeric labels have no small item limit.
- Only list portions are structured. Trailing personal speech stays prose; multiple lists can coexist.
- Clear hesitation sounds can be removed. Meaningful uses, quotations and code identifiers are retained.
- Scripts, repetitions, corrections, unfinished wording, numbers, names, URLs and code remain intact. No correction dictionary, translation, autocomplete or AI rewrite is used.

The five supplied samples are covered as content-preservation fixtures. Their illustrative punctuation is not promised byte-for-byte: the native formatter does not infer arbitrary grammatical sentence boundaries or pauses from text alone. In sample 5, the first spoken `rachit` URL is retained alongside the corrected `rachitkothadia` URL. Replacing the original with the correction would contradict the core rules.

No formatter can reconstruct speech omitted or misrecognized by the upstream transcriber. Ambiguous prose stays prose rather than guessing a list.

## Permission handling

Mac indicators now read the running app's actual permission APIs. A helper denial cannot overwrite a grant held by the app. A helper grant is not presented as permission to record; it can only suggest reopening when macOS still has cached keyboard denial. An already authorized microphone does not trigger another permission request. Probes have a two-second timeout. No TCC resets or settings database writes are performed.

Three fresh LaunchServices probes of the unchanged installed 1.1.1 build returned all three grants as true. This supports retained system grants, but does not reproduce the user's reported loss. A misleading helper snapshot was found in the indicator code and corrected.

The preview Mac package is ad hoc signed. Its designated requirement changes with its binary; installing a different build can require new grants. A stable Developer ID certificate is required for reliable identity across upgrades. Reopening an unchanged installed build does not rewrite or resign it. This is distinct from a same-version relaunch.

Windows keeps its browser profile and settings in the same per-user directory. The browser microphone gate no longer saves temporary allow/deny decisions into that profile. A previously saved ChatGPT website microphone decision is reset to default before loading, without touching Windows' microphone privacy setting, browser login or other website permissions. Actual access remains restricted to the trusted origin during explicit dictation.

## Verification boundaries

The shared fixtures test output and repeated formatting on both platforms, including arbitrary tools and shopping items, English, Hindi, Marathi, Hinglish, Gujarati, protected literals, ordinary prose, technical corrections and the exact reported website example. Native policies, session cancellation, history and installer lifecycle suites run separately.

Windows testing uses a Windows runner, isolated WebView2 profile, synthetic audio and disposable editors. It does not establish physical microphone or real ChatGPT-account success on every friend's laptop. No claim of perfect ASR or universal formatting accuracy is made.
