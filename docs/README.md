# 글레이즈 문서

이 폴더는 macOS Apple Silicon 기반 AI 영상 플레이어 "글레이즈"의 기획, 벤치마크, 제품 방향, 개발 의사결정을 기록하는 공간이다.

현재 문서는 임시로 `/Users/edwin/Documents/MAC Video Player/docs`에 작성되었다. 사용자가 지정한 SynologyDrive 프로젝트 폴더에 쓰기 권한이 열리면 아래 경로로 이전한다.

`/Users/edwin/Library/CloudStorage/SynologyDrive-Edwin-NAS/#1. Personal/Project/글레이즈/docs`

## 문서 목록

- `01_benchmark_mac_app_store.md`: Mac App Store 기준 영상 플레이어 경쟁 제품 벤치마크
- `02_product_direction.md`: 글레이즈의 제품 방향, 핵심 기능, 차별화 전략
- `03_ai_subtitle_workflow.md`: 온디바이스 AI 자막 생성 및 백그라운드 처리 흐름
- `04_product_development_plan.md`: 개발 착수 전 제품/기능/디자인/기술 실행 계획
- `05_browser_extension_strategy.md`: Chrome/Safari 확장 연동, 웹 영상 열기, HLS/다운로드 정책 검토
- `06_platform_global_expansion_plan.md`: macOS 이후 모바일, Windows, 글로벌 언어 확장 계획
- `07_mvp_scope_and_decisions.md`: MVP 포함/제외 범위와 개발 착수 전 의사결정
- `08_brand_naming_strategy.md`: 글레이즈/Glaze 브랜드 네이밍과 제품명 체계
- `09_monetization_feature_tiers.md`: 기능 구현 후 무료/유료/Pro 후보를 판단하기 위한 수익화 필터링 기준
- `10_development_start_checklist.md`: macOS 앱 개발 착수 전 체크리스트와 초기 구현 단계
- `11_ui_reference_design_direction.md`: 외부 UI 레퍼런스 기반 글레이즈 디자인 방향
- `12_service_text_inventory.md`: 메뉴, 버튼, 알림, 상태, 오류 등 서비스 텍스트 인벤토리
- `13_user_flows.md`: 핵심 사용자 플로우와 예외/FAQ 후보 정리
- `14_working_principles.md`: 구현, 검증, 문서화, GitHub 반영을 유지하기 위한 작업 운영 원칙

## 제품 한 줄 정의

글레이즈는 Apple Silicon의 온디바이스 AI 성능을 활용해, 자막이 없는 다국어 영상을 재생 전에 자동으로 자막화하고 한국어 감상 경험을 준비해주는 macOS 영상 플레이어다.
