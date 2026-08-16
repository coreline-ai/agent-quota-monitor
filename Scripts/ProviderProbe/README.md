# ProviderProbe

제품 target과 분리된 read-only 조사 도구다.

- `fixture_guard.py scan`: fixture secret/PII와 JSON 상태 검사
- `fixture_guard.py manifest`: SHA-256 manifest 출력
- `codex_rate_limits_probe.py`: 승인 후 공식 app-server의 `account/rateLimits/read`만 호출
- `safe_validation.py inspect`: CLI·로그인 증거·설정 capability를 secret 비노출 형태로 검사
- `safe_validation.py baseline/compare`: allowlist credential/config의 hash·mtime·mode를 검증 전후 비교
- `test_safe_validation.py`: symlink·권한·redaction·무결성 비교 자체 테스트

Codex probe는 login·logout·refresh·thread·model·reset-credit method를 보내지 않는다. 결과는 stdout에 normalized quota field만 출력하고 원본 payload와 account metadata는 저장하지 않는다.

## 권장 실계정 검증 순서

```zsh
python3 Scripts/ProviderProbe/test_safe_validation.py
python3 Scripts/ProviderProbe/safe_validation.py baseline --output /tmp/quotabeacon-provider-baseline.json
python3 Scripts/ProviderProbe/safe_validation.py inspect --output /tmp/quotabeacon-provider-inspect.json
python3 Scripts/ProviderProbe/codex_rate_limits_probe.py
python3 Scripts/ProviderProbe/safe_validation.py compare \
  --baseline /tmp/quotabeacon-provider-baseline.json \
  --output /tmp/quotabeacon-provider-comparison.json
```

- `/tmp` evidence 파일은 `0600`으로 생성한다.
- `inspect`의 stdout에서는 credential hash·mtime을 제거한다.
- Claude 설정은 status-line/GLM endpoint/plugin 여부만 파생하며 command·key 값을 출력하지 않는다.
- Grok·GLM은 공개된 독립 앱용 quota contract가 없으면 수치를 생성하지 않는다.
