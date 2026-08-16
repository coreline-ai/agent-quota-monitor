# Quota trends Reset Bands concept prompt

- 생성 방식: built-in `image_gen`
- use case: `ui-mockup`
- reference/edit target: 실제 QuotaBeacon 추세 XCUITest screenshot
- 결과 이미지: [quota-trends-reset-bands-concept-20260816.png](quota-trends-reset-bands-concept-20260816.png)

## Final prompt

```text
Use case: ui-mockup
Asset type: high-fidelity macOS desktop app redesign concept for QuotaBeacon
Input image: the supplied screenshot is the edit target and product-shell reference.
Primary request: preserve the existing QuotaBeacon dark macOS window, title bar, left navigation sidebar, spacing language, and overall 1520x1144 composition. Redesign only the main "추세" content as a precise, production-ready quota trend dashboard.
Composition:
- Keep the fixed top detail header and left sidebar unchanged.
- Main header: "추세", with compact Provider chips "Claude" selected, "Grok", "Codex", and range control "24시간", "7일", "30일" with "24시간" selected.
- Add a small coverage caption: "수집 1시간 53분 · LIVE 50개 표본".
- Add a restrained summary strip with exact labels: "현재 잔여 47%", "변화 -2.1%/시간", "리셋 1시간 후".
- Main chart surface title: "Claude 잔여 추세".
- Show a real time-series chart, not a scatter plot: three clean linear quota lanes sharing the same time axis. Lane end labels exactly: "5시간 47%", "7일 16%", "Fable 주간 4%".
- Use cyan for healthy, amber for warning, coral-red for critical, consistent with the existing Beacon Ledger.
- Include subtle horizontal threshold guides labeled "주의 25%" and "위험 10%".
- Include one thin translucent vertical Reset Band with a dashed center line and small label "리셋"; lines must break across a reset boundary rather than falsely connect.
- Show only the latest observation as a larger point; earlier observations form quiet continuous lines with a very faint area fill.
- Bottom utility row: "실선 LIVE · 점선 캐시" and "현재 속도 기준 예상 소진 오전 5:01".
Style/medium: crisp native macOS SwiftUI product mockup, dark graphite surfaces, subtle borders, no glassy neon, no stock-market aesthetic.
Information hierarchy: the line directions and current end values are dominant; controls and provenance are secondary. Eliminate the oversized mixed symbol legend seen in the reference.
Typography: macOS system typography, strong Korean legibility, tabular numerals.
Constraints: keep all content inside the main scroll region below the fixed header; no overlap with the sidebar or window chrome; no external provider logos; no mascots; no copied third-party UI; no watermark.
Avoid: scatter-only chart, rainbow palette, excessive cards, gradients, huge labels, illegible microtext, fake browser chrome, light theme.
```
