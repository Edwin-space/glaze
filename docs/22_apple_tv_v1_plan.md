# Apple TV를 v1.0에 함께 넣기

작성일: 2026-08-24

로드맵에서 v1.1이던 Apple TV를 v1.0 동시 출시로 올린 결정에 따른 조사와 계획이다.

## 이미 된 것

- `GlazeCore`를 tvOS에서 컴파일 가능하게 분리했다. WhisperKit이 tvOS를 지원하지 않아 전사 코드만 `GlazeTranscription`으로 떼어냈다. Apple TV는 전사를 하지 않으므로 이건 우회가 아니라 실제 경계다.
- `GlazeTV` 타깃이 Apple TV 4K 시뮬레이터에서 빌드·실행된다.
- SSDP 탐색과 ContentDirectory 탐색을 `GlazeCore`로 옮겨 Mac과 Apple TV가 같은 코드를 쓴다. 시뮬레이터에서 실제 LAN의 미디어 서버 2대를 찾는 것까지 확인했다.

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
4. 리모컨 조작(재생/일시정지, 탐색, 자막 선택)과 포커스 동선
5. 이어보기 — `PlaybackPositionStore`는 `MediaResource` 기준이라 그대로 쓸 수 있다
