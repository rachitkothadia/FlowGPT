# FlowGPT 1.1.1 preview

Both platforms check this repository's published releases shortly after startup and every six hours while running. Mac displays a nonactivating update panel; Windows queues a silent tray notification that opens About when clicked. Dictation delays checks/notices, and each version is announced once per launch. A fully quit application resumes checking on its next launch. Windows notification settings may suppress notices.

Source build: `796d2d8ccd0241d828ed351eccfd002107e6b324`.

- [Windows build and installed-payload checks](https://github.com/rachitkothadia/FlowGPT/actions/runs/38582077745): passed.
- [Mac build and policy checks](https://github.com/rachitkothadia/FlowGPT/actions/runs/38582077597): passed.
- Local Mac package: 120 tests passed; warnings-as-errors compilation, bundle signature integrity and DMG verification passed.
- Windows: 79 portable checks, [52 native fixtures](windows-native-fixtures-111.json), [17 UI checks](windows-ui-fixtures-111.json), and [11 installation/upgrade checks](windows-installer-fixtures-111.json) passed, including the released 1.0-to-1.1.1 upgrade.

Installers:

- `FlowGpt-1.1.1-arm64.dmg`: `f72dd1d4ebb87cb82195cee83cc2fac3b6decc8253c0c14787d880bb3176ad76`
- `FlowGPT-1.1.1-Windows-x64-Setup.exe`: `9149376c346301555f3e3a738288713e9747265ce96ababa615f3061a553fed8`

The release includes one shared `SHA256SUMS.txt` containing both entries. Both updaters select their compatible installer and its exact checksum.

This preview remains unsigned on Windows and ad hoc signed without notarization on Mac. Publisher credentials are still required for trusted distribution. Mac updates open the verified DMG for manual replacement; Windows opens its verified EXE installer. Older builds without automatic checks must install 1.1.1 once to receive future notices.

The automatic-notice code compiles on both platforms, but a live future-version notice was not replayed. Historical physical microphone and Word measurements belong to the 1.1.0 package, not this package. Other limitations, including ambiguous Mac PowerPoint canvas focus and unverified Windows physical microphone/live-account/Office behavior, remain described in [the 1.1 validation report](FLOWGPT_11_VALIDATION.md).
