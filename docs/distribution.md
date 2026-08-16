# 배포 가이드

확인일: `2026-08-16 KST`

## 현재 가능한 로컬 후보

1. `Scripts/build_release.sh`로 Universal Release 앱을 빌드한다.
2. `Scripts/package_release.sh`로 앱, LICENSE, third-party notices, changelog, privacy/distribution 문서를 포함한 ZIP과 SHA-256을 만든다.
3. ad-hoc 산출물은 개발 검증용이며 공개 배포용이 아니다.

## Developer ID gate

공개 배포에는 저장소 밖에서 다음 값이 필요하다.

- Apple Developer Program Team ID
- `Developer ID Application` certificate
- `xcrun notarytool store-credentials`로 만든 Keychain profile

```zsh
SIGNING_IDENTITY='Developer ID Application: …' Scripts/build_release.sh
Scripts/package_release.sh
NOTARY_PROFILE='QuotaBeacon-Notary' Scripts/notarize_release.sh
Scripts/verify_release.sh /path/to/QuotaBeacon.app
```

서명 identity, Apple ID password, App Store Connect key는 source·xcconfig·CI log에 기록하지 않는다.

## 자동 업데이트 gate

- Sparkle archive signing key, HTTPS appcast URL, 공개 release host가 아직 제공되지 않았다.
- 따라서 현재 build에는 자동 업데이트 프레임워크나 appcast가 포함되지 않는다.
- key와 URL이 확정되면 Sparkle 공식 binary framework를 별도 dependency review 후 추가하고 정상 upgrade·동일 버전·downgrade 거부를 검증한다.

## 미완료 외부 검증

- notarization 및 stapling
- 깨끗한 macOS 계정에서 최초 실행·Keychain 승인·삭제
- 10분 idle 및 장기 sleep/wake·network flap soak
- Sparkle update와 downgrade 방지

위 항목은 필요한 인증정보·별도 환경 없이 완료로 표시하지 않는다.
