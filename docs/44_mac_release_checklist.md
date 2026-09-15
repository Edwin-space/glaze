# 맥 출시 — 최종 점검과 심사 제출 작업 리스트

작성일: 2026-09-15 · 대상: macOS `1.0 (10)` (2026-09-15 업로드)

맥을 먼저 낸다(`docs/28` §2). 이 문서는 업로드된 빌드 10을 직접 열어 본 결과와,
심사 제출까지 남은 일을 **누가 해야 하는지**로 나눈 목록이다.

## 1. 점검 결과 — 통과

| 항목 | 확인 방법 | 결과 |
|---|---|---|
| 서명 | 업로드한 `Glaze.pkg`를 풀어 `codesign --verify --deep --strict` | 통과. 앱·ffmpeg·ffprobe·libvlccore 모두 `Apple Distribution: TAESUNG YOO` |
| 설치 패키지 | `pkgutil --check-signature` | `3rd Party Mac Developer Installer`로 서명 |
| 샌드박스 | 앱 entitlements | `app-sandbox`, `network.client`, `files.user-selected.read-write`, `bookmarks.app-scope`, `assets.movies.read-write`만 있음 |
| 헬퍼 | ffmpeg·ffprobe entitlements | `app-sandbox` + `inherit`만 있음. 앱스토어 규칙에 맞음 |
| 번들 구조 | 번들 목록 | VLC 플러그인 264개가 `Frameworks`에 있음. `.jar`·정적 라이브러리 없음. 113MB |
| 실제 실행 | 샌드박스가 켜진 릴리스 앱으로 `test file/testmedia.mkv` 열기 | 재생됨. 샌드박스 거부 로그 0건, 크래시 리포트 없음 |
| Info.plist | 파일 확인 | 버전 1.0 (10), 카테고리, `ITSAppUsesNonExemptEncryption=false`, 로컬 네트워크 문구(한/영) 모두 있음 |
| 프라이버시 매니페스트 | 번들 안 `PrivacyInfo.xcprivacy` | 추적 없음, 수집 없음, UserDefaults CA92.1 |
| 오픈소스 고지 | `MacLicensesView`, `VLC-LICENSE-THIRD-PARTY.md` | 들어 있음 |

## 2. 점검 결과 — 고칠 것

**A. 공개 저장소에 빌드 10의 소스가 없다 (심사 전 필수)**
LGPL 대응은 "앱 전체를 공개한다"는 결정에 기대고 있다(`docs/28` §2). 그런데 빌드 10에 들어간
변경 108개 파일이 커밋되지 않았고, `origin/main`은 `ee27f1f`에 머물러 있다. 배포하는 바이너리와
공개된 소스가 일치해야 이 결정이 성립한다.

**B. 개인정보 처리방침에 문의 이메일이 비어 있다 (심사 전 필수)**
`docs/PRIVACY.md`에 `—문의 이메일—`이 그대로 있다. 처리방침 URL이 이 파일을 가리키므로
심사자에게도 그대로 보인다.

**C. 처리방침에 음성 인식 모델 다운로드가 빠져 있다**
자막 생성은 처음 쓸 때 WhisperKit이 Hugging Face에서 모델을 받는다
(`SubtitleGenerator.swift:67`). 영상이나 음성은 보내지 않지만, 외부와 통신하는 것은 사실이다.
"이용자의 지시로 외부와 통신하는 경우"에 한 줄 넣어야 한다.

**D. 샌드박스에서 확인하지 않은 경로**
Debug 빌드는 샌드박스가 꺼져 있어(`project.yml`), 평소 테스트로는 아래 경로가 검증되지 않는다.
릴리스 빌드로 따로 확인해야 한다.
- 자막 생성: 모델 다운로드 위치와 ffmpeg 오디오 추출
- `.nfo`·자막을 영상 옆에 쓰기(사용자가 고른 폴더와 Movies 폴더)
- WebDAV·시놀로지·DLNA 연결
- 재실행 후 최근 파일 다시 열기(보안 범위 북마크)

**E. ffprobe dSYM 경고 — 막지 않음**
업로드 때 `Upload Symbols Failed`가 떴다. ffprobe 안에서 난 크래시만 기호화되지 않는다.
이번 출시에는 그대로 둔다.

## 3. 작업 리스트

### 내가 할 수 있는 것

- [ ] A. 변경을 커밋하고 `origin/main`에 푸시한다. 빌드 10 태그 `mac-1.0-10`도 붙인다
- [ ] C. 처리방침(한/영)에 Hugging Face 모델 다운로드 문장을 넣는다
- [ ] D. 릴리스(샌드박스) 빌드로 자막 생성·파일 쓰기·북마크를 확인한다
- [ ] 심사 메모 초안: NAS 없이 테스트하는 방법(로컬 파일 열기), TMDB는 사용자 키가 필요하다는 점, `assets.movies.read-write`를 쓰는 이유(`.nfo`·자막 저장)
- [ ] 맥 스크린샷 초안(2880×1800): 재생 화면, 정보 패널, 자막 생성, 설정 → 단축키. **실제 NAS 주소가 찍히지 않게** 로컬 파일과 가짜 서버 이름으로 만든다(`docs/28` §6)
- [ ] A~C가 끝나 코드가 바뀌면 빌드 11로 다시 아카이브하고 업로드한다

### 계정 소유자만 할 수 있는 것 (App Store Connect)

- [ ] B. 문의 이메일 주소 정하기
- [ ] macOS 버전에 연결된 빌드를 (6) → 최신 빌드로 교체
- [ ] App Privacy **Publish** — `Data Not Collected`
- [ ] Content Rights 선언 — 앱에 서드파티 콘텐츠가 들어 있지 않음
- [ ] 연령 등급 설문
- [ ] 스크린샷 업로드(맥 1장 이상, 최대 10장)
- [ ] 심사 메모 입력 후 **Submit for Review**

### 결정할 것

- [ ] **최소 macOS 26.0 유지 여부.** 지금은 macOS 26 사용자만 설치할 수 있다
- [ ] **자동 출시인지 수동 출시인지.** 심사가 통과되면 바로 출시할지, 직접 누를지

## 4. 순서

1. A 커밋·푸시, C 처리방침 수정 (B 이메일을 받으면 함께)
2. D 샌드박스 확인 → 문제가 있으면 고치고 빌드 11
3. 스크린샷·심사 메모
4. App Store Connect 입력(계정 소유자) → 제출

## 5. 진행 기록 (2026-09-15)

| 항목 | 결과 |
|---|---|
| A. 소스 공개 | 커밋 전 검사에서 **실제 NAS 주소**(IP·호스트명)가 문서 2개와 코드·테스트 2개에 있어 예시 주소(`203.0.113.10`, `my-nas.synology.me`)로 바꿨다. 그 뒤 커밋·푸시 |
| B. 문의 창구 | 이메일 대신 GitHub Issues로 둔다. 이메일이 정해지면 사이트 두 곳만 고친다 |
| C. 처리방침 | Hugging Face 모델 다운로드와 Apple 번역 언어 자료를 추가했다. 아이폰 TMDB, 캐시, 시청 기록도 반영했다 |
| 사이트 | GitHub Pages가 **꺼져 있었고 사이트도 없었다**(모든 주소 404). `site/`에 소개·처리방침·이용약관·지원을 만들고 `.github/workflows/pages.yml`로 배포하게 했다. 저장소 설정에서 Pages를 켜는 것은 계정 소유자가 한다 |
| 처리방침 원문 | `docs/PRIVACY.md`는 사이트 주소 안내로 바꿨다. 문장은 `site/`에만 둔다 |
| 결정 | 최소 macOS 26.0 유지, 심사 통과 후 수동 출시 |
| D. 샌드박스 경로 확인 | 실기기 테스트 항목이라 이번에는 뺐다 |
| 계정 소유자 절차 | `docs/45_app_store_connect_owner_guide.md` |
