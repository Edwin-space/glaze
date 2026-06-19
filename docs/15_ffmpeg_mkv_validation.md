# FFmpeg / MKV 검증 계획

작성일: 2026-06-18  
프로젝트명: 글레이즈 / Glaze

## 문서 목적

이 문서는 AVFoundation/AVKit 기반 Player MVP 이후, MKV와 고해상도 영상 대응을 위해 FFmpeg 도입 필요성을 검증하는 기준 문서다.

목표는 바로 FFmpeg를 붙이는 것이 아니라, App Store 배포 가능성, 웹 배포/Pro 분리 가능성, 라이선스 리스크, 사용자 가치, 구현 공수를 같은 기준에서 판단하는 것이다.

## 현재 결론

2026-06-19 기준 1차 결론:

- MVP 기본 재생 엔진은 계속 AVFoundation/AVKit으로 유지한다.
- FFmpeg는 `Player MVP 직후 검증` 단계로 착수하되, MKV/고해상도 대응은 사용자 확보를 위한 기본 경쟁력으로 본다.
- 무비스트, IINA, VLC류 플레이어에서 사용자가 기대하는 코덱/컨테이너 대응을 벤치마크 기준으로 둔다.
- App Store 버전은 샌드박스, 자가완결 앱 번들, 외부 코드 다운로드 금지 기준을 우선한다.
- FFmpeg를 앱에 포함할 경우 LGPL 준수 가능 빌드만 1차 후보로 둔다.
- GPL 또는 nonfree 옵션이 필요한 고급 코덱 기능은 App Store 기본판에 넣지 않고 웹 배포/Pro 분리 후보로 관리한다.
- 사용자의 실제 고해상도 MKV 샘플에서 AVKit 실패율이 높거나 다중 오디오/내장 자막/오디오 추출 UX가 부족하면 플레이어 엔진 보강을 진행한다.
- AVKit에 맞춘 MP4 remux 후 재생은 호환성 보강용 임시 경로이며, 무비스트처럼 파일 등록 직후 즉시 화면을 띄우는 수준을 목표로 하면 직접 MKV 재생 엔진이 필요하다.

## 제품 경쟁력 기준

AI 자막 준비가 글레이즈의 차별점이지만, 영상 플레이어로 선택받으려면 기본 재생 호환성이 먼저 신뢰를 줘야 한다. 따라서 코덱/컨테이너 대응은 후순위 고급 기능이 아니라 초기 제품 품질 기준으로 관리한다.

1차 목표는 모든 코덱을 자체 디코딩하는 것이 아니라, 실제 사용자가 많이 만나는 MKV 파일을 아래 네 단계로 분류하고 대응하는 것이다.

| 분류 | 의미 | 제품 처리 방향 |
|---|---|---|
| 직접 재생 | AVKit이 컨테이너/트랙을 바로 재생 | 기본 재생 경로 |
| 보조 처리 | 비디오는 가능하지만 컨테이너, 오디오, 자막 추출 보완 필요 | remux, 오디오 추출, 내장 자막 추출 검토 |
| FFmpeg 필요 | AVKit 인식/재생 실패 | LGPL-only FFmpeg 번들 후보 |
| 분리 후보 | GPL/nonfree 또는 특수 코덱 필요 | 웹 배포/Pro 후보 |

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
- FFmpeg Download: https://ffmpeg.org/download.html

검토 기준:

- FFmpeg 기본 라이선스는 LGPL 2.1 이상이다.
- 선택 옵션과 최적화에 따라 GPL이 적용될 수 있다.
- `--enable-gpl` 또는 GPL 라이브러리 사용 여부를 반드시 확인한다.
- `--enable-nonfree` 빌드는 배포 전략에서 매우 높은 리스크로 본다.
- FFmpeg를 배포물에 포함하면 소스 제공, 빌드 방법, 고지, EULA 문구 등 준수 항목을 관리해야 한다.
- FFmpeg 공식 프로젝트는 소스 코드를 제공하며, macOS 실행 파일은 제3자 빌드 링크로 안내한다. 따라서 App Store 후보 바이너리는 공식 소스 기반 자체 빌드 또는 출처/플래그가 검증된 빌드만 사용한다.

글레이즈 적용:

- App Store 후보 빌드는 `--enable-gpl`, `--enable-nonfree` 없는 LGPL 빌드만 검토한다.
- GPL 기능이 필요하면 해당 기능은 웹 배포/Pro 후보로 분리한다.
- About 화면, 웹 다운로드 페이지, EULA 또는 라이선스 문서에 FFmpeg 고지를 포함해야 한다.
- 개발 검증은 공식 소스 tarball을 내려받아 `--disable-gpl`, `--disable-nonfree`로 빌드하는 `./script/build_lgpl_ffmpeg_tools.sh`를 우선 사용한다.

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
- `--remux` 옵션으로 첫 번째 오디오 트랙을 AAC로 보정한 MP4 임시 파일 생성 테스트
- AAC 보정 remux 실패 시 stream copy remux를 재시도

앱 내부 진단:

- 미디어 정보 패널에서 컨테이너, AVKit 직접 재생 가능 여부, 인식된 트랙과 코덱을 표시한다.
- 이 패널은 사용자용 고급 설정이 아니라 개발 검증과 향후 고객지원/FAQ의 근거 데이터를 쌓기 위한 초기 도구다.
- MKV/WebM/AVI 재생 실패 시 FFmpeg가 설치 또는 번들되어 있으면 MP4 캐시로 remux 후 AVPlayer 재생을 재시도한다.
- 첫 번째 오디오 트랙이 AVKit 후보 코덱이면 stream copy를 우선 적용하고, 필요할 때만 AAC 192kbps stereo 보정으로 재시도한다.
- stream copy remux는 fragmented MP4(`+empty_moov+default_base_moof+frag_keyframe`)로 생성하고, 초기 재생 조각이 만들어지면 전체 파일 완성을 기다리지 않고 AVPlayer 재생 URL로 넘긴다.
- remux 전 `ffprobe`로 첫 번째 비디오 코덱을 확인하고, AVKit 재생 후보가 아닌 코덱은 음성만 자동 재생하지 않는다.
- HEVC를 MP4로 remux할 때는 Apple AVKit 호환성을 위해 `-tag:v hvc1`을 적용한다.
- FFmpeg가 없으면 호환성 도구가 필요하다는 안내를 표시한다.
- 개발/검증 앱은 프로젝트 `Tools/ffmpeg`, `Tools/ffprobe`에 실행 파일이 있으면 앱 번들 `Contents/Resources/Tools`로 복사해 런타임에서 우선 감지한다.

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
- 앱 내부 미디어 정보 패널을 실제 MKV/MP4/MOV 샘플로 검증한다.
- LGPL-only FFmpeg 번들 후보와 빌드/고지/소스 제공 절차를 정리한다.

## 실제 테스트 기록

### 2026-06-19 MKV 드래그앤드롭 테스트

관찰:

- `사이버 포뮬러 더블 원 02.mkv` 드래그앤드롭
- 같은 폴더의 MKV 6개가 재생목록으로 자동 구성됨
- 같은 이름의 `.smi` 자막 파일이 감지되고 자막 표시 상태로 전환됨
- AVKit/macOS 기본 재생 경로에서는 본편 재생 실패, `Cannot Open` 상태 확인

판단:

- 드래그앤드롭, 재생목록 구성, sidecar 자막 감지는 정상 동작한다.
- 현재 병목은 MKV 컨테이너/코덱의 AVKit 직접 재생 한계다.
- 이 케이스는 `FFmpeg 필요` 또는 `보조 처리(remux) 필요` 후보로 기록한다.

후속 조치:

- 앱은 MKV/WebM/AVI 실패 시 일반 `Cannot Open` 대신 FFmpeg/remux 호환성 처리 필요 안내를 표시한다.
- 미디어 정보 패널을 자동으로 열어 컨테이너/트랙 인식 상태를 확인하게 한다.
- 앱은 FFmpeg가 사용 가능한 환경에서 실패한 MKV를 MP4 캐시로 remux해 AVPlayer 재생을 재시도한다.
- 다음 검증에서 `ffprobe`로 비디오/오디오/자막 스트림을 확인한다.

### 2026-06-19 호환성 remux 경로 구현

구현:

- 앱 내부 `FFmpegTool` 추가: 번들 `Tools/ffmpeg`, 번들 루트 `ffmpeg`, `/opt/homebrew/bin/ffmpeg`, `/usr/local/bin/ffmpeg`, `/usr/bin/ffmpeg` 순서 탐색
- 개발 앱 번들 스크립트가 프로젝트 `Tools/ffmpeg`, `Tools/ffprobe`를 `Contents/Resources/Tools`로 복사하도록 추가
- 검증 스크립트가 시스템 PATH보다 프로젝트 `Tools`의 `ffmpeg`/`ffprobe`를 우선 사용하도록 수정
- 앱 내부 `FFmpegRemuxer` 추가: `-map 0:v:0 -map 0:a? -c copy -movflags +faststart` 방식으로 MP4 캐시 생성
- `-c:v copy -c:a aac -b:a 192k -ac 2` 방식의 오디오 호환성 보정 remux를 우선 시도하고, 실패 시 stream copy 재시도
- LGPL-only FFmpeg 로컬 빌드 스크립트 추가: `./script/build_lgpl_ffmpeg_tools.sh`
- `AVPlayerItem` 실패 시 MKV/WebM/AVI는 remux를 1회 자동 시도
- remux 성공 시 원본 파일명, 원본 sidecar 자막, 원본 재생목록을 유지하고 remux 캐시만 재생 URL로 사용
- 검증 스크립트에 `--remux` 옵션 추가

남은 과제:

- 현재 개발 환경에는 `ffmpeg`/`ffprobe`가 없어 실제 샘플 remux 결과는 아직 미검증
- `Tools` 디렉터리는 번들 슬롯만 제공하며, 실제 바이너리는 LGPL-only 빌드 후보 확인 후 별도로 배치해야 함
- `./script/build_lgpl_ffmpeg_tools.sh`를 실행해 LGPL-only FFmpeg 로컬 빌드를 확보하고 실제 MKV 샘플을 검증
- ffprobe 기반 스트림 분석으로 remux 가능/불가능 사전 판단
- AC3/FLAC/ASS/내장 자막 등 stream copy만으로 MP4 호환이 어려운 케이스 처리

### 2026-06-19 초기 지연 재검토

관찰:

- MKV 파일을 재생목록에서 선택하면 FFmpeg 호환성 준비 메시지 이후 영상 표시까지 체감 지연이 남는다.
- 무비스트류 플레이어는 MKV를 직접 디코딩하므로 파일 등록 직후 화면 표시가 가능하다.
- Glaze의 현 구조는 AVKit이 읽을 수 있는 MP4 캐시를 먼저 만들기 때문에 첫 실행 파일에서는 구조적 지연이 발생한다.

단기 조치:

- AAC/ALAC/MP3/AC3/EAC3처럼 AVKit 후보 오디오가 포함된 MKV는 stream copy를 우선한다.
- stream copy 결과는 fragmented MP4로 만들고, 초기 조각이 준비되면 전체 파일 완성을 기다리지 않는다.
- 완성되지 않은 캐시를 재사용하지 않도록 `.complete` 마커를 별도로 관리한다.

제품 판단:

- 이 조치는 첫 화면 지연을 줄이는 완화책이지, 직접 MKV 재생 엔진을 대체하지 않는다.
- 사용자 기대치가 무비스트, IINA, VLC에 맞춰져 있으므로 Player MVP 다음 기술 의사결정은 libmpv/VLC/libav 기반 직접 재생 경로 검토가 우선이다.
