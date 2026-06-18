# FFmpeg / MKV 검증 계획

작성일: 2026-06-18  
프로젝트명: 글레이즈 / Glaze

## 문서 목적

이 문서는 AVFoundation/AVKit 기반 Player MVP 이후, MKV와 고해상도 영상 대응을 위해 FFmpeg 도입 필요성을 검증하는 기준 문서다.

목표는 바로 FFmpeg를 붙이는 것이 아니라, App Store 배포 가능성, 웹 배포/Pro 분리 가능성, 라이선스 리스크, 사용자 가치, 구현 공수를 같은 기준에서 판단하는 것이다.

## 현재 결론

2026-06-18 기준 1차 결론:

- MVP 기본 재생 엔진은 계속 AVFoundation/AVKit으로 유지한다.
- FFmpeg는 `Player MVP 직후 검증` 단계로 착수한다.
- App Store 버전은 샌드박스, 자가완결 앱 번들, 외부 코드 다운로드 금지 기준을 우선한다.
- FFmpeg를 앱에 포함할 경우 LGPL 준수 가능 빌드만 1차 후보로 둔다.
- GPL 또는 nonfree 옵션이 필요한 고급 코덱 기능은 App Store 기본판에 넣지 않고 웹 배포/Pro 분리 후보로 관리한다.
- 사용자의 실제 고해상도 MKV 샘플에서 AVKit 실패율이 높을 때만 플레이어 엔진 확장을 진행한다.

## 공식 기준

### Apple App Store / Mac App Store

확인 출처:

- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

검토 기준:

- Mac App Store 앱은 적절히 sandboxed 되어야 한다.
- Mac App Store 앱은 self-contained single app bundle이어야 한다.
- 앱은 기능을 크게 바꾸는 코드 또는 리소스를 외부에서 다운로드/설치/실행하면 안 된다.
- 앱은 public API를 사용하고 현재 OS에서 정상 동작해야 한다.

글레이즈 적용:

- App Store 버전은 앱 번들 내부에 포함된 재생 기능만 사용한다.
- FFmpeg 바이너리/라이브러리를 후속 다운로드로 받아 기능을 추가하는 방식은 App Store 기본 전략에서 제외한다.
- 웹 배포판에서는 notarization, hardened runtime, 라이선스 고지, 소스 제공 정책을 별도로 설계한다.

### FFmpeg 라이선스

확인 출처:

- FFmpeg License and Legal Considerations: https://ffmpeg.org/legal.html

검토 기준:

- FFmpeg 기본 라이선스는 LGPL 2.1 이상이다.
- 선택 옵션과 최적화에 따라 GPL이 적용될 수 있다.
- `--enable-gpl` 또는 GPL 라이브러리 사용 여부를 반드시 확인한다.
- `--enable-nonfree` 빌드는 배포 전략에서 매우 높은 리스크로 본다.
- FFmpeg를 배포물에 포함하면 소스 제공, 빌드 방법, 고지, EULA 문구 등 준수 항목을 관리해야 한다.

글레이즈 적용:

- App Store 후보 빌드는 `--enable-gpl`, `--enable-nonfree` 없는 LGPL 빌드만 검토한다.
- GPL 기능이 필요하면 해당 기능은 웹 배포/Pro 후보로 분리한다.
- About 화면, 웹 다운로드 페이지, EULA 또는 라이선스 문서에 FFmpeg 고지를 포함해야 한다.

## 로컬 환경 확인

2026-06-18 현재 이 개발 환경에서는 아래 도구가 설치되어 있지 않다.

- `ffmpeg`: not installed
- `ffprobe`: not installed
- `mediainfo`: not installed

따라서 이번 단계에서는 검증 프레임과 스크립트만 추가했고, 실제 샘플별 결과는 도구 설치 및 샘플 영상 확보 후 기록한다.

## 검증 스크립트

추가된 스크립트:

```bash
./script/validate_media_capability.sh
```

샘플 파일 검사:

```bash
./script/validate_media_capability.sh "/path/to/sample.mkv" "/path/to/sample.mp4"
```

스크립트 역할:

- `ffmpeg`, `ffprobe`, `mediainfo` 설치 여부 확인
- `ffmpeg -version` 기준 GPL/nonfree 빌드 플래그 탐지
- macOS `mdls` 기반 파일 타입/코덱 메타데이터 확인
- `ffprobe`가 있을 경우 비디오/오디오/자막 스트림 정보 출력

## 샘플 세트 기준

검증 샘플은 실제 사용자가 보유한 개인 영상 또는 저작권 문제가 없는 테스트 파일만 사용한다.

필수 샘플:

- MP4 / H.264 / AAC / 1080p
- MP4 / HEVC / AAC / 4K
- MOV / ProRes 또는 HEVC
- MKV / H.264 / AAC 또는 AC3 / 1080p
- MKV / HEVC / 10-bit / AAC 또는 FLAC / 4K
- MKV / 다중 오디오 트랙
- MKV / 내장 자막 트랙
- HDR 샘플

기록 필드:

| 샘플 | 컨테이너 | 비디오 코덱 | 오디오 코덱 | 자막 트랙 | 해상도 | AVKit 재생 | 자막 감지 | 오디오 추출 | FFmpeg 필요 | 비고 |
|---|---|---|---|---|---|---|---|---|---|---|
| TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

## 검증 항목

### 1. AVFoundation/AVKit 재생 가능 범위

- 앱에서 파일 선택 가능 여부
- 영상 표시 여부
- 오디오 출력 여부
- 탐색 안정성
- 전체화면 안정성
- 4K/HDR 재생 시 프레임 드롭 체감
- 다중 오디오 트랙 접근 가능성
- 내장 자막 트랙 접근 가능성

### 2. 오디오 추출 필요성

AI 자막 생성을 위해 재생 가능 여부와 별도로 오디오 추출 가능성을 확인해야 한다.

검토 기준:

- AVAssetReader로 오디오 트랙을 읽을 수 있는가
- MKV에서 AVFoundation이 오디오 트랙을 인식하는가
- FFmpeg 없이 WAV/PCM 추출이 가능한가
- 고해상도 긴 영상에서 추출 속도와 메모리 사용량이 허용 가능한가

### 3. FFmpeg 도입 방식 후보

| 방식 | App Store 적합성 | 장점 | 리스크 | 1차 판단 |
|---|---:|---|---|---|
| AVFoundation/AVKit only | 높음 | 배포/심사 단순, macOS 네이티브 | MKV/특수 코덱 한계 | MVP 기본 |
| FFmpeg CLI 번들 | 중간 | 구현 단순, 추출 작업에 유리 | 프로세스 실행, 라이선스 고지, 샌드박스 검토 | 기술 검증 후보 |
| FFmpegKit류 래퍼 | 중간 | Swift 연동 단순 | 유지보수/라이선스/플랫폼 정책 의존 | 신중 검토 |
| libav* 직접 연동 | 중간 | 제어력 높음 | 구현 공수 큼, 크래시/메모리 관리 부담 | 후순위 |
| 웹 배포판 FFmpeg 기능 | 높음 | App Store 제약 회피 가능 | 별도 배포/업데이트/보안 부담 | Pro 후보 |

## 기능 티어 태그

| 기능 | MVP | 무료/유료 후보 | App Store 가능성 | Pro 분리 가능성 | 정책 리스크 |
|---|---|---|---|---|---|
| AVKit 기본 재생 | 포함 | 무료 후보 | 높음 | 낮음 | 낮음 |
| MP4/MOV 안정 재생 | 포함 | 무료 후보 | 높음 | 낮음 | 낮음 |
| MKV 기본 열기 시도 | 검증 | 무료 후보 | 중간 | 중간 | 중간 |
| FFmpeg 기반 고급 코덱 지원 | 검증 | Pro 후보 | 검토 필요 | 높음 | 중간~높음 |
| FFmpeg 기반 오디오 추출 | 검증 | 유료/Pro 후보 | 검토 필요 | 중간 | 중간 |
| 내장 자막 트랙 추출 | 검증 | 유료 후보 | 검토 필요 | 중간 | 중간 |
| 웹 배포판 고급 미디어 엔진 | 제외 | Pro 후보 | 낮음 | 높음 | 중간 |

## 진행 순서

1. 검증 스크립트와 문서 기준 확정
2. 저작권 문제가 없는 샘플 영상 세트 확보
3. 현재 AVKit 앱에서 샘플별 재생 결과 기록
4. `ffmpeg`/`ffprobe` 설치 또는 빌드 후보 준비
5. 샘플별 스트림 구조와 AVKit 실패 원인 비교
6. LGPL-only FFmpeg 빌드 가능성 검토
7. App Store 기본판과 웹 배포/Pro 분리 기준 업데이트
8. 실제 도입 방식 결정

## 다음 작업

- 샘플 영상 폴더를 정하고 검증 파일명을 문서에 추가한다.
- `ffmpeg`와 `ffprobe` 설치 또는 별도 빌드 방식을 결정한다.
- 앱 내부에서 AVAsset 트랙 정보를 표시/로그로 남기는 디버그 도구를 추가한다.
