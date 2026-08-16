# Provider 계약 기준

확인일: `2026-08-16 KST`

이 문서는 공식 문서와 로컬에 설치된 공식 CLI가 공개한 schema만 기록한다. 외부 프로젝트 source·fixture는 사용하지 않았다.

## 계약 등급

| 등급 | 의미 | 제품 처리 |
|---|---|---|
| `documented` | Provider 공식 문서에 field와 의미가 명시됨 | Stable 후보 |
| `observed` | 공식 client가 생성한 schema 또는 직접 수집한 redacted payload로 확인됨 | client version과 함께 Beta |
| `experimental` | 공개 UX만 있고 machine-readable 계약이 없음 | 수치를 만들지 않고 상태 전용 |

## Provider 요약

| Provider | 계약 | 입력 | 확인된 값 | 출시 상태 |
|---|---|---|---|---|
| Claude | `documented` | Claude Code status-line JSON | 5시간·7일 사용률, reset; 각 window 독립 누락 가능 | 로그인 확인, snapshot bridge 전 |
| Codex | `observed` | 공식 `codex app-server` JSON-RPC | primary·secondary, reset, duration, plan, credits | 실계정 read-only probe PASS, `codex-cli 0.145.0` |
| Grok | `documented` UX / `experimental` machine contract | Settings → Usage | 공용 weekly pool, product breakdown, reset, extra credits | 상태 전용 |
| Z.ai | `documented` UX / `experimental` machine contract | 공식 usage-query plugin | 5시간·weekly quota 존재 | 상태 전용 |

## Claude

- 공식 계약: `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage`는 `0...100`이다.
- reset은 Unix epoch seconds다.
- `rate_limits`와 각 window는 첫 API 응답 전 또는 계정 유형에 따라 없을 수 있다.
- status-line은 로컬 script로 JSON을 전달하며 자체로 모델 token을 소비하지 않는다.
- 제품은 Claude 설정을 자동 수정하지 않는다. 사용자가 명시적으로 bridge를 설치한 경우에만 snapshot을 읽는다.
- timeout: 파일 읽기 2초. 최소 client version은 직접 fixture 확보 전 미확정이다.

## Codex

- 로컬 공식 client: `codex-cli 0.145.0`.
- `codex app-server generate-json-schema --experimental`에서 `account/rateLimits/read`를 확인했다.
- 응답은 historical `rateLimits`와 선택적 `rateLimitsByLimitId`를 가진다.
- 각 bucket은 `primary`, `secondary`, `credits`, `planType`, `rateLimitReachedType`을 독립적으로 생략할 수 있다.
- window는 `usedPercent`, 선택적 `resetsAt`, `windowDurationMins`를 가진다.
- app-server adapter는 `account/rateLimits/read`만 호출한다. login, logout, refresh, reset-credit consume, model/thread method는 금지한다.
- timeout: initialize 3초, read 8초, 전체 12초.
- `2026-08-16` 실계정 read-only probe에서 plan, primary window, reset, duration, credits field를 확인했다. 실제 값과 원본 response는 저장하지 않았다.

## Grok

- 공식 FAQ는 유료 사용자의 단일 weekly pool, product별 breakdown, weekly reset, Extra Usage Credits UI를 설명한다.
- 공개된 안정적인 read-only machine endpoint는 확인하지 못했다.
- 브라우저 cookie와 비공개 endpoint 수집은 금지한다.
- 제품은 `unsupportedContract` 상태를 반환하며 수치를 생성하지 않는다.

## Z.ai

- 공식 문서는 5시간·weekly limit과 공식 usage-query plugin을 제공한다.
- Coding Plan은 공식 지원 도구에서만 사용하도록 제한된다.
- QuotaBeacon은 모델/API 호출로 quota를 조회하지 않는다.
- 공개된 독립 앱용 machine contract를 확인하기 전에는 `unsupportedContract` 상태를 반환한다.
- 사용자가 입력한 key는 Keychain에만 저장하지만 quota endpoint 확인 전에는 호출하지 않는다.

## 공통 typed state

- `available`, `partial`, `stale`, `notConfigured`, `authenticationRequired`, `unsupportedAccount`, `unsupportedContract`, `rateLimited`, `offline`, `failed`
- error code: `missingCredential`, `invalidCredential`, `forbidden`, `notFound`, `rateLimited`, `server`, `timeout`, `cancelled`, `malformedPayload`, `unsupported`, `io`
- unknown field는 무시하되 unknown limit type은 원문이 아닌 안전한 type label로 보존한다.
- 값 누락은 0% 또는 100%로 바꾸지 않는다.

## 실계정 gate

실계정 probe는 credential을 읽고 Provider에 접속할 수 있으므로 별도 사용자 승인이 필요하다. 실행 전후 allowlist credential의 SHA-256과 mtime을 비교하고, 원본 응답은 저장하지 않으며 normalized/redacted evidence만 기록한다.

`2026-08-16` 승인 검증 결과:

- Codex: 공식 read-only rate-limit probe 성공, credential hash·mtime 불변.
- Claude: host 로그인 확인. QuotaBeacon용 snapshot은 비활성이라 quota fixture는 미수집.
- Grok: credential file 구조·권한·expiry 증거 확인. 공식 quota CLI command 미확인으로 상태 전용 유지.
- Z.ai: 현재 PATH·Claude 설정·plugin 목록에서 로그인 경로를 찾지 못해 상태 전용 유지.
- 상세: [Provider 실환경 검증 보고서](provider-validation-2026-08-16.md)
