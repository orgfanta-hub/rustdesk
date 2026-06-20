LuxCom 안드로이드 런처 아이콘 — 이 폴더에 넣으세요.

apply-branding.mjs (LUX_ANDROID=1) 가 빌드 시 이 폴더의 아이콘을 RustDesk 기본 아이콘 위에 덮어씁니다.
미제공(이 폴더에 아이콘 없음) 시 RustDesk 기본 아이콘으로 빌드됩니다(빌드는 정상).
원본(RustDesk)에 존재하는 아이콘 파일만 교체하므로 누락돼도 안전합니다.

[방법 A — 밀도별 PNG (권장, 가장 깔끔)]
  mipmap-mdpi/ic_launcher.png      48x48
  mipmap-hdpi/ic_launcher.png      72x72
  mipmap-xhdpi/ic_launcher.png     96x96
  mipmap-xxhdpi/ic_launcher.png    144x144
  mipmap-xxxhdpi/ic_launcher.png   192x192
  (선택) 각 폴더에 ic_launcher_round.png · ic_launcher_foreground.png · ic_stat_logo.png 동일 규격
    - ic_launcher_foreground.png = 적응형 아이콘 전경(투명 배경, 안전영역 위해 가장자리 여백)
    - ic_stat_logo.png           = 알림용 단색(흰색 실루엣) 권장

[방법 B — 단일 고해상도 1개 (간편)]
  ic_launcher.png  (예: 512x512 이상)
  → CI 의 ImageMagick(magick/convert)으로 밀도별 자동 리사이즈(러너에 기본 설치).
  (라운드/적응형 전경도 같은 이미지로 채워져 모양이 최적은 아님 — 정밀히 하려면 방법 A)

배경색은 brand.config.json 의 android.launcherBackgroundColor 로 지정(기본 #0E8A7E 소프트 틸).
