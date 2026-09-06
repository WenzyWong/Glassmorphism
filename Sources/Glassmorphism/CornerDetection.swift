import CoreGraphics
import Foundation

/// 偵測圖片自身的圓角半徑。
///
/// 只認「帶 alpha 通道、四角是透明的」這一種 —— 也就是視窗截圖、去背素材最常見的形式。
/// 不透明的圖片，或是用純色背景畫出來的假圓角，一律回傳 0（當作直角）。
///
/// 量法：掃最外側那一列（行），找第一個不透明像素離角落多遠，再用 `trueRadius`
/// 換算回真正的半徑（量到的值會固定短少約 √r，原因見該函式的註解）。
/// 四個角各量水平、垂直兩次，共 8 個值，彼此吻合才採用，
/// 避免把不規則的透明形狀誤判成圓角。
enum CornerDetector {

    /// alpha 超過這個值就算不透明。抗鋸齒邊緣是漸變的，取中間值最接近真實半徑。
    private static let opaqueThreshold: UInt8 = 128

    /// 小於這個半徑視為直角（純粹是抗鋸齒造成的一兩個像素）
    private static let minimumRadius = 2.0

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// 回傳偵測到的圓角半徑（原圖像素）。判定為直角或無法確定時回傳 0。
    static func detect(in image: CGImage) -> Double {
        let w = image.width, h = image.height
        guard w >= 16, h >= 16, hasAlpha(image) else { return 0 }

        // 四邊中點都必須不透明，否則這不是一個「填滿的圓角矩形」，
        // 而是別種帶透明區的圖（去背的 logo、圓形頭像切片之類），不該套用。
        guard edgeMidpointsAreOpaque(image) else { return 0 }

        // 上限只是為了不要在超大圖上配置過多暫存記憶體。半徑大於 1024px 的圖極少見，
        // 真的遇到就會掃不到不透明像素而回傳 0（保守地當作沒有圓角）。
        let probe = min(min(w, h) / 2, 1024)
        guard probe >= 8 else { return 0 }

        var measurements: [Double] = []
        for corner in Corner.allCases {
            guard let (horizontal, vertical) = measure(corner, in: image, probe: probe) else {
                return 0            // 有角量不出來就整個放棄
            }
            measurements.append(horizontal)
            measurements.append(vertical)
        }

        let median = measurements.sorted()[measurements.count / 2]
        guard median >= minimumRadius else { return 0 }

        // 八個量測值必須彼此吻合，否則不是等圓角的矩形
        let tolerance = max(2.0, median * 0.2)
        guard measurements.allSatisfy({ abs($0 - median) <= tolerance }) else { return 0 }

        return median
    }

    // MARK: - 量測

    /// 回傳該角落沿水平邊、垂直邊各量到的半徑；掃不到不透明像素則回傳 nil。
    private static func measure(_ corner: Corner, in image: CGImage, probe: Int) -> (Double, Double)? {
        let w = image.width, h = image.height
        let origin: CGPoint
        switch corner {
        case .topLeft:     origin = CGPoint(x: 0, y: 0)
        case .topRight:    origin = CGPoint(x: w - probe, y: 0)
        case .bottomLeft:  origin = CGPoint(x: 0, y: h - probe)
        case .bottomRight: origin = CGPoint(x: w - probe, y: h - probe)
        }
        let crop = CGRect(origin: origin, size: CGSize(width: probe, height: probe))
        guard let region = image.cropping(to: crop),
              let alpha = alphaMap(of: region, size: probe) else { return nil }

        // 把「外側角落」統一換算成裁切區裡的座標，兩條邊各往內掃
        let outerX = (corner == .topLeft || corner == .bottomLeft) ? 0 : probe - 1
        let outerY = (corner == .topLeft || corner == .topRight) ? 0 : probe - 1
        let stepX = outerX == 0 ? 1 : -1
        let stepY = outerY == 0 ? 1 : -1

        // 沿著水平邊掃：外側那一列，從角落往內找第一個不透明像素
        var horizontal: Double?
        for i in 0..<probe {
            let x = outerX + i * stepX
            if alpha[outerY * probe + x] >= opaqueThreshold { horizontal = Double(i); break }
        }
        // 沿著垂直邊掃：外側那一行
        var vertical: Double?
        for i in 0..<probe {
            let y = outerY + i * stepY
            if alpha[y * probe + outerX] >= opaqueThreshold { vertical = Double(i); break }
        }

        guard let hh = horizontal, let vv = vertical else { return nil }
        return (trueRadius(fromEdgeMeasurement: hh), trueRadius(fromEdgeMeasurement: vv))
    }

    /// 由最外側像素列量到的值還原真正的半徑。
    ///
    /// 「頂列第一個不透明像素的 x 就是 r」只在數學上的邊線成立；實際上最外側那一列
    /// 是一條高 1px 的帶子，中心離邊緣 0.5px。圓弧在深度 d 處的水平位置是
    /// x = r − √(2rd − d²)，代入 d = 0.5 得 m = r − √(r − 0.25)，
    /// 反解得 r = m + √m + 0.5。
    ///
    /// 少了這一步，量到的半徑會固定短少約 √r（r=60 會量成 52，r=300 會量成 283）。
    private static func trueRadius(fromEdgeMeasurement m: Double) -> Double {
        guard m > 0 else { return 0 }
        return m + m.squareRoot() + 0.5
    }

    /// 四邊中點的不透明檢查
    private static func edgeMidpointsAreOpaque(_ image: CGImage) -> Bool {
        let w = image.width, h = image.height
        let points = [
            CGPoint(x: w / 2, y: 0),          // 上
            CGPoint(x: w / 2, y: h - 1),      // 下
            CGPoint(x: 0, y: h / 2),          // 左
            CGPoint(x: w - 1, y: h / 2)       // 右
        ]
        for p in points {
            let rect = CGRect(x: p.x, y: p.y, width: 1, height: 1)
            guard let px = image.cropping(to: rect),
                  let a = alphaMap(of: px, size: 1),
                  a[0] >= opaqueThreshold else { return false }
        }
        return true
    }

    // MARK: - 像素存取

    /// 取出區塊的 alpha 通道。回傳的緩衝區由上而下排列，`map[y * size + x]`。
    ///
    /// 本來想用 alphaOnly 的 context（一個像素一個位元組），但 Swift 介面上
    /// CGContext 的 space 不接受 nil，只好畫成 RGBA 再抽出 alpha 位元組。
    /// 8 位元的 premultipliedLast 在記憶體中就是 R,G,B,A 的順序，alpha 在第 4 個。
    private static func alphaMap(of image: CGImage, size: Int) -> [UInt8]? {
        let count = size * size
        var rgba = [UInt8](repeating: 0, count: count * 4)
        let drawn = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base,
                                      width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
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
