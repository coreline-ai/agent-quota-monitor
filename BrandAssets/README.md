# Brand asset sources

QuotaBeacon ships small raster marks only for visual identification in its local
menu-bar UI. They are not used to imply sponsorship, partnership, or endorsement.

## QuotaBeacon project mark

- `Sources/quotabeacon-generated-master.png`
- Created for Coreline-ai with the built-in OpenAI image-generation tool on
  `2026-08-17`.
- Direction: a physical harbor beacon inside a quota/reset gauge; no AI sparkle,
  robot, neural-network, chat, or heartbeat motif.
- `Scripts/generate_brand_assets.py` crops and resizes this master for the app,
  popover header, and monochrome status-item family.

## Provider identification marks

| UI label | Pinned source | Repository source file |
|---|---|---|
| Claude | Simple Icons `16.21.0`, `claude.svg` | `claude-mark-source.png` |
| Codex | Official OpenAI GitHub organization avatar, `https://github.com/openai.png` | `codex-openai-mark-source.png` |
| Grok | Official xAI GitHub organization avatar, `https://github.com/xai-org.png` | `grok-xai-mark-source.png` |
| Gemini | Simple Icons `16.21.0`, `googlegemini.svg` | `gemini-mark-source.png` |
| GLM | Official Z.ai GitHub organization avatar, `https://github.com/zai-org.png` | `zai-mark-source.png` |

The two Simple Icons source shapes are provided by the Simple Icons project
under CC0-1.0. Product names and marks remain trademarks of their respective
owners. Organization-avatar marks remain the property of their respective
owners and are included only for nominative product identification.

Generated shipping images are under
`AIQuotaMonitor/Resources/Assets.xcassets/Provider*.imageset`.

