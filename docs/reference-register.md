# 외부 참조 등록부

작성일: `2026-08-16 KST`

## 사용 원칙

이 문서의 항목은 연구·위험 확인·동작 비교용이다. 등록은 source code, fixture, UI, asset, build script 사용 허가를 의미하지 않는다.

구현은 공식 문서와 직접 수집한 redacted fixture를 기반으로 작성한다.

## 등록 항목

| 참조 | 분류 | 허용 목적 | 구현에 재사용 금지 | 상태 |
|---|---|---|---|---|
| Claude Code statusline 문서 | 공식 문서 | rate limit field·null 조건·reset 의미 확인 | 문서 예제 script의 제품 코드 복사 | 사용 가능 |
| Z.ai Usage Query Plugin 문서 | 공식 문서 | GLM quota 기능과 사용자 흐름 확인 | plugin source·payload fixture 복사 | 사용 가능 |
| Claude Code statusline schema | 공식 문서 | `five_hour`, `seven_day`, null/reset 의미 확인 | 예제 payload·script 복사 | 사용 가능 |
| 로컬 Codex `0.145.0` app-server 생성 schema | 공식 client schema | `account/rateLimits/read`, primary/secondary/credits 확인 | 계정 응답·credential 저장 | 사용 가능 |
| xAI Grok FAQ·Models | 공식 문서 | weekly usage UX와 Grok Build 가격 근거 확인 | cookie·model endpoint 수집 | 사용 가능 |
| xAI Grok Build billing extension | 공식 client source | first-party billing URL·header·response field 확인 | source code·fixture 복사, billing 외 endpoint 호출 | 계약 관찰만 |
| Z.ai Coding Plan overview·policy·pricing | 공식 문서 | 5시간/주간 limit, 지원 도구 제한, 가격 catalog 확인 | 지원 밖 Coding endpoint 호출 | 사용 가능 |
| OpenAI·Anthropic model pricing | 공식 문서 | 날짜가 있는 API 정가 catalog 작성 | 구독 결제액으로 오표시 | 사용 가능 |
| Apple Developer 문서 | 공식 문서 | status item, Keychain, 서명, 공증 검증 | 해당 없음 | 사용 가능 |
| TokenRemain | 참고 제품 | Provider 범위, 성능·라이선스 위험 확인 | source·type·file tree·UI·asset·script | 참고만 |
| CodexBar | 참고 제품 | CLI 버전·계정 유형·fallback 위험 확인 | source·test·fixture·protocol·script | 참고만 |
| ClaudeBar | 참고 제품 | 메뉴바 제품 범위와 상태 표현 비교 | source·UI·asset·구조 | 참고만 |
| ccusage | 검증 도구 | 신규 local parser 결과의 개발 환경 비교 | code·parser·fixture·제품 bundle | 개발 비교만 |
| [QuotaSignal](https://go.quotasignal.com/login)·[QuotaLedger](https://quotaledger.com/)·[AgentGauge](https://www.agentgauge.ai/) 공개 제품 페이지 | 이름 충돌 조사 | 신규 표시 이름 후보의 공개 사용 여부 확인 | 이름·UI·문구·에셋 재사용 | 조사 완료 |

## 구현 증거 기록 형식

Provider 또는 기능 구현 전에 다음을 추가한다.

```text
ID:
확인 날짜:
공식 계약 URL:
확인한 동작:
직접 수집 fixture:
신규 구현 위치:
외부 source 사용 여부: 아니오
검증 결과:
```

## Phase 1 확인

- 신규 source root: `AIQuotaMonitor/`
- 신규 test root: `AIQuotaMonitorTests/`, `AIQuotaMonitorUITests/`
- 프로젝트 생성 방식: 직접 작성한 Xcode project
- 외부 dependency: 없음
- 외부 source·fixture·asset import: 없음
- 최종 표시 이름: `QuotaBeacon`
- 신규 asset 생성기: `Scripts/generate_brand_assets.py`

## Phase 2~7 확인

| ID | 확인 날짜 | 공식 계약 | 확인한 동작 | 신규 구현 | 외부 source |
|---|---|---|---|---|---|
| REF-P2-CLAUDE | 2026-08-16 | https://code.claude.com/docs/en/statusline | 5시간/7일 사용률, epoch reset, window별 누락 | `Providers/Claude/**` | 사용 안 함 |
| REF-P2-CODEX | 2026-08-16 | 로컬 `codex app-server generate-json-schema` | `account/rateLimits/read`, primary/secondary/credits | `Providers/Codex/**` | 사용 안 함 |
| REF-P2-GROK | 2026-08-16 | https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-shell/src/extensions/billing.rs | first-party billing GET, 사용률·기간·reset·선불 잔액 | 독립 Swift adapter + synthetic parser | 사용 안 함 |
| REF-P2-ZAI | 2026-08-16 | https://docs.z.ai/devpack/overview | 5시간/주간 Coding Plan quota와 지원 도구 제한 | 상태 전용 + synthetic parser | 사용 안 함 |
| REF-P4-PRICE | 2026-08-16 | Provider별 공식 model pricing | 날짜·출처·alias 기반 API 정가 | `Resources/PricingCatalog.json` | 사용 안 함 |
