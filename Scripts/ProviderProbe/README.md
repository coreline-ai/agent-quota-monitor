# ProviderProbe

제품 target과 분리된 read-only 조사 도구다.

- `fixture_guard.py scan`: fixture secret/PII와 JSON 상태 검사
- `fixture_guard.py manifest`: SHA-256 manifest 출력
- `codex_rate_limits_probe.py`: 승인 후 공식 app-server의 `account/rateLimits/read`만 호출
- `claude_oauth_usage_probe.py`: 승인 후 기존 Claude Code Keychain access token으로 Anthropic usage GET만 호출하고 field 존재·credential 불변만 출력
- `grok_billing_probe.py`: 승인 후 xAI 공식 CLI billing backend GET만 호출하고 field 존재·credential 불변만 출력
- `glm_plugin_usage_probe.py`: 승인 후 기존 `claude-glm` profile로 설치된 Z.ai 공식 usage plugin을 정확히 1회 실행하고 limit type·percentage 유효성·profile 불변만 출력
- `safe_validation.py inspect`: CLI·로그인 증거·설정 capability를 secret 비노출 형태로 검사
- `safe_validation.py baseline/compare`: allowlist credential/config의 hash·mtime·mode를 검증 전후 비교
- `test_safe_validation.py`: symlink·권한·redaction·무결성 비교 자체 테스트
- `test_grok_billing_probe.py`: Grok credential 선택·redirect 거부·redacted 출력 자체 테스트
- `test_glm_plugin_usage_probe.py`: GLM alias strict parser·quota section 분리·redacted evidence 자체 테스트

Codex probe는 login·logout·refresh·thread·model·reset-credit method를 보내지 않는다. 결과는 stdout에 normalized quota field만 출력하고 원본 payload와 account metadata는 저장하지 않는다.

Grok probe는 정확한 first-party CLI billing URL에 GET 한 번만 보낸다. refresh token·cookie·redirect·model endpoint를 사용하지 않으며 실제 quota, token, user ID, 원본 payload를 출력하지 않는다.

## 권장 실계정 검증 순서

```zsh
python3 Scripts/ProviderProbe/test_safe_validation.py
python3 Scripts/ProviderProbe/test_claude_oauth_usage_probe.py
python3 Scripts/ProviderProbe/test_grok_billing_probe.py
python3 Scripts/ProviderProbe/test_glm_plugin_usage_probe.py
python3 Scripts/ProviderProbe/safe_validation.py baseline --output /tmp/quotabeacon-provider-baseline.json
python3 Scripts/ProviderProbe/safe_validation.py inspect --output /tmp/quotabeacon-provider-inspect.json
python3 Scripts/ProviderProbe/codex_rate_limits_probe.py
python3 Scripts/ProviderProbe/claude_oauth_usage_probe.py
python3 Scripts/ProviderProbe/grok_billing_probe.py
python3 Scripts/ProviderProbe/glm_plugin_usage_probe.py
python3 Scripts/ProviderProbe/safe_validation.py compare \
  --baseline /tmp/quotabeacon-provider-baseline.json \
  --output /tmp/quotabeacon-provider-comparison.json
```

- `/tmp` evidence 파일은 `0600`으로 생성한다.
- `inspect`의 stdout에서는 credential hash·mtime을 제거한다.
- Claude 설정은 status-line/GLM endpoint/plugin 여부만 파생하며 command·key 값을 출력하지 않는다.
- Claude OAuth usage probe는 승인 후 Keychain access token을 메모리에서만 읽어 Anthropic usage GET을 1회 호출하고 field 존재·credential 불변 여부만 출력한다.
- Grok은 공식 client source에서 관찰된 billing 계약만 Beta로 검증한다. GLM은 shell alias를 실행하지 않고 허용된 두 environment만 설치된 공식 plugin에 전달하며 Model/Tool output과 실제 percentage를 출력하지 않는다.
