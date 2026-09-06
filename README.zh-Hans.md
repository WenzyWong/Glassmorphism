# Glassmorphism 毛玻璃叠加

[English](README.md) · [繁體中文](README.zh-Hant.md) · **简体中文**

一个 macOS 小工具：把图片拖进来，在图上叠任意多块毛玻璃面板，用滑块调每一个参数，
最后以**原图尺寸**导出。

![效果示例](docs/example.png)

## 功能

- **多块面板**：每块各自持有完整的样式与文字，互不影响。
- **自动对齐图片圆角**：图片本身有圆角时（例如窗口截图），会量出半径并作为面板的默认圆角。
- **全参数滑块**：模糊半径、叠色颜色与浓度、圆角、边框、噪点颗粒、外阴影。
- **面板上可打字**：标题与副标题，字体、字号、颜色、对齐都能调。
- **所见即所得**：预览与导出走同一个渲染器，画面上看到什么，导出就是什么，只差分辨率。
- **原尺寸导出**，或直接复制到剪贴板。
- **三种语言**：English、简体中文、繁體中文，从「语言」菜单实时切换。

## 安装

到 [Releases 页面](../../releases) 下载最新的 zip，解压后把 `Glassmorphism.app`
拖到 `/Applications`。

这个 App 只做了临时签名、**没有经过公证**（公证需要付费的 Apple 开发者账号），
所以首次打开会被 macOS 拦下。两种做法：在 App 上点右键选「打开」，或者清掉隔离属性：

```bash
xattr -dr com.apple.quarantine /Applications/Glassmorphism.app
```

通用二进制（Apple 芯片 + Intel），需要 macOS 13 或更高版本。

## 从源码构建

只需要 Command Line Tools，不需要安装完整的 Xcode。

```bash
./build.sh                  # 编译本机架构 → dist/Glassmorphism.app
open dist/Glassmorphism.app

./release.sh 1.0.0          # 通用二进制 + zip + 校验和，可直接上传
```

开发时也可以直接 `swift run`。

## 使用

| 操作 | 方式 |
|---|---|
| 载入图片 | 拖进窗口、按 ⌘O，或用本 App 打开文件 |
| 选中面板 | 在画布上点该面板，或点右侧列表 |
| 移动面板 | 直接拖动 |
| 缩放面板 | 拖动 8 个控制点的任意一个 |
| 临时关掉磁吸 | 拖动时按住 ⌥ |
| 新建面板 | ⌘N |
| 复制面板 | ⌘D |
| 删除面板 | ⌘⌫ |
| 调整叠放层级 | ⌘] 上移、⌘[ 下移 |
| 导出 PNG | ⌘S（原图尺寸） |
| 复制 | ⇧⌘C（原图尺寸） |

未选中的面板是白色虚线框，选中的是实线框加 8 个控制点。

移动与缩放都会磁吸对齐：目标是图片的四边与中线，以及其他面板的边与中线，吸住时会用洋红色
画出参考线。吸附距离是**画面上的 8 个点**而不是图片的某个比例，所以窗口放大缩小手感都一样。
要微调时按住 ⌥ 可以临时关掉。

## 参数

每块面板各自一套。

- **毛玻璃**：模糊半径、叠色、叠色浓度、圆角半径、噪点颗粒
- **边框**：宽度、颜色、透明度
- **阴影**：开关、扩散、浓度
- **文字**：标题、副标题、字体、标题加粗、标题／副标题字号、颜色、对齐、行距、内边距

默认值直接写在 `GlassStyle` 的属性初始值上（模糊 30px、叠色 10%、
边框 3px / 50%、阴影开启 69px / 30%）。这些是绝对像素值，载入很小的图时会由
`ParamRange` 夹回滑块范围内；文字尺寸则仍随图片大小自适应。

圆角是例外：载入图片时由 `CornerDetector` 量出图片自身的圆角半径作为默认值，量不到就是 0
（直角）。它只认 alpha 通道上的透明圆角，也就是窗口截图或去背素材的样子；用纯色背景画出来的
假圆角不会被检测到。实际量到多少会显示在「信息」区。

## 所见即所得是怎么做到的

这是动代码前唯一需要先理解的约定：

- 面板矩形用**归一化坐标**存储（0…1，原点左上），与分辨率无关。
- 所有像素参数（模糊半径、圆角、字号…）一律以**原图像素**为单位。
- `GlassRenderer.render(base:spec:scale:)` 是唯一的合成实现。预览传入缩略图与
  `scale = 缩略图宽 / 原图宽`，导出传入原图与 `scale = 1`，内部把所有像素参数乘上
  `scale`。因此两者只可能差在分辨率。

每块面板的合成顺序：外侧投影 → 圆角路径 clip → 贴**整张图的模糊版**（铺满整幅，
所以玻璃底下的内容与原图精确对齐）→ 叠色 → 噪点（overlay）→ 描边 → CoreText 画文字。

每块面板的模糊都采样自**原始底图**，而不是已经画上前几块面板的画布。因此面板互相重叠时
不会重复模糊，每块的外观也不受叠放顺序影响。

## 文件结构

```
Package.swift
Sources/Glassmorphism/
  GlassApp.swift        入口、菜单、开文件事件
  ContentView.swift     布局、拖放、工具栏、导出／复制
  CanvasView.swift      图片显示、面板选中／拖动／缩放
  InspectorView.swift   面板列表与参数
  Model.swift           GlassPanel、参数模型、滑块范围、AppState
  Renderer.swift        CoreGraphics + CoreImage 合成
  Localization.swift    三个语言的字符串表
  CornerDetection.swift 从 alpha 通道量出图片自身的圆角
  Snapping.swift        拖动与缩放时的磁吸对齐
Resources/
  Info.plist            bundle 信息（__VERSION__ 在构建时替换）
  AppIcon.icns          由 Tools/make-icon.sh 生成
Samples/
  sample.png            低饱和的测试底图，带细节可检查模糊效果
  rounded-window.png    圆角窗口截图，用来测圆角检测
Tools/                  打包、图标生成、测试（run-tests.sh）
build.sh                开发构建
release.sh              通用二进制 + zip，供 GitHub Release 使用
```

## 致谢

使用 [Claude Code](https://claude.ai/code) 协作开发。

## 许可

MIT，见 [LICENSE](LICENSE)。
