# 보안·개인정보 설계

확인일: `2026-08-16 KST`

## 데이터 흐름

- QuotaBeacon은 자체 서버와 telemetry를 사용하지 않는다.
- Claude는 사용자가 명시적으로 지정한 `0600` read-only snapshot만 읽는다.
- Codex는 사용자가 활성화한 경우 공식 `codex app-server`의 `initialize`, `account/rateLimits/read`만 호출한다.
- Grok과 Z.ai는 공개된 독립 앱용 machine contract가 확정될 때까지 수치를 조회하지 않는다.
- Z.ai 수동 키는 macOS Keychain의 `ThisDeviceOnly` generic password로만 저장한다.
- 원본 Provider payload, 프롬프트·응답 본문, 이메일, 계정 ID, 홈 경로는 history/export에 저장하지 않는다.

## 위협 모델과 통제

| 위협 | 통제 |
|---|---|
| credential 파일 바꿔치기 | symlink 거부, owner·regular file·allowlist·`0600` 검사 |
| credential 변조 | read-only API, write-back·refresh·login 메서드 없음, fixture에서 hash/mtime 비교 |
| CLI hang/orphan | timeout, cancellation, TERM 후 KILL, stdout/stderr 분리 |
| 부분 응답 오표시 | window별 optional 처리, `nil`을 퍼센트로 만들지 않음 |
| 오래된 값의 LIVE 오표시 | last-known-good provenance 보존 및 freshness를 `stale`로 변경 |
| 로그·export 유출 | 중앙 `Redactor`, diagnostic 제외 export, release secret scan |
| 비공개 API 사용 | Grok/Z.ai 상태 전용, browser cookie/WebView 수집 금지 |

## 사용자 데이터 삭제

- Z.ai 키: 설정의 **삭제**로 Keychain item 제거.
- History: 제품의 versioned JSON 파일 제거(현재 Beta에서는 history 연결 전).
- 앱 제거 시 별도 서버 데이터는 없다.

## 현재 보안 제한

- `2026-08-16` 승인된 실계정 검증에서 Codex read-only quota probe와 Claude host auth 확인을 수행했다. 9개 allowlist fingerprint의 hash·mtime·mode는 전후 불변이었다.
- Grok은 credential file metadata만 확인했고, Z.ai는 현재 실행 환경에서 login 경로를 찾지 못했다.
- Claude snapshot bridge 설치, Keychain add/read/replace/delete 실기기 test, Developer ID 공증은 아직 실행하지 않았다.
- crash reporter와 원격 분석 SDK는 포함하지 않는다.

실환경 검증 상세: [Provider 실환경 검증 보고서](provider-validation-2026-08-16.md)
