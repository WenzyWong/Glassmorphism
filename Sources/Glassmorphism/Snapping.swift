import CoreGraphics
import Foundation

/// 拖動與縮放面板時的磁吸對齊。
///
/// 全部在歸一化座標（0…1）裡算，但**吸附距離必須由呼叫端換算成歸一化再傳進來**，
/// 因為它的來源是「畫面上的幾個點」—— 直接寫死歸一化的門檻，同一張圖在不同視窗
/// 大小下手感會不一樣，窄視窗會變得很黏。
enum Snapping {

    /// 吸附距離（畫面上的點）。呼叫端要除以該軸在畫面上的長度換成歸一化。
    static let distance: CGFloat = 8

    /// 把單一座標吸到最近的目標上。沒有目標落在距離內就回傳 nil。
    /// 用於縮放：只有被拖動的那條邊會移動。
    static func snap(_ value: Double, to targets: [Double], threshold: Double) -> Double? {
        var best: Double?
        var bestDistance = threshold
        for target in targets {
            let d = abs(target - value)
            if d <= bestDistance {
                bestDistance = d
                best = target
            }
        }
        return best
    }

    /// 整段一起吸：左緣、中線、右緣三者任一貼上目標，就把整段平移過去。
    /// 用於移動：面板大小不變。回傳需要的平移量與命中的參考線位置。
    static func snapSpan(min lo: Double, max hi: Double, to targets: [Double],
                         threshold: Double) -> (offset: Double, guide: Double)? {
        let edges = [lo, (lo + hi) / 2, hi]
        var best: (offset: Double, guide: Double)?
        var bestDistance = threshold
        for edge in edges {
            for target in targets {
                let d = abs(target - edge)
                if d <= bestDistance {
                    bestDistance = d
                    best = (target - edge, target)
                }
            }
        }
        return best
    }

    /// 兩軸的吸附目標：圖片的兩邊與中線、內容範圍的兩邊與中線，
    /// 加上其他每一塊面板的兩邊與中線。會排除自己，不然面板永遠吸在原地動不了。
    ///
    /// 內容範圍通常等於整張圖，但視窗截圖不是 —— 那時要吸的是視窗的邊，
    /// 不是外圍那圈透明背景的邊。兩者都留著，重複的值不影響取最近的判斷。
    static func targets(excluding id: UUID, panels: [GlassPanel],
                        content: CGRect) -> (x: [Double], y: [Double]) {
        var x: [Double] = [0, 0.5, 1, content.minX, content.midX, content.maxX]
        var y: [Double] = [0, 0.5, 1, content.minY, content.midY, content.maxY]
        for panel in panels where panel.id != id {
            let r = panel.rect
            x.append(contentsOf: [r.minX, r.midX, r.maxX])
            y.append(contentsOf: [r.minY, r.midY, r.maxY])
        }
        return (x, y)
    }
}
