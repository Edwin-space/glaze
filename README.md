# 글레이즈 (Glaze)

한 편의 영화를 어느 기기에서 보든 자막이 준비되어 있게 하는 미디어 플레이어.
macOS · iOS · iPadOS · tvOS.

## 무엇을 하는가

집에 있는 NAS에는 자막 없는 영상이 쌓인다. 글레이즈는 **맥에서 기기 안의 AI로 음성을
받아쓰고 한국어로 옮겨** 자막 파일을 영상 옆에 써 둔다. 작품 정보와 포스터도 함께
둔다. 그러면 아이폰이든 애플TV든 그 폴더를 열기만 하면 자막과 포스터가 이미 거기에 있다.

| 계층 | 역할 |
|---|---|
| **macOS** | 작업실 — 자막을 만들고, 작품 정보를 영상 옆에 쓴다 |
| **iOS · iPadOS** | 클라이언트 — 준비된 자막과 포스터로 감상 |
| **tvOS** | 클라이언트 |

영상은 VLC 엔진으로 재생한다. NAS에 있는 영상의 상당수가 Matroska(MKV)인데
AVFoundation은 그것을 열지 못하기 때문이다.

음성 인식과 번역은 **전부 기기 안에서** 이루어진다. 영상도 음성도 밖으로 나가지 않는다.

## 빌드

```bash
brew install xcodegen
script/install_vlc_runtime.sh      # 맥용 VLC 런타임 (LGPL 플러그인만 남긴다)
script/build_lgpl_ffmpeg_tools.sh  # 맥용 ffmpeg/ffprobe (GPL 구성 요소 없이)
xcodegen generate
open Glaze.xcodeproj
```

스킴은 `GlazeMac` · `GlazeiOS` · `GlazeTV` 세 개다. 테스트:

```bash
cd Packages/GlazeCore && swift test
```

`Tools/` 안의 바이너리는 저장소에 없다. 위 두 스크립트가 내려받아 만든다.

## 서드파티 코드 — LGPL 고지

글레이즈는 **libVLC**(맥은 `dlopen`, iOS·tvOS는 VLCKit으로 정적 링크)와 **FFmpeg**를
사용한다. 둘 다 **LGPL-2.1-or-later**다.

LGPL은 이 소프트웨어를 받은 사람이 **라이브러리를 고쳐 다시 링크할 수 있어야 한다**고
요구한다(§6). 이 저장소가 공개되어 있는 것이 그 조건을 만족시키는 방식이다. 고친
VLCKit이나 libVLC로 바꿔 쓰려면:

- **macOS** — `Tools/vlc`의 내용을 바꾸고 다시 빌드한다. 앱은 그 라이브러리를 실행 중에
  불러오므로, 빌드된 앱의 `Contents/Frameworks/vlc`를 직접 교체해도 된다
- **iOS · tvOS** — `project.yml`의 VLCKit 패키지를 원하는 빌드로 바꾸고 다시 빌드한다

플러그인 하나하나의 라이선스 감사 기록은 `Tools/vlc/LICENSE-THIRD-PARTY.md`에 있다.
GPL 전용 플러그인은 배포본에서 제외했고, 남긴 목록은 `Packaging/vlc-plugins.txt`가
고정한다.

Apache-2.0과 MIT로 배포되는 나머지 의존성은 각 앱 안의 **오픈소스 라이선스** 화면에
있다.

작품 정보는 TMDB에서 가져온다. 이 제품은 TMDB API를 사용하지만 TMDB가 보증하거나
인증한 것은 아니다.

## 라이선스

글레이즈의 소스 코드는 MIT다. [LICENSE](LICENSE)를 보라.

## 기록

설계 판단과 그 이유는 [`docs/`](docs)에 시간순으로 적혀 있다.
