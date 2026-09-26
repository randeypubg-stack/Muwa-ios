# Muwa subtitles — OpenAI backend

The additive v2 endpoints preserve the app contract and legacy transcribe endpoint. No Premium entitlement is required. A signed-in account is required for generation, with the existing daily limit of 20 new operations per user, shared database caching and duplicate-request leases.

Provider: server-side OPENAI_API_KEY (connected in Floot). Original: whisper-1 verbose JSON with word and segment timestamps. Translation: gpt-4.1-mini, six target languages, immutable original IDs/times. Canonical Muwa CDN only, no redirects, at most 24 MiB audio / 10 minutes. No generated timestamps, incomplete word alignments fall back to phrase highlighting. Keys never enter the native app or repository.

2026-09-26 real audio test: upstream 429 credit_balance_exhausted, type insufficient_quota. Mapped to OUT_OF_CREDITS/503. Connection is configured but successful real transcription and six translations are NOT yet verified. No production publication. Replenish the connected API balance before repeating integration checks. Test accounts were deleted.

Unit tests cover language normalization, word preservation, missing word fallback, silence omission, source restrictions, quota errors, and existing document/translation validation. These are not real recognition-quality evidence.

Next: validate real nasheeds and all translations, then publish backward-compatible server changes. Persisted transcript cache remains available independently of future API calls. Provider usage requires ongoing API balance; this is not offline on-device inference.

