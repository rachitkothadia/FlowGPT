# FlowGPT 1.3

## Output changes

Both platforms use the same native C++ UTF-8 engine. Formatting adds no network request. The original provider transcript remains in History.

- Related coordinated item phrases and parallel actions can become lists without saying “list”, “first”, “second”, “like” or “जैसे”. Introduction words are optional grammatical context.
- Ordinary lists and shopping/to-do items use circle bullets (•). Separator commas become line breaks; spoken conjunctions and item wording remain. Full conversational clauses, addressed questions and self-corrections remain separate, in spoken order.
- Procedural actions can become numbered lines without requiring spoken numeric labels. Explicit numeric sequences remain supported without a small item limit.
- A price/item continuation after a question can resume the list without moving the question or inventing a heading.

Detection examines text structure and repeated predicates, not a product dictionary. It remains heuristic: ambiguous discourse and mixed grammatical structures cannot be classified perfectly without semantic inference. Tests cover both the reported successes and cases that should remain prose. No claims of universal semantic accuracy or recovery of words the provider omitted are made.

## Currency amounts

The compiled table uses [Unicode CLDR](https://cldr.unicode.org/translation/currency-names-and-symbols), pinned at commit `91c267402229a59e3ef2774544f001bf959e8809` (48.2.3). It contains 307 identifiers, including historical currencies and accounting units, and translated names from 23 locales. Every identifier is supported beside an identifiable amount. English and common Hindi/Marathi spelled amounts and decimal digits from multiple scripts are supported; unsupported spellings and fractional expressions remain unchanged.

Examples: “hundred rupees” → ₹100, “fifty dollars” → $50, “twenty euros” → €20, “25 Canadian dollars” → CA$25, “100 Japanese yen” → ¥100. Explicit national dollar names retain their distinguishing symbols. Currency codes stand in when no suitable distinct symbol exists; this is not an invented symbol.

Generic rupees use INR (₹), matching this app's stated Indian context; generic dollars use the shared family sign $. Other ambiguous unqualified names such as “pesos” or “crowns” are not assigned a country. “Ten pounds of rice” is not treated as GBP. Quotes, code, dates, technical code collisions and unsupported modifiers are protected. Currency formatting is an explicit exception to preserving the exact written words of a monetary amount: no exchange conversion, rounding or inference of unclear numbers is performed.

The dataset is vendored, reproducibly generates `CurrencyData.h`, and its Unicode license is included in both installers. No live exchange-rate or currency service is used.

## Runtime and permission scope

Permissions, login persistence, audio capture, insertion, clipboard restoration, background lifecycle and updater consent are unchanged by this release. macOS preview builds remain ad hoc signed and unnotarized; a changed build can still require renewed grants until stable Developer ID signing is configured. Windows previews remain unsigned.

The currency table is initialized from read-only rows into a heap lookup, avoiding a large automatic initializer on small worker stacks. This was corrected after a failing Swift worker-thread test. Formatting exceptions return the original text through the existing C API.

## Verification of the release

Application source: `853b0fe92f2b0a8af2a4a06bc60aa98777ba04ce`. Later documentation and benchmark-counter changes do not change the packaged application. The benchmark counter includes the first bullet, which has no preceding newline.

| Check | Result |
| --- | --- |
| Local Swift suite | 123 tests passed |
| Portable C++ policies | 547 checks passed |
| Shared formatting cases, exact output and idempotence | 81 cases passed on both native adapters |
| Currency-code coverage | All 307 identifiers checked beside an amount |
| No-introduction 1,000-item list | All items retained; about 12 ms on the development Mac; formatted output remains unchanged on a second pass |
| Packaged Mac synthetic browser checks | 50 passed |
| Packaged Mac window checks | 10 passed |
| Mac CI | [Passed for the release source](https://github.com/rachitkothadia/FlowGPT/actions/runs/38645289440) |
| Windows CI | [Passed for the release source](https://github.com/rachitkothadia/FlowGPT/actions/runs/38645289647) |
| Windows actual app/browser fixtures | 54 checks passed |
| Windows UI smoke checks | 17 checks passed |
| Windows install, prior-release upgrade, reinstall and uninstall | 11 checks passed |

Evidence: [formatting report](formatting-validation-13.json), [shared input/output cases](../Shared/Tests/formatting.json), [Mac browser fixture report](mac-browser-fixtures-13.json), [Mac window fixture report](mac-window-fixtures-13.json).

Windows evidence: [native app/browser report](windows-native-fixtures-13.json), [UI smoke report](windows-ui-fixtures-13.json), [installer report](windows-installer-fixtures-13.json). The downloaded Windows artifact was checked against its GitHub SHA-256 digest and each extracted file's ZIP CRC; the installer was checked against its bundled checksum before release upload. Uploaded installer and checksum digests were checked against local bytes.

| Installer | SHA-256 |
| --- | --- |
| `FlowGpt-1.3.0-arm64.dmg` | `020491245a1ae1ee6c7d4712cec88e1b7e22d7c48c6ec0962fbf8c3cfcfd22e9` |
| `FlowGPT-1.3.0-Windows-x64-Setup.exe` | `d7feb53edf67c4746f6a8a45e8ff2346a9af87cc58873a0fdeaf35b40e876c9c` |

The suites cover Hindi, English, Marathi, mixed scripts, additional language examples, no-introduction shopping items/tasks, procedural steps, questions interrupting lists, repetitions, self-corrections, quoted/code content, existing provider bullets, negative numbers, currency identities and uncertain amounts. The coverage is software/fixture evidence, not a guarantee of speech recognition accuracy. Real microphone capture, live ChatGPT transcription, physical Windows typing and Office insertion were not newly verified for this formatting release. The historical device checks retain their original scope and versions.
