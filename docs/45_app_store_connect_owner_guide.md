# 맥 심사 제출 — 계정 소유자가 직접 할 일

작성일: 2026-09-15 · 대상: macOS `1.0 (10)` · 출시 방식: **심사 통과 후 직접 출시**

동의·선언·제출처럼 계정 소유자가 책임지는 단계만 모았다. 위에서부터 순서대로 진행하면 된다.
App Store Connect의 메뉴 이름은 계정 언어와 시기에 따라 조금 다를 수 있다.

---

## 0. 사이트 켜기 (GitHub, 5분)

처리방침·지원 URL이 열려야 App Store Connect에 입력할 수 있다. 사이트 파일과 배포
워크플로(`.github/workflows/pages.yml`)는 저장소에 올라가 있고, **Pages 설정만 꺼져 있다.**

1. https://github.com/Edwin-space/glaze/settings/pages 를 연다
2. **Build and deployment → Source**를 **GitHub Actions**로 바꾼다
3. https://github.com/Edwin-space/glaze/actions 에서 **Pages** 워크플로를 연다.
   실행 기록이 없거나 실패했다면 **Run workflow**를 누른다
4. 초록색으로 끝나면 아래 네 주소가 열리는지 확인한다

| 페이지 | 주소 |
|---|---|
| 소개 (마케팅 URL) | https://edwin-space.github.io/glaze/ |
| 개인정보 처리방침 | https://edwin-space.github.io/glaze/privacy/ |
| 이용약관 | https://edwin-space.github.io/glaze/terms/ |
| 지원 | https://edwin-space.github.io/glaze/support/ |

> 처리방침과 지원 페이지의 문의 창구는 GitHub Issues로 되어 있다. 이메일을 넣고 싶으면
> `site/privacy/index.html`, `site/support/index.html`의 "문의" 부분을 바꾸면 된다.

---

## 1. 앱 정보 URL 바꾸기

**App Store Connect → 앱 → 글레이즈**

1. 왼쪽 **일반 → 앱 정보**
   - **개인정보 처리방침 URL**: `https://edwin-space.github.io/glaze/privacy/`
2. 왼쪽 **macOS 앱 → 1.0 제출 준비 중**
   - **지원 URL**: `https://edwin-space.github.io/glaze/support/`
   - **마케팅 URL**: `https://edwin-space.github.io/glaze/`
3. 오른쪽 위 **저장**

> 지금은 처리방침 URL이 GitHub 파일 보기 주소(`.../blob/main/docs/PRIVACY.md`)로 들어가 있을 것이다.
> 그 파일은 새 사이트로 가는 안내만 남기고 정리했으니 반드시 바꿔야 한다.

---

## 2. 빌드 연결

**macOS 앱 → 1.0 제출 준비 중 → 빌드**

1. 연결된 빌드 `1.0 (6)` 옆 **−** 로 뺀다
2. **+** 를 누르고 **1.0 (10)** 을 고른다
   - 목록에 없으면 아직 처리 중이다. 처리가 끝나면 이메일이 온다
3. 수출 규정 질문이 뜨면 **아니요(암호화를 쓰지 않음 / 면제 대상)**
   - plist의 `ITSAppUsesNonExemptEncryption = false` 덕분에 보통 묻지 않는다
4. **저장**

> 빌드 10 이후 저장소에서 바뀐 것은 사이트, 문서, 아이폰의 처리방침 링크, 테스트용 예시 주소뿐이다.
> 맥 앱의 동작은 같으므로 **맥은 빌드 10으로 제출한다.**

---

## 3. App Privacy — 게시

**일반 → 앱 개인정보 보호**

1. 입력 상태가 **데이터를 수집하지 않음(Data Not Collected)** 인지 확인한다
   - 아니라면 **시작하기 → "이 앱에서 데이터를 수집합니까?" → 아니요**
2. 오른쪽 위 **게시(Publish)** 를 누른다

**"수집하지 않음"이 맞는 이유** (애플 기준으로 "수집"은 개발자나 제3자 파트너가 데이터를
실시간 처리에 필요한 시간보다 오래 기기 밖에서 보관하는 것이다)

- 분석·광고·크래시 수집 SDK가 없다
- TMDB에는 영상 제목만 보내며 이용자를 식별하는 정보는 없다. 이용자가 넣은 키로 요청할 때만 간다
- Hugging Face에는 모델 파일 다운로드 요청만 간다
- NAS 정보는 기기의 키체인에만 있다

---

## 4. 콘텐츠 권한 (Content Rights) 선언

**일반 → 앱 정보 → 콘텐츠 권한** (처음 제출할 때 팝업으로 뜨기도 한다)

질문: **"앱이 제3자 콘텐츠를 포함하거나, 표시하거나, 이용합니까?"**

| 선택 | 이유 |
|---|---|
| **예** | 정보 패널이 TMDB의 포스터와 줄거리를 표시한다 |

이어지는 질문 **"필요한 권리를 보유하고 있습니까?"** → **예**

- TMDB API 약관은 출처 표시를 조건으로 사용을 허락한다. 앱과 사이트에 표시 문구가 있다
  ("This product uses the TMDB API but is not endorsed or certified by TMDB.")
- 이용자가 재생하는 영상은 이용자 본인의 파일이다. 앱이 제공하는 콘텐츠가 아니다.
  이용자 책임은 이용약관 3조에 적었다

---

## 5. 연령 등급 설문

**일반 → 앱 정보 → 연령 등급 → 편집**

앱 자체에는 콘텐츠가 들어 있지 않다. 이용자가 가진 파일을 재생하는 도구다. 아래는 그 기준으로
정리한 권장 답이다.

| 항목 | 권장 답 | 이유 |
|---|---|---|
| 자녀 보호 기능(Parental Controls) | 아니요 | 없음 |
| 연령 확인(Age Assurance) | 아니요 | 없음 |
| 제한 없는 웹 접근(Unrestricted Web Access) | **아니요** | 웹 브라우저가 없다. 이용자가 지정한 서버와 TMDB API에만 접속한다 |
| 사용자 생성 콘텐츠(User-Generated Content) | 아니요 | 이용자끼리 콘텐츠를 공유하는 기능이 없다 |
| 메시지·채팅 | 아니요 | 없음 |
| 광고 | 아니요 | 없음 |
| 욕설·저속한 유머 | 없음 | 앱에 들어 있는 콘텐츠 없음 |
| 공포 | 없음 | 〃 |
| 알코올·담배·약물 | 없음 | 〃 |
| 의료·건강 정보 | 없음 | 〃 |
| 성적 콘텐츠·노출 | 없음 | 〃 |
| 폭력(만화·사실적·잔혹) | 없음 | 〃 |
| 도박·모의 도박·확률형 아이템 | 없음 | 〃 |
| 경품·콘테스트 | 아니요 | 〃 |

예상 결과: **4+**

> TMDB 검색은 `include_adult=false`로 요청한다(`TMDBMetadataProvider.swift:113`). 그래서 성인
> 작품의 포스터나 줄거리가 앱 화면에 나오지 않는다.

---

## 6. 스크린샷과 문구

**macOS 앱 → 1.0 제출 준비 중 → 앱 미리보기 및 스크린샷**

- 크기: **2880×1800** (또는 2560×1600 · 1440×900 · 1280×800, 16:10)
- 1장 이상, 최대 10장. 권장 구성: 재생 화면 / 자막 생성 / 정보 패널 / 네트워크 폴더 / 설정 → 키보드
- **주의 1:** 영상 장면은 저작권이 없는 것을 쓴다. 예를 들면 Blender 재단의 공개 영화처럼 CC 라이선스인 작품
- **주의 2:** NAS 주소, 서버 이름, 개인 폴더 이름이 보이지 않게 한다 (`docs/28` §6)

설명·키워드·부제는 9월 7일에 입력한 것을 유지한다. 부제는 `맥에서 자막을 만들고, 어디서나 봅니다`다.
설명에 "시놀로지 로그인" 같은 **맥에 없는 기능이 적혀 있지 않은지만** 다시 본다.
맥은 NAS를 WebDAV와 DLNA로만 연결한다. 없는 기능이 설명에 있으면 심사 거절 사유(2.3.1)가 된다.

---

## 7. 심사 정보와 메모

**macOS 앱 → 1.0 제출 준비 중 → 앱 심사 정보**

| 칸 | 입력 |
|---|---|
| 로그인 필요 | **체크 해제** (계정이 없는 앱) |
| 연락처 | 이름, 전화번호, 이메일 (심사팀만 본다) |
| 첨부 파일 | 선택. 저작권 문제가 없는 짧은 영상 하나를 올려 두면 심사자가 바로 확인할 수 있다 |

**메모** (영어로 쓴다. 그대로 붙여 넣어도 된다)

```
Glaze is a video player for files the user already owns. There is no account,
no sign-in, and no content provided by the app.

HOW TO TEST WITHOUT ANY SERVER
1. Launch Glaze and choose File > Open Video… (⌘O), or drag any .mkv/.mp4 file onto the window.
2. Playback: Space play/pause, ←/→ skip 10 s, ↑/↓ volume. All keys can be changed
   in Settings > Keyboard.
3. Subtitles: open the subtitle panel (View > Subtitles, ⌘1) and generate subtitles.
   The first run downloads the on-device speech model from Hugging Face; audio and
   video never leave the Mac. Translation uses Apple's Translation framework.

OPTIONAL FEATURES THAT NEED THE USER'S OWN SETUP
- Network media: WebDAV servers (Settings > Network) and DLNA/UPnP servers found on
  the local network. These are the user's own home servers, so no demo server is provided.
- Film information: uses TMDB and requires the user's own TMDB API key
  (Settings > Film information). The app works fully without it.

ENTITLEMENTS
- files.user-selected.read-write and assets.movies.read-write: subtitle (.srt) and
  film information (.nfo, poster) files are saved next to the video the user opened,
  so other devices find them in the same folder.
- network.client: the user's own media servers, TMDB, and the one-time speech model download.
- Bundled ffmpeg/ffprobe helpers are sandboxed and inherit the app sandbox.

OPEN SOURCE
The app uses libVLC and FFmpeg under LGPL-2.1. Full source code is public at
https://github.com/Edwin-space/glaze, and notices are in Glaze > Open Source Licenses.
```

> 메모 속 메뉴 이름(Open Video…, View > Subtitles, Settings > Keyboard / Network / Film information,
> Open Source Licenses)은 앱의 영어 문자열(`en.lproj/Localizable.strings`)과 맞췄다.

---

## 8. 출시 방식 — 직접 출시

**macOS 앱 → 1.0 제출 준비 중 → 버전 출시(Version Release)**

- **이 버전을 수동으로 출시(Manually release this version)** 를 고른다

심사를 통과하면 상태가 **개발자 출시 대기 중(Pending Developer Release)** 이 된다.
그 뒤 원하는 때에 **이 버전 출시** 를 누르면 판매가 시작된다.

---

## 9. 제출

1. **macOS 앱 → 1.0 제출 준비 중** 에서 빨간 경고가 없는지 본다
2. 오른쪽 위 **심사에 추가(Add for Review)** → **심사에 제출(Submit to App Review)**
3. 상태가 **심사 대기 중(Waiting for Review)** 으로 바뀌면 끝

> iOS·tvOS 버전은 같은 앱 레코드 안에 따로 있다. 이번에는 **macOS만** 제출한다.
> 다른 플랫폼 버전에는 손대지 않아도 맥 제출에 영향이 없다.

---

## 체크리스트

- [ ] 0. GitHub Pages 켜고 네 주소 확인
- [ ] 1. 처리방침·지원·마케팅 URL 교체
- [ ] 2. 빌드 (6) → (10) 교체
- [ ] 3. App Privacy 게시
- [ ] 4. 콘텐츠 권한 선언
- [ ] 5. 연령 등급 설문
- [ ] 6. 스크린샷 업로드, 설명에 맥에 없는 기능이 없는지 확인
- [ ] 7. 심사 정보와 메모
- [ ] 8. 수동 출시 선택
- [ ] 9. 심사에 제출
