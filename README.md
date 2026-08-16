# QuotaBeacon

QuotaBeacon은 Codex·Claude Code·Grok Build·Z.ai GLM Coding Plan의 구독 quota와 로컬 token/예상 API 비용을 **서로 분리해서** 보여주는 Greenfield macOS 메뉴 막대 앱입니다.

> 현재 버전: `0.1.0-beta.1`  
> 최소 환경: macOS 14, Apple Silicon/Intel Universal

## 현재 동작

- 메뉴 막대 popover에서 네 Provider의 `LIVE / 부분 데이터 / 캐시 / 연결 필요 / 확인 불가` 상태를 구분합니다.
- Codex는 사용자가 설정에서 명시적으로 승인하면 공식 `codex app-server`의 read-only rate-limit method만 사용합니다.
- Claude는 사용자가 지정한 `0600` status snapshot 파일만 읽습니다.
- Grok은 사용자가 명시적으로 승인하면 `grok login`의 `0600` credential을 읽기 전용으로 사용해 xAI 공식 CLI billing backend에서 주간 사용률·reset·선불 잔액을 조회합니다. 이 경로는 `observed · Beta`입니다.
- Z.ai는 안전한 독립 앱용 machine contract가 확정되기 전까지 수치를 만들지 않습니다.
- quota 값마다 출처·계약 등급·관측 시각·최신성·reset을 보존합니다.
- 상세 창에서 개요, 한도, 추세, 데이터 소스, 설정을 제공합니다.
- 원본 payload·프롬프트·응답·계정 ID를 저장하지 않고 redacted JSON/CSV만 내보냅니다.

## 빌드와 테스트

```zsh
xcodebuild -project AIQuotaMonitor.xcodeproj \
  -scheme AIQuotaMonitor \
  -configuration Debug \
  -destination 'platform=macOS' build

xcodebuild -project AIQuotaMonitor.xcodeproj \
  -scheme AIQuotaMonitor \
  -destination 'platform=macOS' test
```

```zsh
Scripts/ProviderProbe/fixture_guard.py scan
python3 Scripts/ProviderProbe/test_safe_validation.py
python3 Scripts/ProviderProbe/test_grok_billing_probe.py
Scripts/audit_originality.sh
Scripts/security_audit.py
Scripts/build_release.sh
Scripts/package_release.sh
```

## 연결 안전장치

1. 앱은 기본적으로 모든 credential 기반 Provider 연결을 끈 상태로 시작합니다.
2. **설정 → Provider 연결 → 승인하고 연결 적용**에서 사용자가 명시적으로 활성화합니다.
3. 로그인, OAuth refresh, browser cookie import, 모델 호출, credit 소비, credential write-back은 하지 않습니다. Grok adapter는 access token과 user ID를 메모리에서만 선택하고 refresh token을 선택·사용·전송하지 않습니다.
4. 실제 계정 fixture 수집과 Developer ID 공증은 별도 credential 승인이 필요합니다.

## 문서

- [현재 Grok 개발 계획](dev-plan/implement_20260816_184557.md)
- [정본 전체 개발 계획](dev-plan/implement_20260816_133341.md)
- [Provider 계약](docs/provider-contracts.md)
- [Provider 실환경 검증](docs/provider-validation-2026-08-16.md)
- [아키텍처](docs/architecture.md)
- [보안·개인정보](docs/security-privacy.md)
- [배포](docs/distribution.md)
- [외부 참조 등록부](docs/reference-register.md)

## 독립 구현 정책

외부 오픈소스와 앱은 조사·비교에만 사용했습니다. 외부 source, fixture, UI 구조, asset, build script는 포함하지 않습니다. 제품 source와 test source는 `Scripts/audit_originality.sh`로 별도 검사합니다.
