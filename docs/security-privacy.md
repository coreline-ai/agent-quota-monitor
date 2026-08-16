# 보안·개인정보 설계

확인일: `2026-08-16 KST`

## 데이터 흐름

- QuotaBeacon은 자체 서버와 telemetry를 사용하지 않는다.
- Claude는 사용자가 연결을 승인한 경우 `Claude Code-credentials` Keychain 항목의 access token만 메모리에서 선택하고 Anthropic OAuth usage HTTPS GET에 사용한다. refresh token은 읽거나 전송하지 않는다.
- Codex는 사용자가 활성화한 경우 공식 `codex app-server`의 `initialize`, `account/rateLimits/read`만 호출한다.
- Grok은 사용자가 opt-in한 경우에만 검증된 `grok login` auth file에서 access token과 user ID를 메모리로 선택하고 xAI 공식 CLI billing backend의 단일 HTTPS GET을 호출한다. refresh token은 선택·사용·전송하지 않는다.
- Z.ai는 사용자가 opt-in한 경우 기존 `claude-glm` alias와 설치된 공식 `glm-plan-usage` plugin만 사용한다. shell profile을 실행하지 않고 ZAI base URL과 auth token 두 값만 메모리에서 선택해 공식 plugin process에 전달한다.
- 과거 수동 Z.ai Keychain item은 더 이상 수집에 사용하지 않으며 설정에서 삭제만 할 수 있다.
- 원본 Provider payload, 프롬프트·응답 본문, 이메일, 계정 ID, 홈 경로는 history/export에 저장하지 않는다.

## 위협 모델과 통제

| 위협 | 통제 |
|---|---|
| credential 파일 바꿔치기 | symlink 거부, owner·regular file·allowlist·`0600` 검사 |
| credential 변조 | read-only API, write-back·refresh·login 메서드 없음, fixture에서 hash/mtime 비교 |
| Claude token 노출 | `/usr/bin/security` 출력은 process memory에서 최소 JSON field만 parse, Authorization header 구성 후 비저장; generic diagnostic만 기록 |
| CLI hang/orphan | timeout, cancellation, TERM 후 KILL, stdout/stderr 분리 |
| 부분 응답 오표시 | window별 optional 처리, `nil`을 퍼센트로 만들지 않음 |
| 오래된 값의 LIVE 오표시 | last-known-good provenance 보존 및 freshness를 `stale`로 변경 |
| 로그·export 유출 | 중앙 `Redactor`, diagnostic 제외 export, release secret scan |
| 비공개·과도한 API 사용 | Claude/Grok은 공식 client에서 관측한 정확한 usage/billing URL의 GET만 allowlist하고 redirect·cookie·cache를 거부; Claude는 180초 성공 cache와 429 backoff 적용; GLM은 설치된 공식 plugin script만 1회 실행하고 5분 성공 cache 적용; browser cookie/WebView 수집 금지 |
| Claude 설정 충돌 | 직접 OAuth 경로는 `~/.claude/settings.json`과 statusLine을 수정하지 않음; 검증용 임시 QuotaBeacon bridge 제거 후 원래 statusLine 복원 확인 |
| Grok token 노출 | access token은 Authorization header 구성에만 사용, refresh token 미선택·미사용·미전송, generic diagnostic만 기록 |
| GLM shell profile 실행·주입 | `.zshrc`를 source/eval하지 않고 `claude-glm` 한 줄을 자체 tokenization; command·ZAI HTTPS host 검증; 허용된 두 environment만 직접 Node process에 전달 |
| GLM plugin output 노출 | stdout 크기 제한, ZAI platform/Quota marker allowlist, Model/Tool section 폐기, quota JSON의 두 percentage만 정규화; stderr·원본 body 비저장 |
| 외부 plugin 바꿔치기 | Claude user cache의 고정 marketplace/plugin subtree만 탐색하고 symlink 거부, manifest name/version과 script regular-file 상태 확인 |

## 사용자 데이터 삭제

- 과거 Z.ai 수동 키: 설정의 **기존 미사용 수동 키 삭제**로 Keychain item 제거.
- History: 설정의 **History 삭제**로 제품의 versioned JSON 파일 제거.
- 앱 제거 시 별도 서버 데이터는 없다.

## 현재 보안 제한

- `2026-08-16` 승인된 실계정 검증에서 Codex read-only quota probe와 Claude Keychain OAuth usage probe를 수행했다. Claude probe는 HTTP 200과 5시간·7일·Fable field 존재만 출력했고 token·원본 payload는 출력·저장하지 않았다.
- Claude credential은 probe 전후 불변이었고 앱 재시작 후에도 Keychain direct source로 `LIVE`를 확인했다. 임시 snapshot bridge는 제거했으며 사용자의 기존 Claude statusLine을 복원했다.
- Grok은 승인된 실계정 read-only probe에서 HTTP 200과 billing field 존재 여부를 확인했으며 credential SHA-256·mtime·mode는 모두 불변이었다. 실제 token·user ID·quota 값·원본 payload는 저장하지 않았다.
- 설치된 Grok Build `1.0.4`의 ACP `x.ai/billing`은 `-32601`이므로, 현재 adapter는 공식 client source와 binary에서 확인된 first-party CLI billing backend를 직접 사용한다. 이 계약은 `observed · Beta`이며 client 변경 시 재검증한다.
- Z.ai 공식 plugin `0.0.1`과 기존 `claude-glm` profile을 redacted probe로 검증했다. 실제 quota 값·token·Model/Tool usage·원본 payload는 보고서나 repository에 저장하지 않았고 profile hash·mtime은 불변이었다.
- 설치 앱은 normalized ratio만 history에 저장하며 `available`, 두 window, `officialCLI`, `observed`, `live`를 확인했다. Coding Plan 지원 도구 정책과 plugin output drift 때문에 Beta로 유지한다.
- Developer ID 공증은 아직 실행하지 않았다. 개인 설치본은 ad-hoc 서명으로 무결성을 검증했다.
- crash reporter와 원격 분석 SDK는 포함하지 않는다.

실환경 검증 상세: [Provider 실환경 검증 보고서](provider-validation-2026-08-16.md)
