# Provider 실환경 검증 보고서

실행일: `2026-08-16 KST`

## 검증 범위

- Provider: Codex, Claude Code, Grok Build, Z.ai GLM Coding Plan
- 원칙: read-only, 모델 호출 없음, prompt 전송 없음, login/logout/refresh 명령 없음
- 비밀정보: credential 값·계정 ID·이메일·원본 payload·홈 경로를 저장하지 않음
- 무결성: allowlist credential/config 9개 항목의 SHA-256·mtime·mode를 실행 전후 비교

## 결과 요약

| Provider | 로그인/설치 증거 | quota 검증 | 판정 |
|---|---|---|---|
| Codex | `codex-cli 0.145.0`, auth file regular/owner 일치/`0600` | 공식 app-server `account/rateLimits/read` 성공. plan·primary window·reset·duration·credits field 관측 | QuotaBeacon LIVE 연결 가능 |
| Claude | Claude Code `2.1.233`, host 환경 `claude auth status` 로그인 확인 | status-line은 설정돼 있으나 QuotaBeacon snapshot은 비활성·미설정 | 로그인 확인, quota bridge 필요 |
| Grok | Grok Build `1.0.4 stable`, auth JSON valid/credential material 있음/미래 expiry 증거/`0600` | CLI 공개 command에 usage·quota·billing 없음 | 로그인 file 증거 확인, quota는 상태 전용 |
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

- 샌드박스 내부 `claude auth status`는 Keychain 접근 제한으로 false negative를 반환했다.
- 사용자 승인 host read-only 재검사에서는 `loggedIn=true`, `authMethod=claude.ai`를 확인했다.
- 기존 status-line command는 존재하지만 QuotaBeacon의 `claude.snapshotEnabled`는 false다.
- quota 수치를 얻으려면 기존 status-line을 보존하면서 `rate_limits`만 `0600` 파일로 atomic write하는 bridge가 필요하다.
- 이번 작업은 `~/.claude/settings.json`을 변경하지 않았다.

## Grok 검증

- auth file은 regular file, owner 일치, `0600`, valid JSON이다.
- credential material과 아직 지나지 않은 expiration field가 존재한다는 boolean 증거만 확인했다.
- token, expiry timestamp, 계정 정보는 출력·저장하지 않았다.
- 공식 CLI help에는 `login`은 있으나 quota 조회 command가 없으므로 모델 호출이나 비공개 endpoint로 검증하지 않았다.

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

## 잔여 조치

1. Claude quota 연결: 기존 status-line 보존형 snapshot bridge 설치를 별도 승인 후 진행한다.
2. GLM: 실제 로그인에 사용한 command/path 또는 공식 `glm-plan-usage` plugin 설치 여부를 확인한다.
3. Grok: 공식 machine-readable quota command가 공개될 때까지 status-only를 유지한다.
4. Codex: 현재 read-only app-server 연결을 Beta LIVE 경로로 유지하고 client version 변경 시 schema test를 재실행한다.
