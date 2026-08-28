# Changelog

## Unreleased

- Fixed automatic refresh so the 1/5/15-minute preference is honored, overlapping triggers share one completed refresh, and opening the popover does not lose a refresh request.
- Fixed global backoff so one failed Provider no longer delays healthy Providers; 15/60-minute backoff now requires every attempted Provider to fail in consecutive cycles.
- Made exhausted quota explicit as `한도 소진 · 사용 100%`, including Grok's exact 100% boundary.
- Marked reused Claude, Gemini, and Z.ai cache observations as `recent` instead of `live` while preserving their original observation time.
- Reduced resident and refresh-peak memory by compacting normalized history into five-minute/reset-aware observations with 30-day/8-MiB retention, skipping no-op persistence, lazily creating the dashboard, and caching trend presentation models.
- Isolated XCUITests from real Provider opt-ins and preserved the user's application preferences around each UI test.
- Made user-initiated refresh bypass Claude, Gemini, and Z.ai success caches while preserving Provider rate-limit backoff, and added continuous or Reduce-Motion-safe progress feedback with second-level completion time in the menu-bar popover.

## 0.1.0-rc.1 — 2026-08-20 (local validation)

- Added root and eligible local external-volume capacity badges to the menu-bar popover. Disk observations are isolated from quota snapshots, history, export, and notifications.
- Added deterministic Provider display-order regression coverage for visibility changes, scope-style filtering, settings re-entry, and relaunch persistence.
- Completed the local code release-candidate gate: 95 XCTest/XCUITest cases, Universal `arm64`/`x86_64` build, ad-hoc signature integrity, ZIP checksum, fixture, security, and originality audits.
- Kept Developer ID signing, notarization, and public distribution out of this development completion scope; see `docs/distribution.md`.

## 0.1.0-beta.1 — 2026-08-16

- Added the Greenfield QuotaBeacon macOS menu-bar app and Signal Ledger dashboard.
- Added validated quota domain models, typed provider states, provenance, freshness, last-known-good merge, history retention, timeout/cancellation, credential validation, Keychain storage, and refresh policy.
- Added independent synthetic fixture parsers for Claude, Codex, Grok, and Z.ai.
- Added opt-in read-only Claude Keychain OAuth usage, Codex app-server, Grok Build billing, and Z.ai official GLM usage-plugin adapters.
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
- Added strict `claude-glm` profile discovery without shell execution, official `glm-plan-usage` plugin/runtime discovery, quota-only output extraction, 5-hour token and monthly MCP windows, five-minute success caching, GLM connection GUI, redacted live probe, and actual installed-app LIVE verification.

### Known limitations

- No real-account payload is stored; real-account probes retain only redacted field-presence evidence after explicit approval.
- Grok billing is `observed · Beta` and must be revalidated when the Grok Build client contract changes. Installed Grok Build `1.0.4` exposes the billing schema but its ACP `x.ai/billing` method currently returns `-32601`, so QuotaBeacon uses the same first-party CLI billing backend directly.
- Claude OAuth usage is `observed · Beta` and must be revalidated if Claude Code credential or usage endpoint contracts change.
- Z.ai GLM is `observed · Beta`, requires the official Claude Code plugin plus an existing `claude-glm` profile, and exposes no reset timestamp in plugin version `0.0.1`.
- Developer ID notarization and Sparkle updates require owner-supplied credentials and release URLs.
