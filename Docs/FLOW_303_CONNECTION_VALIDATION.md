# Flow 3.0.3 connection test

The screenshot showed Whisper HTTP 200 and GPT-OSS HTTP 400. The generic error label hid Groq's response. A fresh live request with the saved key returned GPT-OSS HTTP 429, explicitly identifying the daily token quota. This does not establish the cause of the earlier 400.

The old health check reused all dictation instructions and asked for plain OK under JSON-object response mode, with medium reasoning. It consumed an unnecessarily large token reservation and had inconsistent output instructions. The new check uses a small dedicated JSON prompt and low reasoning, with a 512-token output reservation. Actual dictation prompts, local validators, NLP memory and credential storage are unchanged. The new GPT-OSS check returned HTTP 200 with the existing saved key. A successful small check does not guarantee enough quota for longer dictation.

Failed model checks now display the bounded provider error message instead of only Request failed. Credentials are redacted and failed_generation content is omitted. Results still require exactly HTTP 200 and no automatic test retries. The sidebar and About version labels now come from the bundle rather than hardcoded 2.5 strings.

Native regression coverage includes request size/JSON consistency and credential/error redaction. API checks use synthetic text and the bundled speech sample, never microphone recordings. No privacy grants or personal NLP history are changed. This is a local ad hoc signed build, without Developer ID or notarization.
