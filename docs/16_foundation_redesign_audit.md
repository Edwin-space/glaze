# 기초 재설계를 위한 전체 감사 결과

작성일: 2026-08-10
프로젝트명: 글레이즈 / Glaze

## 문서 목적

이 문서는 `docs/01`~`docs/15` 전체와 `Sources/Glaze` 전체 코드(3,346줄)를 정독한 결과를 정리한 감사 보고서다. 목적은 두 가지다.

1. 지금까지의 진행 상황을 정확한 근거로 정리한다.
2. "기초부터 다시 설계"할 때 무엇을 바꾸고, 무엇을 유지해야 하는지 판단 기준을 제공한다.

이 문서는 결정 문서가 아니라 판단 근거 문서다. 실제 재설계 방향은 이 문서를 보고 별도로 확정한다.

## 1. 문서 vs 코드: 진행 상황 정합성

`docs/`는 매우 잘 관리되고 있다. `14_working_principles.md`의 "구현 → 검증 → 문서화 → 커밋 → 푸시" 루프가 실제로 지켜졌고, `10_development_start_checklist.md`와 `13_user_flows.md`는 코드 상태를 정확히 반영한다. 이 부분은 재설계에서도 그대로 유지할 가치가 있다.

문제는 문서가 틀려서가 아니라, 문서가 정확하게 보여주는 실제 진행 배분이 제품 방향과 어긋나 있다는 점이다.

| Phase | 문서상 상태 | 코드 근거 |
|---|---|---|
| 0. 프로젝트 기반 | 완료 | Swift Package, localization 구조 존재 |
| 1. Player MVP | 완료 | `AVPlayerView` 기반 재생 확인 |
| 2. 외부 자막(SRT/VTT/SMI) | 대부분 완료 | `SubtitleParser.swift`(232줄), `SubtitleSidecarDetector.swift` 동작 |
| 3. FFmpeg 검증 → 3B 네이티브 VLC 엔진 | "진행 중"이지만 실제로는 최근 30개 커밋 중 다수를 차지 | `NativeVLCLibrary.swift`(200줄), `NativeVLCPlayerView.swift`(156줄), `FFmpegTool.swift`(473줄, 대부분 fallback으로 강등된 죽은 경로) |
| 3A. AI 미디어 라이브러리 기반 | "진행 중" | `MediaAsset.swift`(118줄) 모델만 존재, 버튼 자리만 표시(placeholder) |
| 4. AI 자막 생성 (핵심 가치) | 착수 전 | 코드 0줄 |
| 5. 번역 (핵심 가치) | 착수 전 | 코드 0줄 |

`02_product_direction.md`가 정의한 핵심 가치는 "자막 없는 영상을 AI로 미리 자막화하고 한국어 번역까지 준비하는 것"이다. 그런데 지금까지의 33개 커밋 중 최근 15개 이상이 재생 엔진(VLC 번들링, remux, prewarm, 재생목록 캐시 재사용)에 쓰였고, 제품을 다른 경쟁 플레이어와 구분 짓는 AI 자막/번역 파이프라인은 아직 코드가 전혀 없다. `07_mvp_scope_and_decisions.md`가 원래 "AVFoundation/AVKit으로 먼저 진행하고, FFmpeg는 Player MVP 직후 빠른 검증"이라고 못박았던 항목이, 실제로는 VLC 네이티브 엔진 전체 이식이라는 훨씬 큰 작업으로 확장되어 메인 트랙을 차지한 상태다.

## 2. 코드 아키텍처 감사

### 2.1 God View: `PlayerView.swift`

`Sources/Glaze/Features/Player/PlayerView.swift`는 1,489줄로 전체 Swift 코드의 44%를 차지한다. 이 파일 하나가 다음을 모두 담당한다.

- 뷰 렌더링: header, videoSurface, playerChrome, 4개의 사이드 패널(자막/미디어정보/재생목록/AI 어시스턴트), empty state, drop overlay
- 재생 상태: `AVPlayer`, KVO observer 3종, time observer
- 재생 엔진 라우팅: AVKit vs VLC 선택, 호환성 remux 오케스트레이션
- 재생목록: 폴더 스캔, 배경 확장, 이전/다음 탐색
- 자막: sidecar 감지, 파싱 연결, cue 표시, 파일 선택/전환
- 미디어 정보 패널 상태
- AI 어시스턴트 패널 상태 (아직 기능 없음)
- 드래그앤드롭 처리
- 30개 이상의 `@State` 변수

뷰모델이나 서비스 레이어가 전혀 없다. SwiftUI View 구조체 하나가 UI, 재생 엔진 오케스트레이션, 파일시스템 접근, 네트워크 없는 프로세스 실행(FFmpeg)까지 직접 수행한다. 지금 시점에는 기능이 적어 감당되지만, AI 자막 생성/번역/작업 큐/라이브러리(`04_product_development_plan.md`가 예고한 Job Queue, Library Manager, Metadata Manager, Sync Layer)가 이 구조 위에 얹히면 유지보수가 사실상 불가능해진다.

### 2.2 재생 엔진이 3세대를 거치며 레이어가 쌓임

`15_ffmpeg_mkv_validation.md`의 기록을 보면 재생 엔진이 다음 순서로 바뀌었다.

1. AVKit 단독
2. AVKit + FFmpeg remux(MP4 캐시) — 현재도 코드에 473줄 그대로 존재
3. VLC/libVLC 네이티브 엔진 — 현재 기본 경로

문제는 2번이 "폐기"가 아니라 "비상 fallback으로 재분류"되어 코드가 그대로 남아있다는 점이다. `FFmpegTool.swift`, `FFmpegRemuxer`, `FFmpegProcessRegistry`가 여전히 빌드되고, `PlayerView.swift` 안에는 `compatibilityAttemptedPaths`, `isPreparingCompatibilityPlayback`, `prepareCompatibilityPlayback` 같은 2번 세대의 상태 변수와 로직이 3번 세대(VLC) 로직과 나란히 남아있다. 두 세대의 재생 경로 분기, 오류 메시지, 상태 플래그가 한 파일 안에서 뒤섞여 있어 어떤 코드가 실제로 실행되는 경로인지 읽어서 바로 판단하기 어렵다.

### 2.3 저수준 네이티브 바인딩이 앱 코드에 직접 노출

`NativeVLCLibrary.swift`는 `dlopen`/`dlsym`으로 `libvlc.dylib` 심볼을 런타임에 직접 로드하고 C 함수 포인터 타입을 손으로 선언한다(`@convention(c)` 12개). 번들 경로 탐색도 5가지 후보 경로를 순회하는 방식으로 구현되어 있다(`Bundle.main`, 실행파일 상대경로, 소스 체크아웃 경로 등). 이 구조는 다음 문제를 안고 있다.

- **App Store 배포 리스크 — GPL 모듈 제거 완료(2026-08-10)**: `dlopen`으로 동적 로드하는 방식 자체는 문제가 아니다. VideoLAN 공식 확인: "App Store 이용약관은 GPLv2와 양립 불가능하지만, LGPLv2.1 배포는 완전히 허용된다"(VLCKit 공식 문서). 즉 `libvlc`/`libvlccore`(LGPL-2.1)만 쓰면 App Store 배포가 가능하다.
  원래 `Tools/vlc/plugins`에 번들되어 있던 339개 플러그인은 curated LGPL 세트가 아니라 데스크톱 VLC.app을 통째로 추출한 것이었다. **전수 검사 완료**: 각 플러그인 바이너리에 VideoLAN이 빌드 시점에 직접 심어두는 라이선스 선언 문자열(`strings <plugin>.dylib | grep "Licensed under the terms of"`)을 339개 전부에 대해 실행해 GPL 선언 플러그인을 식별했다 — 추측이 아니라 각 바이너리 자체의 자기 선언 기반. FFmpeg 계열 4개(`avcodec`/`avformat`/`avutil`/`swscale`)는 별도로 FFmpeg 자체가 심는 `"lib<name> license: ..."` 문자열로 확인(`libavcodec`/`libavformat`/`libavutil`/`libswscale`는 LGPL 확인, `libpostproc`만 GPL로 확인되어 제거).
  **총 74개 제거, 265개 유지**(원래 문서가 지목했던 x264/dvdnav/dvdread/goom 5개보다 범위가 넓었다 — VideoLAN이 공식적으로 GPL로 남겨둔 인터페이스·스트리밍/트랜스코딩·DVD 모듈 카테고리 전체와, mad/faad/postproc를 추가로 확인). 상세 목록과 제거 근거는 `Tools/vlc/LICENSE-THIRD-PARTY.md`에 정리했고, LGPL이 요구하는 라이선스 고지도 그 파일로 충족한다.
  **결론**: libVLC 기술 자체를 버릴 필요는 없었고, 실제로 버리지 않았다 — 현재 dlopen 기반 구조를 유지한 채 플러그인 세트만 curate하는 방식으로 진행했다(VLCKit 전면 이전은 하지 않기로 결정). 제거 후 실제 재생 회귀 테스트(MP4/H.264+AAC, MKV/HEVC 5.1)로 정상 동작 확인.
  **법적 면책**: 이 분류는 각 플러그인의 자체 임베디드 라이선스 선언과 VideoLAN 공식 자료를 근거로 한 합리적 판단이지 법률 자문이 아니다. 실제 App Store 제출 전 라이선스 전문가 검토를 권장하며, 특히 `liba52_plugin`(업스트림 a52dec 프로젝트 자체는 GPL이나 VLC 모듈 자체 선언은 LGPL)과 `liblive555_plugin`(자체 커스텀 라이선스 텍스트)는 `LICENSE-THIRD-PARTY.md`에 별도로 플래그해뒀다.
- **라이선스 관리**: VLC 애플리케이션 자체와 위 GPL 모듈들은 GPL이지만, libvlc/libvlccore 엔진 자체와 VideoLAN이 재라이선싱한 대부분의 재생 모듈은 LGPL이다("Press Release on modules relicensing to LGPL", videolan.org). LGPL-only를 목표로 했던 FFmpeg 정책과 동일한 기준을 VLC 플러그인 선택에도 적용해야 한다.
- **소스 경로 하드코딩**: `sourceCheckoutRuntimeURL()`가 `#filePath` 기준으로 상위 5단계 디렉터리를 올라가 `Tools/vlc`를 찾는다. 이런 경로 가정은 프로젝트 구조가 조금만 바뀌어도 깨진다.

### 2.4 반대로 잘 만들어진 부분

전부 문제인 것은 아니다. 재설계에서도 유지할 만한 부분:

- `Core/Subtitle/*` (SubtitleCue, SubtitleFile, SubtitleParser, SubtitleSidecarDetector): 책임이 명확히 분리되어 있고, SMI 레거시 인코딩 처리 등 실사용 디테일이 잘 반영됨.
- `Core/DesignSystem/*`, `L10n.swift`: 작고 명확한 단일 책임 구조.
- `MediaPlaylistBuilder.swift`, `MediaInspector.swift`: 순수 함수 위주로 잘 분리됨.
- `docs/` 전체의 운영 방식 자체(문서-코드 동기화 원칙, 텍스트 인벤토리 관리): 프로세스로서는 계속 가져갈 가치가 있음.

즉 문제는 "설계 원칙이 없다"가 아니라 "원칙이 있는 모듈(Core/Subtitle, DesignSystem)과 원칙 없이 커진 모듈(PlayerView, 재생 엔진)이 공존하며 후자가 프로젝트의 중심을 차지했다"는 것이다.

## 3. 핵심 진단 요약

1. **제품 방향 드리프트**: 차별화 가치(AI 자막/번역)가 아직 코드로 존재하지 않는 상태에서, 범용 플레이어들과 경쟁하는 영역(MKV 네이티브 재생, VLC 번들링)에 개발 리소스 대부분이 쓰였다. `01_benchmark_mac_app_store.md`가 스스로 경고한 "Infuse와 정면으로 범용 플레이어 경쟁을 하지 말라"는 원칙과 실제 작업 배분이 어긋나 있다.
2. **아키텍처 부채**: `PlayerView.swift` 단일 파일에 UI/상태/오케스트레이션이 모두 몰려 있어, 다음 단계(AI 자막 생성, 작업 큐, 라이브러리)를 얹을 기반이 아니다.
3. **세대교체 잔재**: FFmpeg remux 세대의 코드/상태가 VLC 세대 위에 그대로 남아 두 경로가 뒤섞여 있다.
4. **배포 전제 미검증**: App Store 배포를 전제로 문서를 써왔지만, 지금 채택한 핵심 기술(VLC dlopen 동적 로딩)이 그 전제와 맞는지 아직 확인되지 않았다.

   > **2026-08-10 부분 검증**: "App Sandbox 활성화 상태에서 `dlopen`이 동작하는가"는 확인됐다 — Xcode 프로젝트 전환 이후 `Packaging/Glaze.entitlements`(app-sandbox 포함)를 Release 설정에 실제로 적용해 빌드하고, 실행 중인 프로세스에 `lldb`로 attach해서 번들 안의 VLC dylib에 직접 `dlopen`을 호출해봤다 — 정상적으로 핸들이 반환됐고 `dlerror`도 없었다(앱 자신의 번들/컨테이너 안 리소스는 샌드박스 예외 대상이라 예상된 결과). 이 과정에서 `Tools/vlc/lib/libvlc.dylib`/`libvlccore.dylib` 심볼릭 링크가 깨져 있던(빈 타겟) 별개의 버그도 함께 발견해 고쳤다.
   >
   > **아직 확인되지 않은 것**: 이번 테스트는 로컬 "Apple Development" 서명(Hardened Runtime 미적용, `flags=0x0`)에서 이뤄졌다. 실제 App Store 제출은 Apple Distribution 인증서로 Archive하는 별도 경로이고, 이때 Hardened Runtime + Library Validation이 더 엄격하게 적용될 수 있어 ad-hoc 서명된 VLC dylib들이 그때도 통과하는지는 실제 Archive 시점에 다시 확인해야 한다. 아래 §2.3의 GPL 플러그인 교체 작업과 함께 진행할 것.

## 4. 재설계 방향 제안

아래는 결정이 아니라 선택지와 권장 순서다.

### 4.1 범위 재정렬 (우선순위 재조정)

재생 엔진 고도화(4K 첫 프레임 지연 튜닝, 다중 오디오 트랙, 내장 자막 트랙 등 `Phase 3B` 잔여 항목)를 잠시 동결하고, 이미 "재생 가능한 수준"에서 멈춘 뒤 `Phase 4 AI 자막 생성`으로 먼저 진입하는 것을 권장한다. 이유:

- 지금 재생 품질(VLC로 MKV 첫 프레임 표시 확인됨)은 이미 "핵심 가치를 검증하기에 충분한 수준"이다.
- 제품의 존재 이유(AI 자막 사전 생성)가 코드로 한 번도 검증되지 않은 채 다음 라운드 재생 엔진 튜닝에 들어가는 것은 리스크가 크다.
- Whisper/Core ML 기반 음성 인식은 재생 엔진과 무관하게 독립적으로 검증 가능하다(`03_ai_subtitle_workflow.md`가 이미 별도 기술 검증 트랙으로 분리해 두었다).

### 4.2 아키텍처 재설계 (God View 해체)

`PlayerView.swift`를 계층으로 분리하는 것을 권장한다.

- **PlaybackController** (ObservableObject): AVPlayer/VLC 상태, KVO, 엔진 라우팅, 호환성 remux 로직을 뷰에서 분리
- **PlaylistStore**: 재생목록 스캔/전환 로직
- **SubtitleController**: 감지/파싱/표시/전환 로직 (이미 Core/Subtitle의 순수 로직은 잘 분리되어 있으므로, 여기 상태 관리만 추가)
- **MediaAssetStore**: `MediaAsset`, 메타데이터, 자막 준비 상태 — `Phase 3A`/`Phase 4` 이후 커질 라이브러리 데이터의 기반
- **PlayerView**: 위 컨트롤러들을 조합해 화면만 그리는 얇은 View로 축소

이 분리는 `06_platform_global_expansion_plan.md`가 요구한 "자막 생성 엔진과 UI의 분리", "작업 큐와 라이브러리 데이터 모델의 이식 가능성"과도 직접 일치한다. 즉 지금 재설계하면 향후 iOS/다른 플랫폼 이식 시에도 재사용 가능하다.

### 4.3 디자인 시스템 재설계: Apple 네이티브 디자인 시스템 그대로 채택

`11_ui_reference_design_direction.md`와 `Core/DesignSystem/GlazeColors.swift`는 지금까지 "글레이즈만의" 디자인 토큰을 만드는 방향이었다(`teal` 계열 강조색 하드코딩, 커스텀 `StatusBadge` 캡슐 컴포넌트 등). 이 방향을 재설계 시점에 바꾼다.

새 방향: 커스텀 디자인 토큰을 최소화하고 Apple의 표준 디자인 시스템을 그대로 따른다.

- 강조색: `GlazeColors.accent`(teal 하드코딩) 대신 시스템 tint/`Color.accentColor`, `.tint()` 사용
- 배경/패널: 이미 `.windowBackgroundColor`, `.controlBackgroundColor` 등 시스템 컬러를 쓰고 있는 부분은 유지
- 컴포넌트: 커스텀 `StatusBadge` 같은 자체 컴포넌트보다 표준 `Label`, `ControlGroup`, `Menu`, system `Material`(`.regularMaterial`, `.ultraThinMaterial`) 우선 사용
- 아이콘: SF Symbols 그대로 사용(이미 대부분 적용됨)
- 타이포그래피: 시스템 텍스트 스타일(`.title2`, `.caption` 등) 그대로 사용, 커스텀 폰트/사이즈 정의 지양
- Dark Mode, Dynamic Type, 접근성 대비는 커스텀 처리 대신 시스템 기본 동작에 맡긴다

이유:

- macOS와 iOS 양쪽에서 별도 튜닝 없이 일관된 룩을 자동으로 얻을 수 있다. iOS 확장을 전제로 하면 이 이점이 커진다.
- HIG 준수도가 높아져 App Store 심사와 사용자 신뢰 측면에서 유리하다.
- "AI가 앞에 나서지 않는다"는 `02_product_direction.md`의 브랜드 원칙과도 맞는다. 시스템 UI를 그대로 쓰면 자연스럽게 "조용한 AI" 톤이 만들어진다.

브랜드 고유 요소는 앱 아이콘, 자막 오버레이 스타일 정도로 최소화하고, 나머지 chrome은 시스템 컴포넌트에 맡긴다. `GlazeSpacing`처럼 브랜드 색상과 무관한 간격 토큰은 유지해도 무방하다.

### 4.4 iOS 확장을 전제로 한 아키텍처 재설계

기존 `06_platform_global_expansion_plan.md`는 iOS/iPadOS를 "macOS MVP 안정화 이후"의 Phase B로 미뤄뒀다. 방향이 바뀌었다: Apple Silicon 온디바이스 AI(Core ML/Neural Engine)를 macOS와 iOS 양쪽에서 활용하는 것이 제품 계획에 들어오면서, iOS 확장은 "나중에 고려할 옵션"이 아니라 지금 아키텍처 단계에서부터 반영해야 하는 전제가 됐다.

단, 이는 "지금 iOS 앱을 만든다"는 뜻이 아니라 "지금 짜는 구조가 iOS 확장을 막지 않아야 한다"는 뜻이다. 이 구분을 유지한다.

재설계 방향:

- `Package.swift`를 플랫폼 독립 모듈과 플랫폼 UI 모듈로 분리한다. 예: `GlazeCore`(라이브러리 타겟 — `MediaAsset`, 자막 파싱, AI 자막/번역 엔진 인터페이스, Job Queue, 데이터 모델. AppKit/UIKit/SwiftUI에 의존하지 않는 순수 Swift/Foundation/Core ML 레이어)와 `GlazeMac`(현재 executable 타겟, AppKit/AVKit/VLC 등 macOS 전용 재생 엔진 포함)으로 나눈다.
- 4.2에서 제안한 `PlaybackController`/`SubtitleController`/`MediaAssetStore` 같은 컨트롤러 계층도 이 분리를 염두에 두고, 플랫폼 종속 부분(AVKit/VLC 재생 표면)과 플랫폼 독립 부분(자막 파싱, 상태 모델)을 처음부터 구분해서 설계한다.
- AI 자막 생성/번역 파이프라인(Phase 4/5)은 애초에 Core ML 기반으로 검토되고 있으므로, 이 모듈은 처음부터 `GlazeCore`에 두고 macOS/iOS 양쪽 타겟에서 공유 가능하게 만든다.
- VLC/libVLC 네이티브 엔진은 macOS 전용이므로 iOS 타겟에는 들어가지 않는다. iOS에서는 AVFoundation/AVKit이 기본 재생 경로가 될 가능성이 높다 — 이 점도 재생 엔진을 `GlazeMac` 쪽에 격리해야 하는 이유 중 하나다.

### 4.5 세대 잔재 정리

`FFmpegTool.swift`/`FFmpegRemuxer`(473줄)를 완전히 제거할지, 명확한 fallback 모듈로 격리할지 결정이 필요하다. 현재는 어중간하게 "코드는 있지만 기본 경로는 아님" 상태로 `PlayerView.swift`의 여러 상태 변수와 얽혀 있다. 유지한다면 별도 `LegacyCompatibility` 모듈로 완전히 격리하고, 폐기한다면 관련 상태 변수도 함께 제거해야 한다.

### 4.6 배포 전제 재확인

VLC/libVLC dlopen 번들링 방식이 App Store 심사를 통과할 수 있는지 조기에 검증할 것을 권장한다. 이 판단이 늦어질수록, App Store 배포가 막혔을 때 되돌릴 작업(다른 재생 엔진으로 재이식)이 커진다. `09_monetization_feature_tiers.md`가 이미 "MKV 네이티브 재생은 App Store 가능성 검토 필요, Pro 분리 가능성 중간"으로 태그해 둔 것과 같은 맥락이다.

## 5. 결정 확정 사항 (2026-08-10)

4절의 권장안을 그대로 채택해 확정했다. 순서는 원래 나열 순서가 아니라, 검증 비용이 낮고 다른 결정을 뒤집을 수 있는 항목이 먼저 오도록 재정렬했다.

1. **VLC App Store 배포 가능성 + GPL 라이선스 — 완료(2026-08-10)**. `libvlc`/`libvlccore`(LGPL-2.1)만 쓰면 App Store 배포가 가능하다(2.3절). `Tools/vlc/plugins`의 339개 플러그인을 전수 검사해 GPL 선언 74개를 제거(265개 유지, curated LGPL 세트로 전환), `Tools/vlc/LICENSE-THIRD-PARTY.md`에 LGPL 고지 문서 작성, 제거 후 실제 재생(MP4/MKV) 회귀 테스트까지 완료. VLCKit 전면 이전은 하지 않고 현재 dlopen 구조를 유지하기로 결정. (`09_monetization_feature_tiers.md` 반영)
2. **재생 엔진 고도화 동결, Phase 4 AI 자막 생성으로 전환**. 4K 첫 프레임 튜닝, 다중 오디오 트랙, 내장 자막 트랙 등 `Phase 3B` 잔여 항목은 동결하고, 지금 수준(VLC로 MKV 첫 프레임 표시 확인됨)에서 AI 자막 생성 파이프라인 구현으로 넘어간다(4.1절). (`02_product_direction.md` 반영)
3. **`GlazeCore`/`GlazeMac` 모듈 분리 — 지금 아키텍처 단계에서 반영**. iOS 앱 출시 시점은 여전히 뒤에 있지만(`06_platform_global_expansion_plan.md` Phase B 유지), 구조 자체는 지금부터 플랫폼 독립(`GlazeCore`)/macOS 전용(`GlazeMac`)으로 나눠 짠다(4.4절). (`06_platform_global_expansion_plan.md` 반영)
4. **`PlayerView.swift` God View 해체 — 3번과 함께 지금 진행**. `PlaybackController`/`PlaylistStore`/`SubtitleController`/`MediaAssetStore`로 분리한다(4.2절). AI 자막 기능을 얹기 전에 끝내야, 얹는 시점에 같은 리팩터링을 두 번 하지 않는다.
5. **디자인 시스템 재설계 — Apple 네이티브 그대로 채택**(4.3절). `GlazeColors.accent`(teal 하드코딩)와 커스텀 `StatusBadge`를 시스템 tint/표준 컴포넌트로 교체한다. `GlazeSpacing`처럼 브랜드 색상과 무관한 간격 토큰은 유지한다. (`11_ui_reference_design_direction.md` 반영)
6. **FFmpeg remux 세대 잔재 — 삭제 대신 격리**(4.5절). `FFmpegTool.swift`/`FFmpegRemuxer`를 삭제하지 않고 별도 `LegacyCompatibility` 모듈로 완전히 격리한다. VLC가 처리하지 못하는 예외 케이스에 대한 안전망 가치가 아직 검증되지 않은 상태에서 완전 삭제는 되돌리기 어려운 결정이므로, 우선 격리를 통해 `PlayerView.swift`에서 두 세대의 상태 변수가 뒤섞이는 문제만 먼저 해소한다.

이 결정에 따라 `02`, `04`, `06`, `07`, `09`, `11` 문서를 함께 갱신했다. `01`, `03`, `05`, `08`, `10`, `12`~`15`는 이번 재설계 결정과 직접 충돌하는 내용이 없어 변경하지 않았다.
