import AppKit
import SwiftUI

// MARK: - 座標與尺寸約定
//
// （整個 App 的核心約定，改動前請先讀）
//   * 面板矩形用「歸一化座標」儲存：x/y/width/height 皆為 0...1，原點在圖片左上角。
//   * GlassStyle / TextStyle 裡所有像素單位的值（模糊半徑、圓角、字級…）
//     一律以「原圖像素」為單位。
//   渲染時只要把像素參數乘上 scale（= 實際繪製底圖寬 / 原圖寬），
//   預覽與導出就必然一致。

/// 滑桿範圍集中在這裡，Inspector 與預設值的夾限共用同一份定義。
enum ParamRange {
    static func unit(_ size: CGSize) -> Double {
        let u = min(size.width, size.height)
        return u > 0 ? Double(u) : 1000
    }

    static func blur(_ u: Double)         -> ClosedRange<Double> { 0...(u * 0.15) }
    static func corner(_ u: Double)       -> ClosedRange<Double> { 0...(u * 0.5) }
    static func borderWidth(_ u: Double)  -> ClosedRange<Double> { 0...(u * 0.02) }
    static func shadowRadius(_ u: Double) -> ClosedRange<Double> { 0...(u * 0.15) }
    static func titleSize(_ u: Double)    -> ClosedRange<Double> { 0...(u * 0.3) }
    static func subtitleSize(_ u: Double) -> ClosedRange<Double> { 0...(u * 0.2) }
    static func lineGap(_ u: Double)      -> ClosedRange<Double> { 0...(u * 0.1) }
    static func padding(_ u: Double)      -> ClosedRange<Double> { 0...(u * 0.2) }
    static let ratio: ClosedRange<Double> = 0...1
    static let noise: ClosedRange<Double> = 0...0.6
}

private func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double {
    min(max(v, r.lowerBound), r.upperBound)
}

// MARK: - 樣式

struct GlassStyle: Equatable {
    // 這裡的字面值就是新面板的預設外觀
    var blurRadius: Double = 30
    var tintColor: Color = .white
    var tintOpacity: Double = 0.10
    var cornerRadius: Double = 0
    var borderWidth: Double = 3
    var borderColor: Color = .white
    var borderOpacity: Double = 0.50
    var noiseAmount: Double = 0
    var shadowEnabled: Bool = true
    var shadowRadius: Double = 69
    var shadowOpacity: Double = 0.30

    /// 預設值是絕對像素值；很小的圖上可能超出滑桿範圍，這裡夾回去。
    static func defaults(for size: CGSize) -> GlassStyle {
        let u = ParamRange.unit(size)
        var s = GlassStyle()
        s.blurRadius   = clamp(s.blurRadius, ParamRange.blur(u))
        s.cornerRadius = clamp(s.cornerRadius, ParamRange.corner(u))
        s.borderWidth  = clamp(s.borderWidth, ParamRange.borderWidth(u))
        s.shadowRadius = clamp(s.shadowRadius, ParamRange.shadowRadius(u))
        return s
    }
}

enum TextAlign: String, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }

    func name(_ s: Strings) -> String {
        switch self {
        case .left: return s.alignLeft
        case .center: return s.alignCenter
        case .right: return s.alignRight
        }
    }

    var ctAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

struct TextStyle: Equatable {
    var title: String = ""
    var subtitle: String = ""
    /// 空字串代表使用系統字體
    var fontFamily: String = ""
    var titleBold: Bool = true
    var titleSize: Double = 48
    var subtitleSize: Double = 20
    var color: Color = .white
    var align: TextAlign = .center
    var lineGap: Double = 8            // 標題與副標之間的間距
    var padding: Double = 32           // 文字距面板邊緣的內縮

    /// 文字尺寸維持隨圖片大小自適應
    static func defaults(for size: CGSize) -> TextStyle {
        let u = ParamRange.unit(size)
        var t = TextStyle()
        t.titleSize = (u * 0.075).rounded()
        t.subtitleSize = (u * 0.032).rounded()
        t.lineGap = (u * 0.015).rounded()
        t.padding = (u * 0.04).rounded()
        return t
    }
}

// MARK: - 面板

/// 一塊毛玻璃。每塊各自持有完整的樣式與文字，互不影響。
struct GlassPanel: Identifiable, Equatable {
    var id = UUID()
    var rect: CGRect            // 歸一化，原點左上
    var style: GlassStyle
    var text: TextStyle
}

struct RenderSpec: Equatable {
    /// 陣列順序即繪製順序：後面的疊在前面的之上
    var panels: [GlassPanel]
}

// MARK: - App 狀態

@MainActor
final class AppState: ObservableObject {
    /// 原圖（原始像素）
    @Published private(set) var original: CGImage?
    /// 供預覽用的縮圖，最長邊不超過 previewMaxSide
    @Published private(set) var previewBase: CGImage?
    @Published private(set) var sourceName: String = ""

    @Published var panels: [GlassPanel] = []
    @Published var selection: UUID?

    /// 介面語言，記在 UserDefaults，下次開啟沿用
    @Published var language: Language = AppState.storedLanguage {
        didSet {
            Strings.current = language.strings
            UserDefaults.standard.set(language.rawValue, forKey: AppState.languageKey)
        }
    }

    /// 當前語言的字串表
    var s: Strings { language.strings }

    private static let languageKey = "interfaceLanguage"

    private static var storedLanguage: Language {
        guard let raw = UserDefaults.standard.string(forKey: languageKey),
              let lang = Language(rawValue: raw) else { return .system }
        return lang
    }

    init() {
        Strings.current = language.strings
    }

    /// 渲染完成的預覽畫面
    @Published private(set) var preview: NSImage?
    @Published var statusMessage: String?

    private let previewMaxSide: CGFloat = 1400

    var imageSize: CGSize {
        guard let original else { return .zero }
        return CGSize(width: original.width, height: original.height)
    }

    var hasImage: Bool { original != nil }
    var spec: RenderSpec { RenderSpec(panels: panels) }

    var selectedIndex: Int? {
        guard let selection else { return nil }
        return panels.firstIndex { $0.id == selection }
    }

    /// 預覽底圖相對原圖的縮放係數
    private var previewScale: CGFloat {
        guard let original, let previewBase, original.width > 0 else { return 1 }
        return CGFloat(previewBase.width) / CGFloat(original.width)
    }

    // MARK: 載入

    func load(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
        else {
            statusMessage = s.errorRead
            return
        }
        load(image: img, name: url.lastPathComponent)
    }

    func load(image: CGImage, name: String) {
        original = image
        sourceName = name
        previewBase = GlassRenderer.downscale(image, maxSide: previewMaxSide)
        GlassRenderer.invalidateCache()
        lastRenderedSpec = nil
        panels = []
        selection = nil
        addPanel()                      // 新圖預設就帶一塊面板
        statusMessage = nil
        refreshPreview()
    }

    // MARK: 面板管理

    func newPanel() -> GlassPanel {
        GlassPanel(rect: cascadeRect(),
                   style: GlassStyle.defaults(for: imageSize),
                   text: TextStyle.defaults(for: imageSize))
    }

    @discardableResult
    func addPanel() -> UUID? {
        guard hasImage else { return nil }
        let p = newPanel()
        panels.append(p)
        selection = p.id
        return p.id
    }

    func duplicateSelected() {
        guard let i = selectedIndex else { return }
        var copy = panels[i]
        copy.id = UUID()
        // 稍微錯開，免得完全疊住看不出來
        copy.rect = offset(copy.rect, by: 0.03)
        panels.insert(copy, at: i + 1)
        selection = copy.id
    }

    func deleteSelected() {
        guard let i = selectedIndex else { return }
        panels.remove(at: i)
        selection = panels.isEmpty ? nil : panels[min(i, panels.count - 1)].id
    }

    /// 把選中的面板往上/下移一層（影響互相遮蓋的順序）
    func moveSelected(up: Bool) {
        guard let i = selectedIndex else { return }
        let j = up ? i + 1 : i - 1
        guard panels.indices.contains(j) else { return }
        panels.swapAt(i, j)
    }

    private func cascadeRect() -> CGRect {
        let w = 0.5, h = 0.28
        let step = 0.045 * Double(panels.count)
        return CGRect(x: min(0.10 + step, 1 - w),
                      y: min(0.14 + step, 1 - h),
                      width: w, height: h)
    }

    private func offset(_ r: CGRect, by d: Double) -> CGRect {
        CGRect(x: min(r.minX + d, 1 - r.width),
               y: min(r.minY + d, 1 - r.height),
               width: r.width, height: r.height)
    }

    // MARK: 預覽

    /// 上一次真正算過的 spec。拖曳時手勢已經即時重算過，
    /// 之後 onChange 補送的同一份 spec 就直接跳過，不重複渲染。
    private var lastRenderedSpec: RenderSpec?

    func refreshPreview() {
        guard let previewBase else { preview = nil; return }
        let current = spec
        guard current != lastRenderedSpec else { return }
        guard let cg = GlassRenderer.render(base: previewBase, spec: current, scale: previewScale) else { return }
        lastRenderedSpec = current
        preview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// 以原圖解析度合成
    func renderFullResolution() -> CGImage? {
        guard let original else { return nil }
        return GlassRenderer.render(base: original, spec: spec, scale: 1)
    }

    // MARK: 導出

    func exportPNG() {
        guard let image = renderFullResolution() else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = suggestedFileName()
        savePanel.canCreateDirectories = true
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        guard let data = pngData(image) else {
            statusMessage = s.errorEncode
            return
        }
        do {
            try data.write(to: url)
            statusMessage = s.exported("\(image.width)×\(image.height)", url.lastPathComponent)
        } catch {
            statusMessage = s.errorWrite(error.localizedDescription)
        }
    }

    func copyToPasteboard() {
        guard let image = renderFullResolution(), let data = pngData(image) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
        statusMessage = s.copied("\(image.width)×\(image.height)")
    }

    private func pngData(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width, height: image.height)
        return rep.representation(using: .png, properties: [:])
    }

    private func suggestedFileName() -> String {
        let base = (sourceName as NSString).deletingPathExtension
        return (base.isEmpty ? "glass" : base) + "-glass.png"
    }
}
