# ECHO – Assumptions and decisions

Decisions made without asking, so they can be reversed. Newest at the bottom.

## Naming and platform
- **Name: ECHO.** The mockup used ECHO; the feature list offered Lumina or ECHO. Display name, permission strings and spoken text say ECHO. The Xcode target is still `diffAI` (renaming a target is risky and cosmetic).
- **Deployment target lowered from iOS 27.0 to 17.0.** Verified the whole codebase builds at 17.0 unchanged. Elderly users are likely on older phones.
- **AI backend stays Anthropic (Claude).** The request said "like Gemini"; that describes the experience, not the vendor. `AIService` is a protocol, so swapping to Gemini is one file (`RemoteAIService`).
- **Model id `claude-sonnet-5-5`.** Chosen for speed over Opus; speech latency matters more than depth here.

## Security and identity
- **"Face ID + voice recognition" became Face ID / Touch ID / passcode only.** iOS has no speaker-verification API. Claiming voice as a factor would be false security.
- **SMS verification not built.** It requires a backend to send codes. Noted as a later step.
- **Password fields are never read, typed into by voice, or clicked through.** The app tells the user to do those steps by hand.
- **API key lives in Keychain** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), entered in Settings. Never in source or UserDefaults.

## Voice and audio
- **Voice barge-in only on headphones/AirPods.** On the phone speaker the microphone would hear ECHO's own voice. Tapping, the Stop button, shaking, and saying "stop" always work.
- **Silence of about 1 second ends an utterance.** Elderly users pause mid-sentence; this may need to grow to 1.5 s after real testing.
- **VoiceOver announcements cannot be cancelled by the app.** When VoiceOver is on, "stop" cannot cut a sentence short; it only prevents the next one.

## Scope
- **"Open a site and app by voice":** websites yes; other apps only if they expose a URL scheme (iOS forbids launching arbitrary apps). Built as websites plus `tel:`, `sms:`, `mailto:`.
- **Email/SMS require the user to tap Send** in the system sheet. iOS has no silent-send API. Fully automatic sending would need a backend.
- **Demo data is clearly fake** (example.com addresses, 555 numbers, "demo" in every title).
- **Voice-only mode still shows one screen** (status, avatar/mic, hidden transcript). It is not literally blank, so VoiceOver and Switch Control users keep a target to act on.
- **Caregiver dashboard is local demo data.** A real one needs a server and consent flow.

## AI behaviour
- **Model `claude-opus-5-5`, effort `low`.** Opus 5.5 is the required default; `low` effort keeps time-to-first-word short for voice. Thinking cannot be turned off on this model.
- **With the live AI on, keyword matching is minimal.** The router handles only control words (stop, yes, no, repeat, pause…) and exact app commands (open camera, help me, voice only…). Everything else goes to the model, which chooses tools. Offline (no key), the full keyword router runs instead.
- **Tool results go back to the model** (a real tool-use loop, up to 4 rounds), so it can chain actions and narrate what happened. Thinking blocks are replayed verbatim; the system prompt and tool list are byte-stable; history is append-only. `prefix_mismatch_behavior: drop_block` is set as a safety net so a history edit never 400s.
- **Server-side refusal fallback (`fallbacks: "default"`) is on.** A safety-classifier refusal is re-run on Anthropic's recommended fallback model inside the same call. Say if you want this off.
- **The context line (screen, time of day, location, open web page) is stored inside each user message** at creation time, never injected at send time, so replayed history is identical.
- **Images are re-sent for every message still in the 20-message window.** Stripping them later would edit history. Typical sessions have one or two photos, so this was accepted.

## Review fixes applied (from the independent code review)
- The microphone is **muted while ECHO speaks**: partial text still flows for barge-in, but nothing heard becomes a request; recognition restarts with a 0.5 s grace window after speech. Echo cancellation (`setVoiceProcessingEnabled`) is enabled best-effort. Without this the app transcribed and obeyed its own voice, including auto-confirming its own "say yes" prompt.
- VoiceOver announcements are now queued and completion-tracked (`announcementDidFinishNotification`) instead of estimated with a sleep. "Always use VoiceOver" falls back to the app voice when VoiceOver is off, so the app is never silent.
- First launch asks for microphone/speech permission when the user first taps the mic, not only on the onboarding button.
- Camera: `start()` waits until the session runs; a second capture while one is pending returns nil instead of leaking a continuation.
- Web: JavaScript results come through the completion-handler API (a nil result crashed the async overload on "scroll"); submit targets the form the user typed into; submit buttons inside forms route through the approval screen; `WKUIDelegate` opens `target=_blank` links in place; the web view has a real frame before the screen opens.
- Router: "yes"/"no" only match short phrases; "help me", "back", "home", "call", "history", "tips", "camera" no longer fire inside sentences.
- Screens announce themselves once (the engine no longer also speaks the screen name in screen mode).

## Mockup additions (lumina-mockup.html)
- **My Day (briefing) screen** and **Safety screen** added as navigation chips, following the mockup's structure. The mockup's visual language (pure black, system blue) was NOT adopted; the mint/navy ECHO theme the UI agent built is kept until you have seen it.
- **"Call emergency services"** picks the number from the device region: 911 (US/CA/MX), 999 (GB/IE), 000 (AU), 112 elsewhere. Always behind the approval screen.
- Weather in the briefing is demo text.

## Orchestration (how this was built)
- Four parallel agents built self-contained modules against the contracts in `Core/Voice/ApprovalRequest.swift` (ApprovalRequest, DialogFlow) and the screen/action enums. The orchestrator owns `ConversationEngine`, `ActionExecutor`, `VoiceCommandRouter`, `AssistantTools`, `AppEnvironment`, `SightAssistApp` and does all wiring and the final build.
