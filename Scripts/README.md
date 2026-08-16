# Scripts

이 디렉터리의 script는 AIQuotaMonitor 프로젝트를 위해 신규 작성한다.

Phase 1 도구:

- `audit_greenfield_references.sh`: 제품 source에서 참고 프로젝트 고유 문자열을 검사한다.
- `generate_brand_assets.py`: 외부 이미지 입력 없이 `QuotaBeacon` app/menu-bar asset을 재생성한다. 실행에는 Pillow가 필요하며 생성된 PNG와 asset catalog metadata는 저장소에 포함한다.

이후 build, secret scan, packaging, notarization, energy measurement script를 단계별로 추가한다.
