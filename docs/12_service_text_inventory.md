# 서비스 텍스트 인벤토리

작성일: 2026-06-18  
프로젝트명: 글레이즈 / Glaze

## 문서 목적

이 문서는 글레이즈 앱 내부에 표시되는 모든 텍스트를 유형별로 관리하기 위한 기준 문서다. 메뉴, 버튼, 알림, 상태 메시지, 오류 메시지, 설정 문구를 분리해 관리하면 이후 localization, 사용자 가이드, FAQ, 고객지원 문서를 만들 때 일관성을 유지할 수 있다.

## 관리 원칙

- 한국어와 영어를 기본으로 작성한다.
- 사용자 시스템 언어가 한국어 또는 영어이면 해당 언어를 사용한다.
- 미지원 언어 환경에서는 영어를 fallback으로 사용한다.
- AI/기술 용어보다 사용자가 얻는 결과를 먼저 말한다.
- 오류 메시지는 원인과 다음 행동을 함께 제공한다.
- 같은 의미의 문구를 화면마다 다르게 쓰지 않는다.
- 기능이 확정되지 않은 문구는 `draft` 상태로 관리한다.

## 텍스트 유형

| 유형 | 목적 | 예시 |
|---|---|---|
| 메뉴 | macOS 메뉴/명령 | 영상 열기, 자막 불러오기 |
| 버튼 | 사용자의 명시적 액션 | 자막 생성, 그냥 시청 |
| 상태 | 현재 파일/자막/작업 상태 | 자막 없음, 생성 중 |
| 안내 | 사용자의 선택을 돕는 설명 | 자막 생성은 요청 시에만 시작됩니다 |
| 알림 | 중요한 변화나 완료 안내 | 한국어 자막 생성 완료 |
| 오류 | 실패와 해결 방법 | 저장 권한이 필요합니다 |
| 설정 | 앱 동작 정책 | 저장 위치, 모델 모드 |
| 빈 화면 | 시작/무상태 화면 | 영상을 열어 자막 준비를 시작하세요 |
| 가이드 | 도움말/FAQ로 확장될 설명 | 자막 파일은 어디에 저장되나요? |

## 현재 앱 텍스트

| 키 | 한국어 | 영어 | 유형 | 상태 |
|---|---|---|---|---|
| `app.name` | 글레이즈 | Glaze | 브랜드 | 확정 |
| `command.open_video` | 영상 열기... | Open Video... | 메뉴 | 구현 |
| `open_panel.title` | 영상을 선택하세요 | Choose a video | 시스템 패널 | 구현 |
| `player.empty_title` | 영상을 열어 자막 준비를 시작하세요 | Open a video to prepare subtitles | 빈 화면 | 구현 |
| `player.empty_subtitle` | 로컬 영상부터 시작합니다. 자막이 없으면 글레이즈가 준비를 도와드립니다. | Start with a local file. If subtitles are missing, Glaze will help prepare them. | 빈 화면 | 구현 |
| `player.no_file` | 선택된 영상 없음 | No video selected | 상태 | 구현 |
| `player.open_video` | 영상 열기 | Open Video | 버튼 | 구현 |
| `subtitle.generate` | 자막 생성 | Generate Subtitles | 버튼 | 구현 |
| `subtitle.error.read_failed` | 자막 파일을 읽을 수 없습니다. | Could not read subtitle file. | 오류 | 구현 |
| `subtitle.import` | 자막 파일 불러오기 | Import Subtitle File | 버튼 | 구현 |
| `subtitle.import_panel.title` | 자막 파일을 선택하세요 | Choose a subtitle file | 시스템 패널 | 구현 |
| `subtitle.panel.toggle` | 자막 | Subtitles | 버튼 | 구현 |
| `subtitle.panel.title` | AI 자막 준비 | AI Subtitle Prep | 패널 제목 | 구현 |
| `subtitle.panel.subtitle` | 재생 전에 재사용 가능한 자막을 준비합니다. | Prepare reusable subtitles before playback. | 안내 | 구현 |
| `subtitle.panel.language` | 영상 언어 | Video language | 설정 | 구현 |
| `subtitle.panel.auto_detect` | 자동 감지 | Auto detect | 설정값 | 구현 |
| `subtitle.panel.output` | 출력 | Output | 설정 | 구현 |
| `subtitle.panel.output_dual` | 원문 + 한국어 | Original + Korean | 설정값 | 구현 |
| `subtitle.panel.output_korean_available` | 한국어 자막 사용 가능 | Korean subtitle available | 상태 | 구현 |
| `subtitle.panel.output_original_available` | 자막 파일 사용 가능 | Subtitle file available | 상태 | 구현 |
| `subtitle.panel.mode` | 모델 모드 | Model mode | 설정 | 구현 |
| `subtitle.panel.mode_standard` | 표준 | Standard | 설정값 | 구현 |
| `subtitle.panel.storage` | 저장 위치 | Save location | 설정 | 구현 |
| `subtitle.panel.storage_ask` | 생성 시 확인 | Ask when generating | 설정값 | 구현 |
| `subtitle.status.no_video` | 영상 없음 | No video | 상태 | 구현 |
| `subtitle.status.no_subtitle` | 자막 없음 | No subtitles | 상태 | 구현 |
| `subtitle.status.ready_to_generate` | 생성 가능 | Ready to generate | 상태 | 구현 |
| `subtitle.status.subtitle_detected` | 자막 감지됨 | Subtitles found | 상태 | 구현 |
| `subtitle.status.korean_subtitle_detected` | 한국어 자막 감지됨 | Korean subtitles found | 상태 | 구현 |
| `subtitle.status.hint` | 자막 생성은 사용자가 요청할 때만 시작됩니다. | Subtitle generation starts only when you ask for it. | 안내 | 구현 |
| `subtitle.status.generate_or_import_hint` | 같은 이름의 자막을 찾지 못했습니다. 필요할 때 생성하거나 불러올 수 있습니다. | No matching subtitles found. Generate subtitles or import a file when needed. | 안내 | 구현 |
| `subtitle.status.detected_hint_format` | 감지됨: %@ | Detected: %@ | 상태 | 구현 |
| `subtitle.status.loaded_hint_format` | 표시 중: %@ | Showing: %@ | 상태 | 구현 |
| `subtitle.status.subtitle_loaded` | 자막 표시 중 | Subtitles loaded | 상태 | 구현 |

## 앞으로 필요한 텍스트 그룹

### 자막 파일 불러오기

- 자막 파일 불러오기: 구현
- SRT/VTT/SMI 파일 선택: 구현
- 지원하지 않는 자막 형식입니다
- 자막 파일을 읽을 수 없습니다: 구현

### 자막 생성 요청

- 한국어 자막 파일이 없습니다. 자막을 생성할까요?
- 자막 생성
- 그냥 시청
- 자막 파일 불러오기
- 저장 위치 선택
- 앱 내부에 저장
- 영상 파일 옆에 저장

### 작업 진행

- 오디오 추출 중
- 음성 인식 중
- 자막 정리 중
- 번역 중
- 완료
- 실패
- 다시 시도

### 권한/저장 오류

- 저장 권한이 필요합니다
- 영상 폴더에 쓸 수 없습니다
- 앱 내부 저장으로 변경할까요?
- 파일이 이동되었거나 삭제되었습니다

### 가이드/FAQ 후보

- 자막은 어디에 저장되나요?
- 온디바이스 처리는 무엇인가요?
- 왜 MKV 파일이 재생되지 않나요?
- SMI 자막도 지원하나요?
- 자막 생성에는 얼마나 걸리나요?
- 생성된 자막을 다른 플레이어에서도 쓸 수 있나요?

## 업데이트 규칙

- 새로운 화면을 만들 때 이 문서에 텍스트 키를 먼저 추가한다.
- 한국어/영어 문구를 동시에 작성한다.
- 구현된 키는 `Localizable.strings`와 대조한다.
- FAQ나 사용자 가이드로 확장 가능한 문구는 별도 후보에 남긴다.
