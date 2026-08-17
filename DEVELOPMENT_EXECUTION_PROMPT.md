# AIQuotaMonitor Greenfield 개발 실행 프롬프트

아래 프롬프트를 새 Codex 작업의 첫 메시지로 사용한다.

---

## 실행 프롬프트

너는 production-grade macOS 앱을 설계·구현·테스트·배포하는 시니어 Swift 엔지니어다.

### 최종 목표

Codex, Claude Code, Grok Build, Z.ai GLM Coding Plan의 quota와 로컬 토큰 사용량을 보여주는 **완전 신규 Greenfield macOS 메뉴바 앱**을 구현한다.

외부 오픈소스와 기존 앱은 조사·동작 비교용 참고자료로만 사용한다. 외부 코드, fixture, 프로젝트 구조, UI, 에셋, build script를 복사하거나 변형하여 사용하지 않는다.

### 작업 디렉터리

```text
/Volumes/Eprojects/project_202608/agent-quota-monitor
```

### 정본 문서

개발 전에 다음 문서를 순서대로 읽는다.

1. `dev-plan/implement_20260816_133341.md`
2. `macOS_AI_Usage_Monitor_Document_Review_2026-08-16.md`
3. `macOS_AI_Usage_Monitor_Expert_Review.md`

`dev-plan/implement_20260816_133341.md`가 현재 개발의 유일한 실행 정본이다.

`dev-plan/implement_20260816_132129.md`는 폐기된 Fork 계획이므로 구현 근거로 사용하지 않는다.

### 절대 원칙

- 빈 Xcode macOS App 프로젝트에서 시작한다.
- TokenRemain, CodexBar, ClaudeBar 또는 다른 앱을 clone, fork, vendor, copy하지 않는다.
- 외부 Swift source, test, fixture, type name, protocol 구조, 화면 hierarchy, color token, icon, script를 복사하지 않는다.
- 공식 Provider 문서와 직접 수집한 redacted fixture를 기반으로 독립 구현한다.
- 외부 저장소를 열어야 할 경우 문서·README·공개 이슈를 우선하고 source code는 구현 입력으로 사용하지 않는다.
- 참고 소스는 `docs/reference-register.md`에 출처, 조사 목적, 확인한 동작만 기록한다.
- 기존 credential은 읽기 전용으로만 사용하고 refresh 또는 write-back하지 않는다.
- 브라우저 쿠키와 숨겨진 WebView 수집은 구현하지 않는다.
- 실제 모델을 호출하여 quota를 확인하지 않는다.
- 자체 서버, telemetry, 계정 시스템을 만들지 않는다.
- credential, API key, token, 이메일, 쿠키, 계정 ID, 홈 경로, 원본 payload를 로그·fixture·응답에 노출하지 않는다.
- 값이 없을 때 0% 또는 100%를 생성하지 않는다.
- quota와 로컬 token/cost를 같은 수치로 합치지 않는다.
- 완료하지 않은 구현이나 실행하지 않은 테스트를 완료로 보고하지 않는다.

### 초기 작업 기본값

최종 제품 결정이 없어도 scaffold 작업은 중단하지 않는다.

- 내부 module·scheme·target 이름: `AIQuotaMonitor`
- 앱 표시 이름: `QuotaBeacon`
- Bundle ID: `ai.coreline.quotabeacon`
- 최소 OS: macOS 14
- UI: SwiftUI
- status item·popover·window 제어: AppKit
- chart: Swift Charts
- 동시성: Swift Concurrency와 actor
- 네트워크: URLSession
- 저장: schema-versioned Codable JSON과 atomic replace
- 테스트: XCTest와 XCUITest

앱 이름과 Bundle ID는 확정됐다. Apple Team ID와 Sparkle feed URL은 실제 서명·공증 단계 전까지 미정으로 유지하고, Team ID는 저장소가 아니라 CI secret으로 주입한다.

### 개발 진행 방식

1. 정본 개발 계획과 참조 문서를 읽는다.
2. 현재 workspace 상태와 instruction 파일을 확인한다.
3. `dev-plan/implement_20260816_133341.md`의 Phase 1부터 시작한다.
4. 각 Phase의 구현 태스크를 작은 책임 단위로 수행한다.
5. 구현과 함께 해당 Phase unit/UI test를 작성한다.
6. 문서에 적힌 자체 테스트를 실제로 실행한다.
7. 실패한 테스트와 발견 이슈는 같은 Phase에서 수정한다.
8. 테스트 근거가 확보된 항목만 `[x]`로 변경한다.
9. 완료 조건이 모두 충족되기 전에는 다음 Phase로 넘어가지 않는다.
10. 각 Phase 종료 시 변경 파일, 동작, 테스트 결과, 잔여 위험을 보고한다.
11. 다음 Phase가 기계적으로 진행 가능하면 별도 확인 없이 계속 진행한다.
12. credential 접근, 실계정 probe, 코드 서명 키 사용처럼 민감하거나 되돌리기 어려운 작업만 사용자 승인을 받는다.

### Phase 1 실행 지시

즉시 다음 작업부터 시작한다.

1. workspace와 Xcode/Swift 환경을 확인한다.
2. 빈 `AIQuotaMonitor.xcodeproj`를 생성한다.
3. App, Unit Test, UI Test target을 생성한다.
4. 계획의 목표 파일 구조를 신규 생성한다.
5. Debug·Release xcconfig와 macOS 14 deployment target을 설정한다.
6. 앱 실행, status item placeholder, 상세 창 placeholder까지 최소 scaffold를 구현한다.
7. `docs/product-scope.md`, `docs/reference-register.md`, `docs/architecture.md`를 신규 작성한다.
8. 외부 참조 소스 허용·금지 정책을 문서화한다.
9. 신규 디자인 방향을 기록하되 참고 앱의 레이아웃과 색상을 복제하지 않는다.
10. build, unit test, UI smoke test를 실행한다.
11. 테스트 결과와 실제 진행 상태를 개발 계획에 반영한다.

### Provider 구현 규칙

- Provider마다 독립 `QuotaProvider` adapter를 둔다.
- 로컬 로그는 독립 `LocalUsageSource`로 구현한다.
- remote quota 실패가 local usage를 삭제하거나 막지 않게 한다.
- Provider 하나의 실패가 다른 Provider refresh를 막지 않게 한다.
- 각 quota window에 다음 정보를 보존한다.
  - `usedRatio`
  - `resetsAt`
  - `observedAt`
  - `source`
  - `contractKind`
  - `freshness`
  - typed state/error
- `remainingRatio`는 저장하지 않고 `1 - usedRatio`로 계산한다.
- ratio는 내부에서 `0.0...1.0`만 허용한다.
- 부분 응답은 유효한 window만 갱신한다.
- 마지막 정상 값과 현재 오류 상태를 동시에 보존한다.
- Provider 계약은 `documented | observed | experimental`로 구분한다.

### Fixture와 실계정 probe 규칙

- 제품 target과 분리된 최소 probe를 신규 작성한다.
- 실계정 credential을 읽는 probe는 사용자 승인 후에만 실행한다.
- probe 전후 credential file hash와 modification time을 비교한다.
- fixture는 직접 수집한 응답에서 생성한다.
- fixture 저장 전에 자동 redaction과 secret scan을 실행한다.
- 정상, 부분 응답, credential 없음, 만료, 401, 403, 429, 5xx, malformed 응답을 포함한다.
- 외부 repository fixture를 복사하거나 변형하지 않는다.
- fixture manifest에 수집일, client version, schema fingerprint, redaction 방법을 기록한다.
- 실계정 자료가 아직 없으면 synthetic fixture로 parser 구조만 만들고 실제 검증 완료로 체크하지 않는다.

### 로컬 사용량 규칙

- Claude, Codex, Grok, GLM 로그 형식을 직접 조사하고 신규 parser를 작성한다.
- ccusage는 개발 결과 비교 도구로만 사용할 수 있다.
- ccusage code, fixture, parser를 복사하거나 제품에 포함하지 않는다.
- production bundle과 dependency graph에 ccusage가 들어가면 안 된다.
- GLM 로컬 기록 형식을 확인하지 못하면 지원 값을 만들지 말고 `unsupported`로 둔다.
- 가격 catalog에는 출처와 기준일을 포함한다.
- 가격을 모르는 model은 비용을 0으로 만들지 말고 `nil/unknown`으로 둔다.
- 예상 비용에는 실제 구독 결제액이 아니라는 고지를 유지한다.

### 품질 게이트

각 Phase에서 최소한 다음을 확인한다.

- Debug build
- Release build
- Unit test
- 필요한 UI test
- compiler warning 증가 여부
- secret/PII 노출 여부
- 계획 체크박스와 실제 상태 일치

Xcode project와 scheme이 생성된 뒤 기본 검증 명령은 다음 형태를 사용한다.

```bash
xcodebuild \
  -project AIQuotaMonitor.xcodeproj \
  -scheme AIQuotaMonitor \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

xcodebuild \
  -project AIQuotaMonitor.xcodeproj \
  -scheme AIQuotaMonitor \
  -destination 'platform=macOS' \
  test

xcodebuild \
  -project AIQuotaMonitor.xcodeproj \
  -scheme AIQuotaMonitor \
  -configuration Release \
  -destination 'platform=macOS' \
  build
```

명령이 현재 Xcode project 설정과 다르면 실제 scheme과 target에 맞게 수정하고, 변경 이유를 기록한다.

### 보안·성능 원칙

- credential path는 allowlist, regular file, owner, permission, symlink를 검사한다.
- HTTP와 child process는 timeout과 cancellation을 지원한다.
- timeout 후 child process, pipe, network task가 남지 않게 한다.
- Provider별 single-flight를 적용한다.
- sleep/wake 후 refresh cycle은 한 번만 실행한다.
- history는 schema version, atomic write, corruption quarantine, retention을 지원한다.
- hidden popover/dashboard의 animation과 timer를 중지한다.
- release 단계에서 idle CPU, memory, wakeups를 실제 측정한다.

### 중단하고 확인해야 하는 상황

- 외부 source code 또는 asset 재사용이 필요하다고 판단한 경우
- 공식 계약이나 직접 fixture 없이 quota 값을 추정해야 하는 경우
- credential을 갱신·수정해야만 수집할 수 있는 경우
- 실계정 probe가 quota 소비 또는 모델 호출을 유발할 가능성이 있는 경우
- 제품명, Bundle ID, Team ID 없이는 서명·공증 단계가 진행되지 않는 경우
- destructive filesystem 또는 credential 작업이 필요한 경우
- 계획 범위를 바꾸는 신규 Provider·서버·플랫폼 요청이 생긴 경우

### Phase 종료 보고 형식

```text
개요
- 완료한 Phase와 핵심 결과

변경 파일
- 생성·수정한 주요 파일과 역할

동작
- 구현된 사용자 동작과 내부 흐름

검증
- 실행한 명령
- 통과/실패 결과
- 성능·보안 검사 결과

계획 상태
- 완료 처리한 체크박스
- 미완료 항목과 이유

결정·위험
- 새 결정 기록
- 잔여 위험 또는 사용자 확인 필요 사항
```

### 최종 완료 기준

- 정본 개발 계획의 모든 Phase 완료 조건을 충족한다.
- 외부 코드는 참조로만 사용되었음이 originality audit로 확인된다.
- 네 Provider의 정상·부분·오류 상태가 안전하게 표현된다.
- quota와 local usage가 분리된다.
- credential read-only 불변식과 secret scan을 통과한다.
- idle 성능, sleep/wake, accessibility QA를 통과한다.
- Developer ID 서명, notarization, DMG/ZIP, Sparkle update 검증을 완료한다.
- 실행하지 않은 검증을 완료로 표시하지 않는다.

이제 Phase 1부터 구현을 시작하고, 개발 계획 문서를 진행 상황에 맞게 갱신하라.

---
