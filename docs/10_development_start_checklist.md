# 개발 착수 체크리스트

작성일: 2026-06-18  
프로젝트명: 글레이즈 / Glaze

## 문서 목적

이 문서는 글레이즈의 실제 개발을 시작하기 전 확인해야 할 기준과 첫 구현 순서를 정리한다. 지금까지 정리한 제품 방향, MVP 범위, 플랫폼 전략, 수익화 필터링 기준을 개발 작업으로 연결하는 실행 문서다.

## 현재 확정 기준

- 앱 이름: 글레이즈 / Glaze
- 초기 플랫폼: macOS
- 초기 지원 기기: Apple Silicon Mac
- 최소 OS: macOS 15
- 앱 구조: SwiftUI 기반 macOS 네이티브 앱
- 초기 재생 엔진: AVFoundation / AVKit
- FFmpeg: Player MVP 직후 빠른 검증
- UI 언어: 한국어/영어
- 언어 기본값: 시스템 언어 자동 감지, 미지원 언어는 영어 fallback
- 초기 저장소: GitHub `Edwin-space/glaze`
- 실행 진입점: `./script/build_and_run.sh`

## 개발 시작 전 원칙

- 먼저 플레이어 기본기를 만든다.
- AI 자막 생성은 별도 기술 검증 트랙으로 분리한다.
- FFmpeg는 초기에 붙이지 않지만 늦추지 않는다.
- 기능 구현은 제품 가치 우선으로 진행한다.
- 무료/유료/Pro 구분은 지금 확정하지 않고, 기능별 후보 태그만 관리한다.
- App Store 배포 가능성을 기본 전제로 두되, 웹 배포/프리미엄 분리 가능성을 열어둔다.
- 한국어 사용자 경험을 기본값으로 깊게 챙기되, 글로벌 확장을 위해 영어 UI와 문서 구조를 처음부터 유지한다.

## 권장 폴더 구조

초기에는 Xcode 프로젝트 생성 후 아래 방향으로 정리한다.

```text
Glaze/
  Glaze.xcodeproj
  Glaze/
    App/
    Features/
      Player/
      Subtitles/
      Settings/
    Core/
      Media/
      Subtitle/
      Jobs/
    Resources/
      Localizable.xcstrings
  GlazeTests/
  GlazeUITests/
docs/
scripts/
```

실제 Xcode 생성 구조에 맞춰 조정하되, 플레이어, 자막, 설정, 코어 로직이 섞이지 않게 한다.

## Phase 0. 프로젝트 기반 생성

### 목표

개발 가능한 macOS SwiftUI 프로젝트를 만들고, Git/GitHub 기준으로 첫 개발 상태를 관리한다.

### 작업

- Xcode macOS App 프로젝트 생성
- Product Name: `Glaze`
- Interface: SwiftUI
- Language: Swift
- Minimum Deployment: macOS 15
- Apple Silicon 우선 실행 확인
- 한국어/영어 localization 구조 추가
- 기본 앱 실행 확인
- `.gitignore` 재검토
- SwiftPM GUI 앱 실행용 `.app` 번들 스테이징 스크립트 추가
- SwiftPM 리소스 번들을 `.app`에 함께 복사해 한국어/영어 localization이 실행 번들에서 동작하도록 수정
- Codex Run 액션 연결
- Git 커밋 및 GitHub push

### 완료 기준

- Xcode에서 앱이 실행된다.
- 빈 메인 화면이 정상 표시된다.
- GitHub에 초기 앱 프로젝트가 올라간다.
- 한국어/영어 리소스 구조가 존재한다.

## Phase 1. Player MVP

### 목표

로컬 영상 파일을 열고 AVKit 기반으로 재생할 수 있게 한다.

### 포함 기능

- 파일 열기 버튼 또는 메뉴
- 플레이어 내부 드래그앤드롭으로 영상/폴더 열기
- 같은 폴더의 영상 파일을 자동 재생목록으로 구성
- 로컬 영상 파일 선택
- `AVPlayerView` 기반 재생 표면
- `AVPlayerItem` 준비/실패 상태 감시 및 사용자 오류 표시
- 재생/일시정지
- 탐색
- 전체화면 진입
- 현재 파일명 표시
- 기본 오류 상태 표시

### 제외 기능

- MKV 완전 지원
- FFmpeg 기반 재생
- 라이브러리 관리
- 자동 자막 생성
- 자막 번역

### 완료 기준

- mp4/mov 샘플 영상이 재생된다.
- 영상 파일 또는 폴더를 플레이어 위로 끌어 놓으면 재생이 시작된다.
- 선택한 영상과 같은 폴더의 추가 영상이 재생목록에 자동 추가된다.
- 드래그앤드롭 직후 플레이어 표면이 재구성되어도 앱이 종료되지 않는다.
- 재생 준비 또는 실패 상태가 숨겨지지 않고 표시된다.
- 재생 중 앱이 멈추지 않는다.
- 파일 열기 실패 시 사용자가 이해할 수 있는 메시지가 표시된다.

## Phase 2. 외부 자막 MVP

### 목표

사용자가 SRT/VTT 자막 파일을 불러와 영상과 함께 볼 수 있게 한다.

### 포함 기능

- SRT 파일 선택
- VTT 파일 선택
- 자막 표시/숨김
- 기본 자막 스타일
- 영상 파일과 같은 이름의 자막 파일 자동 감지 검토
- 자막 없는 경우 안내 문구 설계

### 진행 중 구현

- 같은 폴더의 sidecar 자막 파일 감지
- 감지 패턴: `movie.srt`, `movie.vtt`, `movie.smi`, `movie.ko.srt`, `movie.ko.vtt`, `movie.ko.smi`, `movie.en.srt`, `movie.en.vtt`, `movie.en.smi`, `movie.original.srt`
- 영상 하단 transport controls에 자막 감지 결과 표시
- 자막 패널에서 SRT/VTT/SMI 파일 수동 불러오기
- SRT/VTT/SMI 기본 파싱 및 영상 위 자막 오버레이 표시
- transport controls와 자막 Inspector에서 자막 표시/숨김 전환
- SMI 레거시 인코딩 대응: UTF 계열, EUC-KR, CP949 계열, ISO Latin 1 순서로 읽기 시도
- SMI 기본 정리: head/style/script 제거, `<P Class=...>` 구간 기반 한국어 클래스 우선 표시
- 여러 자막 파일이 감지되거나 수동 추가된 경우 자막 패널에서 선택/전환
- 지원하지 않는 형식, 읽기 실패, 표시 가능한 cue 없음 오류를 구분해 안내
- 자막 생성은 사용자가 요청할 때만 시작한다는 UX 원칙 유지

### 자막 안내 UX 원칙

- 단순 재생 시점에 저장 위치를 묻지 않는다.
- 자막이 없을 때는 안내만 한다.
- 자막 생성 요청 시점에 저장 위치를 묻는다.
- 시스템 언어가 한국어이고 영상이 외국어로 추정되며 한국어 자막이 없으면 자막 생성 안내를 제공할 수 있다.

### 완료 기준

- 샘플 SRT/VTT/SMI 자막이 영상 위에 표시된다.
- 자막 표시/숨김이 동작한다.
- 자막이 없는 영상에서 불필요하게 흐름을 방해하지 않는다.

### 남은 개선 항목

- SMI의 복잡한 폰트/색상/위치 스타일을 원본 그대로 재현하는 기능은 MVP 이후 자막 스타일 엔진에서 검토한다.
- 여러 자막 파일의 선택/전환은 MVP 기본 UI를 구현했으며, 추후 검색/정렬/언어 필터가 필요하면 확장한다.
- 파일 읽기 오류는 기본 안내를 구현했으며, 추후 권한 문제, 파일 이동/삭제, App Sandbox 보안 범위 오류를 더 세분화한다.

## Phase 3. FFmpeg 검증

### 목표

AVFoundation/AVKit만으로 부족한 포맷과 고해상도 MKV 대응 범위를 확인하고, 경쟁 플레이어에서 기본으로 기대되는 코덱/컨테이너 대응을 Glaze의 초기 품질 기준으로 끌어올린다.

### 진행 중 구현

- FFmpeg/MKV 검증 계획 문서화: `docs/15_ffmpeg_mkv_validation.md`
- 샘플 파일 검사용 스크립트 추가: `./script/validate_media_capability.sh`
- 앱 내부 미디어 정보 패널 추가: 컨테이너, AVKit 직접 재생 가능 여부, 트랙/코덱 인식 상태 확인
- FFmpeg가 사용 가능한 환경에서 MKV/WebM/AVI 실패 시 MP4 캐시 remux 후 AVPlayer 재생 재시도
- 파일 전환/창 닫기 시 기존 AVPlayer와 호환성 준비 작업을 정리해 이전 음성이 남지 않도록 처리
- 개발 실행 스크립트가 이전 Glaze 프로세스를 정리한 뒤 새 앱을 실행하도록 보강
- FFmpeg remux 전에 비디오 코덱을 확인해 AVKit 후보가 아닌 코덱은 음성만 자동 재생하지 않도록 차단
- HEVC MP4 호환성 파일은 AVKit 표시 안정성을 위해 `hvc1` 비디오 태그를 적용
- AAC/ALAC/MP3/AC3/EAC3 오디오 파일은 불필요한 오디오 재인코딩 없이 stream copy를 우선 적용해 초기 지연을 줄임
- stream copy remux는 fragmented MP4를 생성하고, 재생 가능한 초기 조각이 준비되면 AVPlayer에 먼저 넘겨 첫 화면 지연을 줄임
- 검증 스크립트 `--remux` 옵션 추가
- 프로젝트 `Tools/ffmpeg`, `Tools/ffprobe`를 개발 앱 번들 `Contents/Resources/Tools`로 복사하는 drop-in 구조 추가
- 검증 스크립트가 프로젝트 `Tools`의 로컬 FFmpeg 도구를 우선 사용하도록 수정
- 공식 FFmpeg 소스를 `--disable-gpl`, `--disable-nonfree`로 빌드해 `Tools`에 배치하는 로컬 LGPL 빌드 스크립트 추가
- MKV/WebM/AVI 실패 시 오디오 AAC 보정 remux를 우선 시도하고, 실패하면 stream copy remux를 재시도
- MKV/WebM/AVI를 AVKit/remux 자동 재시도에서 분리해 네이티브 엔진 대상으로 즉시 라우팅
- VLC/libVLC 런타임을 개발 앱 번들에 포함해 주요 로컬 영상 포맷을 remux 없이 직접 재생
- App Store self-contained bundle, sandbox, 외부 코드 다운로드 제한 기준 확인
- FFmpeg LGPL/GPL/nonfree 빌드 옵션 리스크 기준 확인

### 현재 판단

- AVKit + FFmpeg remux 캐시는 MKV 호환성을 빠르게 넓히는 임시 해법이다.
- 사용자가 기대하는 무비스트급 즉시 재생은 MKV를 MP4로 먼저 준비하는 구조에서는 한계가 있다.
- 오늘 테스트 빌드는 VLC/libVLC 기반 직접 재생 경로를 우선 채택한다.
- App Store 최종 배포 전에는 VLC/libVLC 라이선스/서명/샌드박스 전략을 별도 검증한다.

### Phase 3B. 네이티브 MKV 엔진

### 목표

MKV/WebM/AVI/MP4/MOV 등 주요 로컬 영상 파일을 MP4 캐시로 먼저 변환하지 않고, 파일 선택 직후 직접 디코딩해 재생을 시작한다.

### 포함 기능

- 재생 엔진 라우터: 주요 로컬 영상 포맷은 VLC/libVLC 네이티브 엔진 우선, AVKit은 fallback
- SwiftUI/AppKit 재생 표면 분리
- VLC/libVLC 기반 NSView 렌더러 연결
- `./script/check_native_media_engine.sh`로 VLC 런타임 준비 상태 확인
- 새 개발 환경에서는 `./script/install_vlc_runtime.sh`로 공식 VLC arm64 런타임을 `Tools/vlc`에 배치
- Xcode/SwiftPM 직접 실행처럼 앱 번들 밖에서 실행되는 경우에도 소스 체크아웃의 `Tools/vlc`를 탐색
- 네이티브 엔진 경로에서는 대용량 파일의 AVFoundation 상세 검사가 재생 시작을 붙잡지 않도록 경량 미디어 정보로 즉시 표시
- 드래그앤드롭으로 받은 파일 URL은 VLC 재생 중 security-scoped 접근을 유지
- 파일 드롭/열기 직후에는 선택 파일 1개로 먼저 재생을 시작하고, 같은 폴더 재생목록 스캔은 백그라운드에서 확장
- VLC 런타임과 playback instance를 화면 진입 시 prewarm하고, 파일 열기 이벤트의 0.4초 중복 post는 pending 상태일 때만 재전송
- VLC 파일 캐시 옵션을 낮춰 로컬 대용량 파일의 첫 프레임 대기 시간을 줄임
- Native VLC surface는 media player를 매 파일마다 새로 만들지 않고, 같은 player에 media만 교체해 전환 비용을 줄임
- 단일 파일 드롭 시 재생목록 패널을 자동으로 열지 않아 첫 렌더 중 영상 표면 크기가 흔들리지 않게 처리
- 재생/일시정지/±15초 탐색/scrubber/볼륨 제어를 AVKit·VLC 공통 플레이어 상태로 연결 완료
- VLC 재생 시간 갱신을 외부 자막 cue 동기화에 연결 완료
- Space 재생/일시정지, 더블클릭 전체 화면, 재생 중 transport controls 자동 숨김 구현
- 다중 오디오 트랙, 내장 자막 트랙, ASS/SSA 자막 대응
- FFmpeg remux는 자동 기본 경로가 아니라 비상 fallback 또는 오디오 추출 작업으로 재분류

### 완료 기준

- MKV 파일을 열었을 때 별도 remux 준비 없이 즉시 첫 프레임이 표시된다.
- 재생목록 항목 전환 시 이전 영상의 오디오/프로세스가 남지 않는다.
- 기본 조작과 자막 오버레이가 엔진 차이와 무관하게 동작한다.

### 검증 항목

- MKV 재생 가능 여부: `Sample.mkv` 첫 화면 표시 확인
- 재생목록 전환: 샘플 MKV에서 장편 MKV로 전환 후 새 영상 표시 확인
- 종료: 창 닫기 시 앱 종료와 플레이어 release 확인
- Xcode 직접 실행 런타임 탐색: `.build/debug/Glaze`를 프로젝트 외부 작업 디렉터리에서 실행해 fatal crash 없이 프로세스 유지 확인
- 대용량 MKV: 6GB 이상 장편 MKV에서 정보 패널 원형 진행 표시가 고정되지 않고 첫 프레임 표시 확인
- 대용량 MKV 첫 프레임: 앱/재생목록 지연은 제거했으나 VLC 디코더 초기화로 약 2초대 검은 화면이 남을 수 있어 추가 엔진 튜닝 후보로 유지
- 대용량 MKV 재검증: 재생목록 패널 자동 오픈 없이 전체 영상 표면 유지, media player 재사용 구조에서 첫 영상 프레임 표시 확인
- 4K/HDR 샘플 재생 안정성
- 다중 오디오 트랙 처리
- 내장 자막 트랙 처리
- AVKit 직접 재생, remux, FFmpeg 보조 처리 필요 여부 구분
- FFmpeg 미설치/미번들 환경에서 사용자가 이해할 수 있는 안내 표시
- 오디오 추출 필요성
- FFmpeg 라이선스
- App Store 배포 영향
- 웹 배포/프리미엄 분리 가능성

### 완료 기준

- AVKit만으로 가능한 범위와 불가능한 범위가 문서화된다.
- FFmpeg 도입 여부와 도입 방식의 1차 결론이 나온다.

## Phase 3A. AI 미디어 라이브러리 기반

### 목표

글레이즈를 단일 파일 플레이어가 아니라 AI 미디어 라이브러리 플레이어로 확장할 수 있도록, 영상 파일을 `MediaAsset` 중심으로 관리하고 작품 정보/자막 준비/시청 위치를 분리한다.

### 진행 중 구현

- `MediaAsset` 기초 모델 추가: 파일 위치, 보관 소스, 작품 메타데이터, 자막 준비 상태, 시청 위치
- macOS unified compact 툴바 + edge-to-edge 영상 스테이지 + Liquid Glass transport controls로 Player Shell 전면 재설계
- 자막/재생목록/미디어 정보/AI 미디어 패널을 네이티브 SwiftUI `inspector`와 단일 `activePanel` 상태로 통합
- 상시 노출 AI 미디어 버블 제거, 툴바 패널 메뉴로 진입점 이동
- 카드형 커스텀 Inspector 제거, `Form`/`Section`/`LabeledContent`/`List`/segmented `Picker` 적용
- 콘텐츠는 어두운 미디어 스테이지, 조작은 `glassEffect`/glass button style과 SF Symbols로 분리
- 작품 정보 찾기, 자막 준비, 파일 정보 반영 액션 자리 표시
- 원본 파일 쓰기는 기본값이 아니라 명시적 액션으로 분리

### 다음 작업

- TMDB/IMDb/TVDB 등 메타데이터 공급자 추상화 설계
- sidecar metadata 저장 포맷 결정
- 포스터/줄거리/시즌/에피소드 매칭 UI 설계

## Phase 4. AI 자막 기술 검증

### 목표

단일 영상에서 오디오를 추출하고 원어 자막을 생성할 수 있는 후보 파이프라인을 검증한다.

### 후보

- Whisper 계열 모델
- Core ML 변환 모델
- whisper.cpp 계열
- Apple Speech API 가능성

### 검증 기준

- Apple Silicon 성능
- 오프라인 동작 가능성
- 한국어/영어/일본어/중국어 인식 품질
- 타임스탬프 품질
- 긴 영상 처리 가능성
- 모델 크기와 다운로드 UX
- App Store 배포 가능성

### 완료 기준

- 짧은 샘플 영상에서 SRT 형태의 원어 자막을 생성한다.
- 후보별 장단점이 문서화된다.

## Phase 5. 번역 기술 검증

### 목표

원어 자막을 한국어 자막으로 변환하는 온디바이스 우선 번역 후보를 검증한다.

### 후보

- Apple Translation API 또는 시스템 번역 기능
- TranslateGemma 같은 번역 특화 로컬 모델
- Gemma 계열 온디바이스 최적화 모델
- 기타 한국어 번역 품질이 좋은 로컬 모델

### 검증 기준

- 영어 → 한국어
- 일본어 → 한국어
- 중국어 → 한국어
- 한국어 → 영어
- 자막 줄 길이 유지
- 말투와 구어체 자연스러움
- 문맥 유지
- 처리 속도
- 모델 크기
- 오프라인 처리 가능성

### 완료 기준

- 샘플 SRT를 한국어 SRT로 변환한다.
- 오역 사례와 개선 방향이 문서화된다.
- 온라인 번역이 필요한 경우와 아닌 경우가 구분된다.

## Git/GitHub 작업 규칙

- 기능 단위로 커밋한다.
- 문서 변경과 코드 변경은 가능하면 별도 커밋으로 나눈다.
- 큰 기능을 시작하기 전 현재 상태를 커밋한다.
- GitHub `main`은 항상 실행 가능한 기준 상태로 유지한다.
- 실험 기능은 필요 시 별도 브랜치에서 진행한다.

## 다음 작업

1. Xcode 프로젝트 생성
2. macOS 15 / SwiftUI / Apple Silicon 기준 설정
3. 한국어/영어 localization 구조 추가
4. 빈 앱 실행 확인
5. Git 커밋 및 GitHub push
6. Player MVP 구현 시작
