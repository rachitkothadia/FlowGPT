# Windows component notices

FlowGPT's original source is distributed under the repository's MIT license. Bundled Microsoft components are distributed under their respective license and redistribution terms, not relicensed by FlowGPT.

- Windows App SDK and WinUI: [Windows App SDK license](https://github.com/microsoft/WindowsAppSDK/blob/main/LICENSE) and [WinUI license](https://github.com/microsoft/microsoft-ui-xaml/blob/main/LICENSE).
- C++/WinRT: [C++/WinRT license](https://github.com/microsoft/cppwinrt/blob/master/LICENSE).
- WebView2 SDK and Evergreen Runtime: [Microsoft WebView2 license terms](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution#license-terms-and-notices).
- Native Visual C++ runtime: [Microsoft Visual Studio redistributable terms](https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution).

The installer includes the Windows App SDK runtime and the native C++ runtime files. It runs Microsoft's signed WebView2 Evergreen bootstrapper, which may download the matching runtime from Microsoft. The user's ChatGPT browser profile is created locally after installation and is never bundled in the installer.
