# FlowGPT Windows 1.0.0 reported crash: released-binary mapping

Reported exception: `0xc0000005`, module timestamp `0x6aceb4e9`, fault RVA `0x000000000000a03b`.

Matching release build: `8a9f3c4314ef91f97f8d69bf20b07616f3dcc719`, GitHub Actions run `38479882836`, artifact `11855973683`. EXE/PDB members selectively extracted and ZIP CRC verified. The Windows binary was inspected, never executed on macOS.

- EXE COFF timestamp: `0x6aceb4e9`, exact match.
- EXE SHA256: `5862fbc5bdc441b8d75418328e87f99237de313abe6f9d48b16a6d27059e3bb4`.
- PE image base: `0x140000000`.
- PE CodeView and PDB GUID bytes both: `8ce90e60083ebd4ba1def5751b1c1e93`; age `1`.
- PDB symbol: `?editable@Insertion@flow@@CA_NPEAUIUIAutomationElement@@@Z` (`flow::Insertion::editable(IUIAutomationElement*)`).
- Symbol section 1 offset `0x8ff0`, plus `.text` RVA `0x1000`, gives function RVA `0x9ff0`.
- Reported fault is function offset `+0x4b`.

Disassembly around the fault:

```text
RVA a022: mov edx,0x2712          ; UIA_ValuePatternId (10002)
RVA a027: call [rax+0x70]        ; IUIAutomationElement::GetCurrentPatternAs
RVA a02a: test eax,eax
RVA a02c: js a058                ; failure takes alternative pattern path
RVA a02e: mov dword [rsp+0x20],1 ; readonly defaults TRUE
RVA a036: mov rcx,[rsp+0x28]     ; returned value-pattern interface pointer
RVA a03b: mov rax,[rcx]          ; REPORTED FAULT: load interface vtable
RVA a03e: lea rdx,[rsp+0x20]
RVA a043: call [rax+0x28]        ; IUIAutomationValuePattern::get_CurrentIsReadOnly
```

The released source at `Windows/Platform.h:175` checked HRESULT success, then dereferenced the pattern interface without a non-null check:

```cpp
if(SUCCEEDED(e->GetCurrentPatternAs(UIA_ValuePatternId,IID_PPV_ARGS(&value)))) {
    BOOL readonly=TRUE;
    return SUCCEEDED(value->get_CurrentIsReadOnly(&readonly))&&!readonly;
}
```

The next fallback in the same function checks Edit/Document control IDs `50004`/`50030` and TextPatternId `10014`, independently confirming this function's identity in machine code.

Conclusion: the reported access violation is definitively at the unchecked value-pattern COM interface dereference in `Insertion::editable`, rather than speech/history writing. The register state/accessed address was not supplied, so an exactly-null versus stale/invalid pointer cannot be distinguished from this Event Viewer record alone. Guard HRESULT and pointer, handle provider failures without exiting, and add a successful-call-with-null-pattern regression fixture. Extend the same safeguards to other UIA/browser COM results and catch failures at native/WinUI callback boundaries.

This maps an actual reported crash to matching release code. It does not claim the friend's exact runtime conditions were reproduced locally.
