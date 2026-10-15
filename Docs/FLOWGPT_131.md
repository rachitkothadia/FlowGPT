# FlowGPT 1.3.1

This patch fixes the reported shopping transcript's structure. The original words, language, explanation and question order are preserved.

The formatter now establishes related declared items across sentences before splitting coordinated phrases. Explanations such as “So for laptop I would go for Dell Alienware” stay with the preceding item. A declared object list uses circle bullets even when the items have ordinal labels; actual procedural sequences retain numbering.

Leading connectors stay with their following item. A literal `• And` followed by `• then ...` is repaired into one bullet, outside protected quotes/code. Existing bullets no longer disable formatting of the remaining prose in the entire transcript. Each existing bullet line is protected from being split into smaller items.

A bounded recent-list context permits an explicit addition such as “a toothbrush as well” after a question and a brief acknowledgement. Questions and unrelated complete statements remain prose. This uses native structural rules and adds no network request, model or prediction history. It cannot infer every ambiguous conversational relationship or repair missing speech-recognition words.

The regression set includes the complete supplied transcript both before formatting and with the malformed bullets already present, plus meeting agendas, travel purchases, long technical explanations, Hindi/Marathi examples, quoted/code negatives, unrelated statements and connector chains. Assertions compare the full output and verify that formatting it again does not change it.

## Reported example after the fix

```text
Okay. So I'm going for DMart. So I have multiple things which I need to buy.

• One is the laptop. So for laptop I would go for Dell Alienware.
• And second is MacBook sleeve, because I need to cover my MacBook.
• The third is a charging cable for my MacBook, which is gonna be C to C type.
• And then I would go for wafers
• and maybe some T-shirts.

And Brijesh, तेको क्या चाहिए? Okay.

• So a toothbrush as well.
```

Capture, login storage, permissions and insertion are unchanged. The installed Mac app and its permission grants were not modified during packaging. macOS and Windows preview-signing limitations described in the installation guide still apply.

## Verification

- 96 shared full-output cases pass, including repeat-formatting checks.
- 577 portable C++ checks pass.
- 123 Swift tests pass.
- The fixture harness passes AddressSanitizer and UndefinedBehaviorSanitizer checks.
- A 1,000-item no-introduction list retains every item and formats in about 12 ms on the development Mac. This measures local formatting, not transcription latency.

These are software/fixture results; they do not establish perfect classification of arbitrary speech or new live-microphone/Office behavior. Packaged-platform evidence is recorded below when the release jobs finish.
