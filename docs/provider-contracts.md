# Provider 계약 기준

확인일: `2026-08-16 KST`

이 문서는 공식 문서, 로컬에 설치된 공식 client가 관측한 계약, 승인된 redacted 실계정 probe만 기록한다. 외부 프로젝트 source·fixture는 제품에 사용하지 않았다.

## 계약 등급

| 등급 | 의미 | 제품 처리 |
|---|---|---|
| `documented` | Provider 공식 문서에 field와 의미가 명시됨 | Stable 후보 |
| `observed` | 공식 client가 생성한 schema 또는 직접 수집한 redacted payload로 확인됨 | client version과 함께 Beta |
| `experimental` | 공개 UX만 있고 machine-readable 계약이 없음 | 수치를 만들지 않고 상태 전용 |

## Provider 요약

| Provider | 계약 | 입력 | 확인된 값 | 출시 상태 |
|---|---|---|---|---|
| Claude | `observed` | Claude Code macOS Keychain + Anthropic OAuth usage GET | 5시간·7일·Fable 주간 사용률과 reset; 각 window 독립 누락 가능 | 실계정 read-only probe 및 설치 앱 LIVE PASS, Beta |
| Codex | `observed` | 공식 `codex app-server` JSON-RPC | primary·secondary, reset, duration, plan, credits | 실계정 read-only probe PASS, `codex-cli 0.145.0` |
| Grok | `observed` | xAI 공식 Grok Build CLI billing backend | 공용 사용률, weekly/monthly 기간, reset, 선불 잔액 | 실계정 read-only probe PASS, Beta |
| Z.ai | `observed` | `claude-glm` profile + 공식 `glm-plan-usage` plugin `0.0.1` | 5시간 token·월간 MCP 사용률, reset 없음 | 실계정 read-only probe 및 설치 앱 LIVE PASS, Beta |

## Claude

- 설치된 Claude monitor 참조 구현과 승인된 실계정 probe에서 `Claude Code-credentials` Keychain JSON의 `claudeAiOauth.accessToken`을 primary credential로 확인했다.
- adapter는 `GET https://api.anthropic.com/api/oauth/usage`만 호출한다. request에는 bearer access token, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/2.1.0`만 필요한 인증/호환 header로 사용하고 body·cookie는 보내지 않는다.
- 응답의 `five_hour`, `seven_day`에서 `utilization` 또는 `used_percentage`를 `0...100`으로 읽는다. reset은 ISO-8601, epoch seconds, epoch milliseconds를 허용한다.
- `limits[]`의 `kind=weekly_scoped`, `scope.model.display_name=Fable` 항목은 별도 Fable 주간 window로 정규화한다. 기존 `fable_weekly` 계열 field는 schema drift fallback이다.
- 5시간 또는 7일 window 하나만 존재하면 `partial`로 보존하고 누락 값을 0%로 만들지 않는다.
- 성공 응답은 actor 내부에서 최소 180초 재사용한다. `429`는 `Retry-After` 숫자 또는 기본 15분 backoff를 적용해 usage endpoint 과호출을 방지한다.
- URLSession은 ephemeral이며 redirect·cookie·response cache를 거부한다. timeout은 10초다.
- access token은 메모리에서만 사용한다. refresh token을 parse·사용·전송하거나 Keychain을 갱신하지 않으며 Claude 설정/statusLine도 수정하지 않는다.
- endpoint는 공개 stable API 문서가 아니라 first-party client 동작과 실계정 응답에서 관측한 계약이므로 `observed · Beta`다. 공식 statusLine `rate_limits`는 독립 fallback 계약으로만 유지한다.

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
- xAI 공식 Grok Build source와 설치 binary에서 CLI billing backend `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` 및 `config.creditUsagePercent`, `currentPeriod`, `billingPeriodEnd`, `prepaidBalance` 계약을 확인했다.
- installed client: `grok 1.0.4 (d846eb93d94d) [stable]`.
- 설치 버전의 `grok agent stdio`에 `x.ai/billing`을 호출하면 `-32601 Method not found`가 반환된다. 따라서 ACP RPC는 제품 경로로 사용하지 않고, 공식 client가 사용하는 first-party billing backend만 `observed · Beta`로 호출한다.
- request는 GET 한 번으로 제한하며 bearer access token, CLI auth marker, user ID, client version header만 전송한다. redirect·cookie·response cache는 거부하고 refresh token은 선택·사용·전송하지 않는다.
- parser는 `config.creditUsagePercent`를 우선 사용하고 구형 `monthlyLimit/used`는 fallback으로만 처리한다. 누락·범위 밖·0 denominator를 실제 0%로 만들지 않는다.
- `2026-08-16` 승인된 실계정 probe에서 HTTP 200과 필요한 field 존재를 확인했고 credential SHA-256·mtime·mode는 불변이었다. 실제 값과 원본 response는 저장하지 않았다.
- timeout: HTTP 전체 15초. client/source 계약 변경 시 synthetic fixture, unit test, redacted 실계정 probe를 다시 실행한다.
- 브라우저 cookie, WebView, model call, auto-topup endpoint 사용은 금지한다.

## Z.ai

- 공식 문서와 `zai-org/zai-coding-plugins`는 Claude Code용 `glm-plan-usage` plugin과 `/glm-plan-usage:usage-query` 흐름을 제공한다.
- 로컬 공식 plugin `0.0.1`의 read-only script는 `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`을 사용하고 ZAI platform의 Model usage, Tool usage, Quota limit을 한 번의 script 실행에서 조회한다.
- QuotaBeacon은 plugin source를 포함하거나 endpoint를 재구현하지 않는다. 사용자가 연결을 켠 경우에만 설치된 cache의 manifest·script와 `claude-glm` alias를 strict 탐지한 뒤 공식 script process를 정확히 1회 실행한다.
- shell alias는 실행하지 않는다. 한 줄 alias를 tokenization해 `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` 두 값만 자식 process environment로 전달하고 나머지 environment·flag·command는 무시한다. ZAI HTTPS base URL과 `claude` command가 아니면 거부한다.
- stdout의 Model/Tool section과 원본 quota response는 저장·export·log하지 않는다. `Platform: ZAI`와 `Quota limit data:` 뒤의 단일 JSON object만 분리하고, `Token usage(5 Hour)`와 `MCP usage(1 Month)` percentage만 정규화한다.
- 공식 output에는 두 window의 reset 시각이 없으므로 `resetsAt=nil`을 보존한다. 누락 window는 `partial`, 0%는 실제 0%, 범위 밖 값은 malformed로 처리한다.
- 성공 결과는 5분 재사용하며 process timeout은 25초다. 실행 내부 retry·loop·모델 호출·login/logout·credential write-back은 없다.
- Coding Plan Usage Policy의 지원 도구 제한과 외부 plugin dependency 때문에 이 경로는 `observed · Beta`다. plugin 미설치·profile 미검출·output drift를 실제 값으로 추정하지 않고 typed state로 표시한다.

## 공통 typed state

- `available`, `partial`, `stale`, `notConfigured`, `authenticationRequired`, `unsupportedAccount`, `unsupportedContract`, `rateLimited`, `offline`, `failed`
- error code: `missingCredential`, `invalidCredential`, `forbidden`, `notFound`, `rateLimited`, `server`, `timeout`, `cancelled`, `malformedPayload`, `unsupported`, `io`
- unknown field는 무시하되 unknown limit type은 원문이 아닌 안전한 type label로 보존한다.
- 값 누락은 0% 또는 100%로 바꾸지 않는다.

## 실계정 gate

실계정 probe는 credential을 읽고 Provider에 접속할 수 있으므로 별도 사용자 승인이 필요하다. 실행 전후 allowlist credential의 SHA-256과 mtime을 비교하고, 원본 응답은 저장하지 않으며 normalized/redacted evidence만 기록한다.

`2026-08-16` 승인 검증 결과:

- Codex: 공식 read-only rate-limit probe 성공, credential hash·mtime 불변.
- Claude: Keychain credential 존재, OAuth usage HTTP 200, 5시간·7일·Fable field 존재, credential 불변을 확인했다. 설치 앱은 statusLine bridge 없이 3개 window를 `LIVE · keychain · observed`로 표시했다.
- Grok: 공식 CLI billing backend read-only probe 성공, 필요한 field 존재와 credential SHA-256·mtime·mode 불변 확인. `observed · Beta` LIVE 경로로 사용.
- Z.ai: `claude-glm` alias의 ZAI profile과 공식 `glm-plan-usage` `0.0.1`을 확인하고 redacted official script probe에 성공했다. 설치 앱은 5시간 token·월간 MCP 두 window를 `LIVE · officialCLI · observed`로 표시했으며 profile hash·mtime은 불변이었다.
- 상세: [Provider 실환경 검증 보고서](provider-validation-2026-08-16.md)
