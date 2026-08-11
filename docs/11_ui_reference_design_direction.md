# UI 레퍼런스 및 디자인 방향

작성일: 2026-06-18  
최종 수정: 2026-08-11 (macOS 플레이어 승인 시안 확정)
프로젝트명: 글레이즈 / Glaze

## 확정된 브랜드 (2026-08-10)

전면 재설계를 거쳐 브랜드가 확정됐다. 소스 오브 트루스는 Figma 문서다: [Glaze Brand Guidelines](https://www.figma.com/design/p1Y9SkEuKnXdfMHWBiSmRa)(팀 드라이브 "#9. 참고 자료"). 색상 값·타입 램프·로고·카피 원칙을 바꿀 때는 이 문서를 먼저 갱신하고 코드/이 파일에 반영한다.

- **브랜드 콘셉트**: "글레이즈"(유약을 입히다) — 자막 없는 영상이 재생 전에 이해 가능한 상태로 "코팅"된다는 은유. 브랜드마크는 앱 아이콘과 마케팅 자산에서 사용하고, 플레이어 크롬에는 반복 노출하지 않는다.
- **포지셔닝**: 한국 사용자에서 시작하지만 메시지는 처음부터 글로벌 — "언어는 더 이상 장벽이 아닙니다 / Language is no longer a barrier." (Messaging 페이지에 미션·태그라인·헤드라인 공식·App Store 카피 정리됨)
- **색**: `Color.accentColor`는 `Assets.xcassets/AccentColor`를 통해 브랜드 앰버(Light `#B36F2E` / Dark `#E0954A`)로 바인딩한다. 그 외 화면 색은 macOS 시스템 semantic color를 사용한다.
- **타입**: 실제 앱은 시스템 폰트를 그대로 쓰되, 헤드라인·타이틀 역할에는 `Font.system(_, design: .rounded)`를 적용해 Figma Typography 페이지의 SF Pro Rounded 지정과 맞춘다.
- **로고 에셋**: `Sources/GlazeMac/Resources/Assets.xcassets/AppIcon.appiconset`에 Figma에서 내보낸 실제 PNG가 채워져 있다(플레이스홀더 아님).
- **카피 원칙**: 다국어 보이스 원칙(짧은 문장, 관용구 지양, 용어집 고정, 한/영 직접 검수)과 UX 라이팅 Do/Don't는 Figma Voice & Tone 페이지 참고.

## 문서 목적

이 문서는 글레이즈의 macOS 앱 UI 디자인 방향을 잡기 위한 레퍼런스 분석 문서다. 기능 구현과 별개로, 어떤 화면 감각과 정보 구조를 가져가야 하는지 정리한다.

글레이즈는 단순한 영상 플레이어가 아니라, 자막 없는 영상을 감상 가능한 상태로 준비해주는 AI 미디어 도구다. 따라서 UI는 "영상 감상"과 "AI 자막 준비 상태"를 동시에 다뤄야 한다.

## 조사 범위

외부 검색과 공식 페이지를 기준으로 아래 레퍼런스를 확인했다.

- IINA: macOS 네이티브 플레이어 감각
- Infuse: 프리미엄 미디어 라이브러리와 Apple 생태계 경험
- Elmedia Player: 세밀한 재생 제어와 자막/스트리밍 기능
- Submarine Player: AI 자막 생성/번역 중심 제품
- Figma Community/디자인 템플릿: 무드보드 후보

Figma Community는 검색 결과와 일부 이미지 레퍼런스는 확인 가능하지만, 직접 페이지 접근은 제한될 수 있다. 따라서 디자인 영감으로는 활용하되, 제품 결정의 핵심 근거는 실제 플레이어 제품과 공식 문서에 둔다.

## 레퍼런스별 관찰

### IINA

IINA는 "modern media player for macOS"를 전면에 내세우며, macOS 디자인 언어와 시스템 기능을 잘 따라가는 플레이어다. 공식 페이지에서도 post-Yosemite macOS 디자인 언어, Dark Mode, Picture-in-Picture, Touch Bar, System Media Control, customizable UI, online subtitles, thumbnail preview, plugin system을 강조한다.

글레이즈에 적용할 점:

- 기본 플레이어 화면은 최대한 조용해야 한다.
- 영상 위 컨트롤은 반투명 오버레이로 제한한다.
- macOS 네이티브 느낌을 해치지 않는 아이콘/버튼 밀도를 유지한다.
- Dark Mode를 기본 감상 모드로 강하게 고려한다.
- PIP, 시스템 미디어 컨트롤 같은 macOS 기본 기능과 충돌하지 않게 한다.

피해야 할 점:

- IINA처럼 확장성과 설정이 강해지더라도, 글레이즈의 초기 MVP에서 설정을 과하게 노출하지 않는다.
- 글레이즈는 IINA의 mpv/범용 플레이어 포지션을 그대로 따라가지 않는다.

## Infuse

Infuse는 단순 플레이어보다 "아름답게 정리된 개인 미디어 라이브러리"를 강하게 보여준다. 공식 페이지는 라이브러리, 메타데이터, 포스터, NAS/클라우드/미디어 서버, iCloud 동기화, 고성능 재생, subtitles, Pro 티어를 잘 묶고 있다.

글레이즈에 적용할 점:

- 장기적으로 라이브러리 화면은 영상 목록이 아니라 "감상 준비 상태"를 보여줘야 한다.
- 포스터/메타데이터보다 자막 상태, 번역 상태, 처리 큐 상태가 글레이즈의 핵심 정보가 된다.
- Free/Pro 구분은 기능이 많아진 뒤에도 사용자가 이해하기 쉬운 구조여야 한다.
- Apple 기기 전체로 확장할 때 일관된 미디어 경험을 고려한다.

피해야 할 점:

- 초기부터 Infuse처럼 풍부한 메타데이터 라이브러리를 만들려고 하면 MVP가 흐려진다.
- 글레이즈는 "예쁜 라이브러리"보다 "자막 준비된 라이브러리"를 먼저 잡는다.

## Elmedia Player

Elmedia는 재생 제어, 포맷 지원, 스트리밍, 자막 설정, preview thumbnails, hotkeys, external audio/subtitles, playback speed 같은 세부 기능을 전면에 보여준다.

글레이즈에 적용할 점:

- 플레이어 컨트롤은 기본 조작과 고급 조작을 분리해야 한다.
- 자막 스타일, 싱크, 속도, 오디오 트랙은 향후 고급 패널로 확장할 수 있게 둔다.
- 미리보기 썸네일과 탐색 UX는 장기적으로 중요한 감상 품질 요소다.
- 자막이 글레이즈의 핵심인 만큼, 자막 설정은 일반 플레이어보다 더 접근성이 좋아야 한다.

피해야 할 점:

- 모든 제어를 한 화면에 노출하면 글레이즈의 "조용한 AI" 감각이 깨진다.
- 고급 설정은 필요하지만, 초기에 도구상자처럼 보이면 안 된다.

## Submarine Player

Submarine Player는 글레이즈와 가장 가까운 직접 레퍼런스다. 공식 페이지 기준으로 Apple Silicon, macOS 15+, 즉시 자막 생성, 로컬 처리, 19개 언어, 복수 전사 모델, 배치 처리/내보내기, 이중 자막, Free/Plus/Pay Once 구조를 제공한다.

글레이즈에 적용할 점:

- AI 자막 상태는 사용자가 즉시 이해해야 한다.
- 모델 선택은 "빠른/표준/고정확도"처럼 결과 중심으로 표현한다.
- 이중 자막은 외국어 학습과 한국어 감상에 모두 중요하다.
- 배치 처리와 내보내기는 향후 강력한 유료 후보가 될 수 있다.
- 온디바이스/오프라인 처리와 개인정보 보호는 UI에서 신뢰감 있게 보여줘야 한다.

글레이즈의 차별화:

- Submarine은 "보는 중 바로 자막"에 가깝다.
- 글레이즈는 "보기 전에 준비된 자막"과 "라이브러리 전체의 자막 준비 상태"를 더 깊게 가져간다.
- 따라서 UI도 실시간 자막 표시만이 아니라, 준비 큐, 완료 상태, 재사용 가능한 자막 자산을 보여줘야 한다.

## Figma Community와 디자인 템플릿 활용

Figma Community의 media player, video player, music player 템플릿은 분위기 탐색에는 유용하다. 다만 많은 템플릿은 모바일/웹/음악 플레이어 중심이며, 실제 macOS 네이티브 앱의 정보 구조와는 거리가 있을 수 있다.

활용 방식:

- 색감과 카드 밀도 참고
- 재생 컨트롤 레이아웃 참고
- 플레이리스트/큐 패널 형태 참고
- 다크 테마, 반투명 오버레이, 미니 플레이어 컴포넌트 참고

주의:

- Figma 템플릿의 과한 카드 UI를 macOS 플레이어에 그대로 가져오지 않는다.
- 음악 플레이어의 앨범 아트 중심 UI를 영상 플레이어에 그대로 적용하지 않는다.
- 웹 대시보드 스타일을 네이티브 플레이어에 그대로 이식하지 않는다.

## 글레이즈 UI 핵심 원칙

## Apple 플랫폼 공통 구조 (2026-08-11)

macOS의 시각적 소스 오브 트루스는 [승인된 macOS 플레이어 UI](17_approved_macos_player_ui_spec.md)와 Figma `Approved / macOS Player UI` 페이지다. 크로스플랫폼 구조와 상태 계약은 [크로스플랫폼 플레이어 UI 레퍼런스 연구](16_cross_platform_player_ui_research.md) 및 Figma `Architecture / Cross-platform Player` 페이지를 참고하되, 해당 구조도를 시각적 최종안으로 사용하지 않는다.

- 공통: 재생 상태, 자막 준비 상태, 명시적 자막 생성 계약을 공유한다.
- macOS: native toolbar + transient contextual micro controls + trailing Inspector
- iPadOS regular width: 영상 + trailing Inspector
- iPadOS compact width: Inspector 내용을 resizable Sheet로 전환
- iOS: edge-to-edge player + medium/large detent Sheet
- production design은 현재 deployment baseline과 맞는 macOS 26 / iOS·iPadOS 26 UI Kit를 사용한다. Apple 27 UI Kit는 forward exploration에만 사용한다.

Liquid Glass는 영상 위 controls와 navigation 같은 기능 레이어에 제한한다. 영상·설정 내용 자체를 Glass content layer로 만들지 않으며, 텍스트가 많은 Inspector와 Sheet에는 regular material 또는 standard material을 사용한다. 영상 위에서는 넓은 Glass bar나 캡슐을 만들지 않고 각 조작의 원형 micro control에만 clear variant를 적용한다.

## 플레이어 크롬 기준

영상은 창의 주 콘텐츠 레이어로 가장자리까지 확장한다. 파일 열기와 Inspector 진입은 macOS 창 툴바에 두고, 재생·탐색·자막·볼륨처럼 영상과 직접 관계된 조작만 영상 위 Liquid Glass 기능 레이어에 둔다.

설계 원칙:

- 영상 감상을 방해하지 않도록 창 툴바를 1차 탐색 체계로 사용한다.
- 반복 액션은 SF Symbols와 표준 `Button`/`Menu`로 제공하고 도움말을 붙인다.
- 기능 패널은 SwiftUI 네이티브 `inspector`로 열며 한 번에 하나만 표시한다.
- 패널을 열어도 창 전체 폭이 늘어나지 않고 기존 영상 영역 안에서 공간을 나눠 쓴다.
- 재생 중 포인터가 멈추면 transport controls가 자동으로 물러나 영상에 집중할 수 있어야 한다.
- Space 재생/일시정지, 더블클릭 전체 화면처럼 Mac 사용자가 기대하는 입력을 지원한다.
- 빈 화면과 드래그 상태는 사용자가 바로 파일을 놓을 수 있음을 보여준다.
- 플레이어 기본 기능은 AI 자막보다 먼저 이해되어야 한다.

## AI 미디어 어시스턴트 기준

AI 기능은 별도 챗봇 앱처럼 전면화하지 않는다. 사용자가 툴바의 패널 메뉴에서 명시적으로 AI 미디어 인스펙터를 열었을 때만 작품 정보, 자막 준비, 번역, 파일 정리 같은 다음 행동을 제안한다.

설계 원칙:

- 영상 감상 중 상시 노출되는 AI 버블은 두지 않는다.
- 패널을 열면 현재 파일의 제목 후보, 자막 준비 상태, 보관 위치를 보여준다.
- 작품 메타데이터와 포스터는 라이브러리 화면에서 더 풍부하게 보여준다.
- 원본 파일을 수정하는 액션은 항상 명시적이고 되돌릴 수 있는 흐름으로 설계한다.
- 장기적으로 Apple TV/모바일에서는 어시스턴트보다 준비된 라이브러리와 이어보기가 더 중요하다.

### 1. 영상이 중심이다

플레이어 화면에서는 영상이 가장 커야 한다. AI 자막 기능은 필요할 때 나타나고, 평소에는 감상 흐름을 방해하지 않는다.

### 2. 자막 상태는 숨기지 않는다

자막 없음, 원어 자막 있음, 한국어 자막 있음, 생성 가능, 생성 중, 완료, 실패 상태는 명확해야 한다.

### 3. AI 용어보다 사용자 결과를 먼저 보여준다

나쁜 예:

- ASR model loaded
- Translation engine unavailable

좋은 예:

- 자막 생성 준비 완료
- 한국어 자막을 만들 수 있습니다
- 번역 품질을 높이려면 고정확도 모드를 사용하세요

### 4. macOS 네이티브 감각을 유지한다

버튼, 패널, 사이드바, 메뉴, 단축키는 macOS 사용자가 기대하는 방식으로 작동해야 한다.

### 5. 한국어/영어 텍스트 길이를 모두 견딘다

한국어 UI는 짧고 명확하게 유지하고 영어·독일어·프랑스어처럼 문자열이 길어지는 언어를 위해 최소 40%의 확장 여유를 둔다. 라벨 열을 고정 폭으로 만들지 않으며 말줄임표보다 줄바꿈, 컨테이너 확장, Inspector 폭 조정을 우선한다. 내부 언어·품질 값은 locale 독립 식별자로 유지하고 화면에만 번역 문자열을 표시한다. RTL 환경에서는 의미 구조를 미러링하되 재생 시간축과 시간 표기의 진행 방향은 미디어 관례를 따른다.

## 구현된 화면 구조

### Player 화면

구성:

- 창 툴바 중앙: 현재 파일명
- 창 툴바 우측: 자막, 보조 패널 메뉴, 영상 열기
- 중앙: 창 너비를 우선 사용하는 검정 영상 스테이지
- 영상 하단: 컨테이너 없는 얇은 시간축 + 좌측 시간·볼륨 + 중앙 ±15초·재생 + 우측 CC·PiP·전체 화면 micro controls
- 우측: 자막/재생목록/미디어 정보/AI 미디어를 전환하는 시스템 Inspector(380–420pt 가변 폭)

우측 Inspector는 기본적으로 닫혀 있으며, 사용자가 툴바의 trailing Inspector 토글이나 transport controls의 CC 액션을 선택할 때만 열린다. 툴바 토글은 선택 상태에서 브랜드 앰버로 강조한다. 내부 정보는 `Form`, `Section`, `LabeledContent`, `List`, `Menu` 기반 입력으로 구성한다.

### Empty State

빈 화면도 영상이 나타날 자리라는 점을 즉시 이해하도록 어두운 미디어 스테이지를 유지한다. 장식 카드는 두지 않고 SF Symbol, 짧은 제목, 설명, `glassProminent` 영상 열기 버튼만 중앙에 배치한다. 약한 단색 방사형 명암은 콘텐츠 깊이 표현에만 사용한다.

권장 메시지:

- 한국어: "영상을 놓고 바로 재생하세요"
- 영어: "Drop a video and start watching"

보조 문구:

- "어떤 포맷이든 열어보세요. 자막이 없을 때만 글레이즈가 조용히 도와드립니다."

### Transport Controls

영상이 열린 경우에만 하단에 transient controls를 표시한다. 전체를 감싸는 단일 Glass surface나 좌·우 캡슐을 사용하지 않고, 정보와 조작을 다음 네 그룹으로 분리한다.

구성:

- 독립 시간축: Glass 컨테이너 없이 얇은 track과 scrubber를 전체 폭에 가깝게 표시
- 좌측 정보·볼륨: 현재/전체 시간과 개별 원형 볼륨 버튼
- 중앙 재생: 15초 뒤로, 재생·일시정지, 15초 앞으로를 개별 원형 버튼으로 배치하고 재생 버튼만 한 단계 크게 표시
- 우측 보기·자막: CC, PiP, 전체 화면을 개별 원형 버튼으로 배치. 좁은 폭에서는 낮은 빈도 action을 더보기로 축약
- 자막 생성·불러오기·언어·품질: transport controls에서 제외하고 Inspector 또는 Sheet에서 제공

각 원형 control에는 `clear` Liquid Glass 또는 반투명 material을 적용하고 밝은 영상에서는 컨트롤 주변 하단에만 최대 35% 수준의 국부 dimming을 더한다. `Reduce Transparency`가 활성화되면 더 불투명한 regular material로 대체한다. macOS hit area는 최소 28–32pt, iOS/iPadOS touch target은 최소 44pt를 확보하며 실제 아이콘은 SF Symbols를 사용한다. 여러 버튼을 하나의 `GlassEffectContainer`에 넣더라도 버튼마다 시각적 경계를 유지하고 하나의 캡슐로 합쳐 보이지 않게 한다.

Inspector의 `자막 만들기`와 `자막 파일 가져오기`는 전체 폭 text button을 유지한다. 낯선 AI 액션은 icon-only로 축약하지 않으며, 아이콘은 14–16pt로 제한해 라벨보다 시각적으로 앞서지 않게 한다. 결과 언어와 품질은 `Menu`로 표시해 번역 문자열 길이에 따라 자연스럽게 확장되도록 한다.

재생 중에는 2.5초 비활동 후 controls를 숨기고 포인터 이동·Space 입력·일시정지 시 다시 표시한다. 자막은 controls가 표시될 때만 충돌하지 않도록 위로 이동한다.

### AI Subtitle Panel

자막 생성 요청 시 나타나는 패널.

필드:

- 영상 언어: 자동 감지/직접 선택
- 출력: 원어, 한국어, 이중 자막
- 모드: 빠른, 표준, 고정확도
- 저장 위치: 앱 내부, 영상 위치
- 액션: 자막 생성, 자막 파일 불러오기, 그냥 시청

## 초기 디자인 시스템 방향 (2026-08-10 개정)

기존 방향은 "글레이즈만의" 커스텀 디자인 토큰(teal 강조색 하드코딩, 커스텀 `StatusBadge` 캡슐 컴포넌트 등)을 만드는 것이었다. 이 방향을 바꾼다: 커스텀 토큰을 최소화하고 Apple 표준 디자인 시스템을 그대로 따른다.

이유:

- macOS와 iOS 양쪽에서 별도 튜닝 없이 일관된 룩을 자동으로 얻을 수 있다. iOS 확장을 전제로 하면 이 이점이 커진다.
- HIG 준수도가 높아져 App Store 심사와 사용자 신뢰 측면에서 유리하다.
- "AI가 앞에 나서지 않는다"는 제품 원칙과 맞는다. 시스템 UI를 그대로 쓰면 자연스럽게 "조용한 AI" 톤이 만들어진다.

### 색상

- 기본 감상 영역: 거의 검정에 가까운 다크 배경(유지)
- 패널 영역: macOS `.windowBackgroundColor`, `.controlBackgroundColor` 등 시스템 컬러(유지)
- 강조색: 커스텀 teal 하드코딩 대신 시스템 tint / `Color.accentColor` / `.tint()` 사용
- 오류: macOS system red
- 완료: system green
- 경고: system orange

주의:

- 전체 UI가 보라/파랑 그라데이션 앱처럼 보이면 안 된다.
- AI 제품처럼 과한 네온/글로우를 쓰지 않는다.
- 브랜드 고유 색상은 앱 아이콘과 자막 오버레이 스타일 정도로 최소화한다.

### 타이포그래피

- 시스템 텍스트 스타일(`.title2`, `.caption` 등)을 그대로 사용, 커스텀 폰트/사이즈 정의는 지양
- 파일명과 상태는 작고 명확하게
- 패널 제목은 compact하게
- 버튼 텍스트는 짧게

### 컴포넌트

- 커스텀 컴포넌트보다 표준 `Label`, `Menu`, `Slider`, `Form`, `List`, `LabeledContent`, `inspector`를 우선 사용
- 영상 위 상호작용 레이어에만 `glassEffect`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`를 사용한다.
- 상태 표시는 커스텀 `StatusBadge` 캡슐 대신 표준 `Label` + system color로 대체
- segmented control: 자막 출력 모드
- popover/panel: 자막 생성 옵션
- sidebar: MVP 이후 라이브러리
- progress bar: 자막 생성 진행률
- 아이콘: SF Symbols 그대로 사용(이미 대부분 적용됨)
- Dark Mode, Dynamic Type, 접근성 대비는 커스텀 처리 대신 시스템 기본 동작에 맡긴다

`GlazeSpacing`처럼 브랜드 색상과 무관한 간격 토큰은 유지해도 무방하다.

## 현재 코드 반영 상태 (2026-08-10)

1. 어두운 edge-to-edge 미디어 스테이지와 unified compact 창 툴바 적용 완료
2. 기존 구현은 시간축, 재생/일시정지, ±15초 탐색, 이전/다음, 볼륨, 전체 화면을 단일 Liquid Glass transport surface로 제공
3. 재생 중 controls 자동 숨김과 Space/더블클릭 입력 적용 완료
4. 직접 만든 `PlayerInspectorLayout` 제거, SwiftUI `inspector` + `Form`/`List` 기반 가변 Inspector 적용 완료
5. VLC/libVLC의 재생 상태·시간·길이·탐색·볼륨 API를 공통 playback 상태에 연결 완료
6. VLC 시간 갱신을 자막 cue 동기화에도 연결 완료
7. 어두운 미디어 빈 상태와 강조색 Glass 기본 액션 적용 완료
8. 한국어/영어 재생 조작 텍스트 동기화 완료
9. 승인된 Contextual Micro Glass 시안과 다국어 구현 계약을 Figma `Approved / macOS Player UI` 페이지 및 설계 문서에 반영 완료, SwiftUI 구현 전환은 대기

## 참고 출처

- IINA 공식 웹사이트: https://iina.io/
- Infuse 공식 웹사이트: https://firecore.com/infuse
- Elmedia Player 공식 웹사이트: https://www.elmedia-video-player.com/
- Submarine Player 공식 웹사이트: https://submarineplayer.com/
- Figma Community: https://www.figma.com/community
- Apple HIG — Playing video: https://developer.apple.com/design/human-interface-guidelines/playing-video
- Apple HIG — Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- Apple HIG — Toolbars: https://developer.apple.com/design/human-interface-guidelines/toolbars
- Apple HIG — Sheets: https://developer.apple.com/design/human-interface-guidelines/sheets
- Apple Design Resources: https://developer.apple.com/design/resources/
- Apple — Build a SwiftUI app with the new design: https://developer.apple.com/videos/play/wwdc2025/323/
- Apple — Meet Liquid Glass: https://developer.apple.com/videos/play/wwdc2025/219/
