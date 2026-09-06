# 애플TV가 재생 때마다 죽던 이유

작성일: 2026-09-06

`docs/24`가 "원인을 로그로 보지 못했다"고 남겨둔 애플TV 크래시의 정체를 찾았다.
아이폰 플레이어를 고치다 같은 증상을 시뮬레이터에서 재현하면서 드러났다.

## 무엇이었나

```
__assert_rtn
vlc_player_SetSubtitleTextScale
libvlc_video_set_spu_text_scale
-[VLCMediaPlayer setCurrentSubTitleFontScale:]
TVPlaybackModel.start(_:at:subtitleURL:preferredSubtitleLanguageCode:…)
closure #2 in TVPlayerView.body.getter
```

VLC의 `currentSubTitleFontScale`은 **비율**을 받는다 — 1.0이 보통 크기이고,
`vlc_player_SetSubtitleTextScale`이 0.1…5 밖의 값에 단언문을 건다. 우리는 사람이
고르는 단위인 **퍼센트**(100)를 그대로 넘겼다. 10000%를 요구한 셈이고, libVLC가
`abort()`로 프로세스를 끝냈다. `SIGABRT`, Abort trap: 6.

## 왜 "큰 파일에서만" 그런 것처럼 보였나

그렇지 않았다. **모든 파일에서 그랬다.**

- 이 줄은 `843ed13`(8월 31일)에 들어왔다
- 재생을 시작하는 곳은 `TVDetailView`와 `TVSeriesView` 둘뿐이고, **둘 다 예외 없이**
  `preferredSubtitleScale: preferences.subtitleScale`을 넘긴다. 기본값은 100이다
- 실기기용 `tvos-arm64` 바이너리에도 이 단언문이 들어 있다 (`strings`로 확인)

그러니 8월 31일 이후 애플TV에서 재생을 누르면 파일이 무엇이든 죽었다. 4K도, HDR도,
5.1ch도 원인이 아니었다 — 그 조건들에서 시도했기 때문에 그렇게 보였을 뿐이다.

**이것으로 설명되지 않는 것:** WebDAV로 폴더를 훑다가 앱이 종료된 건. 그건 재생 시작
시점이 아니므로 별개의 문제이고, 아직 원인 미확인이다.

## 증거

| 리포트 | 시각 | 프로세스 | 원인 |
|---|---|---|---|
| `Glaze-2026-09-04-184813.ips` | 9/4 18:48 | tvOS 시뮬레이터 | 같은 단언문, `TVPlaybackModel.start` |
| `Glaze-2026-09-06-115818.ips` | 9/6 11:58 | iOS 시뮬레이터 | 같은 단언문, `IOSPlaybackModel.start` |
| `Glaze-2026-09-06-115912.ips` | 9/6 11:59 | iOS 시뮬레이터 | 같은 단언문 |

## 고친 방법

단위 변환을 `GlazeCore`의 `SubtitleScale`로 옮겼다. 화면은 퍼센트로 말하고,
플레이어에 넘기기 직전에 비율로 바꾸며, VLC가 받아들이는 범위로 자른다. 두 플레이어가
같은 곳을 쓴다. `SubtitleScaleTests`가 "인터페이스가 제공하는 모든 크기가 VLC가
받아들이는 범위 안에 들어가는가"를 검사한다.

같은 종류의 함정이 하나 더 있었다: `mediaPlayerBufferingChanged`가 주는 값도 퍼센트가
아니라 0…1 비율이다. **VLCKit에서 넘어오는 수치는 단위를 의심하고 확인할 것.**

## 남은 확인

- 고친 빌드를 **실제 애플TV에 설치해 재생**해 보기. 이 문서의 결론은 리포트 세 건과
  바이너리 확인에 근거한 것이고, 실기기에서 재생이 되는 것까지 본 것은 아니다
- WebDAV 폴더 스캔 중 종료 (별개, 원인 미확인)
