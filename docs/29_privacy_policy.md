# 개인정보 처리방침 초안

작성일: 2026-09-06

App Store Connect는 앱마다 처리방침 **URL**을 요구한다. 아래 글을 어딘가에 올리고 그
주소를 넣으면 된다. 내용은 앱이 실제로 하는 일에 맞춰 쓴 것이고, 사실과 다르면 곤란해지는
문서이므로 앱이 바뀌면 같이 고쳐야 한다.

**확인한 사실:** 앱에는 분석·광고 코드가 없고, 계정도 로그인도 없다. 프라이버시
매니페스트(`Packaging/PrivacyInfo.xcprivacy`)의 수집 항목이 비어 있는 것과 이 글은 서로
맞아야 한다.

---

## 한국어

### 글레이즈 개인정보 처리방침

**시행일: 2026년 —월 —일**

글레이즈는 이용자가 가진 영상을 재생하는 앱입니다. 개발자는 이용자에 관한 어떤 정보도
수집하거나 전송받지 않습니다.

**수집하지 않는 것**

계정을 만들지 않으며, 이름·이메일·전화번호를 묻지 않습니다. 사용 기록을 수집하지 않고,
분석 도구나 광고 SDK를 넣지 않았습니다. 개발자의 서버가 없으므로 이용자에게서 개발자에게
전송되는 정보 자체가 없습니다.

**기기에만 저장되는 것**

- 영상을 어디까지 보았는지
- 자막 언어·크기·재생 속도 같은 설정
- 이용자가 직접 입력한 NAS 주소와 로그인 정보

이 값들은 기기 안에만 있습니다. NAS 비밀번호는 시스템 키체인에 저장됩니다. 앱을 지우면
함께 사라집니다.

**이용자의 지시로 외부와 통신하는 경우**

- **이용자의 NAS·미디어 서버** — 이용자가 주소를 입력했을 때만, 그 서버에만 연결합니다
- **TMDB(themoviedb.org)** — 맥 앱에서 작품 정보를 찾을 때, 영상의 제목만 보냅니다.
  이용자를 식별할 수 있는 정보는 보내지 않습니다. 이용자가 TMDB API 키를 직접 입력했을
  때만 동작합니다. 이 제품은 TMDB API를 사용하지만 TMDB가 보증하거나 인증한 것은 아닙니다
- **음성 인식과 번역** — 맥 앱의 자막 생성은 전부 기기 안에서 이루어집니다. 영상이나
  음성이 밖으로 나가지 않습니다

**어린이**

어린이를 대상으로 하지 않으며, 어린이에 관한 정보를 수집하지 않습니다.

**변경**

이 방침이 바뀌면 이 페이지에 고쳐 올리고 시행일을 바꿉니다.

**문의**

—이메일 주소—

---

## English

### Glaze Privacy Policy

**Effective —, 2026**

Glaze plays video you already have. The developer collects nothing about you and
receives nothing from you.

**What is not collected**

There is no account, no sign-in, and no request for your name, email or phone number.
No usage is recorded; there is no analytics or advertising code in the app. There is no
developer server, so there is nothing for information to be sent to.

**What stays on your device**

- how far into a video you got
- settings such as subtitle language, subtitle size and playback speed
- the addresses and credentials of servers you entered yourself

These stay on the device. NAS passwords are held in the system keychain. Deleting the
app removes them.

**When the app talks to something else, at your instruction**

- **your own NAS or media server** — only the address you entered, and only that server
- **TMDB (themoviedb.org)** — when the Mac app looks up film information it sends the
  title of the file and nothing that identifies you. It runs only if you entered your
  own TMDB API key. This product uses the TMDB API but is not endorsed or certified by
  TMDB
- **speech recognition and translation** — subtitle generation on the Mac runs entirely
  on the device. No video or audio leaves it

**Children**

The app is not directed at children and collects nothing about them.

**Changes**

If this policy changes, the revised version appears on this page with a new date.

**Contact**

—email address—
