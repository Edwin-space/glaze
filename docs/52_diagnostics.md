# 기기 내 진단 — 2026-11-09

기록은 기본 꺼짐. iPhone 설정 → 정보 → 진단에서 켠 뒤 테스트한다. 앱 강제 종료 후에도
최근 기록은 남는다. 재실행 → 진단 파일 준비 → 진단 파일 공유에서 AirDrop/파일로 내보낸다.
마켓 빌드에서도 같은 명시적 opt-in을 사용한다. 자동 업로드는 없다.

공통 DiagnosticsCenter가 직렬 utility 큐로 JSONL을 쓴다. OSLog에는 고정 이벤트 이름만
남긴다. 파일 5MB × 3개, 7일 보존, 백업 제외. 진단 화면에서 삭제할 수 있다.
내보내기는 파일을 오래된 순서로 합치고 앱/OS 버전을 붙인다.

원문 오류, 파일/폴더명, 서버 주소, 자막/번역 본문, 인증 값은 기록하지 않는다.
이벤트는 StaticString, 값은 숫자, 자료 식별은 설치별 HMAC으로 제한한다.
시스템 uptime은 내보내지 않고 앱 실행 후 경과 시간과 작업 간 소요 시간만 쓴다.
PrivacyInfo의 CA92.1/C617.1/35F9.1과 사이트 정책을 함께 유지한다.

계측: 앱 시작/활성 상태/메모리 경고, 공통 폴더 읽기, WebDAV 목록, Synology 요청,
DLNA Browse, 자막 다운로드, 미리보기, iPhone 재생·seek·stop·상태·버퍼,
도서 보관함 갱신, 탭 이동, Mac 재생/자막 생성/번역, TV 재생 시작/종료.

같은 UUID의 operation.end를 연결한다. end가 없으면 작업 중 종료/대기를 의심하고,
success=0이면 throw 또는 취소 경로를 확인한다. 각 iPhone 재생은 UUID로 구분하고 이전
재생의 지연 콜백은 배제한다. 메인 큐 heartbeat 10초 지연, 재생 시간 15초 정체 시
별도 큐에서 이벤트를 남긴다. 일시정지/비활성화와 함께 해석한다. 이벤트는 의심 징후이며
무한 루프의 증명이 아니다. C 라이브러리 교착 스택은 Xcode/기기 진단으로 보완한다.

iOS MetricKit은 crash/hang/CPU/disk 진단 개수만 저장한다. 원본 페이로드는 내보내지 않는다.
전체 크래시 스택은 TestFlight/Xcode와 해당 빌드 dSYM을 이용한다.

멈춘 즉시 시각과 동작(다음 파일, seek 등)을 메모한 뒤 종료하고 다시 실행한다.
파일의 마지막 세션, operation.end가 빠진 호출, app.main_unresponsive와
playback.stalled의 순서를 확인한다. 공개 GitHub 이슈에 첨부하지 않는다.
개발자가 직접 받은 파일은 해당 문제 해결 후 30일 이내 삭제한다.

## 검증

- DiagnosticsTests 2개 통과: opt-in, 잘못된 raw ID 제외, HMAC 일관성, 재생성 보존, 삭제, 파일 회전.
- iOS UI 테스트 1개 통과: 설정에서 켬 → 프로세스 종료 → 재실행 후 켜짐 확인 → 보고서 준비 → 공유 버튼 확인. 스크린샷 확인.
- iPhone Debug/Release 서명 빌드, Mac Debug, tvOS 시뮬레이터 Debug 빌드 통과.
- PrivacyInfo plist 검사 및 git diff 공백 검사 통과.
- 실제 iPhone 설치는 기기 잠금/개발 서비스 연결 거절(CoreDevice 4016)로 미완료. 잠금 해제 후 설치 재시도 필요.
- 실제 NAS 다중 파일 재생의 멈춤 원인은 아직 재현·확정하지 않았다. 이 진단 빌드로 수집 후 처리한다.
