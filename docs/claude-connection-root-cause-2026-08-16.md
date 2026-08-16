# Claude 자동 연결 원인 분석

확인일: `2026-08-16 KST`

## 결론

QuotaBeacon이 놓친 것은 Claude Code 로그인이 아니라 **수집 우선순위**였다. 이전 구현은 공식 statusLine 문서를 유일한 quota 계약으로 간주해 별도 snapshot bridge를 요구했다. 실제 monitor는 기존 Claude Code 로그인을 자동 발견한 뒤 OAuth usage를 primary로 읽고, CLI/statusLine을 fallback 또는 live 보강으로 사용한다.

## 직접 확인한 참조 경로

- 설치 앱: `/Applications/Orca.app`
- Keychain adapter: `app.asar.unpacked/out/main/chunks/keychain-*.js`
- OAuth rate-limit service: unpack한 Orca main bundle의 `OAUTH_USAGE_URL`, `readOAuthCredentials`, `fetchViaOAuth`, `mapFableWeeklyWindow`
- statusLine parser: `app.asar.unpacked/out/shared/claude-statusline-rate-limits.js`

관측한 순서는 다음과 같다.

1. macOS Keychain service `Claude Code-credentials`에서 현재 account의 JSON을 읽는다.
2. `claudeAiOauth.accessToken`으로 `GET https://api.anthropic.com/api/oauth/usage`를 호출한다.
3. OAuth usage 실패 유형에 따라 Claude CLI `/usage` fallback을 시도한다.
4. 실행 중 Claude session이 제공하는 statusLine `rate_limits`는 usage endpoint polling을 줄이는 live 보강 신호로 사용한다.

참고 오픈소스 문서도 Keychain OAuth usage primary와 statusLine/CLI secondary 구조를 독립적으로 설명한다: [claudexor integrations](https://github.com/razzant/claudexor/blob/main/docs/INTEGRATIONS.md), [CodexBar Claude provider notes](https://github.com/steipete/CodexBar/blob/main/docs/claude.md).

## 이전 판단이 실패한 이유

| 누락 | 영향 | 수정 control |
|---|---|---|
| 공식 statusLine 문서만 조사 | 로그인돼도 첫 Claude event 전에는 snapshot이 없어 `연결 필요` | credential source → first-party endpoint → CLI fallback → live feed 순서로 조사 |
| `claude auth status`만 신뢰 | sandbox Keychain 제한으로 false negative | host Keychain metadata와 redacted direct probe로 교차 검증 |
| 참조 구현의 primary path 미추적 | 사용자가 path와 bridge를 별도 설정 | Keychain 자동 탐색과 exact GET contract 구현 |
| polling 위험 미반영 | usage endpoint `429` 가능 | 180초 success cache, `Retry-After`/15분 backoff |

## 적용한 독립 구현

- `ClaudeKeychainCredentialReader`: access token만 parse하며 refresh token을 선택하지 않는다.
- `ClaudeOAuthUsageProvider`: allowlist URL의 GET만 허용하고 ephemeral session, no-cookie, no-cache, redirect 거부, 10초 timeout을 적용한다.
- `ClaudeOAuthUsageParser`: 5시간·7일·Fable 주간 window, ISO/epoch reset, 부분 응답을 typed state로 변환한다.
- `ProviderConnectionsView`: snapshot path 입력을 제거하고 기존 Claude Code 로그인 자동 탐색 toggle을 제공한다.
- `claude_oauth_usage_probe.py`: field 존재·HTTP status·credential 불변 여부만 출력하고 token·원본 payload·실제 quota를 출력하지 않는다.

외부 source·fixture·UI는 복사하지 않았으며 Swift 구현과 fixture/test는 QuotaBeacon 계약에 맞춰 새로 작성했다.

## 검증 결과

- 승인된 redacted probe: HTTP 200, 5시간·7일·Fable field 존재, credential 전후 불변.
- Swift unit: 전체 36 PASS, Claude OAuth/Keychain 5 PASS.
- Python: safe validation 16, Claude probe 2, Grok probe 4, legacy bridge 1 PASS.
- 설치 앱: Claude `available`, 3 windows, source `keychain`, contract `observed`, diagnostic 없음.
- 임시 QuotaBeacon bridge 제거 및 사용자의 원래 statusLine 복원 후 앱 재시작: Claude LIVE 유지.
- 실제 연결 화면 scroll: content가 고정 detail header 아래로 clipping되어 상단을 덮지 않음.

## 잔여 위험

OAuth usage endpoint는 공개 stable API가 아니라 first-party client 동작에서 관측한 계약이다. 따라서 `observed · Beta`로 표시하고 Claude Code credential/schema 또는 endpoint 동작 변경 시 synthetic contract test와 redacted probe를 다시 실행한다.
