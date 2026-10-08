# 앱 스토어 등록 이미지

`Tools/make_store_images.py`가 `StoreScreenshots` UI 테스트의 캡처 위에 문구만 얹어
만든다. 그림은 실제로 돌아가는 앱이고, 목업이 아니다.

```bash
# 1. 시뮬레이터를 준비한다 (6.9형 아이폰, 13형 아이패드)
xcrun simctl create "Glaze Shots Phone" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-27-0
xcrun simctl create "Glaze Shots Pad"   com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-16GB com.apple.CoreSimulator.SimRuntime.iOS-27-0

# 2. 각 시뮬레이터의 Glaze Documents에 "Sintel (2010).mkv"를 넣고
#    상태 표시줄을 9:41로 맞춘다
xcrun simctl status_bar <device> override --time "9:41" --cellularBars 4 --wifiBars 3 \
  --batteryState charged --batteryLevel 100

# 3. 찍는다
xcodebuild test-without-building -project Glaze.xcodeproj -scheme GlazeiOSUITests \
  -destination 'id=<device>' -resultBundlePath out.xcresult \
  -only-testing:GlazeiOSUITests/StoreScreenshots

# 4. 꺼내서 문구를 얹는다
xcrun xcresulttool export attachments --path out.xcresult --output-path raw
python3 Tools/make_store_images.py <정리한 캡처 폴더> Marketing/ios/iphone-6.9
```

## 크기

| 대상 | 애플 요구 | 여기 들어 있는 것 |
|---|---|---|
| 아이폰 | 6.9형 1320×2868 | `ios/iphone-6.9/` |
| 아이패드 | 13형 2064×2752 | `ios/ipad-13/` |

실기기로는 두 규격 다 찍을 수 없다. 가진 기기는 6.3형 아이폰과 8.3형 아이패드
미니다. 시뮬레이터는 같은 빌드를 돌리고 픽셀 크기가 정확하다.

## 화면에 나오는 영상

**Sintel** — © Blender Foundation, **CC BY 3.0**, durian.blender.org

라이선스가 요구하는 출처 표시를 **이미지 안에 그려 넣는다**(`CREDIT`). 앱 스토어
목록은 널리 퍼지는 자리이므로 어딘가 다른 문서에 적어 두는 것으로는 부족하다.

테스트에 쓰는 `test file/testmedia.mkv`는 저작권 있는 작품이라 **등록 이미지에 쓰지
않는다.** 실기기 검증에만 쓴다.

## 빠진 것

자막 선택 화면. 테스트에서 그 시트를 여는 데 두 번 실패했고(이름으로, 위치로),
자막 이야기를 하는 문구 아래에 재생 화면이 찍히는 것은 제품에 대한 거짓말이라
아예 뺐다. 시트를 열 수 있게 되면 다시 넣는다.
