# 작업 운영 원칙

작성일: 2026-06-18  
프로젝트명: 글레이즈 / Glaze

## 문서 목적

이 문서는 글레이즈 프로젝트의 작업 방식을 고정하기 위한 운영 원칙이다. MVP 단계라도 임시로 흘려보내지 않고, 기능 구현과 동시에 제품 자료를 축적해 이후 iOS/iPadOS, Android, Windows, 브라우저 확장 개발의 기준 데이터로 활용한다.

## 핵심 원칙

글레이즈의 작업은 항상 아래 흐름을 따른다.

1. 관련 제품/디자인/사용자 플로우 맥락을 확인한다.
2. 기능 또는 문서 작업을 진행한다.
3. 정상 동작 여부를 검증한다.
4. 관련 문서를 갱신한다.
5. Git에 커밋한다.
6. GitHub에 push한다.

이 흐름은 선택 사항이 아니라 기본 작업 방식이다.

## 왜 중요한가

글레이즈는 macOS MVP에서 끝나는 프로젝트가 아니다. macOS 버전은 이후 모바일, Windows, 브라우저 확장으로 확장하기 위한 기준 구현체다.

따라서 MVP 단계부터 아래 자료가 축적되어야 한다.

- 기능이 왜 필요한지
- 사용자가 어떤 흐름으로 사용하는지
- 어떤 텍스트가 화면에 표시되는지
- 어떤 예외/오류가 있는지
- 어떤 정책 리스크가 있는지
- 어떤 플랫폼 확장 고려가 필요한지
- 구현 후 정상 동작했는지

영상 호환성은 번역/AI 기능보다 선행하는 제품 신뢰성 기준으로 관리한다. FFmpeg는 App Store 후보에서는 LGPL-only 빌드와 소스/고지 제공 기준을 충족한 경우에만 번들 후보로 둔다.

이 자료가 쌓여야 나중에 사용자 가이드, FAQ, 고객지원, 다른 플랫폼 기획, 번역/localization 작업을 다시 처음부터 하지 않아도 된다.

## 문서 갱신 규칙

기능이나 사용자 경험이 바뀌면 관련 문서를 같이 갱신한다.

| 변경 유형 | 갱신 문서 |
|---|---|
| 제품 방향 변경 | `02_product_direction.md` |
| AI 자막 흐름 변경 | `03_ai_subtitle_workflow.md` |
| 개발 단계/범위 변경 | `04_product_development_plan.md`, `10_development_start_checklist.md` |
| 브라우저 확장/웹 영상 전략 | `05_browser_extension_strategy.md` |
| 플랫폼 확장 전략 | `06_platform_global_expansion_plan.md` |
| MVP 결정 변경 | `07_mvp_scope_and_decisions.md` |
| 브랜드/이름/톤 변경 | `08_brand_naming_strategy.md` |
| 수익화 후보/필터링 변경 | `09_monetization_feature_tiers.md` |
| UI/디자인 방향 변경 | `11_ui_reference_design_direction.md` |
| 메뉴/버튼/알림/오류 문구 추가 | `12_service_text_inventory.md` |
| 사용자 행동 흐름 변경 | `13_user_flows.md` |

## 서비스 텍스트 관리

사용자에게 보이는 문구는 코드에만 추가하지 않는다.

새 문구가 생기면:

1. `docs/12_service_text_inventory.md`에 추가한다.
2. 한국어/영어 문구를 같이 작성한다.
3. `Localizable.strings`에 반영한다.
4. 문구 유형을 분류한다: 메뉴, 버튼, 상태, 안내, 알림, 오류, 설정, 빈 화면, 가이드.

## 사용자 플로우 관리

새 기능이 생기면 사용자 플로우를 함께 기록한다.

기록해야 할 항목:

- 사용자의 시작 행동
- 앱의 판단
- 표시되는 상태/문구
- 사용자 선택지
- 성공 흐름
- 실패/예외 흐름
- FAQ로 이어질 질문

사용자 플로우가 어색하면 구현을 수정한다. 문서가 코드를 따라가는 것이 아니라, 문서와 코드가 서로 검증해야 한다.

## 검증 기준

코드 변경 후 아래를 확인한다.

- `./script/build_and_run.sh --bundle` — 앱 빌드
- `cd Packages/GlazeCore && swift test` — Core 로직 테스트
- **UI를 바꿨으면 실행 화면을 캡처해 눈으로 확인한다.** 코드에 API가 들어간 것과 화면이 바뀐 것은 다르다
- localization 키 누락이 없는지
- 기존 사용자 플로우가 깨지지 않았는지
- 새 예외 상황이 문서화되었는지

놓치면 조용히 깨지는 항목은 `19_engineering_guardrails.md`에 따로 모았다. **작업 시작 전에 먼저 읽는다.**

## Git/GitHub 원칙

- 정상 검증된 작업은 커밋한다.
- 커밋 후 GitHub에 push한다.
- `main`은 항상 기준 상태로 유지한다.
- 큰 실험은 필요 시 별도 브랜치에서 진행한다.
- 문서만 바꿔도 의미 있는 변경이면 커밋한다.

## 에이전트 기준 파일

루트의 `AGENTS.md`는 Codex/에이전트가 먼저 읽어야 하는 작업 지침이다. 새 세션이나 다른 에이전트가 작업할 때도 이 파일을 기준으로 같은 작업 방식을 유지한다.

## 현재 기준 명령

빌드와 실행:

```bash
./script/build_and_run.sh          # Debug 빌드 후 실행
./script/build_and_run.sh release  # 최적화 빌드 (체감 속도는 이걸로 판단)
```

Core 테스트:

```bash
cd Packages/GlazeCore && swift test
```

`swift build`는 더 이상 앱을 만들지 않는다 — 앱은 `Glaze.xcodeproj`(xcodegen이 `project.yml`에서 생성)로 빌드한다.

GitHub remote:

```text
https://github.com/Edwin-space/glaze.git
```

## 결론

글레이즈의 macOS MVP는 단순 첫 버전이 아니라, 향후 제품군 전체의 기준 구현체다. 그러므로 기능을 만들고 끝내지 않고, 검증하고 기록하고 반영하고 공유하는 방식으로 계속 진행한다.
