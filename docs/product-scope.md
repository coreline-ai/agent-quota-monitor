# AIQuotaMonitor 제품 범위

작성일: `2026-08-16 KST`

## 제품 목표

QuotaBeacon은 Codex, Claude Code, Grok Build, Z.ai GLM Coding Plan의 quota와 로컬 토큰 사용량을 한곳에서 확인하는 완전 신규 macOS 메뉴바 앱이다. Xcode module·scheme·target의 내부 이름은 `AIQuotaMonitor`로 유지한다.

외부 앱은 사용자가 겪는 문제와 Provider 제약을 이해하는 참고자료로만 사용한다. 코드, 프로젝트 구조, 화면, 에셋은 가져오지 않는다.

## 1차 사용자

- 여러 AI coding subscription을 동시에 사용하는 macOS 개발자
- quota reset과 현재 위험 상태를 빠르게 확인하려는 사용자
- 구독 quota와 로컬 token/cost 추정을 구분해 보고 싶은 사용자

## MVP

- macOS status item과 popover
- Claude Code, Codex, Grok Build, Z.ai GLM quota 상태
- Z.ai 공식 Usage Query plugin 기반 5시간 token·월간 MCP quota 연결(Beta)
- quota window별 사용률, reset, 출처, 최신성
- 연결 필요, 인증 만료, 지원 불가, stale, 부분 성공 상태
- 마지막 정상 값 캐시
- 수동·자동 refresh
- 임계치 알림
- 개요, 한도, 추세, 데이터 소스, 설정 dashboard
- 로컬 token과 API 정가 예상 비용
- 한국어 기본 UI와 영어 fallback
- Developer ID 직접 배포

## MVP 제외

- 기존 앱 또는 저장소의 포크
- 외부 source, fixture, UI, asset 재사용
- Mac App Store
- 모바일·Watch·iCloud
- 자체 backend와 telemetry
- 브라우저 cookie/WebView 수집
- 네 Provider 외 확장
- credential 자동 refresh/write-back
- 팀 중앙 관리

## 제품 신뢰 원칙

- 값이 없으면 퍼센트를 표시하지 않는다.
- `nil`, 실제 0%, 실제 100%를 구분한다.
- quota와 local token/cost를 서로 환산하지 않는다.
- cache를 live로 표시하지 않는다.
- 하나의 Provider 실패가 나머지를 막지 않는다.
- 실제 모델 호출로 quota를 확인하지 않는다.
- credential과 원본 payload를 로그에 남기지 않는다.

## 신규 시각 방향

### 방향

- 디자인 언어: `Signal Ledger`
- 메뉴 막대 세부 패턴: `Beacon Ledger`
- 이미지: 사용량을 장식적인 캐릭터가 아니라 조용한 계측 신호로 표현
- 형태: 긴 세로 카드 모음보다 얇은 signal row와 넓은 여백 사용
- 강조: Provider 브랜드색보다 상태·시간·출처의 정보 위계 우선
- 아이콘: 신규 단색 메뉴바 glyph와 신규 macOS app icon 사용
- 차트: quota window와 local token을 별도 surface로 분리

### 추세 그래프: Reset Bands

- 기간 선택은 `24시간 / 7일 / 30일`이며 선택 기간과 History filter·X축 domain을 동일하게 유지한다.
- 기본 화면은 가장 긴급한 연결 Provider 하나를 선택하고, 전체 모드는 Provider별 small multiples로 분리한다.
- Provider 안에서도 5시간·7일·주간 공용 등 quota window를 독립 series로 유지한다.
- 실제 관측값은 직선으로만 연결하며 reset instance, stale 전환, 큰 관측 gap 전후를 이어 그리지 않는다.
- LIVE는 실선, 캐시는 점선과 낮은 불투명도로 표시하고 25% 주의·10% 위험 기준선을 텍스트와 함께 제공한다.
- reset 시각은 얇은 band와 경계선으로 표시하는 제품 고유 패턴 `Reset Bands`를 사용한다.
- 실제 수집 구간이 선택 기간보다 짧으면 그래프를 임의 확대하지 않고 수집 시간·LIVE/전체 표본 수를 명시한다.
- 로컬 token source가 없을 때 가짜 그래프를 만들지 않고 데이터 소스 연결 행동을 제공한다.

### 사용자화 범위

- 화면 밀도: `균형 / 압축`
- quota 표기: `잔여량 / 사용량`을 선택하되 위험 색상은 항상 실제 잔여량 기준
- reset 표기: `남은 시간 / 절대 시각`
- 테마 preset: `시스템 / 미드나이트 / 그래파이트`
- 상세 방식: Provider 행 아래 `상세 펼침 / 요약만`
- Provider 노출: Claude, Codex, Grok, GLM을 메뉴 막대에서 개별 표시/숨김
- 설정은 수집 pipeline이나 credential 승인 상태를 변경하지 않고 화면 표현에만 적용

### 디자인 토큰 원칙

- 색상: 시스템 배경과 중성 회색을 기본으로 하고 indigo는 선택·행동 강조에만 사용한다.
- 상태색: 정상·주의·위험·stale은 Provider 브랜드색과 분리하며 색상만으로 의미를 전달하지 않는다.
- 타이포그래피: 시스템 서체를 사용하고 제목에만 rounded 계열, 수치에는 정렬 가능한 숫자 스타일을 사용한다.
- 간격: 4pt 기준으로 `8/12/16/24/32` 단계만 사용하며 signal row는 카드보다 조밀하게 유지한다.
- 상태 badge: 아이콘·짧은 레이블·색상을 함께 사용하고 `live/stale/partial/error/unsupported`를 명시한다.
- 접근성: 텍스트 대비, Increase Contrast, Reduce Motion, VoiceOver label을 시각 효과보다 우선한다.

### 신규 아이콘 brief

- 메뉴바 glyph는 quota의 시간 창과 신호 흐름을 결합한 단색 template image로 제작했다.
- 16/18/20pt에서 식별 가능해야 하고 Light/Dark 메뉴바에서 동일한 silhouette를 유지한다.
- 앱 아이콘은 겹친 두 개의 시간 창과 한 줄의 계측 신호를 사용하되 Provider logo나 참고 앱 캐릭터를 사용하지 않는다.
- 앱 아이콘과 메뉴바 glyph는 `Scripts/generate_brand_assets.py`에서 독립적으로 생성하며 외부 에셋을 입력으로 사용하지 않는다.
- SF Symbol `chart.line.uptrend.xyaxis`는 asset load 실패 시에만 사용하는 fallback이다.

### 금지

- 참고 앱의 2열 카드 배치 복제
- 참고 앱의 대표 색상·로봇·마스코트 사용
- 참고 앱 screenshot을 tracing하거나 visual input으로 사용
- Provider logo를 출처·상표 검토 없이 사용

## 제품 결정

| 항목 | 임시값 |
|---|---|
| 내부 module·scheme·target | `AIQuotaMonitor` |
| 최종 표시 이름 | `QuotaBeacon` |
| Bundle ID | `com.hwanchoi.quotabeacon` |
| 최소 OS | macOS 14 |
| 배포 | Developer ID 직접 배포 |
| 디자인 언어 | `Signal Ledger` |
| 메뉴 막대 GUI | `Beacon Ledger` |
| 개발 서명 | Xcode `Sign to Run Locally` |
| 배포 Team ID | Phase 7에서 사용자 인증서의 실제 값을 CI secret으로 주입 |

Apple Team ID는 인증서에서 얻어야 하므로 임의 값을 저장소에 기록하지 않는다. Team ID가 없어도 Greenfield 구현과 로컬 검증은 계속하며 실제 Developer ID 서명·공증 직전에만 주입한다.

`QuotaBeacon`은 공개 웹·App Store 검색의 1차 충돌 검사를 거친 제품명이다. 이는 법률상 상표 clearance를 대신하지 않으므로 상용 배포 전 별도 상표 검색을 수행한다.
