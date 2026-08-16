# Changelog

## 0.1.0-beta.1 — 2026-08-16

- Added the Greenfield QuotaBeacon macOS menu-bar app and Signal Ledger dashboard.
- Added validated quota domain models, typed provider states, provenance, freshness, last-known-good merge, history retention, timeout/cancellation, credential validation, Keychain storage, and refresh policy.
- Added independent synthetic fixture parsers for Claude, Codex, Grok, and Z.ai.
- Added opt-in read-only Claude snapshot, Codex app-server, and Grok Build billing adapters; Z.ai remains status-only until a safe machine contract is documented.
- Added strict Grok credential validation, allowlisted HTTPS GET-only transport, redirect/cookie/cache rejection, typed failures, synthetic billing fixtures, and a redacted real-account contract probe.
- Added redacted JSON/CSV preview, local JSONL usage normalization, and dated API list-price catalog.
- Added unit/UI test foundations and release/security/originality scripts.

### Known limitations

- No real-account payload is stored; real-account probes retain only redacted field-presence evidence after explicit approval.
- Grok billing is `observed · Beta` and must be revalidated when the Grok Build client contract changes. Installed Grok Build `1.0.4` exposes the billing schema but its ACP `x.ai/billing` method currently returns `-32601`, so QuotaBeacon uses the same first-party CLI billing backend directly.
- Z.ai quota values are intentionally unavailable.
- Developer ID notarization and Sparkle updates require owner-supplied credentials and release URLs.
