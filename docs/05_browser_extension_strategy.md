# 브라우저 확장 연동 전략

작성일: 2026-06-18  
프로젝트명: 글레이즈

## 문서 목적

이 문서는 글레이즈의 선택적 차별화 후보인 브라우저 확장 연동을 정리한다. Chrome, Safari 등 브라우저에서 사용자가 동영상이 포함된 웹페이지를 보다가, 해당 영상을 글레이즈 플레이어로 넘겨 더 나은 재생, 자막 생성, 번역, 저장/관리 경험을 얻을 수 있게 하는 것이 목표다.

이 기능은 초기 MVP 필수 범위가 아니다. 다만 Submarine Player와 차별화할 수 있는 강한 확장 방향이므로 제품 전략과 기술 검토 항목에 포함한다.

## 제품 아이디어

사용자가 웹사이트에서 동영상 페이지에 접근했을 때, 브라우저 확장이 현재 페이지의 재생 가능한 미디어를 감지한다. 사용자가 명시적으로 "글레이즈에서 열기"를 선택하면, 글레이즈 macOS 앱이 실행되고 해당 영상 스트림 또는 미디어 URL을 받아 자체 플레이어에서 재생한다.

핵심 경험:

> 웹에서 보던 영상을 글레이즈로 가져와, 더 나은 자막 생성/번역/재생 환경에서 본다.

## 차별화 가치

Submarine Player가 로컬 파일 기반 AI 자막 플레이어에 가깝다면, 글레이즈는 로컬 파일과 웹 영상을 모두 "자막 준비 가능한 감상 환경"으로 가져오는 방향을 실험할 수 있다.

차별화 포인트:

- 웹 영상 페이지에서 글레이즈로 열기
- 브라우저 밖 독립 플레이어에서 재생
- 웹 영상에도 AI 자막 생성/번역 적용
- HLS 같은 스트리밍 URL을 감지해 재생
- 가능한 경우 자막 파일 생성과 저장
- 사용자가 허용한 범위에서만 미디어 다운로드 제공
- DRM, 유료 접근 제어, 사이트 정책을 우회하지 않는 준법형 설계

## 지원 범위 원칙

이 기능은 아래 조건을 만족하는 경우에만 지원한다.

- 사용자가 직접 접근 권한을 가진 웹페이지
- DRM으로 보호되지 않은 미디어
- 공개 또는 사용자가 정당하게 접근 가능한 HLS/DASH/직접 파일 URL
- 사이트 약관과 저작권을 침해하지 않는 범위
- 브라우저 확장 권한이 명확히 고지되고 사용자가 직접 실행한 경우

지원하지 않는 범위:

- DRM 우회
- 유료 스트리밍 서비스의 보호 콘텐츠 추출
- 로그인 쿠키나 인증 정보를 몰래 전송하는 방식
- 사이트의 기술적 보호 조치를 회피하는 다운로드
- 사용자의 명시적 실행 없이 자동 수집하는 동작
- 저작권 침해를 유도하는 마케팅

## 기술 접근

### 1. 브라우저 확장

Chrome은 Manifest V3 기반 확장으로 검토한다. 확장은 페이지 내 `video` 요소, `source` 요소, 네트워크 요청, HLS manifest URL 등을 감지한다. 필요한 경우 `webRequest` 권한과 host permission을 사용하되, 권한 범위는 최소화한다.

Safari는 Safari Web Extension 형태로 검토한다. macOS 앱과 함께 배포되는 구조가 자연스럽고, 글레이즈 앱 설치 후 확장을 활성화하는 흐름을 설계할 수 있다.

### 2. 미디어 감지

감지 후보:

- HTMLMediaElement의 `currentSrc`
- `video > source` URL
- `.m3u8` HLS manifest
- `.mpd` DASH manifest
- 직접 미디어 파일 URL: mp4, mov, webm 등
- 페이지 메타데이터의 canonical URL과 제목

감지 결과는 확장 UI에서 사용자에게 보여주고, 사용자가 선택한 항목만 글레이즈로 전달한다.

### 3. 앱 전달 방식

가능한 전달 방식:

- 커스텀 URL 스킴: `glaze://open?url=...`
- Chrome Native Messaging: 확장과 macOS 앱 helper 간 JSON 메시지 교환
- Safari App Extension/containing app 연동

초기에는 커스텀 URL 스킴이 가장 단순하다. 다만 인증 헤더나 세션 의존 요청이 필요한 경우에는 Native Messaging 또는 앱 확장 기반 보안 설계가 필요하다.

### 4. 글레이즈 앱 처리

앱은 전달받은 URL을 직접 재생 가능한지 확인한다.

처리 순서:

1. URL 스킴과 도메인 검증
2. DRM/EME 사용 여부 탐지
3. HLS/DASH manifest 접근 가능성 확인
4. 재생 가능 포맷이면 플레이어에 연결
5. 자막 생성 가능 여부 판단
6. 사용자가 선택한 경우 자막 생성/번역 시작
7. 다운로드 가능 여부는 별도 정책 검사 후 제공

## 다운로드 기능 정책

다운로드는 강력한 기능이지만 리스크가 크다. 따라서 "특수 기능"으로 분리하고, 기본 UX에서는 재생과 자막 생성이 우선이다.

다운로드 허용 후보:

- 사용자가 소유하거나 직접 업로드한 콘텐츠
- 공개 배포가 허용된 미디어
- DRM이 없고 다운로드가 명시적으로 허용된 콘텐츠
- 내부 테스트/개인 백업 등 합법적 사용 케이스

다운로드 제한:

- DRM 보호 콘텐츠
- 스트리밍 서비스의 유료 콘텐츠
- 만료 토큰, 세션 쿠키, referer 강제 조건을 우회해야 하는 콘텐츠
- 사이트 약관상 저장이 금지된 콘텐츠

UX 문구는 "다운로드"보다 "허용된 미디어 저장"처럼 조심스럽게 설계한다. 기능 설명에서도 저작권 침해나 보호 콘텐츠 저장을 암시하지 않는다.

## 보안/개인정보 원칙

- 확장은 필요한 순간에만 활성화한다.
- 가능한 한 `activeTab` 중심으로 시작하고, 광범위한 host permission은 늦게 요청한다.
- 감지한 URL, 페이지 제목, 쿠키, 헤더는 사용자가 실행한 작업에 필요한 경우에만 처리한다.
- 앱으로 전달하는 데이터는 URL, 페이지 출처, 제목, 사용자가 선택한 옵션으로 제한한다.
- 쿠키나 인증 헤더를 앱으로 전달해야 하는 구조는 기본적으로 피한다.
- 확장 메시지 핸들러는 임의 URL 프록시처럼 동작하지 않게 제한한다.
- DRM 또는 EME가 감지되면 "글레이즈에서 열 수 없음"으로 처리한다.

## 개발 우선순위

이 기능은 MVP 이후 실험 트랙으로 둔다.

1. 웹페이지의 직접 mp4 URL을 글레이즈로 열기
2. HLS `.m3u8` URL 감지와 글레이즈 재생
3. 현재 페이지 제목/출처를 라이브러리 항목으로 저장
4. 웹 영상 자막 생성과 한국어 번역
5. Chrome 확장 베타
6. Safari 확장 베타
7. 허용된 미디어 저장 기능 검토
8. 도메인별 지원/차단 정책
9. DRM/EME 감지와 사용자 안내

## 제품 판단

브라우저 확장은 글레이즈의 핵심 MVP가 아니라, 성공했을 때 강한 차별화가 되는 2차 확장 전략이다. 특히 웹 강의, 공개 세미나, 개인 클라우드 영상, DRM 없는 HLS 영상에 AI 자막을 붙일 수 있다면 Submarine Player와 다른 사용 맥락을 만들 수 있다.

다만 이 기능은 법적/정책적 경계가 선명해야 한다. 글레이즈는 보호 콘텐츠를 우회하는 도구가 아니라, 사용자가 정당하게 접근 가능한 영상을 더 좋은 감상 환경으로 가져오는 도구로 설계한다.

## 참고 출처

- Chrome Extensions cross-origin network requests: https://developer.chrome.com/docs/extensions/develop/concepts/network-requests
- Chrome webRequest API: https://developer.chrome.com/docs/extensions/reference/api/webRequest
- Chrome Native Messaging: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
- Chrome Web Store Program Policies: https://developer.chrome.com/docs/webstore/program-policies
- Safari Web Extensions: https://developer.apple.com/documentation/safariservices/safari-web-extensions
- W3C Encrypted Media Extensions: https://www.w3.org/TR/encrypted-media/
