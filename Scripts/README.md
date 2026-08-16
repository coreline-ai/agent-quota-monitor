# Scripts

이 디렉터리의 script는 AIQuotaMonitor 프로젝트를 위해 신규 작성한다.

Phase 1 도구:

- `audit_greenfield_references.sh`: 제품 source에서 참고 프로젝트 고유 문자열을 검사한다.
- `generate_brand_assets.py`: 외부 이미지 입력 없이 `QuotaBeacon` app/menu-bar asset을 재생성한다. 실행에는 Pillow가 필요하며 생성된 PNG와 asset catalog metadata는 저장소에 포함한다.

주요 검증 도구:

- `ProviderProbe/safe_validation.py`: Provider 설치·credential metadata·capability를 redacted 형태로 검사한다.
- `ProviderProbe/codex_rate_limits_probe.py`: Codex 공식 read-only rate-limit 계약을 검증한다.
- `ProviderProbe/claude_oauth_usage_probe.py`: macOS Keychain의 기존 Claude Code access token으로 Anthropic usage endpoint를 GET-only 검증하고 credential 불변 여부·field 존재만 출력한다.
- `ProviderProbe/grok_billing_probe.py`: Grok 공식 CLI billing backend를 GET-only로 검증한다.
- `ProviderProbe/glm_plugin_usage_probe.py`: 기존 GLM profile과 설치된 Z.ai 공식 plugin을 1회 실행해 redacted quota 계약을 검증한다.
- `security_audit.py`, `audit_originality.sh`, `audit_greenfield_references.sh`: 비밀정보·독창성·참조 경계를 검사한다.
- `build_release.sh`, `package_release.sh`: Universal Release와 배포 산출물을 만든다.
