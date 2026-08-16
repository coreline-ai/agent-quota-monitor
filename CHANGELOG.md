# Changelog

## 0.1.0-beta.1 — 2026-08-16

- Added the Greenfield QuotaBeacon macOS menu-bar app and Signal Ledger dashboard.
- Added validated quota domain models, typed provider states, provenance, freshness, last-known-good merge, history retention, timeout/cancellation, credential validation, Keychain storage, and refresh policy.
- Added independent synthetic fixture parsers for Claude, Codex, Grok, and Z.ai.
- Added opt-in read-only Claude Keychain OAuth usage, Codex app-server, and Grok Build billing adapters; Z.ai remains status-only until a safe machine contract is documented.
- Added strict Grok credential validation, allowlisted HTTPS GET-only transport, redirect/cookie/cache rejection, typed failures, synthetic billing fixtures, and a redacted real-account contract probe.
- Added redacted JSON/CSV preview, local JSONL usage normalization, and dated API list-price catalog.
- Added unit/UI test foundations and release/security/originality scripts.
- Fixed dashboard detail scrolling so content remains clipped below the macOS title bar and toolbar.
- Added a dedicated Provider connection screen with explicit apply semantics and Codex CLI auto-discovery, including NVM installs.
- Fixed live Codex app-server reads by waiting for the rate-limit response before terminating the long-running process.
- Fixed Grok login parsing for the fractional ISO 8601 expiration format emitted by Grok CLI.
- Replaced the initial Claude snapshot-only path with automatic discovery of the existing `Claude Code-credentials` macOS Keychain login and an observed Anthropic OAuth usage GET adapter.
- Added Claude 5-hour, 7-day, and Fable weekly parsing, 180-second success caching, 429 backoff, exact request contract tests, and a redacted real-account probe.
- Removed the installed temporary QuotaBeacon status-line bridge and restored the user's original Claude statusLine after direct LIVE verification.

### Known limitations

- No real-account payload is stored; real-account probes retain only redacted field-presence evidence after explicit approval.
- Grok billing is `observed · Beta` and must be revalidated when the Grok Build client contract changes. Installed Grok Build `1.0.4` exposes the billing schema but its ACP `x.ai/billing` method currently returns `-32601`, so QuotaBeacon uses the same first-party CLI billing backend directly.
- Claude OAuth usage is `observed · Beta` and must be revalidated if Claude Code credential or usage endpoint contracts change.
- Z.ai quota values are intentionally unavailable.
- Developer ID notarization and Sparkle updates require owner-supplied credentials and release URLs.
