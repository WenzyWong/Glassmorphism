import CoreGraphics
import Foundation

/// 拼貼進來的圖片圖層。
///
/// 幾何只用「中心點 + 寬度佔比 + 旋轉角」三個量描述，高度由圖片自身的長寬比推出來，
/// 所以縮放一定是等比的 —— 拼貼不該把照片拉變形。
struct PhotoLayer: Identifiable {
    var id = UUID()

    /// 導出用的原始圖
    let image: CGImage
    /// 預覽用的縮圖。預覽每幀都要重畫，直接把大圖縮到小框會很慢。
    let preview: CGImage
    let name: String

    /// 中心點（歸一化，原點左上，相對底圖）
    var center = CGPoint(x: 0.5, y: 0.5)

    /// 寬度佔底圖寬度的比例
    var widthFraction: Double = 0.4

    /// 順時針旋轉角度（度）
    var rotation: Double = 0

    /// 1 = 完全不透明，也就是預設
    var opacity: Double = 1

    var shadowEnabled = false
    var shadowRadius: Double = 40
    var shadowOpacity: Double = 0.35

    /// 圖片自身的長寬比（寬 / 高）
    var aspectRatio: Double {
        let h = Double(image.height)
        return h > 0 ? Double(image.width) / h : 1
    }

    // MARK: - 幾何
    //
    // 這一段的算術一律用 Double，跨 CGFloat 邊界時顯式轉換。
    // CGFloat 與 Double 之間有隱式轉換（SE-0307），混著寫時運算子的重載解析
    // 會隨編譯器版本而不同 —— 同一行在 Swift 6.3 編得過，在 5.10 會報
    // 「ambiguous use of operator」。顯式轉換就沒有這個問題。
    //
    // 歸一化座標的 x 與 y 各自相對底圖的寬與高，兩軸的「單位長度」不一樣，
    // 所以凡是牽涉旋轉的計算都要先換回像素，算完再normalize，
    // 否則旋轉 90° 的圖會被拉扁。

    /// 未旋轉時的像素尺寸
    func pixelSize(inBase base: CGSize) -> CGSize {
        let w = widthFraction * Double(base.width)
        return CGSize(width: w, height: w / aspectRatio)
    }

    /// 未旋轉時的框（歸一化）
    func rect(inBase base: CGSize) -> CGRect {
        let baseW = Double(base.width), baseH = Double(base.height)
        guard baseW > 0, baseH > 0 else { return .zero }
        let px = pixelSize(inBase: base)
        let w = Double(px.width) / baseW
        let h = Double(px.height) / baseH
        return CGRect(x: Double(center.x) - w / 2, y: Double(center.y) - h / 2,
                      width: w, height: h)
    }

    /// 旋轉後的軸對齊外接矩形（歸一化）。磁吸與選取框都用這個。
    func boundingRect(inBase base: CGSize) -> CGRect {
        let baseW = Double(base.width), baseH = Double(base.height)
        guard baseW > 0, baseH > 0 else { return .zero }
        let px = pixelSize(inBase: base)
        let pw = Double(px.width), ph = Double(px.height)
        let radians = rotation * .pi / 180
        let c = abs(cos(radians)), s = abs(sin(radians))
        let w = (pw * c + ph * s) / baseW
        let h = (pw * s + ph * c) / baseH
        return CGRect(x: Double(center.x) - w / 2, y: Double(center.y) - h / 2,
                      width: w, height: h)
    }

    /// 中心到未旋轉框角落的距離（像素）。等比縮放時拿來換算倍率。
    func cornerDistance(inBase base: CGSize) -> Double {
        let px = pixelSize(inBase: base)
        let w = Double(px.width), h = Double(px.height)
        return (w * w + h * h).squareRoot() / 2
    }
}

extension PhotoLayer: Equatable {
    /// CGImage 沒有 Equatable，用參照比較就夠 —— 同一張圖不會被重新載入成兩個實例。
    static func == (lhs: PhotoLayer, rhs: PhotoLayer) -> Bool {
        lhs.id == rhs.id
            && lhs.image === rhs.image
            && lhs.center == rhs.center
            && lhs.widthFraction == rhs.widthFraction
            && lhs.rotation == rhs.rotation
            && lhs.opacity == rhs.opacity
            && lhs.shadowEnabled == rhs.shadowEnabled
            && lhs.shadowRadius == rhs.shadowRadius
            && lhs.shadowOpacity == rhs.shadowOpacity
    }
}

extension PhotoLayer {
    /// 滑桿範圍。與 ParamRange 一樣集中在一處，Inspector 與夾限共用。
    enum Range {
        static let widthFraction: ClosedRange<Double> = 0.03...2.0
        static let rotation: ClosedRange<Double> = -180...180
        static let opacity: ClosedRange<Double> = 0.05...1
        static func shadowRadius(_ unit: Double) -> ClosedRange<Double> { 0...(unit * 0.15) }
        static let shadowOpacity: ClosedRange<Double> = 0...1
    }

    /// 新拖進來的圖片：擺在中央，寬度大約佔底圖的一半，但不超過原生尺寸。
    static func make(image: CGImage, preview: CGImage, name: String,
                     baseSize: CGSize, index: Int) -> PhotoLayer {
        var layer = PhotoLayer(image: image, preview: preview, name: name)
        let native = baseSize.width > 0 ? Double(image.width) / Double(baseSize.width) : 0.5
        layer.widthFraction = min(0.5, max(0.08, native))
        layer.shadowRadius = (ParamRange.unit(baseSize) * 0.03).rounded()
        // 連續拖入多張時錯開，才不會完全疊在一起
        let step = 0.04 * Double(index)
        layer.center = CGPoint(x: min(0.5 + step, 0.9), y: min(0.5 + step, 0.9))
        return layer
    }
}
