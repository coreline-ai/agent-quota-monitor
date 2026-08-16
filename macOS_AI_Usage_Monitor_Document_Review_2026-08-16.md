# macOS AI 사용량 모니터 개발 문서 검토 보고서

검토 일시: `2026-08-16 KST`  
검토 대상: `macOS_AI_Usage_Monitor_Expert_Review.md`  
검토 범위: 구현 가능성, 외부 연동 안정성, 데이터 모델, 보안·라이선스, 배포, 테스트 가능성, 문서 구조

## 1. 종합 결론

**판정: 조건부 승인**

문서는 제품 방향, UI 원칙, 로컬 사용량과 구독 한도의 분리, 실패 상태 표현, 직접 배포 전략을 설명하는 **기술 검토·제품 제안서**로서는 완성도가 높다.

다만 현재 상태로 바로 포크와 구현을 시작하기에는 다음 두 항목이 선행되어야 한다.

1. TokenRemain 기준 버전과 Provider별 수집 계약을 고정한다.
2. Apache-2.0 재배포 의무와 비오픈소스 에셋 제거 범위를 릴리스 체크리스트로 구체화한다.

또한 현재 공통 데이터 모델은 문서가 강조하는 핵심 가치인 **숫자의 출처·최신성·부분 실패**를 한도 창별로 표현하지 못한다. 이 부분은 UI 구현 전에 수정하는 것이 안전하다.

## 2. 잘 정리된 부분

- 구독 한도와 로컬 토큰·비용 추정을 분리했다.
- `nil`과 실제 0%/100%를 구분하는 원칙이 명확하다.
- 마지막 정상 값, stale 상태, 연결 필요, 지원 불가 계정을 구분했다.
- Provider 하나의 실패가 전체 갱신을 막지 않도록 했다.
- 원문 응답과 비밀정보를 로그에 남기지 않는 원칙이 좋다.
- allowlist 경로, 파일 소유권, 심볼릭 링크 방어를 명시했다.
- 메뉴바·상세 화면·데이터 소스 화면의 역할이 명확하다.
- App Sandbox 제약을 고려해 Developer ID 직접 배포를 권장한 방향이 현실적이다.
- 접근성, idle CPU, sleep/wake, 프로세스 종료까지 QA 범위에 포함했다.

## 3. 우선순위별 검토 결과

### P0-01. Fork 기준선과 외부 수집 계약이 고정되어 있지 않음

관련 위치: 원문 25~31, 80~95, 182~298, 1077~1086행

문서는 TokenRemain의 현재 구조와 `main` 브랜치 링크를 기반으로 포크를 권장하지만, 기준 태그·커밋·검증 날짜를 적지 않았다. Provider 수집은 OAuth 파일, CLI RPC, 비공개 백엔드, CLI 버전에 민감하므로 upstream 변경이나 Provider 변경만으로 설계 전제가 달라질 수 있다.

2026-08-16 검토 시점의 TokenRemain `main` 기준선은 다음과 같다.

- commit: `3490d4a92c97af12280daca9357c8f1ef83172b4`
- upstream commit date: `2026-08-13T09:40:33Z`
- README 표시 버전: `v1.3.5 · build 32`

필수 수정:

- 포크 대상 태그와 전체 commit SHA를 문서 상단에 고정한다.
- 모든 GitHub `main` 링크를 해당 commit permalink로 바꾼다.
- Provider별로 `문서화된 공식 계약 / 공식 CLI의 관찰된 동작 / 비공개 endpoint / 로컬 추정`을 구분한다.
- 최소 CLI 버전, 마지막 검증일, fixture 버전, 실패 시 feature flag/kill switch를 기록한다.
- Phase 0을 통과하기 전에는 UI 퍼센트 표시를 구현하지 않는다.

완료 기준:

- 네 Provider 각각에 대해 로그인·로그아웃·만료·부분 응답·지원 불가 계정 fixture가 있다.
- fixture 파일에 비밀정보가 없고 수집일, 앱/CLI 버전, 응답 schema 버전이 기록되어 있다.
- 연동 경로가 바뀌어도 0% 또는 100%로 오표시하지 않는 테스트가 있다.

### P0-02. 라이선스 설명이 에셋 교체에 치우쳐 있고 재배포 의무가 불완전함

관련 위치: 원문 35~52, 955~968행

원문은 브랜드·로봇·스크린샷·디자인 에셋 교체를 정확히 강조한다. 그러나 배포 제품이 충족해야 할 Apache-2.0 의무는 `Apache-2.0 고지 유지` 한 줄보다 구체적이어야 한다.

[TokenRemain ASSET-LICENSE](https://github.com/Carstin520/token-remain/blob/3490d4a92c97af12280daca9357c8f1ef83172b4/ASSET-LICENSE.md)는 이름, 로고, 아이콘, 마스코트, 스크린샷, 목업, 1차 제작 시각 에셋을 Apache-2.0 범위에서 제외한다. [Apache-2.0 LICENSE](https://github.com/Carstin520/token-remain/blob/3490d4a92c97af12280daca9357c8f1ef83172b4/LICENSE)는 재배포 시 라이선스 사본, 수정 파일 고지, 관련 저작권·상표·귀속 고지, NOTICE 처리 의무를 둔다.

필수 수정:

- `LICENSE`, `NOTICE`, 수정 파일 고지 정책을 릴리스 태스크로 추가한다.
- `Vendor/ccusage`, SwiftPM 의존성, Provider icon 등 제3자 라이선스를 전수 조사한다.
- `THIRD_PARTY_NOTICES.md` 또는 동등한 산출물을 완료 기준에 넣는다.
- 삭제·교체 대상 에셋을 glob/path 목록과 자동 검사 스크립트로 관리한다.
- UI 구조를 참고하더라도 원본 색상·대표 배치·일러스트 표현을 그대로 복제하지 않는 디자인 검토를 둔다.
- 상업 배포 전 법률 검토가 필요할 수 있음을 명시한다.

### P1-01. 공통 모델이 한도 창별 출처와 최신성을 표현하지 못함

관련 위치: 원문 698~726, 736~776행

현재 제안 모델은 `UsageSnapshot`에 `source`와 `health`를 하나씩만 둔다. 그러나 같은 Provider 안에서도 세션 한도는 OAuth, 크레딧은 별도 endpoint, 로컬 추세는 ccusage, 실패 시 표시는 캐시에서 올 수 있다. Claude의 5시간·7일 창도 각각 독립적으로 누락될 수 있다.

이 구조에서는 다음 오표시가 가능하다.

- 일부 창만 새 값인데 전체 카드가 `LIVE`로 표시됨
- OAuth 값과 캐시 값이 한 source로 뭉침
- 크레딧만 실패했는데 Provider 전체가 실패로 표시됨
- `usedRatio`와 `remainingRatio`가 서로 모순됨

필수 수정:

- `QuotaWindow`와 `CreditBalance`에 `source`, `observedAt`, `freshness`, `contractKind`를 둔다.
- `usedRatio` 하나를 정본으로 저장하고 `remainingRatio`는 계산 속성으로 만든다.
- 파싱 시 `[0, 1]` 범위 검증, clamp 여부, 반올림 규칙을 테스트한다.
- snapshot 전체 상태와 각 값의 상태를 분리한다.

권장 형태:

```swift
struct QuotaWindow: Sendable, Codable, Identifiable {
    let id: String
    let kind: QuotaWindowKind
    let usedRatio: Double?
    let resetsAt: Date?
    let observedAt: Date
    let source: UsageSource
    let contract: SourceContractKind
    let freshness: DataFreshness

    var remainingRatio: Double? {
        usedRatio.map { 1 - $0 }
    }
}
```

### P1-02. 원격 quota와 로컬 로그 수집 책임이 하나의 Adapter에 결합됨

관련 위치: 원문 698~709행

`UsageProviderAdapter`가 `fetchQuota()`와 `fetchLocalHistory()`를 함께 요구한다. GLM처럼 로컬 세션 로그가 없거나, ccusage처럼 여러 Provider 로그를 통합 탐색하는 경우 이 인터페이스는 불필요한 빈 구현과 오류 처리를 만든다.

필수 수정:

- `QuotaProviderAdapter`와 `LocalUsageSource`를 분리한다.
- Provider ID는 두 결과를 화면에서 조인하는 키로만 사용한다.
- ccusage 실행·파싱·가격 추정은 독립 서비스로 둔다.
- quota 수집 실패가 로컬 추세 표시를 막지 않고, 그 반대도 성립하도록 테스트한다.

### P1-03. 연결·지원·부분 실패 상태의 도메인 분류가 부족함

관련 위치: 원문 497~529, 759~776행

`DataSourceHealth`의 freshness와 문자열 오류만으로는 문서에 등장하는 다양한 상태를 안정적으로 구분하기 어렵다.

필수 상태:

- `notConfigured`
- `authenticationRequired`
- `credentialExpired`
- `unsupportedAccount`
- `unsupportedClientVersion`
- `temporarilyUnavailable`
- `partialSuccess`
- `staleCache`
- `rateLimited`
- `permissionDenied`

사용자 메시지와 내부 오류 코드를 분리하고, 알림은 상태 전이 기준으로 dedupe해야 한다.

### P1-04. 추세·소진 예측을 위한 저장 정책과 계산 계약이 없음

관련 위치: 원문 468~486, 684~688, 789~829, 988~1000행

`HistoryStore` 이름과 화면 요구사항은 있지만 다음 구현 결정이 없다.

- 저장소 형식과 schema version
- 보존 기간과 최대 크기
- 샘플링 주기와 중복 제거 키
- 5시간/주간 창 reset 전후 데이터 연결 규칙
- 시간대·DST·시스템 시계 변경 처리
- 예측에 필요한 최소 표본 수와 confidence 표시
- 데이터 내보내기 형식과 개인정보 제거 범위

필수 수정:

- quota history와 local token history를 별도 저장한다.
- reset 발생 시 새 window instance를 생성하고 이전 창과 섞지 않는다.
- 예측 불가 상태를 숫자 대신 `표본 부족`으로 표시한다.
- retention, migration, corruption recovery 테스트를 추가한다.

### P1-05. 메뉴바 대표 값과 알림 위험도 계산 규칙이 지나치게 단순함

관련 위치: 원문 314~347, 833~858행

네 Provider 중 단순히 가장 낮은 잔여율을 표시하면 재설정까지 2분 남은 20%와 재설정까지 6일 남은 25%를 잘못 우선순위화할 수 있다. stale 값이나 연결되지 않은 Provider가 대표 상태에 들어가는 규칙도 없다.

필수 수정:

1. 유효하고 fresh한 창만 위험도 계산에 사용한다.
2. 예상 소진 시각이 reset보다 빠른 창을 최우선으로 둔다.
3. 예측 불가 시 잔여율, reset까지 시간 순으로 보조 정렬한다.
4. stale·부분 실패·연결 필요는 퍼센트와 별도의 상태 배지로 집계한다.
5. 알림은 `(provider, window instance, threshold)` 단위로 한 번만 발송한다.

### P1-06. 읽기 전용 인증 정책과 fallback 구현 규칙을 Provider별로 고정해야 함

관련 위치: 원문 195~233, 261~267, 712~730, 862~883행

문서는 인증정보를 읽기 전용으로 사용하고 refresh token을 갱신하지 않는다고 정한다. 이 원칙은 좋지만, 참고 구현 중에는 access token을 갱신하거나 브라우저 쿠키를 가져오는 경로가 있을 수 있다. fork 과정에서 해당 코드가 남지 않도록 정책을 테스트로 고정해야 한다.

필수 수정:

- Provider별 허용 credential source와 금지 동작을 표로 만든다.
- 기본 정책은 `읽기 전용`, `write-back 금지`, `자동 refresh 금지`, `브라우저 쿠키 import 비활성화`로 고정한다.
- Keychain 읽기 권한 요청은 사용자 동작과 설명 후 수행한다.
- 인증 만료 시 원본 credential을 수정하지 않고 해당 CLI/앱에서 재로그인하도록 안내한다.
- 캐시와 내보내기 파일의 보호 등급 및 삭제 기능을 정의한다.

### P1-07. 현재 단계 목록은 구현 계획과 완료 판정 문서로는 부족함

관련 위치: 원문 932~1061행

문서에는 단계와 예상 기간이 있지만 체크박스, 예상 변경 경로, 단계별 자체 테스트, 결정 기록, 위험 게이트가 없다. 로컬 구조 검사에서도 Markdown 체크박스는 0개였다.

필수 수정:

- 이 문서는 기술 검토서로 유지하고, 별도의 `dev-plan/implement_*.md`를 만든다.
- 각 Phase에 구현 태스크, 자체 테스트, 완료 조건을 둔다.
- Phase 0 Provider fixture 검증을 명시적 go/no-go gate로 만든다.
- 네 Provider를 한 번에 완료하는 일정에는 CLI/API 변동 대응 버퍼를 추가한다.
- Grok·GLM은 Beta로 출시할 수 있는 완료 기준을 별도로 둔다.

### P1-08. 직접 배포와 자동 업데이트의 릴리스 보안 게이트가 부족함

관련 위치: 원문 887~929, 1004~1017행

Developer ID, 공증, Sparkle 방향은 적절하다. 다만 자동 업데이트는 앱 서명 외에 feed와 업데이트 아카이브의 신뢰 경계를 별도로 검증해야 한다.

필수 수정:

- hardened runtime과 전체 중첩 바이너리 서명 검증을 추가한다.
- Sparkle update archive 서명, appcast HTTPS, downgrade/rollback 정책을 정한다.
- CI 비밀정보와 서명 키 접근 범위를 문서화한다.
- `codesign`, `spctl`, notarization ticket, 깨끗한 Mac 설치·업데이트 smoke test를 릴리스 게이트로 둔다.

[Apple Developer ID 안내](https://developer.apple.com/support/developer-id/)는 Mac App Store 외부 배포에 Developer ID 서명과 공증을 사용하는 흐름을 설명한다.

### P2-01. 문서 역할을 분리하면 유지보수가 쉬워짐

현재 1,130행 문서에 기술 검토, 제품 범위, UX 명세, 아키텍처, 보안, 배포, 일정이 모두 들어 있다. 내용 자체는 유용하지만 구현 중 변경 이력을 관리하기 어렵다.

권장 분리:

- `docs/product-scope.md`: 사용자 목표, MVP, 제외 범위
- `docs/provider-contracts.md`: 인증, 수집 경로, 버전, fixture, 실패 상태
- `docs/architecture.md`: 도메인 모델, 책임 경계, 저장소
- `docs/security-privacy.md`: threat model, credential, 로그, export
- `docs/distribution.md`: 라이선스, 서명, 공증, Sparkle
- `dev-plan/implement_*.md`: 실제 Phase, 체크박스, 테스트 결과

### P2-02. 용어·경계값·시간 표현을 명시해야 함

- `공식 사용량`은 `Provider가 반환한 값`과 `공개 문서화된 API`를 구분한다.
- `LIVE`는 고정 1~2분이 아니라 source별 SLA와 refresh interval로 판정한다.
- reset 시각은 절대 시각, 상대 시각, 사용자 시간대를 함께 정의한다.
- 퍼센트는 API 입력 단위와 내부 단위를 명시한다.
- 접근성은 VoiceOver label 예시, 키보드 focus 순서, 최소 대비 기준을 테스트 항목으로 만든다.

## 4. Provider 연동 성숙도 권장 표기

| Provider | 현재 문서 근거 | 권장 계약 등급 | 출시 표기 |
|---|---|---|---|
| Claude Code | 공식 statusline에 5시간·7일 필드가 문서화됨 | Documented | Stable 후보 |
| Codex | CodexBar 구현 문서가 OAuth backend와 app-server RPC를 설명하지만 원문에 공식 OpenAI 계약 링크가 없음 | Observed / version-sensitive | Beta 후 승격 |
| Grok Build | xAI는 주간 사용량 정책을 공개하지만 구체 수집 경로는 CLI 버전과 계정 유형에 민감 | Experimental | Beta |
| GLM Coding Plan | 공식 usage-query plugin은 존재하나 원문이 가정한 직접 quota endpoint schema는 고정되어 있지 않음 | Experimental | Beta |

참고 자료:

- [Claude Code statusline](https://code.claude.com/docs/en/statusline)
- [CodexBar Codex provider 문서](https://github.com/steipete/CodexBar/blob/main/docs/codex.md)
- [CodexBar Grok provider 문서](https://github.com/steipete/CodexBar/blob/main/docs/grok.md)
- [xAI 사용량 안내](https://docs.x.ai/grok/faq)
- [Z.ai Usage Query Plugin](https://docs.z.ai/devpack/extension/usage-query-plugin)

## 5. 구현 시작 전 필수 결정 체크리스트

- [ ] TokenRemain 기준 태그·commit SHA를 확정한다.
- [ ] 원본 브랜드·에셋 삭제 목록을 확정한다.
- [ ] LICENSE·NOTICE·THIRD_PARTY_NOTICES 처리 방식을 확정한다.
- [ ] Provider별 수집 계약 등급과 최소 CLI 버전을 확정한다.
- [ ] 인증정보 읽기·refresh·write-back 정책을 확정한다.
- [ ] 네 Provider 실제 계정 fixture를 비밀정보 제거 후 확보한다.
- [ ] 부분 응답·누락·만료·지원 불가 fixture를 확보한다.
- [ ] quota source와 local usage source 인터페이스를 분리한다.
- [ ] 값별 provenance·freshness 모델을 확정한다.
- [ ] history retention·migration·reset 처리 규칙을 확정한다.
- [ ] 메뉴바 위험도와 알림 dedupe 규칙을 확정한다.
- [ ] 단계별 구현 계획과 자체 테스트 문서를 별도로 만든다.

## 6. 검증 기록

로컬 문서 구조 검사 결과:

- 총 1,130행
- heading 54개
- fenced code block marker 26개로 짝이 맞음
- heading level jump 없음
- 고유 외부 URL 13개
- 구현 진행용 Markdown checkbox 0개

Upstream 확인 결과:

- 문서에 적힌 `ClaudeOAuthUsageService.swift`, `CodexUsageService.swift`, `GrokUsageService.swift`, `ZAIUsageService.swift` 파일은 검토 기준 commit의 실제 tree에 존재한다.
- `UsageStore.swift`, `AdaptiveRefreshPolicy.swift`, `Views/Popover`, `Views/Dashboard` 구조도 존재한다.
- TokenRemain의 Apache-2.0 코드와 별도 에셋 라이선스 설명은 현재 upstream 내용과 일치한다.
- Claude statusline의 `five_hour`, `seven_day`, `used_percentage`, `resets_at` 설명은 현재 공식 문서와 일치한다.
- ccusage의 Claude·Codex·Grok Build 로컬 로그 지원 설명은 현재 문서와 일치한다.

## 7. 최종 권고

원문의 큰 방향은 유지해도 된다. 다만 다음 순서로 문서를 보완한 뒤 구현하는 것이 안전하다.

```text
upstream 기준선 고정
→ 라이선스·에셋 제거 매트릭스
→ Provider 계약/fixture 검증
→ provenance 중심 데이터 모델 수정
→ quota와 local history 책임 분리
→ 단계별 구현 계획 작성
→ 메뉴바 MVP
→ 상세 화면·추세
→ 보안·성능·배포 QA
```

가장 중요한 수정은 UI가 아니라 **각 숫자마다 출처, 수집 시각, 계약 안정성, 최신성, 부분 실패 상태를 함께 보존하는 모델**이다.
