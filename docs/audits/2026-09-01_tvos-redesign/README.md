# tvOS TV 앱 구조 개편 시각 검증

검증일: 2026-09-01  
대상: Apple TV 4K(3세대) tvOS 26.5 시뮬레이터, 3840×2160 캡처

## 순서

- `01–02`: 개편 전 진입·NAS 설정 기준 화면
- `03–09`: 구조 적용 중 온보딩·홈·사이드바·설정 회귀 시안
- `10–12`: 최종 첫 실행 흐름(환영 → 기본 자막 언어 → 미디어 소스)
- `13`: 최종 홈·transient sidebar
- `14`: 최종 설정·기본 자막 언어
- `15`: Apple TV 사이드바 레퍼런스와 구현 화면의 동일 비교 입력

## 검증 결과

- 사이드바의 선택 행과 포커스 행을 분리해 백색 포커스에서도 문자 대비가 유지된다.
- 자막 언어 카드에서 하단 `계속`으로 이동하지 못하던 focus engine 결함을 명시적 `FocusState`로 수정했다.
- 설정의 기본 자막 언어를 압축된 `Picker`에서 가로 카드 선택으로 바꾸어 10-foot 환경의 가독성을 확보했다.
- 실물 Apple TV 재설치는 수행하지 않았다. 사용자 승인 후 실기기 회귀 검증을 진행한다.

## Apple 레퍼런스

- [Designing for tvOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos/)
- [Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/)
- [Playing video](https://developer.apple.com/design/human-interface-guidelines/playing-video/)
- [Apple Design Resources](https://developer.apple.com/design/resources/)

