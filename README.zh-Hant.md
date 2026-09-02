# Glassmorphism 毛玻璃疊加

[English](README.md) · **繁體中文** · [简体中文](README.zh-Hans.md)

一個 macOS 小工具：把圖片拖進來，在圖上疊任意多塊毛玻璃面板，用滑桿調每一個參數，
最後以**原圖尺寸**導出。

![效果範例](docs/example.png)

## 功能

- **多塊面板**：每塊各自持有完整的樣式與文字，互不影響。
- **全參數滑桿**：模糊半徑、疊色顏色與濃度、圓角、邊框、雜訊顆粒、外陰影。
- **面板上可打字**：標題與副標，字型、字級、顏色、對齊都能調。
- **所見即所得**：預覽與導出走同一個渲染器，畫面上看到什麼，導出就是什麼，只差解析度。
- **原尺寸導出**，或直接複製到剪貼板。
- **三種語言**：English、简体中文、繁體中文，從「語言」選單即時切換。

## 安裝

到 [Releases 頁面](../../releases) 下載最新的 zip，解壓後把 `Glassmorphism.app`
拖到 `/Applications`。

這個 App 只做了臨時簽名、**沒有經過公證**（公證需要付費的 Apple 開發者帳號），
所以首次開啟會被 macOS 擋下。兩種做法：在 App 上按右鍵選「打開」，或是清掉隔離屬性：

```bash
xattr -dr com.apple.quarantine /Applications/Glassmorphism.app
```

通用二進位（Apple 晶片 + Intel），需要 macOS 13 或更新版本。

## 從原始碼建置

只需要 Command Line Tools，不需要安裝完整的 Xcode。

```bash
./build.sh                  # 編譯本機架構 → dist/Glassmorphism.app
open dist/Glassmorphism.app

./release.sh 1.0.0          # 通用二進位 + zip + 校驗碼，可直接上傳
```

開發時也可以直接 `swift run`。

## 使用

| 操作 | 方式 |
|---|---|
| 載入圖片 | 拖進視窗、按 ⌘O，或用本 App 開啟檔案 |
| 選取面板 | 在畫布上點該面板，或點右側清單 |
| 移動面板 | 直接拖動 |
| 縮放面板 | 拖動 8 個控制點的任一個 |
| 新增面板 | ⌘N |
| 複製面板 | ⌘D |
| 刪除面板 | ⌘⌫ |
| 調整疊放層級 | ⌘] 上移、⌘[ 下移 |
| 導出 PNG | ⌘S（原圖尺寸） |
| 複製 | ⇧⌘C（原圖尺寸） |

未選中的面板是白色虛線框，選中的是實線框加 8 個控制點。

## 參數

每塊面板各自一套。

- **毛玻璃**：模糊半徑、疊色、疊色濃度、圓角半徑、雜訊顆粒
- **邊框**：寬度、顏色、透明度
- **陰影**：開關、擴散、濃度
- **文字**：標題、副標、字型、標題粗體、標題／副標字級、顏色、對齊、行距、內縮

預設值直接寫在 `GlassStyle` 的屬性初始值上（模糊 30px、疊色 10%、圓角 0、
邊框 3px / 50%、陰影開啟 69px / 30%）。這些是絕對像素值，載入很小的圖時會由
`ParamRange` 夾回滑桿範圍內；文字尺寸則仍隨圖片大小自適應。

## 所見即所得是怎麼做到的

這是動程式碼前唯一需要先理解的約定：

- 面板矩形用**歸一化座標**儲存（0…1，原點左上），與解析度無關。
- 所有像素參數（模糊半徑、圓角、字級…）一律以**原圖像素**為單位。
- `GlassRenderer.render(base:spec:scale:)` 是唯一的合成實作。預覽傳入縮圖與
  `scale = 縮圖寬 / 原圖寬`，導出傳入原圖與 `scale = 1`，內部把所有像素參數乘上
  `scale`。因此兩者只可能差在解析度。

每塊面板的合成順序：外側投影 → 圓角路徑 clip → 貼**整張圖的模糊版**（鋪滿整幅，
所以玻璃底下的內容與原圖精確對齊）→ 疊色 → 雜訊（overlay）→ 描邊 → CoreText 畫文字。

每塊面板的模糊都取樣自**原始底圖**，而不是已經畫上前幾塊面板的畫布。因此面板互相重疊時
不會重複模糊，每塊的外觀也不受疊放順序影響。

## 檔案結構

```
Package.swift
Sources/Glassmorphism/
  GlassApp.swift        進入點、選單、開檔事件
  ContentView.swift     版面、拖放、工具列、導出／複製
  CanvasView.swift      圖片顯示、面板選取／拖動／縮放
  InspectorView.swift   面板清單與參數
  Model.swift           GlassPanel、參數模型、滑桿範圍、AppState
  Renderer.swift        CoreGraphics + CoreImage 合成
  Localization.swift    三個語言的字串表
Resources/
  Info.plist            bundle 資訊（__VERSION__ 在建置時代換）
  AppIcon.icns          由 Tools/make-icon.sh 生成
Samples/sample.png      低飽和的測試底圖，帶細節可檢查模糊效果
Tools/                  打包與圖示生成
build.sh                開發建置
release.sh              通用二進位 + zip，供 GitHub Release 使用
```

## 致謝

使用 [Claude Code](https://claude.ai/code) 協作開發。

## 授權

MIT，見 [LICENSE](LICENSE)。
