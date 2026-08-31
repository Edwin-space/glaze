# Apple TV를 v1.0에 함께 넣기

작성일: 2026-08-24

로드맵에서 v1.1이던 Apple TV를 v1.0 동시 출시로 올린 결정에 따른 조사와 계획이다.

## 이미 된 것

- `GlazeCore`를 tvOS에서 컴파일 가능하게 분리했다. WhisperKit이 tvOS를 지원하지 않아 전사 코드만 `GlazeTranscription`으로 떼어냈다. Apple TV는 전사를 하지 않으므로 이건 우회가 아니라 실제 경계다.
- `GlazeTV` 타깃이 Apple TV 4K 시뮬레이터에서 빌드·실행된다.
- SSDP 탐색과 ContentDirectory 탐색을 `GlazeCore`로 옮겨 Mac과 Apple TV가 같은 코드를 쓴다. 시뮬레이터에서 실제 LAN의 미디어 서버 2대를 찾는 것까지 확인했다.
- Apple TV 4K(3세대, tvOS 26.6)를 Xcode에 페어링·등록하고 개발 프로파일로 설치했다. Synology/Plex 발견, Synology Browse와 MKV 재생을 실기기에서 확인했다(2026-08-31).

## 재생 엔진 — AVPlayer로는 부족하다

실제 사용자 NAS를 탐색해 형식 분포를 셌다(샘플 167개).

| 형식 | 개수 | tvOS AVPlayer |
|---|---|---|
| MKV | 113 (70%) | **재생 불가** |
| MP4 | 47 (29%) | 재생 가능 |
| 기타 | 7 | 불가 |

코덱 자체는 문제가 아니다. 기준 파일은 H.264 High + AAC LC로 tvOS가 네이티브 지원한다. **컨테이너(Matroska)만 열지 못한다.**

서버 쪽 우회도 없다. Plex의 DLNA 응답은 항목당 원본 컨테이너 하나만 제공하고 `DLNA.ORG_CI=0`(트랜스코딩 아님)으로 표시한다. 호환 프로필을 따로 주지 않는다.

즉 AVPlayer만으로 만들면 **사용자 라이브러리의 10편 중 7편이 재생되지 않는다.** 출시 가능한 상태가 아니다.

## 선택지

### A. VLCKit (권장)

VideoLAN 공식 VLCKit은 tvOS를 지원하고(정적 링크, `dlopen` 불필요) 2026-07 SPM 지원이 본체에 병합됐다. MKV를 포함해 Mac 앱이 재생하는 것을 그대로 재생한다.

- 라이선스는 LGPL-2.1 이상으로, macOS 앱이 이미 싣고 있는 libvlc와 같다. **새로운 종류의 리스크가 아니라 이미 필요한 법률 검토의 범위가 넓어지는 것이다.**
- 확인 필요: 미리 빌드된 xcframework에 GPL 전용 모듈(x264, dvdnav, mad, faad, postproc)이 포함되는지. macOS에서는 플러그인 폴더를 직접 추려냈지만 xcframework는 같은 방식으로 손댈 수 없다.

### B. AVPlayer만 — v1.0 tvOS 범위 축소

MP4/MOV/M4V만 재생하고 나머지는 "Mac에서 준비하세요"로 안내한다. 지금 이미 그렇게 동작한다. 추가 라이선스 표면이 없고 일정도 짧지만, 사용자 자신의 라이브러리 기준 70%가 안 나온다.

### C. Mac이 준비한 것만 재생

Mac에 이미 `FFmpegRemuxer`가 있어 MKV를 재인코딩 없이 MP4로 리먹스한다. Mac이 NAS에 준비본을 써두면 Apple TV는 네이티브로 재생한다. 제품 서사("Mac은 작업실, TV는 감상")와 `docs/21`의 NAS 구상에 맞지만, 준비하지 않은 영상은 TV에서 볼 수 없다.

## 남은 작업 (A 기준)

1. VLCKit SPM 의존성 추가, tvOS 플레이어를 VLCKit으로 교체
2. xcframework 포함 모듈 라이선스 확인
3. 자막: DLNA는 sidecar를 표준적으로 노출하지 않는다. Mac이 만든 자막을 Apple TV가 가져오는 경로 결정(`docs/18`의 미해결 항목)
4. ~~리모컨 조작(재생/일시정지, 탐색, 자막 선택)과 포커스 동선~~ — 터치 스크러버·10초 이동·자막 트랙/싱크/크기까지 실기기 빌드에 반영
5. 이어보기 — `PlaybackPositionStore`는 `MediaResource` 기준이라 그대로 쓸 수 있다

## UI 구조 (2026-08-24)

Plex의 Apple TV 앱 구조를 기준으로 잡되, 한 가지 조건이 다르다. **DLNA는 아트워크를 주지 않는다.** 포스터 자리에 회색 사각형을 깐 그리드는 Plex를 흉내 낸 것이지 Plex만 한 것이 아니라, 오히려 더 나쁘다.

가져온 것과 바꾼 것:

| Plex | 글레이즈 | 이유 |
|---|---|---|
| 2:3 포스터 그리드 | 16:9 타일 셸프 | 아트가 없다. 세로 프레임에 그림이 없으면 "이미지 로딩 실패"로 읽히고, 가로 프레임은 "영상"으로 읽힌다 |
| 포스터로 구분 | 제목에서 뽑은 고정 그라디언트 | 매번 같은 색이라 다시 왔을 때 알아본다. 포스터가 셸프에서 하는 일의 대부분이 이것이다 |
| 상세 화면 | 상세 화면 | 그대로 가져왔다. NAS 폴더는 한 단어만 다른 이름으로 가득하고, 세 시간짜리를 잘못 트는 것보다 한 번 더 누르는 게 낫다 |
| 정리된 제목 | `MediaTitleParser` | 가장 큰 차이다. 아래 참조 |

### 제목 파싱

NAS가 주는 것은 `Avatar.Fire.and.Ash.2025.2160p.HDR10Plus.DV.WEBRip.6CH.x265.HEVC-PSA`다. 3미터 떨어진 화면에서는 읽을 수 없고, 대신 실어 줄 포스터도 없다.

연도를 경계로 잘라내면 뒤쪽은 전부 릴리스 메타데이터다. 여기서 제목·연도·시즌/에피소드를 얻고, 화질(4K/HDR10+/Dolby Vision/Atmos)은 배지로 뽑는다. 테스트는 전부 이 NAS에서 실제로 수집한 이름으로 썼다 — 한국어 제목이 섞인 것, 사이트 접두어가 붙은 것, 대괄호로 감싼 것을 포함한다.

### tvOS에서 부딪힌 것

**커스텀 `ButtonStyle`은 버튼을 죽인다.** tvOS는 포커스된 버튼 뒤에 옅은 판을 그리는데, 카드 디자인에서는 뒤에 색 바랜 카드가 한 장 더 있는 것처럼 보인다. `.buttonStyle(.plain)`으로도 `.focusEffectDisabled()`로도 없어지지 않는다. 레이블만 반환하는 `ButtonStyle`을 만들면 판은 사라지지만 **버튼이 영영 안 눌린다** — 리모컨 선택이 무시되는 것과 구분되지 않는다. `.borderless`가 둘 다 해결한다.

**`fullScreenCover`는 한 뷰에 하나만 동작한다.** 상세용과 재생용으로 두 개를 달았더니 두 번째가 조용히 뜨지 않았고, 이것도 선택 버튼이 안 먹는 것처럼 보였다. 단일 `Route` 열거형으로 합쳤다.

## WebDAV (2026-08-26)

DLNA는 탐색이 자동이라는 장점이 있지만 두 가지를 못 한다. 재생 URL이 불투명해서(`80.mkv`, `file.mkv`) **영상 옆에 무엇이 있는지 물어볼 수 없고**, 자막도 포스터도 노출하지 않는다. Plex와 Synology 양쪽에서 확인했다.

WebDAV는 실제 경로를 준다. 폴더 목록 한 번이면 영상과 그 옆의 자막·포스터·`.nfo`가 한꺼번에 보인다.

구현한 것:

- `WebDAVPropfindParser` — `PROPFIND` 멀티스테이터스 응답. 네임스페이스 접두어는 서버마다 다르므로(`D:`, `d:`, `lp1:`) **로컬 이름으로만** 매칭한다. 접두어로 키를 잡으면 한 서버에서는 되고 다음 서버에서는 조용히 빈 목록이 된다.
- `WebDAVClient` — `Depth: 1` 목록과 작은 파일 가져오기. 쓰기는 없다. Apple TV가 NAS를 고칠 이유가 없다.
- `WebDAVCompanionFinder` — 영상 옆 파일 찾기. `film.ko.srt`와 `film-poster.jpg`는 `film.mkv`의 것이고 `film2.srt`는 아니다. 자막은 점, 아트워크는 하이픈으로 구분자가 다른 것이 관례라 둘 다 받는다.
- `WebDAVCredentialStore` — 비밀번호는 **키체인**에 둔다. `UserDefaults`는 평문 파일이고, 연결 모델에 넣으면 환경설정으로 인코딩되어 새어 나간다.
- `WebDAVBrowserModel` — `NetworkMediaBrowserModel`과 같은 모양. 같은 화면이 둘 다 굴린다.

전부 `GlazeCore`에 있으므로 Mac과 Apple TV가 같은 코드를 쓴다. tvOS 컴파일도 확인했다.

**실기 검증은 남았다.** NAS가 집에 있어 사무실에서는 확인할 수 없다. 확인할 것: Synology WebDAV 서버(기본 포트 5006/HTTPS)에 대한 `PROPFIND` 응답 형태, 한글 파일명의 퍼센트 인코딩, 큰 폴더에서의 응답 시간, HTTPS 인증서(자체 서명일 경우 처리).

### Apple TV에서 확인한 것 (2026-08-26)

로컬에 최소 WebDAV 서버(PROPFIND + Range GET)를 띄우고 시뮬레이터로 전 구간을 확인했다.

폴더 목록 → 영상 카드(제목 파싱·연도·화질 배지) → 스트리밍 재생 → **영상 옆 한국어 자막 표시**까지 이어졌다.

**자막을 붙이는 데 두 단계가 필요했다.** 어느 쪽 하나만으로는 안 된다.

1. `VLCMedia.addSlave`는 **재생 전에** 불러야 한다. 재생이 시작된 뒤 `addPlaybackSlave`를 부르면 조용히 무시되고 자막이 아예 로드되지 않는다.
2. 로드된다고 선택되지는 않는다. 우선순위 4("사용자 선택")로 붙여도 컨테이너에 들어 있는 자막 트랙이 그대로 표시된다. 트랙이 생긴 뒤 `selectTextTracks:`로 **명시적으로 골라야** 한다.

중간 상태가 특히 헷갈린다. 서버 로그에는 `.srt` 요청이 찍히므로 자막은 분명히 받아 갔는데 화면에는 내장 프랑스어가 나온다. 서버 요청만 보고 "되고 있다"고 판단하면 안 된다.

**DLNA 서버가 없을 때 NAS를 추가할 수 없었다.** 탐색이 빈손이면 화면 전체가 "미디어 서버를 찾지 못했습니다"로 바뀌는데, NAS를 손으로 추가하는 버튼이 바로 그 화면에 있었다. 지금은 목록 화면이 항상 같고, 못 찾았다는 사실은 한 줄로 알린다.

### Emby와 함께 쓰는 자막 파일명 (2026-08-27)

Mac이 만드는 자막은 `Film.<ISO 언어 코드>.srt`로 저장한다. 예를 들어 일본어 원문은 `Film.ja.srt`, 한국어 번역은 `Film.ko.srt`다. Apple TV의 WebDAV companion 탐색뿐 아니라 Emby·Jellyfin·Kodi가 이미 이해하는 관례라 별도 Glaze 서버나 Emby 플러그인이 필요 없다. 과거 `Film.original.srt`, `Film.original.ko.srt`는 읽기 호환만 유지한다.

### TestFlight 준비 상태 (2026-08-27)

- macOS 브랜드 마크를 유지한 tvOS 앱 아이콘 스택(400×240, App Store 1280×768)과 일반/와이드 Top Shelf 자산을 `GlazeTV` 자산 카탈로그에 추가했다.
- `InfoTV.plist`의 번들 ID는 `PRODUCT_BUNDLE_IDENTIFIER`를 사용해 `project.yml`을 단일 원본으로 삼는다.
- tvOS generic device Release 빌드와 자산 카탈로그 컴파일은 오류 없이 통과했다. 이미지 스택은 레이어마다 중첩 `imageset`이 필요하며, 단순히 이미지 파일을 `imagestacklayer`에 두면 `actool`이 오류를 출력하면서도 빌드 종료 코드를 0으로 내놓으므로 로그까지 확인해야 한다.
- App Store Connect의 Glaze 앱(Apple ID `6800189560`)에는 macOS와 tvOS 1.0 플랫폼이 이미 함께 등록돼 있으며 공통 번들 ID는 `com.edwin.glaze`다. tvOS 타깃에 임시로 사용하던 `com.edwin.glaze.tv`는 등록된 App ID가 아니므로 통합 앱 레코드와 같은 `com.edwin.glaze`로 정정했다.
- 개발자 팀에는 2027-07-29까지 유효한 `Distribution Managed` 인증서가 이미 있다. 인증서를 중복 생성하지 않고 Apple의 관리형 배포 인증서를 사용한다.
- Apple TV 실기기 페어링·등록과 개발 프로파일 생성은 완료했다. Organizer가 기존 관리형 인증서로 클라우드 배포 서명하도록 하며 로컬 Apple Distribution 인증서를 중복 생성하지 않는다.
- 다음 순서는 서명 아카이브 생성 → App Store Connect 업로드 → 내부 TestFlight 설치 → Synology 회귀 테스트와 사무실 Emby/WebDAV 검증이다.

### Apple TV 실기기 개발 설치 (2026-08-31)

- `거실` Apple TV 4K(3세대, tvOS 26.6)를 무선 네트워크로 페어링하고 기기 UDID를 개발자 팀에 자동 등록했다.
- `tvOS Team Provisioning Profile: com.edwin.glaze`로 Debug 실기기 빌드, 설치, 프로세스 실행을 확인했다. 기존 개발 인증서를 사용했으며 새 인증서는 만들지 않았다.
- Xcode의 Devices 창이 간헐적으로 `needs to be unlocked`를 잘못 반환했지만, 같은 연결에서 `xcrun devicectl` 설치·실행은 정상 동작했다.
- 실기기에서 Synology와 Plex SSDP 서버가 발견됐고 Synology UPnP 영상의 VLC 재생을 확인했다. 집에는 Emby가 없으므로 Emby 회귀 테스트는 사무실 NAS에서 이어간다.
- 일반 UPnP 브라우저처럼 사진·음악 루트를 노출하지 않도록, 명시적 미디어 클래스와 제한된 하위 탐색을 결합해 영상이 있는 루트만 남긴다.
- SwiftUI `Slider`는 tvOS에서 사용할 수 없어 포커스 가능한 `UIView` 스크러버를 사용한다. Siri Remote pan, 좌우 10초, VoiceOver adjustable 액션이 같은 시간 이동 경로를 쓴다.
