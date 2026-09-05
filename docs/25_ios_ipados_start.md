# iPhone·iPad — 시작 기록

작성일: 2026-09-06

## 이 앱의 자리

`docs/21`이 정한 역할 분담을 그대로 따른다.

| 계층 | 역할 |
|---|---|
| macOS | 작업실 — AI 전사·번역으로 자막을 만들고, 작품 정보를 영상 옆에 쓴다 |
| **iOS·iPadOS** | **클라이언트 — 준비된 자막과 포스터로 감상** |
| tvOS | 클라이언트 |

**WhisperKit을 넣지 않았다.** iOS에서 돌기는 하지만, 전화기는 사람이 10분짜리 전사를
기다리는 자리가 아니고, 빼면 내려받는 앱이 작아진다. 나중에 필요해지면
`GlazeTranscription`을 의존성에 더하는 것으로 끝난다.

## 이번에 만든 것

- `GlazeiOS` 타깃 (iOS 18.0, iPhone·iPad 공용 `TARGETED_DEVICE_FAMILY: 1,2`)
- 라이브러리: DLNA와 WebDAV 둘 다. 로직은 전부 `GlazeCore` 재사용 —
  `MediaLibraryIndex`, `WebDAVLibraryLoader`, `MediaTitleParser`, `MediaNFOParser`
- 포스터 격자: 화면 폭을 따라 열 수가 늘어난다. 아이폰과 아이패드에 코드가 갈리지 않는다
- 시리즈 화면: 시즌 선택과 에피소드 목록
- 재생: VLCKit. 버퍼는 `MediaCachingPolicy`(원격 3초) — 맥·tvOS와 같은 규칙
- 이어보기: `PlaybackPositionStore` 공유
- 잠금 화면에서도 소리가 이어지도록 `AVAudioSession` + 배경 오디오

## 확인된 것

- 아이폰(iPhone 17 Pro, iOS 26.4) 빌드·설치·실행, 초기 화면 정상
- 아이패드(iPad Pro 13" M5) 빌드·설치·실행. SwiftUI가 탭바를 상단으로 올리는 iPad 기본
  레이아웃이 그대로 적용된다

## 확인되지 않은 것

- **실제 재생.** 시뮬레이터에서 NAS/DLNA에 연결해 영상을 틀어보지 않았다.
  탭 조작이 시뮬레이터에서 반응하지 않아 초기 화면 너머로 못 갔다
- **아이패드 하단에 탭 항목이 한 번 더 보인다.** 상단 탭바와 별개로 화면 아래쪽에
  "보관함 / 미디어 소스"가 다시 나타난다. 원인 미확인
- 자막 표시. `SubtitleParser`로 사이드카를 읽는 경로는 아직 붙이지 않았다 —
  지금은 VLC에 파일을 넘겨 VLC가 그린다
- 실기기(아이폰·아이패드) 설치

## 다음에 할 일

1. 아이패드 탭바 중복 원인 찾기
2. 시뮬레이터에서 DLNA로 재생까지 확인
3. 자막을 앱이 직접 그리도록(맥·tvOS와 같은 모양) 붙이기
