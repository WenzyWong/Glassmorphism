import Foundation

var failures = 0

func check(_ name: String, _ got: Double?, _ want: Double?, tolerance: Double = 1e-9) {
    let ok: Bool
    switch (got, want) {
    case (nil, nil): ok = true
    case let (g?, w?): ok = abs(g - w) <= tolerance
    default: ok = false
    }
    if !ok { failures += 1 }
    func show(_ v: Double?) -> String { v.map { String(format: "%.4f", $0) } ?? "nil" }
    print("\(ok ? "✓" : "✗") \(name) — 期望 \(show(want))，實測 \(show(got))")
}

func panel(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> GlassPanel {
    GlassPanel(rect: CGRect(x: x, y: y, width: w, height: h),
               style: GlassStyle(), text: TextStyle())
}

// ── snap：縮放時單邊吸附 ──
let edges: [Double] = [0, 0.5, 1]
check("貼近中線就吸上", Snapping.snap(0.503, to: edges, threshold: 0.01), 0.5)
check("超過門檻不吸", Snapping.snap(0.52, to: edges, threshold: 0.01), nil)
// 不測「正好等於門檻」：0.51 - 0.5 在浮點下是 0.0100000000000000009，落在門檻兩側全看捨入
check("門檻內側會吸", Snapping.snap(0.509, to: edges, threshold: 0.01), 0.5)
check("門檻外側不吸", Snapping.snap(0.511, to: edges, threshold: 0.01), nil)
check("兩個目標都在範圍內時取最近的",
      Snapping.snap(0.48, to: [0.45, 0.5], threshold: 0.05), 0.5)
check("貼近左邊界", Snapping.snap(0.004, to: edges, threshold: 0.01), 0)
check("貼近右邊界", Snapping.snap(0.997, to: edges, threshold: 0.01), 1)

// ── snapSpan：移動時整塊吸附 ──
func spanOffset(_ lo: Double, _ hi: Double, _ t: [Double], _ th: Double) -> Double? {
    Snapping.snapSpan(min: lo, max: hi, to: t, threshold: th)?.offset
}
func spanGuide(_ lo: Double, _ hi: Double, _ t: [Double], _ th: Double) -> Double? {
    Snapping.snapSpan(min: lo, max: hi, to: t, threshold: th)?.guide
}

check("三條邊都不靠近就不吸", spanOffset(0.1, 0.4, edges, 0.02), nil)
check("左緣吸到 0，整塊左移", spanOffset(0.015, 0.315, edges, 0.02), -0.015)
check("左緣吸附的參考線是 0", spanGuide(0.015, 0.315, edges, 0.02), 0)
check("中線吸到 0.5", spanOffset(0.34, 0.65, edges, 0.02), 0.005)
check("中線吸附的參考線是 0.5", spanGuide(0.34, 0.65, edges, 0.02), 0.5)
check("右緣吸到 1", spanOffset(0.6, 0.99, edges, 0.02), 0.01)
check("右緣吸附的參考線是 1", spanGuide(0.6, 0.99, edges, 0.02), 1)
// 左緣離 0 是 0.015，右緣離 0.5 是 0.005，右緣勝出
check("多條邊都在範圍內時取最近的那條", spanOffset(0.015, 0.495, edges, 0.02), 0.005)
check("取最近那條時參考線也要對", spanGuide(0.015, 0.495, edges, 0.02), 0.5)

// ── targets：目標清單 ──
let a = panel(0.1, 0.1, 0.3, 0.2)
let b = panel(0.6, 0.5, 0.2, 0.2)
let full = CGRect(x: 0, y: 0, width: 1, height: 1)
let t = Snapping.targets(excluding: a.id, panels: [a, b], photos: [],
                         baseSize: CGSize(width: 1000, height: 1000), content: full)

func has(_ list: [Double], _ v: Double) -> Bool { list.contains { abs($0 - v) < 1e-9 } }
func flag(_ name: String, _ ok: Bool) {
    if !ok { failures += 1 }
    print("\(ok ? "✓" : "✗") \(name)")
}
flag("含圖片左右邊與中線", has(t.x, 0) && has(t.x, 0.5) && has(t.x, 1))
flag("含另一塊面板的左緣 0.6", has(t.x, 0.6))
flag("含另一塊面板的中線 0.7", has(t.x, 0.7))
flag("含另一塊面板的右緣 0.8", has(t.x, 0.8))
flag("不含自己的左緣 0.1（否則會吸在原地動不了）", !has(t.x, 0.1))
flag("Y 軸同樣排除自己的上緣", !has(t.y, 0.1))
flag("Y 軸含另一塊面板的上緣 0.5", has(t.y, 0.5))

// 視窗截圖：內容範圍小於整張圖，視窗的邊也要是吸附目標
let window = CGRect(x: 0.08, y: 0.12, width: 0.84, height: 0.80)
let wt = Snapping.targets(excluding: a.id, panels: [], photos: [],
                          baseSize: CGSize(width: 1000, height: 1000), content: window)
flag("含視窗左緣 0.08", has(wt.x, 0.08))
flag("含視窗右緣 0.92", has(wt.x, 0.92))
flag("含視窗中線 0.50", has(wt.x, 0.5))
flag("含視窗上緣 0.12", has(wt.y, 0.12))
flag("含視窗下緣 0.92", has(wt.y, 0.92))
flag("整張圖的邊也保留著", has(wt.x, 0) && has(wt.x, 1))

print(failures == 0 ? "全部通過" : "\(failures) 項失敗")
exit(failures == 0 ? 0 : 1)
