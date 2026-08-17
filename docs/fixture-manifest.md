# Fixture Manifest

확인일: `2026-08-17 KST`

모든 현재 fixture는 공식 문서·공식 CLI schema를 바탕으로 QuotaBeacon을 위해 새로 작성한 **synthetic payload**다. 실제 계정 응답 또는 외부 저장소 fixture가 아니다.

| Provider | 파일 | 종류 | 계약 근거 | redaction | 실제 검증 |
|---|---|---|---|---|---|
| Claude | `claude-{normal,partial,errors,malformed}.json`, `claude-oauth-{normal,partial}.json` | synthetic | 공식 statusLine + 관측된 OAuth usage field | token·계정·실제 quota 미포함 | OAuth field 존재 실계정 검증 |
| Codex | `codex-{normal,partial,errors,malformed}.json` | synthetic | `codex-cli 0.145.0` 생성 schema | ID·workspace·account 미포함 | 미실행 |
| Grok | `grok-{normal,partial,errors,malformed}.json` | synthetic | xAI 공식 Grok Build billing response field | token·user ID·실제 quota 미포함 | field 존재 실계정 검증 |
| Gemini | `gemini-{normal,partial,malformed}.txt` | synthetic TUI text | 공식 Antigravity CLI `/usage`의 Gemini group label | account·email·다른 모델 group의 실제 값·실제 quota 미포함 | `agy 1.1.13` field 존재·무모델 검증 |
| ZAI | `zai-{normal,partial,errors,malformed}.json` | synthetic | 공식 `glm-plan-usage` `0.0.1` Quota limit output | token·Model/Tool usage·account·실제 percentage 미포함 | 공식 script field 존재 및 설치 앱 LIVE 검증 |

## Schema fingerprint

`Scripts/ProviderProbe/fixture_guard.py manifest`가 각 파일 SHA-256을 계산한다. JSON malformed fixture는 고의로 parsing에 실패해야 하며, Gemini fixture는 실제 payload가 아닌 synthetic TUI text다.

```text
725744a2011b20d4d0b64ce0e251cf79f36c10c8017fcc5c71aeb53688d3c60a  Claude/claude-errors.json
ee3bb016ee1b1e395152b5db18af8d7e785aa19a2ab541c9bd9d13dfa8a2a0f0  Claude/claude-malformed.json
6dab46e166c00dc822cee35942c60722417237e370809f2569bd38e3328bdd23  Claude/claude-normal.json
be33fe136a9d446471f73f372d18e791bcb9f1ec5293db61bc069dee583da397  Claude/claude-partial.json
ba973a6768bb7aaea40076f03d100cf9ac8132d91a887983235315051f1ca400  Claude/claude-oauth-normal.json
e33807fe38d8330e55f529863e1a6b9102fba931f2e2a23e41ce845fa13c8fc8  Claude/claude-oauth-partial.json
0b4d6016625e6313fabba827333ea820eb5a5508db95061dcf2a9622a4a30992  Codex/codex-errors.json
51da86c570330d901fbc1aa167c4c41bc17049bbac37ee1e4758769c930aab4f  Codex/codex-malformed.json
8e6a20103356d06d08edf396f76cbcf2b87dd9b35e3964659ef08efd71c56aa9  Codex/codex-normal.json
4d79dc39a8242ed27c282a9bad4e52a8cfed0e367b211ec7307014b595d31f5e  Codex/codex-partial.json
927bcd7d13ea96d84502fd86f17fe6fe286d6c0615d1d8248959cba9038b454f  Gemini/gemini-malformed.txt
98162eda616b44041f5a4fef8b484ee1434ad6a3ae10e5d40287e54398d689fb  Gemini/gemini-normal.txt
3030fd697a91219157a42b6238927642ac8cf667186220a479100bd07a35920d  Gemini/gemini-partial.txt
97351cf842b8ecc5a5760f069b8d29590e281ce06be5fc7d4ec2b338ab6d66c1  Grok/grok-errors.json
3eb6bd8a35e6f35466327f4af1dcb9e77e2ba2330e95a694b7a0cc354b7e7608  Grok/grok-malformed.json
303e14bfd56d0b974f8568aa443cbb9a31df5d84176dc0a8ca268c92803ee1b9  Grok/grok-normal.json
0c5da2186829681997c8f2e4ab3b7aaf3c77b3ea1c2d198c90e734914d7689a2  Grok/grok-partial.json
02ba6d331db44db9acc9f2c8e3083495254b50f83c5f9d1e05ef64a26683bcdf  ZAI/zai-errors.json
13ac8a7b6d413cdf6acbab6735799433f5c949c8789b856a2670d049e7900cf5  ZAI/zai-malformed.json
dbf14fbdcf33d6656bb561b1e27a8673e9c6ea010ed6dbef9f04e65797e9206f  ZAI/zai-normal.json
db4cdea4c443720b5120267b68365c312bb095d6dfa6d9639a1fb190f5f08d3e  ZAI/zai-partial.json
```

## 직접 fixture 추가 조건

1. 사용자 승인 후 read-only probe만 실행한다.
2. 모델/thread/credit 소비 endpoint를 호출하지 않는다.
3. credential hash·mtime이 전후 동일해야 한다.
4. token, key, cookie, 이메일, account/workspace/session ID, 홈 경로를 제거한다.
5. 원본 payload를 repository나 log에 남기지 않는다.
6. 수집일, client version, schema fingerprint, redaction 결과를 이 문서에 추가한다.
