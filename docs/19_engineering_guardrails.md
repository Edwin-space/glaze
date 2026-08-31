# 작업 가드레일 — 반드시 확인할 것

작성일: 2026-08-20

## 문서 목적

"이 상황이면 반드시 이렇게 한다"를 모아둔 문서다. 각 항목은 **실제로 한 번 겪은 사고**에서 나왔다. 원칙을 추상적으로 적어두면 다음에 또 밟기 때문에, 어떤 일이 있었는지를 같이 남긴다.

새 세션이나 다른 에이전트가 작업을 시작하기 전에 이 문서를 먼저 읽는다. 일반 작업 원칙은 `14_working_principles.md`, 이 문서는 그중 **놓치면 조용히 깨지는 것**만 다룬다.

## 1. 빌드와 프로젝트 구조

**빌드 명령은 `xcodebuild`다. `swift build`는 앱을 만들지 않는다.**
`swift build`는 `Packages/GlazeCore`의 테스트를 돌릴 때만 쓴다. 앱은 `./script/build_and_run.sh`(내부적으로 xcodegen + xcodebuild).

**Xcode GUI에서 바꾼 설정은 즉시 `project.yml`에 반영한다.**
`Glaze.xcodeproj`는 생성물이고 gitignore 대상이다. Xcode에서 고른 번들 ID·Team은 다음 `xcodegen generate`에서 **말없이 사라진다.**
→ 실제로 번들 ID와 Team을 Xcode에서 설정한 뒤 `project.yml`에 옮겨 적어 고정했다.

**Swift 파일을 추가·삭제하면 프로젝트를 다시 생성한다.**
xcodegen은 생성 시점의 파일 목록을 스냅샷한다. `project.yml`이 그대로여도 새 파일은 인식되지 않는다.
→ `VesselSignatureView.swift`를 추가했더니 "cannot find in scope"로 빌드가 깨졌다. 지금은 `build_and_run.sh`가 `Sources/GlazeMac` 변경을 감지해 자동 재생성하지만, **Xcode에서 직접 빌드할 때는 수동으로** `xcodegen generate`가 필요하다.

**체감 속도는 Release로 판단한다.**
Debug는 `-Onone`이고 SwiftUI가 프레임마다 훨씬 많은 일을 한다. `./script/build_and_run.sh release`.

## 2. 조용히 실패하는 것들

이 절의 항목은 **빌드가 성공하고 에러도 없는데 결과만 틀린** 경우다. 육안 확인 외에는 잡을 방법이 없다.

**에셋 카탈로그의 accent color는 빌드 설정이 있어야 적용된다.**
`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`이 없으면 `Info.plist`에 `NSAccentColorName`이 들어가지 않고, `Color.accentColor`가 **경고 없이 시스템 파랑으로 폴백**한다.
→ 브랜드 앰버를 적용했다고 보고했지만 실제 화면은 파란 버튼이었다.

**유리(글래스) 표면 뒤에는 반드시 색이 있어야 한다.**
어두운 배경 위의 글래스는 그냥 회색 판으로 렌더링된다. `GlazeAmbientBackdrop` 없이 `glazeGlass`만 쓰면 효과가 보이지 않는다.

**버전 번호는 `project.yml`에만 적는다.**
`CFBundleShortVersionString`이 여러 번 `0.1.0`과 `1.0` 사이를 오갔다. 원인은 값에 주인이 없었다는 것이다 — `Info.plist`에 리터럴로 박혀 있으니 패키징 파일을 건드리는 작업마다 값이 흔들렸다.

지금은 `Info.plist`가 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`을 쓰고 실제 값은 `project.yml`에 있다. 버전을 올릴 때 `Info.plist`는 건드리지 않는다.

**기능의 진입 조건을 한 경로에만 매달지 않는다.**
자막 번역은 `pendingTranslationRequest`가 있을 때만 화면에 나타났는데, 그 값은 **컨테이너에서 내장 트랙을 추출하는 경로에서만** 설정됐다. 그래서 영상 옆에 `.srt`를 두거나 AI로 자막을 만든 사용자에게는 번역 기능이 아예 존재하지 않았다. 빌드도 되고 테스트도 통과했다.

원인은 요청 타입이 `sourceTrack: EmbeddedSubtitleTrack`이었다는 것 — 자료구조가 "어디서 왔는가"를 요구하니 다른 출처는 자기를 설명할 방법이 없었다. 지금은 `SubtitleTranslationSource(displayName:languageCode:)`로 바뀌어 세 경로 모두 통과한다.

기능을 붙일 때는 그 기능에 도달하는 **모든** 경로를 세어본다.

**SwiftUI 앱 생명주기에서 AppKit 문서 열기 델리게이트는 호출되지 않는다.**
`AppDelegate`에 `application(_:openFiles:)`가 구현되어 있고 `Info.plist`에 `CFBundleDocumentTypes`도 선언되어 있었지만, 실행 중인 글레이즈에 파일을 열어도 아무 일도 일어나지 않았다. 로그를 넣어 보니 그 메서드가 **한 번도 호출되지 않았다**. SwiftUI `App`은 열기 이벤트를 자기 경로로 가로채 `onOpenURL`로 전달한다.

빌드도 되고 코드도 그럴듯해 보이는 종류의 실패다. 이벤트 핸들러를 붙였으면 실제로 불리는지 로그로 확인한다.

**AppKit 열기 이벤트는 기본적으로 새 창을 만든다.**
`onOpenURL`을 붙인 뒤에도 화면은 그대로였다. `ObjectIdentifier(playback)`를 로그에 찍어 보니 `PlayerView`가 두 개였다 — 두 번째 창이 새로 생겨 그쪽에서 파일이 재생되고, 사용자가 보고 있던 창은 그대로였던 것이다. `handlesExternalEvents`로 기존 창이 이벤트를 받도록 선언해야 한다.

"컨트롤러 인스턴스 주소를 로그에 찍는다"는 이런 종류의 문제에 가장 빠른 진단이다.

**Debug 빌드로는 절대 볼 수 없는 버그가 있다. 출시 전 Release로 한 번은 돌린다.**
Debug는 샌드박스가 꺼져 있고 Release만 켜져 있다. 그래서 샌드박스 권한 문제는 **출시하는 구성에서만** 나타난다.

실제로 걸린 것: 영상을 열면 그 파일 하나에만 접근 권한이 생긴다. 옆에 있는 `.srt`는 못 읽는다 — 사이드카 자막이라는 기능 전체가 출시 빌드에서 동작하지 않았고, 화면에는 "자막 파일을 읽을 수 없습니다"라고만 떴다. Debug에서는 몇 달 동안 멀쩡했다.

macOS가 이 상황을 위해 문서화한 **related items**를 시도했다 — `Info.plist`에 자막 타입을 `NSIsRelatedItemType`으로 선언하고 `NSFileCoordinator`에 영상을 `primaryPresentedItemURL`로 지목한 프리젠터를 붙이는 방식이다. **동작하지 않았다.** 서명된 샌드박스 Release 빌드에서 `film.en.srt`도, 영상과 기본 이름이 정확히 같은 `film.srt`도 여전히 읽지 못했다.

실제로 통하는 방법은 **폴더에 대한 security-scoped bookmark**를 열기 패널로 한 번 받아 보관하는 것이다. 사용자에게 보이는 동작이 바뀌는 변경이라 아직 넣지 않았다. 넣을 자리는 `RelatedFileAccess`다 — 읽기와 쓰기가 이미 그리로 모인다.

이런 실패는 **통합 로그에 남지 않는다.** `log show`로 샌드박스 거부를 찾아봤지만 실패하는 빌드에서도 아무것도 찍히지 않았다. 화면을 보는 것 말고 판별 방법이 없었다.

**테스트 영상은 `test file/testmedia.mkv`를 쓴다.**
합성 영상으로만 검증하면 행복 경로만 지나간다. 이 기준 파일은 실제로 사람들이 보는 모양이다 — 내장 ASS 자막, 첨부 폰트, 일본어 음성, 프랑스어 자막, 51분, 1.7GB. 여기에 물려서 처음 드러난 결함이 세 개다(자막 이중 렌더링, MKV 오디오 추출 실패, 음성 언어 오탐). 합성 클립은 그 파일이 줄 수 없는 것이 필요할 때만 만들고, 무엇을 왜 썼는지 밝힌다. `.gitignore`에 있으므로 커밋하지 않는다.

**Glaze 프로세스가 여럿 떠 있을 수 있다. 캡처 대상을 PID로 못 박는다.**
사용자가 Xcode에서 자기 빌드를 돌리고 있을 수 있다. `CGWindowListCopyWindowInfo`를 이름으로만 걸러 창을 잡으면 **남의 창을 캡처하고 자기 앱을 봤다고 착각한다.** 실제로 그렇게 해서, 내 앱은 정상인데 스크린샷은 사용자의 세션을 보여줘서 한참 헤맸다. 창을 찾을 때는 `kCGWindowOwnerPID`로 내가 띄운 프로세스만 남긴다.

## 3. UI 검증

**UI를 바꿨으면 실행 중인 앱을 캡처해서 눈으로 확인한다.**
이 세션에서 가장 많이 반복된 실패다. 코드에 API가 들어갔다고 화면에 반영된 것이 아니다. 코드만 grep해서 "적용 완료"라고 보고했다가 실제로는 바뀌지 않은 일이 여러 번 있었다.

```bash
./script/build_and_run.sh --bundle          # 빌드
open -n <앱경로> --args <영상경로>            # 실행
osascript -e 'tell application "System Events" to tell (first application process whose unix id is <pid>) to get {position, size} of window 1'
screencapture -x -R<x>,<y>,<w>,<h> out.png  # 창 영역만 캡처
```

주의할 점:

- Glaze 프로세스가 여러 개일 수 있다(Xcode 디버거에 물린 것 포함). `unix id`로 특정한다.
- 화면이 잠들면 캡처가 검게 나온다. `caffeinate -u -t 20`으로 깨운다.
- Mac이 잠금 상태면 창을 열거나 캡처할 수 없다. **암호 입력으로 잠금 해제는 하지 않는다** — 검증을 멈추고 사용자에게 알린다.
- 컨트롤이 자동 숨김되는 화면은 스페이스바로 일시정지시키면 컨트롤이 유지된다.

**개인 영상으로 UI 검증하지 않는다.**
번들된 ffmpeg로 테스트 영상을 만든다(디코드 전용 빌드라 비디오는 `mpeg4`로 인코딩). 자막 테스트가 필요하면 SRT를 MKV에 먹스한다.

## 4. 라이선스

**`Tools/vlc`를 갱신하면 플러그인 라이선스를 전수 재검사한다.**
VLC는 각 플러그인 바이너리에 자체 라이선스 선언을 심는다.

```bash
strings <plugin>.dylib | grep -i "Licensed under the terms of"
```

GPL 선언이 하나라도 남으면 App Store 배포가 막힌다. 2026-08-10에 339개 중 74개를 제거했다(`Tools/vlc/LICENSE-THIRD-PARTY.md`).

**모델·라이브러리를 도입하기 전에 라이선스 원문을 직접 확인한다.**
이름이나 인지도로 판단하지 않는다. NLLB-200은 CC-BY-NC(비상업), 국내 한국어 LLM도 상당수가 비상업 조항을 둔다. 유료 앱에는 쓸 수 없다.

**모델 가중치를 앱이 대신 내려받지 않는다.**
외부 LLM은 사용자가 직접 받은 것을 가리키게만 한다. 우리가 받아오면 사실상 배포자가 된다(`03_ai_subtitle_workflow.md`).

## 5. 코드 규칙

**Apple 프레임워크가 non-Sendable이면 한 액터 안에 가둔다.**
`TranslationSession`은 non-Sendable 클래스이고 Swift 6 동시성 감사를 거치지 않았다. 액터 경계를 넘기려 하면 "sending ... risks causing data races"가 난다. 세션 작업 전체를 MainActor에 두고 `@preconcurrency import`를 쓴다. 컨트롤러와는 Sendable 스냅샷만 주고받는다.

**자막 번역은 큐 단위로 하지 않는다.**
반드시 `SubtitleSegmenter`로 문장을 재조립한 뒤 번역하고 `SubtitleRedistributor`로 되돌린다. 큐는 표시 단위이지 언어 단위가 아니다(`03_ai_subtitle_workflow.md`).

**비동기 결과를 반영하기 전에 대상이 아직 유효한지 확인한다.**
사용자가 다른 영상으로 넘어간 뒤 도착한 결과가 새 영상에 덮어써지면 안 된다.

**재생 엔진의 성공 여부를 미디어 정보로 대신하지 않는다.**
VLC로 재생하는 파일을 AVFoundation 경량 경로로만 검사했더니 영상은 정상인데 정보 패널은 비어 있는 조용한 실패가 생겼다. 파일명·컨테이너·크기·비트레이트·해상도·트랙은 재생 엔진과 독립된 ffprobe 검사 결과를 우선 사용하고, 도구를 쓸 수 없을 때만 AVFoundation 경량 검사로 fallback한다.

## 6. 사용자 문구

**구현 용어를 사용자 화면에 노출하지 않는다.**
프레임워크·코덱·API 이름은 라벨에도 설명에도 쓰지 않는다.

**한 화면에 같은 라벨이 두 번 나오면 결함이다.**
자막 패널에 "출력"이 두 번 있었다(사용 가능한 자막 상태 / 번역 출력 형식).

**이름만으로 뜻이 통하지 않는 컨트롤에는 `?` 설명을 붙인다.**
`GlazeHelpLabel`을 쓴다. 툴팁으로 대신하지 않는다 — 마우스를 올려야만 뜨고, 있다는 것이 드러나지 않고, 키보드로 접근할 수 없다. 자명한 항목에는 붙이지 않는다(`12_service_text_inventory.md`).

## 7. Git

**`git stash`로 베이스라인을 테스트하지 않는다.**
디버깅 중 `git stash`를 썼다가 커밋하지 않은 세션 작업 전체가 사라질 뻔했다. 즉시 `git stash pop`으로 복구했지만 반복하지 않는다. 비교가 필요하면 별도 브랜치나 worktree를 쓴다.

**되돌릴 수 없는 명령 전에 `git status`를 확인한다.**
`checkout`/`restore`/`reset`/`clean`, 저장소 안의 `rm -rf`가 해당된다.

**창이 안 보일 때 원인은 두 가지다. 순서대로 가른다.**

`CGWindowListCopyWindowInfo`가 창을 반환하지 않고 손쉬운 접근성이 "유효하지 않은 인덱스"를 내는 상황을 코드 회귀로 오진해서, 멀쩡한 변경을 오래 되돌렸다 붙였다 했다. 실제로는 서로 다른 두 원인이 겹쳐 있었다.

1. **화면이 꺼져 있다.** 전체 화면을 캡처해서 완전히 검으면 잠금·절전이다. `caffeinate -u`로 디스플레이는 깨울 수 있지만 **잠금은 풀리지 않는다** — 그때는 GUI 검증을 멈추고 사용자에게 알린다. 비밀번호는 입력하지 않는다.
2. **`open -n`으로 띄웠다.** 같은 번들 ID의 두 번째 인스턴스는 **창 없이** 뜨는 경우가 있다. 프로세스는 살아 있고 메뉴 막대도 가져가지만 창은 끝내 그려지지 않는다. `Settings`(⌘,) 창은 정상적으로 열리므로 SwiftUI 씬 자체는 멀쩡하다 — `WindowGroup`만 창을 만들지 않는다.

두 번째를 한 줄로 가르는 방법: **인자 없이 `open`으로 띄워 본다.** 창이 나오면 코드 문제가 아니다.

`script/build_and_run.sh run`은 이제 `open -n`을 쓰지 않는다.

**`pkill -x Glaze`는 남의 디버그 세션을 죽인다.**
`build_and_run.sh`가 매 빌드마다 이름으로 프로세스를 죽이고 있었다. Xcode 디버거에 물린 앱까지 예고 없이 함께 종료된다. 지금은 이 스크립트가 빌드한 실행 파일 경로와 일치하는 프로세스만 종료한다.

경로 비교에는 함정이 하나 더 있다. 저장소가 한글 디렉터리 안에 있는데 커널이 보고하는 경로는 **NFD(분해형)**, 셸이 들고 있는 문자열은 **NFC(결합형)**라 `pgrep -f "$APP_BINARY"`가 조용히 아무것도 못 찾는다. 양쪽을 정규화한 뒤에 비교해야 한다.

**`open APP 파일`은 파일을 그 앱으로 열지 않는다.**
`-a` 없이 쓰면 `open`은 인자를 각각 독립적으로 연다 — 앱은 앱대로 뜨고, 영상은 그 확장자를 현재 담당하는 **다른 앱**으로 간다. 테스트 대상 빌드로 열려면 `open -a "$APP" 파일`이어야 한다.

**다른 사람의 프로세스를 죽이지 않는다.**
Xcode 디버거에 물린 앱 프로세스가 있을 수 있다. `pkill -x Glaze`는 그것까지 죽인다. PID를 특정해서 종료한다.

## 8. 아직 해결되지 않은 것

### tvOS 실기기와 미디어 탐색

**tvOS에는 SwiftUI `Slider`가 없다.**
컴파일러가 명시적으로 unavailable 처리한다. Apple TV 재생바는 포커스 가능한 `UIView`와 `UIPanGestureRecognizer`로 만들고, 방향키·VoiceOver adjustable 액션도 같은 seek 경로로 합친다. 단순 `ProgressView`는 표시만 가능하고 Siri Remote로 조작할 수 없다.

**UPnP 컨테이너 클래스만 믿으면 사진과 비디오를 구분하지 못한다.**
Synology는 사진과 비디오 루트를 모두 `object.container.storageFolder`로 보낸다. 번역된 폴더명(`사진`, `비디오`)을 하드코딩하지 말고 명시적 audio/image 클래스는 제외한 뒤, 모호한 루트는 깊이·개수 제한을 둔 병렬 Browse로 실제 `video/*` 리소스 존재를 확인한다.

**Apple TV 빌드 ID와 설치 ID는 다르다.**
`xcodebuild -destination`에는 기기 UDID(`00008110-...`)를 쓰고 `xcrun devicectl --device`에는 CoreDevice 식별자(`FBC69999-...`)를 쓴다. 첫 실기기 빌드는 `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`이 필요하다. Codex 샌드박스 안의 `devicectl`은 CoreDeviceService XPC가 끊긴 것처럼 보일 수 있으므로 개발 도구 권한으로 실행해 구분한다.

작업 전에 상태를 확인해야 하는 항목이다.

- ~~샌드박스에서 사이드카 자막을 읽지 못한다~~ **해결(2026-08-24).** `~/Movies`는 `com.apple.security.assets.movies.read-write`로, 그 밖의 폴더는 자막을 못 읽을 때만 한 번 묻는 security-scoped bookmark로 처리한다. related items 단독으로는 통하지 않았다(위 §3).
- Distribution(Developer ID / App Store) 서명 Archive에서 VLC dylib의 `dlopen`이 통과하는지는 아직 모른다. 사용자의 Apple ID가 필요해서 진행하지 못했다.
  - **샌드박스 자체는 통과했다(2026-08-24).** Release 구성(`ENABLE_APP_SANDBOX: YES`, `Glaze.entitlements`)으로 빌드해 팀 서명(`JBN99YZ7KN`)이 붙은 번들이 MKV를 VLC로 재생하는 것까지 확인했다. 헬퍼(`ffmpeg`/`ffprobe`)에도 `com.apple.security.inherit`가 정상적으로 붙는다. 남은 미지수는 배포용 인증서로 다시 서명했을 때뿐이다.
- 그림 자막(PGS·VobSub)은 감지만 하고 읽지 못한다. OCR 미지원 — MVP 제외 범위(`07_mvp_scope_and_decisions.md`)라 v1.0 결격 사항은 아니다.
- 번들된 VLC 플러그인 265개의 라이선스는 바이너리 증거로 정리했지만(`Tools/vlc/LICENSE-THIRD-PARTY.md`) 법률 검토는 받지 않았다. 출시 전 확인이 필요하다.

## 9. v1.0 완료 판정 (2026-08-24)

`07_mvp_scope_and_decisions.md`의 MVP 포함 범위 6개 항목을 출시 구성(Release · 샌드박스 · 팀 서명)에서 `test file/testmedia.mkv`로 확인했다.

| MVP 항목 | 상태 |
|---|---|
| 1. macOS 네이티브 앱 | 충족 — SwiftUI, Apple Silicon, 한/영, 설정 창 |
| 2. 기본 영상 플레이어 | 충족 — 열기·재생·탐색·전체화면·볼륨·현재 파일 |
| 3. 외부 자막 로딩 | 충족 — SRT·VTT·SMI, 표시/숨김, 크기·위치·배경 |
| 4. AI 자막 생성 | 충족 — MKV 포함, 컨테이너 음성 언어 사용 |
| 5. 한국어 번역 자막 | 충족 — 번역만·원문+번역, 시스템 번역과 온디바이스 AI |
| 6. 자막 저장/재사용 | 충족 — 영상 옆/앱 내부 선택, 재열림 시 자동 연결 |

미해결로 남은 두 가지는 코드 문제가 아니다. 배포 인증서 재서명은 Apple ID가 필요하고, VLC 라이선스는 법률 검토가 필요하다.
