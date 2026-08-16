# macOS AI 사용량 모니터 앱 전문가 검토 제안

> 대상 Provider: **Codex / Claude Code / Grok Build / Z.ai GLM Coding Plan**  
> 목표: macOS 상단 메뉴 막대에서 잔여 사용량을 빠르게 확인하고, 상세 화면에서는 한도·추세·데이터 출처·오류 상태까지 확인할 수 있는 네이티브 앱

---

## 1. 검토 결론

첨부한 화면은 단순한 참고 디자인이 아니라, 화면에 표시된 이름 그대로 **TokenRemain이라는 실제 오픈소스 macOS 앱**입니다.

공개 저장소에는 이미 다음 기능이 구현되어 있습니다.

- macOS 메뉴 막대 아이콘과 클릭 팝오버
- 별도의 전체 대시보드 창
- Claude Code, Codex, Grok, Z.ai GLM Coding Plan 사용량
- 5시간·7일·주간 한도와 재설정 카운트다운
- 사용 속도 분석과 소진 예상
- `ccusage` 기반 로컬 토큰·예상 비용·일별 추세
- Keychain 비밀정보 저장
- 자동 새로고침
- 시작 프로그램 등록
- Sparkle 자동 업데이트

Swift·SwiftUI·AppKit 기반의 macOS 14+ 네이티브 앱이며, 첨부 이미지와 거의 동일한 메뉴바·한도·추세 화면까지 소스에 포함되어 있습니다.

따라서 **새로 만드는 것보다 TokenRemain을 포크한 뒤 Codex·Claude·Grok·GLM 전용으로 줄이고 완전히 리브랜딩하는 방식이 가장 합리적**입니다.

참고:

- TokenRemain: <https://github.com/Carstin520/token-remain>

---

## 2. 라이선스에서 가장 중요한 부분

TokenRemain의 **소스 코드와 소스 문서는 Apache-2.0**이지만, 다음 항목은 오픈소스 사용 범위에서 제외되어 있습니다.

- TokenRemain 이름
- 로고와 앱 아이콘
- 로봇·마스코트
- 스크린샷과 제품 목업
- `design/` 및 원본 시각 디자인 에셋
- 일부 리소스 폴더의 1차 제작 아트워크

라이선스 문구상 파생 제품을 배포하거나 상업적으로 사용하려면 이러한 에셋을 전부 교체하거나 별도 허락을 받아야 합니다.

따라서 다음 원칙이 안전합니다.

> **기능 코드와 화면 구조는 활용하되, 이름·로고·캐릭터·색상 체계·대표 아이콘은 새로 제작한다.**

Provider 로고도 각각 제3자의 상표이므로 브랜드 가이드에 맞게 사용하거나, 초기 버전에서는 텍스트와 단색 심볼로 처리하는 것이 좋습니다.

---

## 3. 가장 적합한 구현 전략

### 권장안: TokenRemain 4-Provider Slim Fork

기존 프로젝트에서 다음만 남깁니다.

| 영역 | MVP 적용 |
|---|---|
| Claude Code | 유지 |
| OpenAI Codex | 유지 |
| Grok Build | 유지 |
| Z.ai GLM Coding Plan | 유지 |
| 메뉴바 팝오버 | 유지 후 재디자인 |
| 전체 대시보드 | 유지 후 재디자인 |
| 로컬 토큰·비용 추세 | 유지 |
| 알림 | 유지 |
| 자동 새로고침 | 유지 |
| AI Feed | 제거 |
| iPhone·Watch·iCloud 동기화 | 제거 |
| 기기 메뉴 | 제거 |
| Cursor·Kimi·MiniMax 등 기타 Provider | 제거 |
| Cloudflare Worker 백엔드 | 제거 |
| 로봇 애니메이션 | 제거 및 신규 아이콘으로 교체 |

TokenRemain 소스는 이미 다음과 같이 분리되어 있습니다.

- `App`
- `Services`
- `Stores`
- `Views`
- `Models`

Provider별 서비스도 다음처럼 독립되어 있습니다.

- `ClaudeOAuthUsageService.swift`
- `CodexUsageService.swift`
- `GrokUsageService.swift`
- `ZAIUsageService.swift`

또한 `UsageStore`, `AdaptiveRefreshPolicy`, `Views/Popover`, `Views/Dashboard`도 별도 구조여서 4개 Provider만 남기는 작업이 비교적 명확합니다.

---

## 4. 추가로 참고할 오픈소스

### 4.1 CodexBar

CodexBar는 Provider마다 다음 구조를 두는 방식이 잘 잡혀 있습니다.

- Descriptor
- 여러 Fetch Strategy
- CLI 조회
- OAuth 조회
- 로컬 파일 분석
- 브라우저 세션 fallback
- 공통 Keychain
- HTTP Client
- PTY 및 프로세스 실행

TokenRemain의 수집기가 특정 환경에서 실패할 때 CodexBar의 fallback 방식과 테스트 구조를 참고하는 것이 좋습니다.

- 저장소: <https://github.com/steipete/CodexBar>

### 4.2 ClaudeBar

ClaudeBar는 Claude·Codex·Grok·Z.ai를 포함한 네이티브 메뉴바 앱이며, `QuotaMonitor`를 단일 상태 소스로 사용하는 비교적 단순한 계층형 구조입니다.

TokenRemain 전체 구조가 너무 크다고 판단될 경우 두 번째 기반 후보로 검토할 수 있습니다.

- 저장소: <https://github.com/tddworks/ClaudeBar>

### 4.3 ccusage

ccusage는 Claude Code·Codex·Grok Build 등 로컬 CLI 로그에서 다음 데이터를 계산하는 용도입니다.

- 일별 토큰
- 주별 토큰
- 월별 토큰
- 입력 토큰
- 출력 토큰
- 캐시 토큰
- API 정가 기준 예상 비용

주의할 점은 ccusage가 **구독 잔여 한도 수집기라기보다 로컬 사용 기록 분석기**라는 점입니다.

- 문서: <https://ccusage.com/guide/all-reports>

---

## 5. 사용량 수집 설계의 핵심 원칙

가장 중요한 원칙은 아래 두 데이터를 절대로 한 숫자로 합치지 않는 것입니다.

### 5.1 Provider가 보고한 실제 구독 한도

- 5시간 사용률
- 7일 또는 주간 사용률
- 잔여 비율
- 다음 재설정 시각
- 크레딧 또는 요청 한도

### 5.2 로컬 로그에서 계산한 사용량

- 입력 토큰
- 출력 토큰
- 캐시 토큰
- 날짜별 사용량
- 프로젝트별 사용량
- 세션별 사용량
- API 정가 기준 예상 비용

로컬에서 1억 토큰을 사용했다고 해서 구독 한도의 정확한 퍼센트를 역산할 수 있는 것은 아닙니다.

반대로 구독 한도 50%를 소비했다고 해서 정확한 토큰 수를 알 수 있는 것도 아닙니다.

따라서 화면에 다음과 같이 출처를 명시해야 합니다.

- `공식 사용량`
- `CLI 조회`
- `로컬 로그`
- `API 정가 추정`
- `오래된 데이터`
- `연결 필요`

---

## 6. Provider별 사용량 확인 방식

### 6.1 Claude Code

Claude Code 공식 상태 표시줄 데이터에는 다음 rate limit 정보가 포함될 수 있습니다.

- `rate_limits.five_hour`
- `rate_limits.seven_day`
- `used_percentage`
- `resets_at`

다만 Claude.ai Pro·Max 구독자의 세션에서 첫 응답 이후 제공되는 경우가 있으므로, 값이 없을 때는 0%나 100%로 처리하지 말고 `아직 수집되지 않음`으로 표시해야 합니다.

권장 우선순위:

1. Claude 데스크톱 앱 또는 Claude Code가 보유한 기존 읽기 전용 인증정보
2. 공식 상태 표시줄의 `rate_limits`
3. Claude CLI 상태 조회
4. 로컬 세션 로그는 추세와 비용 계산에만 사용

참고:

- Claude Code Statusline: <https://docs.anthropic.com/en/docs/claude-code/statusline>

---

### 6.2 Codex

Codex는 기존 `~/.codex/auth.json` 인증정보를 읽어 사용량을 조회하거나, 로컬 `codex app-server`를 실행한 뒤 JSON-RPC를 이용할 수 있습니다.

주요 메서드 예시:

- `account/read`
- `account/rateLimits/read`

이를 통해 다음 데이터를 얻을 수 있습니다.

- 기본 사용 창
- 보조 사용 창
- 재설정 시각
- 크레딧
- 계정 상태

프로세스가 응답하지 않을 수 있으므로 각 요청에 timeout을 적용하고 자식 프로세스를 확실히 종료해야 합니다.

권장 우선순위:

1. Codex 앱·CLI의 기존 OAuth 인증정보
2. `codex app-server` JSON-RPC
3. 읽기 전용 사용량 엔드포인트
4. `~/.codex/sessions`는 토큰·추세·예상 비용에만 사용

Codex 구독 사용량과 OpenAI API 과금 사용량도 서로 다른 데이터이므로 화면에서 분리해야 합니다.

참고:

- CodexBar Codex 문서: <https://github.com/steipete/CodexBar/blob/main/docs/codex.md>

---

### 6.3 Grok

MVP 범위는 일반 Grok 웹 채팅 전체가 아니라 **Grok Build 코딩 사용량**으로 명확히 잡는 것이 좋습니다.

Grok Build CLI의 `~/.grok/auth.json`에 저장된 로컬 로그인 인증정보를 이용하여 CLI billing API를 조회할 수 있습니다.

다만 다음 문제가 발생할 수 있습니다.

- Grok CLI 버전에 따라 일부 billing JSON-RPC 메서드가 없음
- Business·Team 계정은 개인 계정용 사용량 구조와 다름
- 계정은 인식되지만 사용량을 얻지 못할 수 있음
- 인증은 정상이나 quota endpoint가 지원되지 않을 수 있음

따라서 Grok Provider는 초기부터 `Beta`로 표시하고, 실패 시 계정은 인식하되 사용량은 다음처럼 보여주는 것이 안전합니다.

- `지원되지 않는 계정 유형`
- `현재 CLI 버전에서 사용량 조회 미지원`
- `로그인은 확인되었지만 quota를 불러오지 못함`

권장 우선순위:

1. `grok login`으로 생성된 로컬 OAuth
2. Grok CLI billing API
3. CLI JSON-RPC가 지원되는 버전이면 사용
4. 웹 세션·쿠키 방식은 기본 비활성화
5. `~/.grok/sessions`는 토큰 추세에만 사용

참고:

- CodexBar Grok 문서: <https://github.com/steipete/CodexBar/blob/main/docs/grok.md>

---

### 6.4 GLM

GLM은 **Z.ai GLM Coding Plan**을 기준으로 구현합니다.

공식 Coding Plan은 다음과 같은 한도를 제공할 수 있습니다.

- 5시간 한도
- 주간 한도
- 크레딧 한도
- 재설정 시각

앱에서는 사용자가 입력한 Coding Plan 전용 키를 macOS Keychain에 저장하고, quota 조회 엔드포인트만 호출하는 방식이 가장 단순합니다.

GLM Team Plan까지 지원하려면 키 외에 조직과 프로젝트 식별자가 추가로 필요할 수 있으므로 Team은 2차 범위로 두는 편이 좋습니다.

최근 응답은 토큰 한도뿐 아니라 `CREDIT_LIMIT` 형태로 내려올 수 있습니다.

알 수 없는 limit type을 무시하면 실제 사용 중인데도 `100% 남음`으로 표시될 수 있으므로, fixture 기반 파서 테스트가 반드시 필요합니다.

참고:

- Z.ai Usage Query Plugin: <https://docs.z.ai/devpack/extension/usage-query-plugin>
- 관련 CodexBar 이슈: <https://github.com/steipete/CodexBar/issues/2724>

---

## 7. 메뉴바 UI 제안

### 7.1 상단 아이콘

기본값은 Provider별 아이콘 4개가 아니라 **하나의 통합 아이콘**을 권장합니다.

이 방식의 장점:

- 메뉴 막대 공간을 적게 사용
- 가장 위험한 상태를 한눈에 확인
- Provider 추가 시 아이콘 수가 늘어나지 않음
- 경고와 오류 상태를 통합 표현 가능

표시 방식 후보:

- 아이콘만 표시하고 경고 상태일 때 배지 추가
- `아이콘 + 가장 부족한 잔여율`
- `아이콘 + 사용자가 선택한 Provider 잔여율`

예시:

```text
◈ 51%
```

이 숫자는 네 Provider 중 가장 낮은 잔여 한도를 표시합니다.

설정에서 다음 선택지를 제공합니다.

- Claude만 표시
- Codex만 표시
- Grok만 표시
- GLM만 표시
- 전체 중 가장 낮은 값 표시
- 퍼센트 숨김
- 아이콘만 표시

상태는 색상뿐 아니라 심볼로도 구분합니다.

| 상태 | 표시 |
|---|---|
| 정상 | 기본 아이콘 |
| 주의 | 작은 점 또는 `!` |
| 위험 | 채워진 경고 배지 |
| 소진 | 금지 또는 빈 게이지 |
| 연결 오류 | 끊어진 링크 |
| 오래된 데이터 | 시계 심볼 |

---

### 7.2 클릭 팝오버

권장 크기:

- 가로: 390~420px
- 세로: 최대 540px

예시:

```text
AI 사용량                         24초 전

Claude       51% 남음
5시간  █████░░░░░   2시간 06분 후
7일    ███████░░░   월요일 09:00

Codex        73% 남음
5시간  ███████░░░   3시간 41분 후
7일    █████████░   목요일 20:43

Grok         연결 필요
Grok Build에 로그인하세요

GLM          88% 남음
5시간  █████████░   4시간 12분 후
7일    █████████░   5일 후

새로고침       상세 보기       설정
```

각 Provider 행에 반드시 포함할 정보:

- Provider 이름
- 가장 촉박한 잔여율
- 5시간·7일 또는 해당 Provider의 실제 한도
- 재설정까지 남은 시간
- 데이터 출처
- 마지막 성공 시각
- 오류 또는 인증 상태

권장 동작:

- 왼쪽 클릭: 팝오버 열기
- 오른쪽 클릭: 컨텍스트 메뉴
  - 새로고침
  - 상세 보기
  - 설정
  - 시작 시 실행
  - 종료

구현은 SwiftUI `MenuBarExtra`만으로 묶기보다 `NSStatusItem + NSPopover`로 하는 편이 다음 기능을 구현하기 쉽습니다.

- 동적 메뉴바 아이콘
- 오른쪽 클릭
- 별도 상세 창
- 팝오버 위치 제어
- Dock 아이콘 표시 전환
- 다중 디스플레이 대응

---

## 8. 상세 화면 구성

MVP에서는 첨부 화면의 사이드바를 다음 5개로 줄이는 것이 좋습니다.

1. 개요
2. 한도
3. 추세
4. 데이터 소스
5. 설정

`기기` 메뉴는 iCloud 동기화를 실제 구현할 때만 추가합니다.

---

### 8.1 개요

표시 항목:

- 네 Provider의 현재 상태
- 가장 먼저 소진될 가능성이 높은 Provider
- 가장 가까운 재설정 시각
- 오늘의 로컬 토큰 사용량
- 경고 또는 인증 오류
- 마지막 전체 동기화 시각

추천 요약 카드:

- `가장 낮은 잔여량`
- `가장 가까운 재설정`
- `오늘 사용한 토큰`
- `오류가 있는 소스`

---

### 8.2 한도

첨부 화면처럼 2열 Provider 카드를 유지하되 다음을 개선합니다.

- 카드 내부 세로 스크롤 제거
- 사용 불가 상태에서 `100% 남음` 표시 금지
- 로그인 경고 배너를 반복해서 크게 표시하지 않기
- `남음`과 `사용` 표현을 화면 전체에서 통일
- 카드 하단에 `출처 · 마지막 갱신` 표시
- 오류 상태에서도 마지막 정상 값을 유지

표시 예:

```text
CLI 조회 · 18초 전
OAuth · 2분 전
로컬 추정 · 오늘 09:15
이전 정상 값 · 27분 전
```

---

### 8.3 추세

서로 다른 단위를 하나의 그래프에 혼합하지 않습니다.

#### 그래프 A: 로컬 토큰 사용량

- 일별 Claude·Codex·Grok·GLM 토큰
- 7일·14일·30일
- Provider별 stacked bar
- Tokens / 예상 비용 전환
- 입력·출력·캐시 토큰 필터

#### 그래프 B: 한도 소비 속도

- 5시간 또는 주간 한도 사용률
- 시간에 따른 퍼센트 변화
- 현재 속도로 재설정 전까지 버틸 수 있는지 표시
- 현재 속도 기반 예상 소진 시각
- 최근 소비 속도 급증 경고

비용은 반드시 다음과 같이 표기합니다.

```text
API 정가 기준 예상 비용
실제 구독 결제액이 아닙니다
```

---

### 8.4 데이터 소스

이 화면이 제품 신뢰도를 결정합니다.

예시:

```text
Claude
상태        정상
수집 방식   Claude OAuth
한도 출처   공식 사용량
로컬 기록   ~/.claude/...
마지막 성공 24초 전

Grok
상태        사용량 수집 실패
수집 방식   Grok Build CLI
원인        Team 계정 사용량 미지원
권장 조치   grok login 확인
```

Provider별 표시 항목:

- 연결 상태
- 인증 방식
- quota 수집 방식
- 로컬 로그 경로
- 마지막 성공 시각
- 마지막 오류 시각
- 마지막 오류 원인
- fallback 사용 여부
- 현재 표시 값이 캐시인지 실시간인지
- 수동 재연결 버튼

---

## 9. 첨부 디자인에 대한 전문가 개선 의견

### 9.1 카드 안쪽 스크롤바

한도 카드마다 별도 세로 스크롤이 있어 대시보드와 카드가 동시에 스크롤됩니다.

이는 사용성이 좋지 않습니다.

개선안:

- 카드는 내용에 따라 높이가 늘어나게 구성
- 전체 화면만 스크롤
- 상세 오류는 disclosure 형태로 펼치기
- 카드 높이 상한을 두지 않기
- 동일 행의 카드 높이는 레이아웃 수준에서 정렬

---

### 9.2 연결되지 않은 Provider의 `100% 남음`

수집하지 못한 값과 실제 100%를 구분해야 합니다.

| 상태 | 권장 표시 |
|---|---|
| 실제 미사용 | `100% 남음` |
| 인증 없음 | `연결 필요` |
| 응답 실패 | `일시적으로 확인 불가` |
| 오래된 값 | `이전 값 · 18분 전` |
| 지원되지 않는 계정 | `현재 계정 유형 미지원` |
| 데이터 없음 | `아직 수집된 데이터 없음` |

---

### 9.3 로그인 경고 반복

각 카드 상단에 동일한 로그인 경고를 크게 표시하기보다 Provider 이름 옆에 작은 상태 배지를 두고, 필요할 때 펼쳐보게 하는 편이 좋습니다.

예시:

```text
Claude   [연결 필요]
```

또는:

```text
Claude   ⚠
```

상세 원인은 카드 하단 또는 데이터 소스 화면에서 확인하도록 구성합니다.

---

### 9.4 차트 축

하루에 사용량이 없는 날이 많으면 현재처럼 1B까지 고정된 축은 데이터가 지나치게 작아 보입니다.

개선안:

- 최대값 기준 동적 Y축
- 기간 변경 시 급격한 축 변화 방지
- 95퍼센타일 기준 상한선 옵션
- 이상치가 있을 경우 별도 마커 표시
- 단위 자동 변환
  - K
  - M
  - B

---

### 9.5 `LIVE` 표현

최근 1~2분 이내 공식 데이터를 성공적으로 수집한 경우에만 `LIVE`를 표시합니다.

권장 상태:

- `LIVE`
- `30초 전`
- `캐시`
- `오래됨`
- `연결 끊김`
- `동기화 중`

로컬 캐시나 20분 전 데이터에는 `LIVE`를 사용하지 않는 것이 정확합니다.

---

### 9.6 사이드바 너비

첨부 화면의 사이드바는 다소 넓습니다.

전체 창이 1200px 전후라면 다음 정도가 적당합니다.

- 기본 사이드바: 210~224px
- 축소 가능 최소 폭: 190px
- Provider 카드 영역 우선 확보
- 화면이 좁아지면 자동 1열 전환

---

### 9.7 접근성

Claude의 코랄, Codex의 파랑처럼 색상으로만 Provider를 구분하지 말아야 합니다.

함께 사용할 요소:

- 아이콘
- Provider 이름
- 선 패턴
- 상태 텍스트
- VoiceOver Label
- 명도 대비
- 경고 심볼

macOS 접근성 옵션도 반영해야 합니다.

- Reduce Motion
- Increase Contrast
- Differentiate Without Color
- VoiceOver
- Dynamic Type에 준하는 텍스트 크기 대응
- 키보드 탐색

---

## 10. 권장 기술 구조

```text
AIQuotaMonitor
├── App
│   ├── StatusBarController
│   ├── PopoverController
│   └── DashboardWindowController
├── Domain
│   ├── ProviderID
│   ├── UsageSnapshot
│   ├── QuotaWindow
│   ├── LocalTokenUsage
│   └── DataSourceHealth
├── Providers
│   ├── Claude
│   ├── Codex
│   ├── Grok
│   └── ZAI
├── Services
│   ├── HTTPClient
│   ├── ProcessRunner
│   ├── CredentialReader
│   ├── KeychainStore
│   ├── LocalLogScanner
│   └── NotificationService
├── Stores
│   ├── UsageStore
│   ├── HistoryStore
│   ├── PreferencesStore
│   └── RefreshCoordinator
└── Views
    ├── Popover
    ├── Overview
    ├── Limits
    ├── Trends
    ├── DataSources
    └── Settings
```

Provider 공통 인터페이스 예시:

```swift
protocol UsageProviderAdapter {
    var id: ProviderID { get }

    func checkAvailability() async -> ProviderAvailability
    func fetchQuota() async throws -> UsageSnapshot
    func fetchLocalHistory(
        range: DateInterval
    ) async throws -> [LocalUsageSample]
}
```

각 Provider는 하나의 수집법이 아니라 우선순위가 있는 전략 목록을 갖게 합니다.

```text
Codex
OAuth → app-server RPC → 마지막 정상 캐시

Claude
OAuth/statusline → CLI → 마지막 정상 캐시

Grok
CLI billing API → 지원되는 RPC → 마지막 정상 캐시

GLM
Keychain API key → 공식 quota endpoint → 마지막 정상 캐시
```

브라우저 쿠키나 숨겨진 WebView 방식은 기본 비활성화하는 것이 좋습니다.

CodexBar도 대시보드 전용 부가 정보 수집을 위한 숨겨진 WebView를 선택 기능으로 두고 있으며, 배터리와 네트워크 사용이 늘 수 있음을 명시하고 있습니다.

---

## 11. 데이터 모델 제안

### 11.1 공통 quota 모델

```swift
struct UsageSnapshot: Sendable, Codable {
    let provider: ProviderID
    let accountLabel: String?
    let fetchedAt: Date
    let source: UsageSource
    let windows: [QuotaWindow]
    let credits: CreditBalance?
    let health: DataSourceHealth
}

struct QuotaWindow: Sendable, Codable, Identifiable {
    let id: String
    let kind: QuotaWindowKind
    let usedRatio: Double?
    let remainingRatio: Double?
    let resetsAt: Date?
    let label: String
}
```

### 11.2 데이터 건강 상태

```swift
enum DataFreshness: String, Codable {
    case live
    case fresh
    case cached
    case stale
    case unavailable
}

struct DataSourceHealth: Sendable, Codable {
    let freshness: DataFreshness
    let lastSuccessAt: Date?
    let lastFailureAt: Date?
    let errorCode: String?
    let userMessage: String?
}
```

중요 원칙:

- `nil`은 0%가 아님
- 수집 실패는 실제 소진과 구분
- `remainingRatio`를 계산할 수 없으면 빈 값으로 유지
- 마지막 정상 스냅샷을 별도 보존
- 원본 응답 전체를 로그에 저장하지 않음

---

## 12. 새로고침과 성능

권장 정책:

| 상황 | 갱신 주기 |
|---|---:|
| 팝오버가 열려 있음 | 30~60초 |
| 최근 Claude/Codex 세션이 활동 중 | 1분 |
| 일반 백그라운드 | 5분 |
| 장시간 미사용 | 10~15분 |
| 수집 실패 반복 | 5분 → 15분 → 60분 |
| 사용자 수동 새로고침 | 즉시 |

구현 원칙:

- Provider마다 동시에 한 번의 요청만 수행
- CLI 프로세스에 8~12초 timeout
- 자식 프로세스 강제 종료 보장
- 실패해도 마지막 정상 값을 삭제하지 않음
- 오래된 값에는 `오래됨` 배지 표시
- sleep 복귀 후 중복 갱신 방지
- 화면이 숨겨지면 차트 애니메이션 중지
- Provider 하나의 실패가 다른 Provider를 막지 않음
- 네트워크 불가 상태에서 불필요한 재시도 방지

TokenRemain도 숨겨진 대시보드의 애니메이션이 계속 실행되면서 CPU와 전력 소비가 증가한 사례를 측정했고, 화면이 보이지 않을 때 애니메이션을 중지하고 세션 활동에 따라 갱신 주기를 조절하는 방식으로 개선했습니다.

참고:

- TokenRemain 성능 문서: <https://github.com/Carstin520/token-remain/blob/main/docs/performance-v1.2.3.md>

권장 성능 목표:

- 유휴 CPU 평균 0.5% 이하
- 메모리 100MB 전후
- 숨겨진 창의 애니메이션 완전 중지
- 중복 CLI 프로세스 없음
- sleep 복귀 후 한 번만 갱신
- Provider 실패가 다른 Provider 갱신을 막지 않음
- 앱 종료 시 모든 자식 프로세스 종료
- 네트워크 요청 취소 지원

---

## 13. 알림 정책 제안

사용량 앱은 알림이 지나치게 많으면 바로 비활성화됩니다.

기본 알림은 다음 정도로 제한하는 것이 좋습니다.

- 잔여량 25% 이하
- 잔여량 10% 이하
- 예상 소진이 재설정 이전으로 계산됨
- 인증 만료
- 3회 이상 연속 동기화 실패
- 한도 재설정 완료

Provider별 알림 설정:

- Claude 알림 활성화
- Codex 알림 활성화
- Grok 알림 활성화
- GLM 알림 활성화
- 25% 경고
- 10% 경고
- 완전 소진 경고
- 재설정 완료 알림
- 야간 알림 끄기

동일 상태에 대한 반복 알림은 방지해야 합니다.

---

## 14. 보안 원칙

- 기존 Claude·Codex·Grok 인증정보는 읽기 전용
- refresh token을 앱이 임의 갱신하거나 덮어쓰지 않음
- GLM 수동 키는 Keychain에만 저장
- 로그에 이메일·토큰·쿠키·응답 원문 기록 금지
- 로컬 파일 경로는 allowlist 방식
- Provider 사용량은 해당 Provider에 직접 요청
- 자체 서버에는 사용량과 인증정보를 전송하지 않음
- 사용량 조회를 위해 모델을 실제 호출하지 않음
- 오류 메시지는 비밀정보 제거 후 저장
- 디버그 로그 내보내기 전 자동 마스킹
- 인증 파일 권한과 소유자 검사
- 심볼릭 링크를 통한 임의 파일 접근 방지

권장 Keychain 분류:

- 사용자가 직접 입력한 GLM 키
- 앱이 생성한 내부 비밀값
- OAuth 인증정보 참조 메타데이터

기존 CLI 인증정보는 가능하면 복사해서 Keychain에 재저장하지 않고 읽기 전용으로 참조합니다.

---

## 15. 배포 전략

### Mac App Store보다 직접 배포 권장

이 앱은 다음 동작이 필요합니다.

- 다른 앱의 설정 파일 읽기
- CLI 인증정보 읽기
- 로컬 세션 로그 읽기
- 자식 프로세스 실행
- 사용자 홈 디렉터리 특정 경로 접근
- Keychain 접근
- CLI 상태 조회

macOS Sandbox에서는 이러한 경로가 제한되고, 자식 프로세스 역시 부모의 Sandbox 권한을 상속합니다.

따라서 초기 배포는 다음 구성이 적합합니다.

- Developer ID 서명
- Apple Notarization
- DMG 또는 ZIP
- Homebrew Cask
- Sparkle 자동 업데이트
- 메뉴바 전용 모드
- 필요할 때만 Dock 아이콘 표시

참고:

- Apple Sandbox 파일 접근 문서:  
  <https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox>
- TokenRemain Sandbox 검토 문서:  
  <https://github.com/Carstin520/token-remain/blob/main/docs/mac-app-store-sandbox-compatibility.md>

Dock에 나타나지 않는 메뉴바 앱은 다음 방식으로 구현할 수 있습니다.

- `LSUIElement`
- `NSApplication.ActivationPolicy.accessory`

참고:

- Apple LSUIElement 문서:  
  <https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement>

---

## 16. 개발 순서와 예상 기간

### 0단계 — 실제 계정 수집 검증: 1~2일

UI부터 만들지 않고 사용 중인 네 계정에서 먼저 확인합니다.

검증 항목:

- Claude 5시간·7일 데이터
- Codex 5시간·7일 데이터
- Grok Build 사용량
- GLM Coding Plan 5시간·주간 데이터
- 재설정 timestamp
- 인증 만료 상태
- 로그아웃 상태
- 지원되지 않는 계정 유형
- 요청이 토큰을 소비하지 않는지 확인
- CLI 버전별 응답 차이

각 응답은 비밀정보를 제거한 fixture로 저장합니다.

---

### 1단계 — Fork와 범위 축소: 2~4일

- TokenRemain 포크
- AI Feed 제거
- Cloudflare 관련 코드 제거
- iCloud·기기·Watch 관련 코드 제거
- Provider를 네 개로 축소
- 패키지명 변경
- Bundle ID 변경
- 원본 브랜드와 에셋 완전 제거
- Apache-2.0 고지 유지
- 신규 앱 이름 결정
- 신규 메뉴바 아이콘 제작
- 신규 앱 아이콘 제작

---

### 2단계 — 메뉴바 MVP: 3~5일

- 통합 메뉴바 상태
- 4개 Provider 팝오버
- 수동 새로고침
- 자동 새로고침
- 마지막 성공 캐시
- 연결 필요 상태
- 오래됨 상태
- 오류 상태
- 임계치 알림
- 시작 시 자동 실행
- 메뉴바 퍼센트 표시 설정

---

### 3단계 — 상세 화면: 3~5일

- 개요
- 한도
- 추세
- 데이터 소스
- 설정
- 한국어 UI
- 비용 추정 고지
- 사용 속도 예측
- 차트 기간 필터
- Provider 필터
- 데이터 내보내기

---

### 4단계 — QA와 배포: 2~4일

- 파서 fixture 테스트
- 자식 프로세스 timeout 테스트
- 로그 비밀정보 검사
- idle CPU 검사
- 메모리 검사
- sleep/wake 검사
- 로그인·로그아웃 검사
- 네트워크 단절 검사
- Developer ID 서명
- Apple 공증
- DMG 생성
- Sparkle 업데이트 검증

---

## 17. 현실적인 개발 기간

한 명의 숙련된 macOS 개발자 기준:

- 개인용 PoC: 1~3일
- 메뉴바 MVP: 약 1주
- 상세 대시보드 포함: 약 2주
- 재배포 가능한 독립 제품: 약 2~4주

개인용으로 기존 프로젝트를 거의 그대로 빌드한다면 하루 안에도 실행 가능하지만, 재배포 가능한 독립 제품으로 만들려면 다음 시간이 추가로 필요합니다.

- 리브랜딩
- Provider별 실제 계정 검증
- 파서 테스트
- 서명
- 공증
- 자동 업데이트
- 성능 QA
- 보안 QA

---

## 18. MVP 완료 기준

다음 항목을 만족하면 1차 MVP 완료로 정의할 수 있습니다.

- macOS 메뉴바에서 네 Provider 상태 확인
- 메뉴바 클릭 시 팝오버 표시
- Claude 사용량 수집
- Codex 사용량 수집
- Grok Build 사용량 수집 또는 지원 불가 상태 명확히 표시
- GLM Coding Plan 사용량 수집
- 각 값의 출처 표시
- 마지막 정상 값 캐시
- 인증 없음과 실제 100%를 구분
- 상세 화면에서 한도와 추세 분리
- 로컬 토큰과 구독 한도 분리
- 잔여량 알림
- 유휴 상태 CPU 0.5% 수준 목표
- 비밀정보 로그 미기록
- Developer ID 서명 및 공증

---

## 19. 최종 권고안

가장 좋은 방향은 다음 한 줄로 정리됩니다.

> **TokenRemain을 기반으로 하되, Codex·Claude·Grok Build·Z.ai GLM Coding Plan만 남긴 로컬 전용 네이티브 macOS 앱으로 축소하고, 이름·아이콘·색상·캐릭터·디자인 에셋은 완전히 새로 만든다.**

핵심 차별점은 화려한 카드가 아니라 다음 세 가지가 되어야 합니다.

1. **Provider가 보고한 실제 잔여 한도**
2. **로컬 로그에서 확인한 토큰 추세**
3. **각 숫자의 출처와 최신 상태를 명확히 표시**

첫 커밋은 UI 제작이 아니라 다음 순서로 진행하는 것이 맞습니다.

```text
fork
→ 원본 브랜드 에셋 제거
→ 4개 Provider 실제 계정 fixture 검증
→ 메뉴바 MVP
→ 상세 대시보드
→ 성능·보안 QA
→ 서명·공증·배포
```

---

## 20. 참고 링크

- TokenRemain  
  <https://github.com/Carstin520/token-remain>

- CodexBar  
  <https://github.com/steipete/CodexBar>

- ClaudeBar  
  <https://github.com/tddworks/ClaudeBar>

- ccusage  
  <https://ccusage.com/guide/all-reports>

- Claude Code Statusline  
  <https://docs.anthropic.com/en/docs/claude-code/statusline>

- CodexBar Codex 문서  
  <https://github.com/steipete/CodexBar/blob/main/docs/codex.md>

- CodexBar Grok 문서  
  <https://github.com/steipete/CodexBar/blob/main/docs/grok.md>

- Z.ai Usage Query Plugin  
  <https://docs.z.ai/devpack/extension/usage-query-plugin>

- GLM `CREDIT_LIMIT` 관련 이슈  
  <https://github.com/steipete/CodexBar/issues/2724>

- TokenRemain 성능 문서  
  <https://github.com/Carstin520/token-remain/blob/main/docs/performance-v1.2.3.md>

- TokenRemain Mac App Store Sandbox 검토  
  <https://github.com/Carstin520/token-remain/blob/main/docs/mac-app-store-sandbox-compatibility.md>

- Apple Sandbox 파일 접근 문서  
  <https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox>

- Apple LSUIElement 문서  
  <https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement>
