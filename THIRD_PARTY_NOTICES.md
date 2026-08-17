# Third-Party Notices

QuotaBeacon is Copyright (c) 2026 Coreline-ai and distributed under the MIT
License. See `LICENSE` for the complete terms.

QuotaBeacon 0.1.0 has no third-party runtime package dependencies.

It links only Apple system frameworks supplied with macOS and uses XCTest only
during development. Python and Pillow are development-time inputs to the
original brand-asset generator and are not bundled in the application.

External products listed in `docs/reference-register.md` were research and
comparison references only. Their code, fixtures, and build scripts are not
included in QuotaBeacon. Small provider identification marks are the sole asset
exception and are documented in `BrandAssets/README.md`.

Claude and Google Gemini source shapes used by the asset generator come from
Simple Icons 16.21.0, which is distributed under CC0-1.0. The Codex/OpenAI,
Grok/xAI, and GLM/Z.ai identification marks are derived from the respective
official GitHub organization avatars. All product names and marks remain the
property or trademarks of their respective owners. Their inclusion is solely
for nominative identification and does not imply affiliation or endorsement.

The optional Z.ai GLM integration executes the separately installed official
`glm-plan-usage` Claude Code plugin (Apache-2.0) from the user's Claude plugin
cache. The plugin is not copied into, linked with, or distributed inside
QuotaBeacon.

The optional Gemini integration executes the separately installed Google
Antigravity CLI (`agy`) and sends only its documented `/usage` command. The CLI
is not copied into, linked with, or distributed inside QuotaBeacon. Its use is
governed separately by Google's applicable product terms; this notice does not
relicense that external product under QuotaBeacon's MIT License.
