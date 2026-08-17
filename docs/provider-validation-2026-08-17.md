# Grok·Gemini 추가 실환경 검증 보고서

실행일: `2026-08-17 KST`

## 검증 범위

- Grok 구독 quota의 5시간 창 존재 여부 재검증
- 공식 Antigravity CLI를 이용한 Gemini quota 수집 가능성 검증
- 원칙: read-only, `/usage` 외 prompt·model·tool·agent command 없음
- 비밀정보: 실제 quota 값, 이메일, 계정 ID, 홈 경로, raw TUI를 출력·저장하지 않음

## 결과 요약

| Provider | 공식/실환경 증거 | 결과 | 판정 |
|---|---|---|---|
| Grok Build | xAI Usage & Limits FAQ, API rate-limit 문서, 설치된 `grok 1.0.4` billing artifact | 구독은 주간 공용 pool. 구독용 5시간 window는 관측되지 않음 | `주간 공용` 유지, unknown period를 5시간으로 추정하지 않음 |
| Gemini | Google Antigravity CLI codelab, 설치된 `agy 1.1.13`, 승인된 redacted `/usage` probe | Gemini 그룹의 주간·5시간 field와 reset evidence 확인 | `observed · Beta` LIVE 수집 가능 |

## Grok 검증

- 공식 FAQ는 유료 사용량을 Chat, Imagine, Voice, Build 등이 공유하는 주간 사용량 pool로 설명한다.
- API 문서의 RPS/TPM은 team·model별 API rate limit이므로 Grok 구독 quota와 합산하지 않는다.
- 설치된 billing contract는 weekly/monthly/unknown period를 전달할 수 있지만 구독용 5시간 period는 관측되지 않았다.
- parser는 `WEEKLY`만 `주간 공용`, legacy `MONTHLY`만 월간 custom window로 매핑한다.
- synthetic `FIVE_HOUR` 값은 `.fiveHour`가 아니라 redacted custom window가 되는 회귀 테스트를 추가했다.

## Gemini 검증

- 기존 `gemini 0.55.1` 개인 Google 로그인은 Antigravity 이전 안내와 함께 거부되었고 ACP command registry에는 stats command가 없었다. 해당 transport는 폐기했다.
- 공식 `agy 1.1.13`을 기존 trusted workspace에서 실행하고 `/usage`만 한 번 전송했다.
- redacted 결과에서 다음 boolean evidence를 확인했다.
  - `GEMINI MODELS` 그룹 존재
  - `Weekly Limit Remaining` field와 유효 percentage 존재
  - `Five Hour Limit Remaining` field와 유효 percentage 존재
  - 두 bucket의 refresh/reset evidence 존재
  - `CLAUDE AND GPT MODELS` 그룹 제외
  - 모델 prompt 전송 없음, model request와 tool call 증가 없음
  - Antigravity settings hash·mtime·mode 불변
  - credential 파일 직접 열람 없음, raw TUI 저장 없음
- 실제 percentage·reset 시각·계정 정보는 stdout, 문서, repository fixture에 남기지 않았다.

## PTY 원인 분석과 수정

- 최초 bounded Expect 실행은 child PTY 크기가 `0x0`으로 생성되어 TUI 본문 없이 terminal control query만 반환했다.
- `expect` process 자체가 아니라 spawn된 child의 slave PTY에 `48x120` 크기를 지정한 뒤 `/usage` 본문이 정상 렌더링되었다.
- 설치 검증에서 terminal capability query가 반복되면 일반 `exp_continue`가 단계 timer를 재시작해 외부 38초 guard까지 도달하는 간헐 timeout을 추가로 확인했다.
- 모든 protocol-response branch를 `exp_continue -continue_timer`로 바꿔 내부 22초·12초 제한을 보존하고, 외부 guard는 cleanup 여유를 포함한 45초로 분리했다.
- 제품과 probe 모두 동일한 child-slave size control, 512 KiB output cap, TERM 뒤 bounded KILL fallback과 wait를 적용했다.
- executor는 raw TUI를 history·diagnostic에 전달하지 않고 `GEMINI MODELS`와 다음 group marker 사이만 parser에 전달한다.

## 보안·무결성 판정

- QuotaBeacon은 Antigravity OAuth credential, account DB, cookie, Code Assist 내부 endpoint를 직접 읽거나 호출하지 않는다.
- `agy` 자동 업데이트는 probe와 제품 수집 동안 비활성화한다.
- TUI가 함께 렌더링하는 account line과 다른 모델 그룹은 메모리에서 즉시 폐기한다.
- 정상 결과는 5분 cache하며 cache를 새 live 요청으로 오표시하지 않는다.

## 설치 앱·UI 확인

- 연결 화면에 `Gemini · Antigravity Beta` toggle, 실행 파일 자동 찾기, trusted workspace evidence, 읽기 전용 경계 설명을 추가했다.
- 메뉴 막대, 개요, 한도, 추세, 데이터 소스, 표시 설정에 다섯 번째 Provider를 연결했다.
- Gemini 알림은 live/partial percentage뿐 아니라 reset evidence가 있는 window에만 허용한다.
- 수정된 Universal Release를 `/Users/hwanchoi/Applications/QuotaBeacon.app`에 설치해 실행했다.
- 설치본의 redacted history는 Gemini `available`, `sharedWeekly`·`fiveHour` 2개, `officialCLI`·`observed`·`live`, diagnostic 없음으로 확인됐다.
- 같은 read-only live probe를 3회 연속 실행해 모두 성공했고 종료 뒤 `agy`·`expect` child가 남지 않았다.

## 자동 검증 결과

- Swift 단위 테스트: `66/66` PASS
- macOS UI 테스트: `2/2` PASS — 대시보드 스크롤, Gemini 연결·표시 설정, 메뉴바 summary/detail 포함
- Provider probe 테스트: `33/33` PASS
- fixture `21`개 guard, security/PII, originality, greenfield audit PASS
- Universal Release: `x86_64 arm64`, codesign strict verify, ZIP checksum PASS

## 재검증 조건

1. `agy` version 또는 `/usage` label·group 구조 변경
2. 개인 Gemini CLI의 Antigravity 이전 정책 변경
3. Grok 공식 FAQ 또는 billing `periodType`에 실제 5시간 window 추가
4. timeout, child cleanup, raw-output 격리 회귀 발생
