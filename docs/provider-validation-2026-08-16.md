# Provider 실환경 검증 보고서

실행일: `2026-08-16 KST`

## 검증 범위

- Provider: Codex, Claude Code, Grok Build, Z.ai GLM Coding Plan
- 원칙: read-only, 모델 호출 없음, prompt 전송 없음, login/logout/refresh 명령 없음
- 비밀정보: credential 값·계정 ID·이메일·원본 payload·홈 경로를 저장하지 않음
- 무결성: 기존 allowlist credential/config fingerprint와 Claude Keychain credential의 전후 불변 여부를 비밀값 없이 비교

## 결과 요약

| Provider | 로그인/설치 증거 | quota 검증 | 판정 |
|---|---|---|---|
| Codex | `codex-cli 0.145.0`, auth file regular/owner 일치/`0600` | 공식 app-server `account/rateLimits/read` 성공. plan·primary window·reset·duration·credits field 관측 | QuotaBeacon LIVE 연결 가능 |
| Claude | Claude Code `2.1.233`, `Claude Code-credentials` macOS Keychain item 존재 | Anthropic OAuth usage GET HTTP 200, 5시간·7일·Fable field 존재; 설치 앱에서 3개 window LIVE | `observed · Beta` LIVE 연결 완료, 별도 statusLine 설정 불필요 |
| Grok | Grok Build `1.0.4 stable`, auth JSON valid/credential material 있음/미래 expiry 증거/`0600` | ACP `x.ai/billing`은 `-32601`; 공식 CLI billing backend GET은 HTTP 200 및 계약 field 관측 | `observed · Beta` LIVE 연결 가능 |
| Z.ai GLM | `glm`, `zai` 독립 CLI 미검출. Claude 설정의 Z.ai endpoint/key mapping 없음. `glm-plan-usage` plugin 미설치 | 공식 bridge 입력이 없어 실행하지 않음 | 현재 shell/Claude 환경에서는 연결 미확인 |

## Codex 실계정 probe

- 전송 method allowlist: `initialize`, `account/rateLimits/read`
- 성공적으로 관측한 normalized field:
  - `planType`
  - `primary.usedPercent`
  - `primary.resetsAt`
  - `primary.windowDurationMins`
  - `credits.balance`, `credits.hasCredits`, `credits.unlimited`
  - `rateLimitReachedType`
- 실제 사용률·reset 값은 개인 사용 데이터이므로 repository fixture나 이 보고서에 저장하지 않았다.
- 원본 app-server response와 account metadata는 저장하지 않았다.

## Claude 검증

상세 원인과 참조 소스 추적은 [Claude 자동 연결 원인 분석](claude-connection-root-cause-2026-08-16.md)에 기록했다.

- 샌드박스 내부 `claude auth status`는 Keychain 접근 제한으로 false negative를 반환했다.
- 사용자 승인 host read-only 재검사에서는 `loggedIn=true`, `authMethod=claude.ai`를 확인했다.
- 설치된 Orca bundle의 Claude rate-limit service를 추적한 결과 수집 순서는 Keychain OAuth usage primary, CLI `/usage` fallback, statusLine live-session 보강이었다.
- primary credential은 macOS Keychain service `Claude Code-credentials`의 `claudeAiOauth.accessToken`이며, primary request는 `GET https://api.anthropic.com/api/oauth/usage`와 OAuth beta/User-Agent header를 사용한다.
- 승인된 redacted probe는 Keychain access token을 메모리에서만 읽어 GET 한 번을 수행했다. HTTP 200, `five_hour`, `seven_day`, Fable `weekly_scoped` 존재와 reset field 존재만 출력했다.
- redacted probe는 token·Keychain JSON·실제 quota 값·원본 response를 stdout 또는 repository에 저장하지 않았고 credential 전후 불변을 확인했다. 설치 앱 history에는 제품 기능상 정규화된 ratio/reset만 로컬 저장된다.
- QuotaBeacon Release 설치 후 Claude는 `available`, 3개 window, source `keychain`, contract `observed`, diagnostic 없음으로 기록됐다.
- 검증을 위해 과거 설치했던 QuotaBeacon statusLine bridge는 제거했고 저장해 둔 사용자의 원래 `statusLine` object를 atomic 복원했다. bridge 제거 및 앱 재시작 뒤에도 Claude LIVE가 유지됐다.

## Grok 검증

- auth file은 regular file, owner 일치, `0600`, valid JSON이다.
- credential material과 아직 지나지 않은 expiration field가 존재한다는 boolean 증거만 확인했다.
- 공식 source와 설치 binary에서 `x.ai/billing`, `/billing?format=credits`, `creditUsagePercent` 계약을 확인했다.
- 설치된 `grok agent stdio`를 initialize한 뒤 `x.ai/billing`을 호출했으나 `-32601 Method not found`였다. credential은 변경되지 않았다.
- 공식 client가 사용하는 `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`를 별도 사용자 승인 후 호출했다.
- HTTP 200과 `config`, `creditUsagePercent`, `currentPeriod`, reset, `prepaidBalance`, unified billing 증거 field의 존재만 기록했다.
- token, expiry timestamp, user ID, 실제 quota·잔액, 원본 payload는 출력·저장하지 않았다.
- 실행 전후 auth file의 SHA-256·mtime·mode는 모두 불변이었다.
- 이 경로는 공개 stable API가 아니라 공식 client에서 관측된 계약이므로 `observed · Beta`로 표시하고 Grok Build 변경 시 재검증한다.

## GLM 검증

- 현재 PATH에서 독립 `glm`·`zai`·ZCode·지원 coding tool CLI를 찾지 못했다.
- 현재 Claude settings는 first-party Claude endpoint를 사용하며 Z.ai endpoint/key/model mapping이 없다.
- 공식 `glm-plan-usage@zai-coding-plugins`도 설치되어 있지 않다.
- 따라서 사용자가 로그인했다고 한 GLM 환경이 별도 shell alias, wrapper, 다른 app profile에 있다면 정확한 실행 command/path가 추가로 필요하다.
- Coding Plan은 공식 지원 도구 전용이므로 QuotaBeacon이 Z.ai credential을 직접 재사용하는 방식은 사용하지 않는다.

## Credential 무결성

- 비교 항목: 9
- hash 변경: 0
- mtime 변경: 0
- mode 변경: 0
- state 변경: 0
- `codex_auth`, `grok_auth`: `0600`
- `claude_settings`, `grok_config`: `0644`; 현재 검사에서는 GLM credential value 설정이 발견되지 않았으며 auth file과 구분한다.
- Claude OAuth probe: Keychain credential 전후 동일, GET-only, refresh/login/write-back 없음.
- Claude settings: 임시 bridge 제거 후 원래 statusLine command 복원, QuotaBeacon bridge/script/config/snapshot 부재 확인.

## 설치 앱·UI 검증

- 설치 위치: `/Users/hwanchoi/Applications/QuotaBeacon.app`
- Universal Release: `arm64`, `x86_64`, hardened runtime, ad-hoc 서명.
- 대시보드 개요: Claude `LIVE`, Codex last-known-good, Grok `LIVE`, Z.ai `Beta · 확인 불가` 확인.
- 연결 화면: Claude toggle 활성, snapshot path 입력 없음, Keychain 자동 탐색 및 no-refresh/no-model-call 설명 확인.
- 한도 화면: Claude 5시간·7일·Fable 주간을 `LIVE · observed · keychain`으로 표시 확인.
- 연결 화면을 끝까지 스크롤한 실제 screenshot에서 고정 detail header 아래로만 content가 clipping되어 상단 이미지/toolbar를 덮지 않는 것을 확인했다.

## 잔여 조치

1. Claude: observed OAuth usage 계약 또는 Claude Code credential schema가 바뀌면 synthetic contract test와 redacted probe를 재실행한다.
2. GLM: 실제 로그인에 사용한 command/path 또는 공식 `glm-plan-usage` plugin 설치 여부를 확인한다.
3. Grok: 현재 first-party CLI billing backend를 Beta LIVE 경로로 유지하고 client version 변경 시 schema·실계정 redacted probe를 재실행한다.
4. Codex: 현재 read-only app-server 연결을 Beta LIVE 경로로 유지하고 client version 변경 시 schema test를 재실행한다.
