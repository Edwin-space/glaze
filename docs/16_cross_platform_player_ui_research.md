# 크로스플랫폼 플레이어 UI 레퍼런스 연구

작성일: 2026-08-11

대상: Glaze macOS 26 MVP와 이후 iOS 26·iPadOS 26 확장

Figma: [Cross-platform Player System](https://www.figma.com/design/p1Y9SkEuKnXdfMHWBiSmRa?node-id=28-2)

## 조사 결론

글레이즈는 플랫폼마다 별개의 플레이어를 설계하지 않는다. `재생 상태`, `자막 준비 상태`, `명시적 자막 생성`은 공통 제품 계약으로 유지하고, 해당 작업을 보여주는 presentation만 입력 방식과 화면 폭에 맞게 바꾼다.

- macOS: resizable window + native toolbar + transient transport controls + trailing Inspector
- iPadOS regular width: 영상과 trailing Inspector를 함께 표시
- iPadOS compact width: Inspector 내용을 resizable Sheet로 전환
- iOS: edge-to-edge player + medium/large detent Sheet

재생 컨트롤은 Apple TV와 YouTube에서 이미 학습된 순서를 활용한다. 다만 하나의 큰 bar에 모든 조작을 넣지 않고 `독립 시간축 + primary playback island + viewing/subtitle island`로 분리한다. iPhone·iPad에서는 시스템 음량 조절과 중복되는 상시 볼륨 슬라이더를 제거한다.

## 조사 범위와 접근 상태

### Mobbin

Mobbin 연결과 검색 도구 노출은 확인했다. 다만 현재 연결 계정은 유료 플랜이 필요해 screen/flow 결과를 반환하지 않았다. 따라서 이번 결론은 Mobbin 화면을 관찰한 결과로 주장하지 않고, 공개된 Apple·YouTube 공식 문서와 Apple Design Resources에서 확인한 컴포넌트를 근거로 삼는다.

### Apple Design Resources

Figma에서 다음 공식 라이브러리를 확인했다.

- macOS 26: Window, Window Button, Push Button, Segmented Control, Utility Panel 등
- iOS and iPadOS 26: Inspector Sheet, iPad Sheet, Full-screen iPhone Sheet, Sidebar, Top Toolbar, Bottom Toolbar, Slider, Liquid Glass text/symbol button 등

현재 Glaze Figma 파일에서는 라이브러리 검색은 가능하지만 live component import 권한이 제한됐다. 이번 Figma 산출물은 구조와 결정 기준을 네이티브 노드로 기록했다. 실제 production frame 단계에서는 해당 라이브러리를 파일에 추가한 뒤 공식 컴포넌트 instance로 교체한다.

프로젝트 최소 버전과 일치시키기 위해 production 기준은 Apple 26 UI Kit로 고정한다. Apple 27 UI Kit는 forward exploration에서만 사용하며 같은 화면 안에 혼합하지 않는다.

## 관찰된 레퍼런스 패턴

### Apple TV on macOS

- 포인터를 영상 위로 이동하면 재생 controls가 나타난다.
- 재생/일시정지, 10초 이동, timeline scrubbing, volume, subtitles, PiP를 제공한다.
- 자막과 오디오는 플레이어의 관련 버튼에서 pop-up menu로 연다.
- PiP는 작은 resizable viewer로 전환된다.

글레이즈 적용: 시간축은 독립적으로 두고, 재생·탐색·음량은 좌측 primary island, CC·PiP·전체 화면은 우측 viewing/subtitle island로 분리한다. 자막 표시 전환은 CC에서 즉시 처리하고, 생성·불러오기·언어·품질 같은 준비 작업만 Inspector로 넘긴다.

### Apple TV on iPadOS

- 화면을 탭해 controls를 표시한다.
- 재생/일시정지, ±10초 이동, 속도, 오디오, 자막, 공유, AirPlay, PiP가 표준 transport action으로 제공된다.
- muted 또는 10초 뒤로 이동할 때 자막을 보조적으로 표시하는 행동이 있다.

글레이즈 적용: iPad는 touch target을 유지하면서 keyboard/pointer도 함께 지원한다. 단일 영상 감상에서는 leading sidebar를 상시 쓰지 않고, 자막 준비는 trailing Inspector 또는 Sheet로 표현한다.

### YouTube

- CC는 player에서 바로 켜고 끄는 직접 조작이다.
- 언어와 자막 스타일 같은 상세 설정은 Settings 하위에 둔다.
- desktop player의 하단 control order는 많은 사용자가 이미 학습한 구조다.

글레이즈 적용: 순서와 정보 구조는 활용하되 픽셀 단위로 복제하지 않는다. Apple 플랫폼의 toolbar, menu, tooltip, keyboard shortcut, touch target 규칙으로 번역한다.

## Apple HIG 기반 결정

### Playing video

- 가능하면 system player의 행동과 interface를 따르고, custom player도 습관적으로 기대하는 interaction을 유지한다.
- controls가 영상을 가리지 않게 하고 재생 중에는 물러나게 한다.
- scrubbing을 지원할 때 thumbnail track을 이후 개선 후보로 둔다.
- PiP와 원본 aspect ratio를 보장한다.

### Liquid Glass

- Liquid Glass는 content가 아니라 controls와 navigation을 위한 기능 레이어다.
- 영상처럼 시각적으로 풍부한 배경 위 transient controls에는 clear variant를 적용하되, 작은 control island에만 제한한다.
- 텍스트가 많고 가독성이 중요한 Inspector·popover·Sheet에는 regular variant 또는 standard material을 사용한다.
- 밝은 영상에서 clear Glass를 쓸 때는 최대 35% 수준의 dimming layer를 검토한다.

### Toolbars, Buttons, Sheets, Sidebars

- toolbar에는 빈도가 높은 action만 두고, 관련이 적은 기능은 overflow menu로 보낸다.
- 익숙한 action은 SF Symbols로 압축하되, macOS에서는 tooltip을 제공한다.
- 낯선 AI action은 icon-only로 만들지 않고 `자막 만들기`처럼 결과 중심 text label을 쓴다.
- iPhone Sheet는 medium/large detent와 grabber를 지원하고 swipe dismiss를 따른다.
- sidebar는 정보 hierarchy 탐색에 사용한다. 자막 준비처럼 현재 영상에 종속된 작업에는 Inspector/Sheet가 더 적합하다.

## 공통 컴포넌트와 상태 계약

| 계약 | 공통 정의 | 플랫폼 표현 |
| --- | --- | --- |
| Player chrome | 독립 시간축, primary island, viewing/subtitle island | Mac hover, iPad/iPhone tap |
| Subtitle readiness | 없음, 기존 자막, 생성 중, 준비 완료, 오류 | 동일한 상태·카피 유지 |
| Subtitle preparation | 상태, 출력 언어, 품질, 저장 위치, 명시적 CTA | Inspector 또는 Sheet |
| Presentation | 현재 영상에 종속된 보조 작업 | Mac Inspector, iPad adaptive, iPhone Sheet |
| Input | 같은 action과 accessibility label | tooltip/keyboard, pointer/touch, gesture |

구현에서는 재생·자막 상태를 `GlazeCore`의 공통 모델로 유지하고, macOS/iPadOS/iOS target이 각 presentation을 조합한다. 플랫폼별 view가 상태를 별도로 소유하지 않게 해야 이어보기와 향후 동기화가 단순해진다.

## Adopt / Adapt / Avoid

### Adopt

- 컨테이너 없는 얇은 독립 시간축
- 좌측 primary playback island와 우측 viewing/subtitle island
- 직접 접근 가능한 CC, PiP, 전체 화면
- 재생 중 자동으로 물러나는 controls
- 10초 이동과 timeline scrubbing

### Adapt

- YouTube의 학습된 control order를 Apple native behavior로 변환
- 영상 위의 작은 island만 clear Liquid Glass, 설정 surface는 regular material로 분리
- 밝은 영상에서 전체 bar 대신 control 주변에만 국부 dimming 적용
- macOS tooltip·keyboard shortcut, iPad pointer·keyboard, iPhone touch·gesture 지원
- 화면 폭에 따라 Inspector와 Sheet를 전환

### Avoid

- 시간축·재생·볼륨·CC·PiP를 모두 감싼 full-width monolithic Glass bar
- CC와 `자막 만들기`를 같은 의미로 중복 노출
- 낯선 AI action의 icon-only 표현
- 데스크톱 고정 패널을 iPhone에 축소 이식
- Apple 26·27 UI Kit 컴포넌트를 같은 production 화면에 혼합

## Production design backlog

| 우선순위 | Figma frame | UX 영향 | 구현 공수 |
| --- | --- | --- | --- |
| P0 | macOS Inspector 닫힘·열림·생성 중 | 높음 | 낮음~중간 |
| P0 | macOS 독립 시간축·좌·우 control island interaction states | 높음 | 낮음~중간 |
| P1 | iPadOS regular Inspector·compact Sheet | 높음 | 중간 |
| P1 | iOS portrait medium·large detent·landscape | 높음 | 중간 |
| P1 | 자막 없음·생성 중·완료·오류 variants | 높음 | 낮음 |

## 출처

- [Apple HIG — Playing video](https://developer.apple.com/design/human-interface-guidelines/playing-video)
- [Apple HIG — Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple HIG — Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Apple HIG — Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Apple HIG — Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
- [Apple HIG — Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple Design Resources](https://developer.apple.com/design/resources/)
- [Apple TV app on Mac — Control playback](https://support.apple.com/guide/tvapp-mac/atv31d6caa7/mac)
- [Apple TV app on iPad — Control playback](https://support.apple.com/guide/ipad/ipad6cf12042/ipados)
- [YouTube Help — Manage caption settings](https://support.google.com/youtube/answer/100078)
