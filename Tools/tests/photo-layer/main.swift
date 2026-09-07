import AppKit

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func image(_ w: Int, _ h: Int) -> CGImage {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(NSColor.white.cgColor)
    c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return c.makeImage()!
}

var failures = 0
func check(_ name: String, _ got: Double?, _ want: Double?, tolerance: Double = 1e-6) {
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
func flag(_ name: String, _ ok: Bool) {
    if !ok { failures += 1 }
    print("\(ok ? "✓" : "✗") \(name)")
}

// 底圖 2400×1600，照片 600×400（長寬比 1.5）
let base = CGSize(width: 2400, height: 1600)
let img = image(600, 400)
var p = PhotoLayer(image: img, preview: img, name: "t")
p.widthFraction = 0.3
p.center = CGPoint(x: 0.5, y: 0.5)

print("── 幾何（縮放一定等比）──")
check("像素寬 = 0.3 × 2400", p.pixelSize(inBase: base).width, 720)
check("像素高由長寬比推出，720 / 1.5", p.pixelSize(inBase: base).height, 480)
check("歸一化寬", p.rect(inBase: base).width, 0.3)
check("歸一化高 = 480 / 1600", p.rect(inBase: base).height, 0.3)
check("框以中心為準，左緣 = 0.5 - 0.15", p.rect(inBase: base).minX, 0.35)

print("\n── 旋轉後的外接矩形 ──")
check("0° 時外框等於本體（寬）", p.boundingRect(inBase: base).width, 0.3)
p.rotation = 90
// 轉 90° 後像素上變成 480 寬 × 720 高
check("90° 寬 = 480 / 2400", p.boundingRect(inBase: base).width, 0.2)
check("90° 高 = 720 / 1600", p.boundingRect(inBase: base).height, 0.45)
p.rotation = 180
check("180° 寬回到 0.3", p.boundingRect(inBase: base).width, 0.3)
p.rotation = 45
// 45°：外框邊長 = (720 + 480) × cos45 = 848.5
check("45° 寬 = (720+480)×cos45 / 2400", p.boundingRect(inBase: base).width,
      (720 + 480) * (2.0.squareRoot() / 2) / 2400, tolerance: 1e-9)
p.rotation = -90
check("-90° 與 90° 對稱", p.boundingRect(inBase: base).width, 0.2)

print("\n── 角度磁吸 ──")
check("88° 吸到 90（直角容差 6）", Snapping.snapAngle(88), 90)
check("93° 吸到 90", Snapping.snapAngle(93), 90)
check("97° 超出直角容差，也不在 15° 刻度上", Snapping.snapAngle(97), nil)
check("44° 吸到 45（刻度容差 3）", Snapping.snapAngle(44), 45)
check("30.5° 吸到 30", Snapping.snapAngle(30.5), 30)
check("7° 兩種容差都不到", Snapping.snapAngle(7), nil)
check("-178° 吸到 -180", Snapping.snapAngle(-178), -180)
check("0.5° 吸到 0（轉正）", Snapping.snapAngle(0.5), 0)
check("179° 吸到 180", Snapping.snapAngle(179), 180)

print("\n── 相等性 ──")
var q = p
flag("複製後相等", q == p)
q.rotation += 1
flag("改角度後不相等", q != p)
let other = PhotoLayer(image: image(600, 400), preview: img, name: "t")
flag("不同圖片實例不相等（比參照）", other != PhotoLayer(image: img, preview: img, name: "t"))

print(failures == 0 ? "\n全部通過" : "\n\(failures) 項失敗")
exit(failures == 0 ? 0 : 1)
