# Changelog

## 0.1.0-beta.1 — 2026-08-16

- Added the Greenfield QuotaBeacon macOS menu-bar app and Signal Ledger dashboard.
- Added validated quota domain models, typed provider states, provenance, freshness, last-known-good merge, history retention, timeout/cancellation, credential validation, Keychain storage, and refresh policy.
- Added independent synthetic fixture parsers for Claude, Codex, Grok, and Z.ai.
- Added opt-in read-only Claude snapshot and Codex app-server adapters; Grok and Z.ai remain status-only until safe machine contracts are documented.
- Added redacted JSON/CSV preview, local JSONL usage normalization, and dated API list-price catalog.
- Added unit/UI test foundations and release/security/originality scripts.

### Known limitations

- No real-account fixture has been collected without explicit credential approval.
- Grok and Z.ai quota values are intentionally unavailable.
- Developer ID notarization and Sparkle updates require owner-supplied credentials and release URLs.
