import CoreGraphics
import Foundation

/// 圖片的幾何分析結果。
struct ImageAnalysis {
    /// 實際內容的範圍（原圖像素座標，原點左上）。
    ///
    /// 這不一定等於整張圖：macOS 的「所選視窗截圖」在視窗外還有一圈陰影與透明邊，
    /// 這裡指的是視窗本體那一塊。整張圖都是實心時就等於整張圖。
    var contentBounds: CGRect

    /// 內容自身的圓角半徑（原圖像素）。0 代表直角或無法判定。
    var cornerRadius: Double

    static func fullFrame(_ image: CGImage) -> ImageAnalysis {
        ImageAnalysis(contentBounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                      cornerRadius: 0)
    }
}

/// 從 alpha 通道判讀圖片的實際內容範圍與圓角。
///
/// 只認「帶 alpha 通道」的圖。不透明的圖片，或用純色背景畫出來的假圓角，
/// 一律回傳整張圖的範圍與 0 圓角。
enum ImageAnalyzer {

    /// 「實心內容」的門檻。必須高過視窗陰影，否則會把陰影算進內容範圍。
    /// 實測 macOS 視窗陰影最濃處大約在 50–90，離 200 有足夠距離。
    private static let solidThreshold: UInt8 = 200

    /// 量圓弧時的門檻。抗鋸齒邊緣是漸變的，取中間值才對得上 `trueRadius` 的幾何推導。
    private static let edgeThreshold: UInt8 = 128

    /// 小於這個半徑視為直角（純粹是抗鋸齒造成的一兩個像素）
    private static let minimumRadius = 2.0

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    // MARK: - 入口

    static func analyze(_ image: CGImage) -> ImageAnalysis {
        guard hasAlpha(image) else { return .fullFrame(image) }
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let bounds = contentBounds(of: image) ?? full
        return ImageAnalysis(contentBounds: bounds,
                             cornerRadius: cornerRadius(of: image, within: bounds))
    }

    // MARK: - 內容範圍

    /// 找出實心像素的外框。
    ///
    /// 兩段式：先在縮圖上粗掃出大概位置（一次繪製就好），再回到原圖解析度，
    /// 只裁四條窄帶把每條邊修到精確。直接在原圖上全掃會需要 W×H×4 的暫存，
    /// 大圖動輒上百 MB。
    static func contentBounds(of image: CGImage) -> CGRect? {
        guard let (coarse, scale) = coarseBounds(of: image) else { return nil }

        // 縮圖會把邊緣的 alpha 平均掉，粗掃的框可能往內縮了將近一個縮圖像素，
        // 所以往外放寬再重掃。
        let pad = min(64, Int((1 / scale).rounded(.up)) + 2)
        return refine(coarse, in: image, pad: pad)
    }

    /// 粗掃：回傳原圖座標的外框，以及所用的縮放比例
    private static func coarseBounds(of image: CGImage) -> (CGRect, Double)? {
        let maxSide = 512
        let longest = max(image.width, image.height)
        let scale = min(1, Double(maxSide) / Double(longest))
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        guard let map = alphaMap(of: image, width: w, height: h) else { return nil }

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where map[row + x] >= solidThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let inv = 1 / scale
        let rect = CGRect(x: Double(minX) * inv, y: Double(minY) * inv,
                          width: Double(maxX - minX + 1) * inv,
                          height: Double(maxY - minY + 1) * inv)
        return (rect, scale)
    }

    /// 在原圖解析度上把四條邊各自修正到精確位置
    private static func refine(_ coarse: CGRect, in image: CGImage, pad: Int) -> CGRect? {
        let w = image.width, h = image.height
        let x0 = max(0, Int(coarse.minX) - pad)
        let x1 = min(w - 1, Int(coarse.maxX) + pad)
        let y0 = max(0, Int(coarse.minY) - pad)
        let y1 = min(h - 1, Int(coarse.maxY) + pad)
        guard x1 > x0, y1 > y0 else { return nil }

        let bandH = min(2 * pad + 1, y1 - y0 + 1)
        let bandW = min(2 * pad + 1, x1 - x0 + 1)

        // 上緣：由上往下找第一條含實心像素的列
        guard let top = scan(image, rect: rect(x0, y0, x1 - x0 + 1, bandH),
                             axis: .rows, fromStart: true).map({ y0 + $0 }),
              // 下緣：由下往上
              let bottom = scan(image, rect: rect(x0, y1 - bandH + 1, x1 - x0 + 1, bandH),
                                axis: .rows, fromStart: false).map({ y1 - bandH + 1 + $0 }),
              // 左緣：由左往右找第一條含實心像素的行
              let left = scan(image, rect: rect(x0, y0, bandW, y1 - y0 + 1),
                              axis: .columns, fromStart: true).map({ x0 + $0 }),
              // 右緣：由右往左
              let right = scan(image, rect: rect(x1 - bandW + 1, y0, bandW, y1 - y0 + 1),
                               axis: .columns, fromStart: false).map({ x1 - bandW + 1 + $0 })
        else { return nil }

        guard right >= left, bottom >= top else { return nil }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    private enum ScanAxis { case rows, columns }

    /// 在一小塊區域裡，找第一條（或最後一條）含實心像素的列／行，回傳區域內的索引
    private static func scan(_ image: CGImage, rect: CGRect,
                             axis: ScanAxis, fromStart: Bool) -> Int? {
        let w = Int(rect.width), h = Int(rect.height)
        guard w > 0, h > 0,
              let crop = image.cropping(to: rect),
              let map = alphaMap(of: crop, width: w, height: h) else { return nil }

        let outer = axis == .rows ? h : w
        let inner = axis == .rows ? w : h
        for step in 0..<outer {
            let i = fromStart ? step : outer - 1 - step
            for j in 0..<inner {
                let index = axis == .rows ? i * w + j : j * w + i
                if map[index] >= solidThreshold { return i }
            }
        }
        return nil
    }

    private static func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - 圓角

    /// 量法：掃內容外框最外側那一列（行），找第一個不透明像素離角落多遠，
    /// 再用 `trueRadius` 換算回真正的半徑。四個角各量水平、垂直兩次共 8 個值，
    /// 彼此吻合才採用，避免把不規則的透明形狀誤判成圓角。
    private static func cornerRadius(of image: CGImage, within bounds: CGRect) -> Double {
        let w = Int(bounds.width), h = Int(bounds.height)
        guard w >= 16, h >= 16 else { return 0 }

        // 內容四邊的中點必須不透明，否則這不是一個「填滿的圓角矩形」，
        // 而是別種帶透明區的圖（去背的 logo、圓形頭像切片之類），不該套用。
        guard edgeMidpointsAreOpaque(image, bounds: bounds) else { return 0 }

        // 上限只是為了不要在超大圖上配置過多暫存記憶體。
        let probe = min(min(w, h) / 2, 1024)
        guard probe >= 8 else { return 0 }

        var measurements: [Double] = []
        for corner in Corner.allCases {
            guard let (horizontal, vertical) = measure(corner, in: image,
                                                       bounds: bounds, probe: probe) else {
                return 0            // 有角量不出來就整個放棄
            }
            measurements.append(horizontal)
            measurements.append(vertical)
        }

        let median = measurements.sorted()[measurements.count / 2]
        guard median >= minimumRadius else { return 0 }

        let tolerance = max(2.0, median * 0.2)
        guard measurements.allSatisfy({ abs($0 - median) <= tolerance }) else { return 0 }

        return median
    }

    /// 回傳該角落沿水平邊、垂直邊各量到的半徑；掃不到不透明像素則回傳 nil。
    private static func measure(_ corner: Corner, in image: CGImage,
                                bounds: CGRect, probe: Int) -> (Double, Double)? {
        let origin: CGPoint
        switch corner {
        case .topLeft:     origin = CGPoint(x: bounds.minX, y: bounds.minY)
        case .topRight:    origin = CGPoint(x: bounds.maxX - Double(probe), y: bounds.minY)
        case .bottomLeft:  origin = CGPoint(x: bounds.minX, y: bounds.maxY - Double(probe))
        case .bottomRight: origin = CGPoint(x: bounds.maxX - Double(probe),
                                            y: bounds.maxY - Double(probe))
        }
        let crop = CGRect(origin: origin, size: CGSize(width: probe, height: probe))
        guard let region = image.cropping(to: crop),
              let alpha = alphaMap(of: region, width: probe, height: probe) else { return nil }

        // 把「外側角落」統一換算成裁切區裡的座標，兩條邊各往內掃
        let outerX = (corner == .topLeft || corner == .bottomLeft) ? 0 : probe - 1
        let outerY = (corner == .topLeft || corner == .topRight) ? 0 : probe - 1
        let stepX = outerX == 0 ? 1 : -1
        let stepY = outerY == 0 ? 1 : -1

        var horizontal: Double?
        for i in 0..<probe {
            let x = outerX + i * stepX
            if alpha[outerY * probe + x] >= edgeThreshold { horizontal = Double(i); break }
        }
        var vertical: Double?
        for i in 0..<probe {
            let y = outerY + i * stepY
            if alpha[y * probe + outerX] >= edgeThreshold { vertical = Double(i); break }
        }

        guard let hh = horizontal, let vv = vertical else { return nil }
        return (trueRadius(fromEdgeMeasurement: hh), trueRadius(fromEdgeMeasurement: vv))
    }

    /// 由最外側像素列量到的值還原真正的半徑。
    ///
    /// 「最外列第一個不透明像素的 x 就是 r」只在數學上的邊線成立；實際上最外側那一列
    /// 是一條高 1px 的帶子，中心離邊緣 0.5px。圓弧在深度 d 處的水平位置是
    /// x = r − √(2rd − d²)，代入 d = 0.5 得 m = r − √(r − 0.25)，
    /// 反解得 r = m + √m + 0.5。
    ///
    /// 少了這一步，量到的半徑會固定短少約 √r（r=60 會量成 52，r=300 會量成 283）。
    private static func trueRadius(fromEdgeMeasurement m: Double) -> Double {
        guard m > 0 else { return 0 }
        return m + m.squareRoot() + 0.5
    }

    /// 內容四邊中點的不透明檢查
    private static func edgeMidpointsAreOpaque(_ image: CGImage, bounds: CGRect) -> Bool {
        let points = [
            CGPoint(x: bounds.midX.rounded(.down), y: bounds.minY),              // 上
            CGPoint(x: bounds.midX.rounded(.down), y: bounds.maxY - 1),          // 下
            CGPoint(x: bounds.minX, y: bounds.midY.rounded(.down)),              // 左
            CGPoint(x: bounds.maxX - 1, y: bounds.midY.rounded(.down))           // 右
        ]
        for p in points {
            let px = CGRect(x: p.x, y: p.y, width: 1, height: 1)
            guard let crop = image.cropping(to: px),
                  let a = alphaMap(of: crop, width: 1, height: 1),
                  a[0] >= edgeThreshold else { return false }
        }
        return true
    }

    // MARK: - 像素存取

    /// 取出區塊的 alpha 通道，縮放到指定尺寸。回傳的緩衝區由上而下排列，`map[y * width + x]`。
    ///
    /// 本來想用 alphaOnly 的 context（一個像素一個位元組），但 Swift 介面上
    /// CGContext 的 space 不接受 nil，只好畫成 RGBA 再抽出 alpha 位元組。
    /// 8 位元的 premultipliedLast 在記憶體中就是 R,G,B,A 的順序，alpha 在第 4 個。
    private static func alphaMap(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        let count = width * height
        guard count > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: count * 4)
        let drawn = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base,
                                      width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .none      // 縮圖只是為了粗定位，不需要平滑
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var alpha = [UInt8](repeating: 0, count: count)
        for i in 0..<count { alpha[i] = rgba[i * 4 + 3] }
        return alpha
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return false
        }
    }
}
