# Flow 2.0 API configuration

The same populated, masked API key field appears in Get Started and Connection. Typing or pasting saves immediately to the user's Application Support/Flow/api-key.txt with file permissions 0600. It remains populated on relaunch; the eye button shows or hides it. The credential is stored without encryption. There is no hidden fallback key or process environment override. Clearing the field deletes the saved key, cancels a pending test and clears prior results. Credentials are never included in a build, installer, diagnostic report or log.

Test API Key reads exactly the current field value. Empty and invalid values fail before any request, even when a previously saved key existed. Speech testing sends the bundled synthetic English sample to the transcription endpoint using whisper-large-v3-turbo. Text testing sends a fixed prompt to chat/completions using openai/gpt-oss-120b. Each model checkmark requires its own HTTP 200. HTTP failures and network failures remain distinct. Both model requests are attempted even if the speech POST returns an HTTP failure.

Ordinary dictation uses Turbo by default. Selecting Marathi uses whisper-large-v3 and the language hint mr. The vocabulary field supplies spelling context rather than chat instructions. Speech uploads have WAV metadata for RIFF/WAVE data; the bundled M4A sample retains MP4 metadata.

Vendor references: [Speech to Text](https://console.groq.com/docs/speech-to-text), [GPT-OSS 120B](https://console.groq.com/docs/model/openai/gpt-oss-120b).
