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
