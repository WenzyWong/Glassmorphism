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
    ///
    /// - Parameter cornerRadius: 偵測到的圖片自身圓角。傳 0 就是直角（原本的預設）。
    static func defaults(for size: CGSize, cornerRadius: Double = 0) -> GlassStyle {
        let u = ParamRange.unit(size)
        var s = GlassStyle()
        s.blurRadius   = clamp(s.blurRadius, ParamRange.blur(u))
        s.cornerRadius = clamp(cornerRadius, ParamRange.corner(u))
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

// MARK: - 圖層順序

enum LayerKind: Equatable {
    case photo, panel
}

/// 指向某一個圖層。疊放順序由 AppState 的 layerOrder 單獨保管，
/// panels / photos 兩個陣列本身的順序不代表任何意義。
struct LayerRef: Identifiable, Equatable {
    let id: UUID
    let kind: LayerKind
}

/// 渲染時的一個項目。陣列順序即繪製順序：後面的疊在前面的之上。
enum RenderItem: Equatable {
    case photo(PhotoLayer)
    case panel(GlassPanel)

    var isPhoto: Bool { if case .photo = self { return true }; return false }
    var isPanel: Bool { if case .panel = self { return true }; return false }
}

struct RenderSpec: Equatable {
    /// 由下而上的完整圖層堆疊
    var items: [RenderItem] = []
    /// 底圖的原始像素尺寸，圖片層算旋轉外框時需要
    var baseSize: CGSize = .zero
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

    /// 拼貼進來的圖片。畫在底圖之上、毛玻璃之下 ——
    /// 玻璃要能模糊拼貼上去的圖，反過來把圖疊在玻璃上則沒什麼實際用途。
    @Published var photos: [PhotoLayer] = []

    /// 由下而上的疊放順序，涵蓋面板與圖片兩種。
    ///
    /// 這是疊放的唯一依據 —— panels / photos 兩個陣列各自的順序沒有意義，
    /// 它們只是「哪些物件存在」的容器。分開存是為了讓 Inspector 還能直接
    /// 綁 $state.panels[i] 這種路徑，不必為了排序把整個模型改成異質陣列。
    @Published var layerOrder: [LayerRef] = []

    /// 目前選中的物件。面板與圖片共用同一個選取，UUID 不會撞號，
    /// 所以直接拿它到兩個陣列裡各找一次就好。
    @Published var selection: UUID?

    /// 從圖片本身量到的圓角半徑（原圖像素）。0 代表直角或無法判定。
    /// 新面板與「重設本面板參數」都會用這個值當圓角預設。
    @Published private(set) var detectedCornerRadius: Double = 0

    /// 圖片裡實際內容的範圍（歸一化）。整張圖都是實心時就是 0…1 的滿框。
    ///
    /// macOS 的「所選視窗截圖」在視窗外還有一圈陰影與透明邊，整張圖的邊界並不是
    /// 視窗的邊界。圓角要從這個範圍量，磁吸也要吸到這個範圍的邊上，
    /// 否則會對齊到透明背景的邊緣。
    @Published private(set) var contentRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// 內容範圍是否小於整張圖
    var contentIsInset: Bool {
        contentRect.minX > 0.001 || contentRect.minY > 0.001
            || contentRect.maxX < 0.999 || contentRect.maxY < 0.999
    }

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

    var spec: RenderSpec {
        RenderSpec(items: layerOrder.compactMap { ref in
            switch ref.kind {
            case .photo: return photos.first { $0.id == ref.id }.map(RenderItem.photo)
            case .panel: return panels.first { $0.id == ref.id }.map(RenderItem.panel)
            }
        }, baseSize: imageSize)
    }

    /// 由上而下（給清單顯示用）
    var layersTopFirst: [LayerRef] { layerOrder.reversed() }

    func photo(_ id: UUID) -> PhotoLayer? { photos.first { $0.id == id } }
    func panel(_ id: UUID) -> GlassPanel? { panels.first { $0.id == id } }

    /// 選中的物件在疊放順序裡的位置
    private var selectedOrderIndex: Int? {
        guard let selection else { return nil }
        return layerOrder.firstIndex { $0.id == selection }
    }

    /// 選中的面板在 panels 裡的索引
    var selectedIndex: Int? {
        guard let selection else { return nil }
        return panels.firstIndex { $0.id == selection }
    }

    /// 選中的圖片在 photos 裡的索引
    var selectedPhotoIndex: Int? {
        guard let selection else { return nil }
        return photos.firstIndex { $0.id == selection }
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

        // 圖片自己有圓角的話（例如視窗截圖），面板就沿用同一個圓角
        let analysis = ImageAnalyzer.analyze(image)
        detectedCornerRadius = analysis.cornerRadius.rounded()
        contentRect = normalized(analysis.contentBounds,
                                 in: CGSize(width: image.width, height: image.height))

        panels = []
        photos = []
        layerOrder = []
        selection = nil
        addPanel()                      // 新圖預設就帶一塊面板
        statusMessage = detectedCornerRadius > 0
            ? s.detectedCorners("\(Int(detectedCornerRadius))")
            : nil
        refreshPreview()
    }

    // MARK: 面板管理

    func newPanel() -> GlassPanel {
        GlassPanel(rect: cascadeRect(),
                   style: GlassStyle.defaults(for: imageSize, cornerRadius: detectedCornerRadius),
                   text: TextStyle.defaults(for: imageSize))
    }

    @discardableResult
    func addPanel() -> UUID? {
        guard hasImage else { return nil }
        let p = newPanel()
        panels.append(p)
        layerOrder.append(LayerRef(id: p.id, kind: .panel))
        selection = p.id
        return p.id
    }

    func duplicateSelected() {
        guard let orderIndex = selectedOrderIndex else { return }
        let ref: LayerRef
        if let i = selectedIndex {
            var copy = panels[i]
            copy.id = UUID()
            // 稍微錯開，免得完全疊住看不出來
            copy.rect = offset(copy.rect, by: 0.03)
            panels.append(copy)
            ref = LayerRef(id: copy.id, kind: .panel)
        } else if let i = selectedPhotoIndex {
            var copy = photos[i]
            copy.id = UUID()
            copy.center = CGPoint(x: min(copy.center.x + 0.03, 1),
                                  y: min(copy.center.y + 0.03, 1))
            photos.append(copy)
            ref = LayerRef(id: copy.id, kind: .photo)
        } else {
            return
        }
        layerOrder.insert(ref, at: orderIndex + 1)   // 複本疊在原件正上方
        selection = ref.id
    }

    func deleteSelected() {
        guard let orderIndex = selectedOrderIndex else { return }
        let ref = layerOrder[orderIndex]
        switch ref.kind {
        case .panel: panels.removeAll { $0.id == ref.id }
        case .photo: photos.removeAll { $0.id == ref.id }
        }
        layerOrder.remove(at: orderIndex)
        // 選取交給原位置的鄰居，刪一整串時比較順手
        if layerOrder.isEmpty {
            selection = nil
        } else {
            selection = layerOrder[min(orderIndex, layerOrder.count - 1)].id
        }
    }

    /// 把選中的物件往上/下移一層。順序是跨種類的 ——
    /// 圖片可以疊到毛玻璃之上，反之亦然。
    func moveSelected(up: Bool) {
        guard let i = selectedOrderIndex else { return }
        let j = up ? i + 1 : i - 1
        guard layerOrder.indices.contains(j) else { return }
        layerOrder.swapAt(i, j)
    }

    /// 直接送到最上層 / 最下層
    func sendSelected(toTop: Bool) {
        guard let i = selectedOrderIndex else { return }
        let ref = layerOrder.remove(at: i)
        layerOrder.insert(ref, at: toTop ? layerOrder.count : 0)
    }

    var canMoveUp: Bool {
        guard let i = selectedOrderIndex else { return false }
        return i < layerOrder.count - 1
    }

    var canMoveDown: Bool {
        guard let i = selectedOrderIndex else { return false }
        return i > 0
    }

    // MARK: 圖片層

    /// 拖進來的圖片會變成一層拼貼，而不是換掉底圖（換底圖走 ⌘O）
    func addPhoto(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            statusMessage = s.errorRead
            return
        }
        addPhoto(image: img, name: url.lastPathComponent)
    }

    func addPhoto(image: CGImage, name: String) {
        guard hasImage else {                 // 還沒有底圖的話，第一張就當底圖
            load(image: image, name: name)
            return
        }
        let preview = GlassRenderer.downscale(image, maxSide: previewMaxSide)
        let layer = PhotoLayer.make(image: image, preview: preview, name: name,
                                    baseSize: imageSize, index: photos.count)
        photos.append(layer)
        layerOrder.append(LayerRef(id: layer.id, kind: .photo))
        selection = layer.id
        statusMessage = s.photoAdded(name)
    }

    /// 新面板擺在內容範圍裡，而不是整張圖裡 —— 視窗截圖的話才不會壓在透明邊上
    private func cascadeRect() -> CGRect {
        let c = contentRect
        let w = c.width * 0.5, h = c.height * 0.28
        let step = 0.045 * Double(panels.count)
        return CGRect(x: min(c.minX + c.width * 0.10 + step * c.width, c.maxX - w),
                      y: min(c.minY + c.height * 0.14 + step * c.height, c.maxY - h),
                      width: w, height: h)
    }

    private func normalized(_ rect: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: rect.minX / size.width, y: rect.minY / size.height,
                      width: rect.width / size.width, height: rect.height / size.height)
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
