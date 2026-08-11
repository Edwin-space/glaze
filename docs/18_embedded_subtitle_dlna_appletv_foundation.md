# 내장 자막·DLNA·Apple TV 기반

작성일: 2026-08-11

## 구현 범위

이번 작업은 macOS 앱에 Apple TV 앱 자체를 추가하는 단계가 아니라, 세 플랫폼이 공유할 데이터·정책 경계를 확정하는 단계다.

- `EmbeddedSubtitleTrack`: 스트림 인덱스, 코덱, 언어, 기본/강제 여부, 텍스트/이미지 유형
- `SubtitlePreparationPlanner`: 사용자 언어 내장 자막 → 다른 언어 cue 번역 → 음성 인식 순서
- `MediaResource`: 로컬 파일과 DLNA 네트워크 영상의 공통 식별·재생 URL
- `NetworkMediaServer`/`NetworkMediaNode`: 서버, 컨테이너, 영상 리소스 모델
- SSDP, Device Description, ContentDirectory SOAP, DIDL-Lite 파서
- macOS SSDP 탐색 서비스와 VLC 네트워크 URL 재생

## 플랫폼 책임

| 계층 | macOS | iOS/iPadOS | tvOS |
|---|---|---|---|
| NAS 탐색 | SSDP/UPnP 탐색·관리 | 동일 Core 모델, 권한 검증 | 감상 중심 탐색 |
| 자막 준비 | ffprobe/ffmpeg, AI 생성·번역 | 준비 자막 소비, 짧은 작업 | 준비된 SRT/VTT 또는 네이티브 트랙 소비 |
| 재생 | AVKit + VLC | AVFoundation 우선 | AVFoundation 우선 |
| 저장 | 앱 라이브러리/sidecar | 동기화 캐시 | 일시 캐시 |

tvOS는 앱 번들 실행 파일을 호출하는 FFmpeg CLI 구조에 의존하지 않는다. macOS에서 추출·번역한 자막을 주소 가능한 앱 자산으로 만들거나, 플랫폼 네이티브 미디어 트랙을 직접 소비해야 한다.

## 현재 지원과 제한

- 텍스트 내장 자막은 감지·SRT 추출·기존 오버레이 표시까지 연결돼 있다.
- 사용자 언어가 없을 때 번역용 cue 요청은 생성하지만, 번역 엔진 실행 연결은 후속 작업이다.
- 이미지 기반 PGS/VobSub는 감지만 하며 OCR은 아직 지원하지 않는다.
- 네트워크 미디어 시트에서 DLNA 서버 탐색·ContentDirectory 폴더 이동·원격 VLC 재생까지 연결했다.
- Synology 모델/DSM 버전별 실기기 검증, 인증이 필요한 리소스, sleep/wake 복구는 남아 있다.
- DLNA는 sidecar 자막을 표준적으로 항상 노출하지 않으므로 생성/번역 자막은 Glaze 앱 라이브러리에서 영상 리소스 ID와 연결해야 한다.

## 출시 게이트

1. Synology Media Server에서 SSDP 탐색, 중첩 폴더 Browse, MKV/MP4 스트리밍을 실기기로 검증한다.
2. range request, seek, 네트워크 단절·재접속, 서버 IP 변경을 검증한다.
3. 내장 자막 언어 선택과 번역 결과 저장을 `MediaAsset` 영속 모델에 연결한다.
4. iOS/iPadOS의 multicast entitlement와 로컬 네트워크 권한을 실기기로 검증한다.
5. tvOS 타겟은 위 네 항목과 준비 자막 동기화 포맷이 확정된 뒤 추가한다.

## 표준·플랫폼 근거

- Apple TN3179 — 로컬 네트워크 개인정보 보호: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- Apple `NSAllowsLocalNetworking` — 로컬 HTTP 리소스의 ATS 선언: https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking
- Apple multicast entitlement: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast
- UPnP ContentDirectory v4: https://openconnectivity.org/wp-content/uploads/2015/11/UPnP-av-ContentDirectory-v4-Service-20101231.pdf
