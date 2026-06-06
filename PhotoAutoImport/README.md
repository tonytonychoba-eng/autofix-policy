# 照片自動匯入（PhotoAutoImport）

一個 macOS **選單列常駐 App**：只要把 SD 卡或隨身碟插上 MacBook，就自動把裡面的
照片與影片複製到你指定的資料夾。

## 功能

- 🔌 **插卡自動匯入**：偵測到可移除卷宗掛載就開始匯入（內接磁碟不會被動到）。
- 📅 **按拍攝日期分資料夾**：存成 `目的地/2026-06-06/IMG_0001.JPG`。
- 🚫 **避免重複匯入**：記住已匯入的檔案，下次插同一張卡不會重複複製。
- 🔔 **完成時發系統通知**：告訴你新匯入幾個、略過幾個。
- 🗑 **匯入後可選清空卡**：成功匯入後跳出確認視窗，你按下才會刪卡上的照片影片
  （預設關閉，要在選單裡打開）。
- 🎬 **匯入後可選送進達芬奇**：成功匯入後詢問你要不要把素材丟進 DaVinci Resolve，
  自動在媒體池 `AutoImport` bin 下依日期建立子 bin 並匯入（需 **Resolve Studio**，預設關閉）。

支援常見格式：JPG/HEIC/PNG/TIFF/RAW（CR2/CR3/NEF/ARW/RAF/ORF/DNG…）、
MOV/MP4/M4V/AVI/MTS/M2TS… 等。

## 系統需求

- macOS 11 以上
- 安裝 Xcode 或 Command Line Tools（提供 `swift` 編譯器）：
  `xcode-select --install`

## 建置與執行

```bash
cd PhotoAutoImport
./scripts/build_app.sh
open PhotoAutoImport.app
```

啟動後，圖示會出現在螢幕**右上角選單列**（不會出現在 Dock）。點圖示就能看到所有設定。

> 為什麼要打包成 `.app` 而不是 `swift run`？因為系統通知中心需要 App 以
> bundle 形式執行。`build_app.sh` 會編譯、組成 `.app`、再做 ad-hoc 簽章。

## 第一次使用要給的權限

macOS 的隱私保護會在第一次需要時跳出詢問，請按允許：

1. **通知** — 啟動時會問，按「允許」才看得到匯入完成通知。
2. **卸除式磁碟區** — 第一次讀卡時可能跳出
   （系統設定 → 隱私權與安全性 → 卸除式磁碟區）。
3. **照片 / 檔案資料夾** — 若匯入到 `~/Pictures` 等位置，可能需要允許存取。

如果讀取卡片或刪檔被擋，到「系統設定 → 隱私權與安全性 → **完整磁碟取用權**」
把 `PhotoAutoImport.app` 加進去最省事。

## 達芬奇整合（選用，需 Resolve Studio）

> ⚠️ DaVinci Resolve 的**外部腳本**只有付費的 **Studio** 版支援；免費版會被擋。

1. 在選單裡打開「**匯入後詢問送進達芬奇**」。
2. Resolve 偏好設定 → System → General → **External scripting using** 設為 **Local**。
3. 匯入照片影片前，先開好 Resolve Studio 並打開一個專案。
4. 之後每次插卡匯入完，App 會問你要不要送進達芬奇；按「送進達芬奇」後，
   它會在媒體池 `AutoImport` bin 底下，依日期建立子 bin（如 `2026-06-06`）並匯入素材。

腳本位於 `davinci/davinci_import.py`，也可以單獨手動執行：

```bash
python3 davinci/davinci_import.py ~/Pictures/AutoImport/2026-06-06
```

## 開機自動啟動（選用）

系統設定 → 一般 → 登入項目 → 「登入時開啟」按 `+`，選 `PhotoAutoImport.app`。

## 設定檔位置

- 偏好設定：標準 `UserDefaults`（`com.local.photoautoimport`）
- 去重紀錄：`~/Library/Application Support/PhotoAutoImport/ledger.json`
  （刪掉這個檔，就等於忘記匯入歷史、下次會重新匯入所有檔案。）

## 專案結構

```
PhotoAutoImport/
├── Package.swift
├── scripts/build_app.sh          # 編譯 + 打包成 .app
├── davinci/davinci_import.py     # 達芬奇媒體池匯入腳本（Resolve Studio）
└── Sources/PhotoAutoImport/
    ├── main.swift                # 進入點，設定為選單列 App
    ├── AppDelegate.swift         # 選單列 UI 與匯入流程串接
    ├── VolumeMonitor.swift       # 監聽插卡 / 列出已連接的卡
    ├── Importer.swift            # 掃描、複製、去重、分資料夾、清空卡
    ├── ImportLedger.swift        # 已匯入紀錄（避免重複）
    ├── DavinciBridge.swift       # 呼叫達芬奇匯入腳本
    ├── Notifier.swift            # 系統通知
    └── Prefs.swift               # 偏好設定
```

## 安全設計

- 「清空卡」**預設關閉**，且一定會先跳確認視窗、列出已匯入數量才動手。
- 只有在「有新檔成功複製、且沒有任何失敗」時才會詢問清空，避免匯入不全就刪卡。
- 複製後會比對檔案大小，一致才算成功並記錄。
