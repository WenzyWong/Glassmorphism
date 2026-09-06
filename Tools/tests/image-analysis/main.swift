import AppKit

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func context(_ w: Int, _ h: Int, alpha: Bool = true) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
              bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast
                                 : CGImageAlphaInfo.noneSkipLast).rawValue)!
}

/// 整張畫布就是一個圓角矩形，四角透明
func roundedRect(_ w: Int, _ h: Int, radius: Double, fillPhoto: Bool = false) -> CGImage {
    let ctx = context(w, h)
    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    if fillPhoto {
        let g = CGGradient(colorsSpace: cs, colors: [NSColor.systemTeal.cgColor,
                                                     NSColor.systemBrown.cgColor] as CFArray,
                           locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: h), options: [])
    } else {
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(rect)
    }
    return ctx.makeImage()!
}

func fullyOpaque(_ w: Int, _ h: Int, alpha: Bool = true) -> CGImage {
    let ctx = context(w, h, alpha: alpha)
    ctx.setFillColor(NSColor.systemIndigo.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

func circle(_ side: Int) -> CGImage {
    let ctx = context(side, side)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
    return ctx.makeImage()!
}

/// 去背素材：中間一塊直角方形，四周全透明
func logoOnTransparent(_ w: Int, _ h: Int) -> CGImage {
    let ctx = context(w, h)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(CGRect(x: w/4, y: h/4, width: w/2, height: h/2))
    return ctx.makeImage()!
}

/// 只有左上角是圓的，其餘直角
func asymmetric(_ w: Int, _ h: Int, radius: Double) -> CGImage {
    let ctx = context(w, h)
    let r = CGFloat(radius)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0))
    p.addLine(to: CGPoint(x: CGFloat(w), y: 0))
    p.addLine(to: CGPoint(x: CGFloat(w), y: CGFloat(h)))
    p.addLine(to: CGPoint(x: r, y: CGFloat(h)))
    p.addArc(center: CGPoint(x: r, y: CGFloat(h) - r), radius: r,
             startAngle: .pi/2, endAngle: .pi, clockwise: false)
    p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
    return ctx.makeImage()!
}

/// macOS 的「所選視窗截圖」：透明邊 + 柔和陰影（偏下）+ 圓角視窗
func windowCapture(imageW: Int, imageH: Int, window: CGRect, radius: Double,
                   shadowAlpha: Double) -> CGImage {
    let ctx = context(imageW, imageH)
    let path = CGPath(roundedRect: window, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if shadowAlpha > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46,
                      color: CGColor(colorSpace: cs, components: [0, 0, 0, shadowAlpha])!)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.setFillColor(NSColor(white: 0.94, alpha: 1).cgColor)
    ctx.fill(window)
    ctx.setFillColor(NSColor(white: 0.82, alpha: 1).cgColor)
    ctx.fill(CGRect(x: window.minX, y: window.maxY - 90, width: window.width, height: 90))
    ctx.restoreGState()
    return ctx.makeImage()!
}

// ── 執行 ──
var failures = 0

func checkRadius(_ name: String, _ image: CGImage, expect: Double, tolerance: Double = 2.5) {
    let got = ImageAnalyzer.analyze(image).cornerRadius
    let ok = abs(got - expect) <= tolerance
    if !ok { failures += 1 }
    print("\(ok ? "✓" : "✗") \(name) — 圓角期望 \(String(format: "%.1f", expect))，實測 \(String(format: "%.1f", got))")
}

func checkBounds(_ name: String, _ image: CGImage, expect: CGRect, tolerance: Double = 1) {
    let got = ImageAnalyzer.analyze(image).contentBounds
    let ok = abs(got.minX - expect.minX) <= tolerance && abs(got.minY - expect.minY) <= tolerance
        && abs(got.width - expect.width) <= tolerance && abs(got.height - expect.height) <= tolerance
    if !ok { failures += 1 }
    func f(_ r: CGRect) -> String {
        String(format: "(%.0f, %.0f, %.0f×%.0f)", r.minX, r.minY, r.width, r.height)
    }
    print("\(ok ? "✓" : "✗") \(name) — 外框期望 \(f(expect))，實測 \(f(got))")
}

print("── 圓角 ──")
checkRadius("直角（有 alpha 通道）", fullyOpaque(800, 600), expect: 0)
checkRadius("直角（無 alpha 通道）", fullyOpaque(800, 600, alpha: false), expect: 0)
checkRadius("圓角 r=24", roundedRect(800, 600, radius: 24), expect: 24)
checkRadius("圓角 r=60", roundedRect(800, 600, radius: 60), expect: 60)
checkRadius("圓角 r=120", roundedRect(800, 600, radius: 120), expect: 120)
checkRadius("圓角 r=60，內容是漸層而非純色", roundedRect(800, 600, radius: 60, fillPhoto: true), expect: 60)
checkRadius("大圖 2400×1600 圓角 r=48", roundedRect(2400, 1600, radius: 48), expect: 48)
checkRadius("極大圓角 r=300", roundedRect(2400, 1600, radius: 300), expect: 300)
checkRadius("正圓形（r 應等於邊長的一半）", circle(600), expect: 300, tolerance: 4)
checkRadius("去背的直角素材", logoOnTransparent(800, 600), expect: 0)
checkRadius("只有單角是圓的，四角不一致", asymmetric(800, 600, radius: 90), expect: 0)
checkRadius("極小圖 12×12", roundedRect(12, 12, radius: 3), expect: 0)
checkRadius("r=1，抗鋸齒等級不算圓角", roundedRect(800, 600, radius: 1), expect: 0)

print("\n── 視窗截圖（透明邊 + 陰影）──")
let win = CGRect(x: 120, y: 150, width: 1600, height: 1000)
let capture = windowCapture(imageW: 1840, imageH: 1300, window: win, radius: 44, shadowAlpha: 0.42)
checkBounds("外框要抓到視窗本體，不是整張圖", capture, expect: win)
// 陰影疊在抗鋸齒邊緣上會把 alpha 推過門檻，量到的半徑略小，容差放寬到 3
checkRadius("圓角要量視窗的，不是整張圖的", capture, expect: 44, tolerance: 3)

let noShadow = windowCapture(imageW: 1840, imageH: 1300, window: win, radius: 44, shadowAlpha: 0)
checkRadius("同一個視窗、拿掉陰影後應更準", noShadow, expect: 44, tolerance: 1.5)

let smallRadius = windowCapture(imageW: 900, imageH: 700, window: CGRect(x: 60, y: 70, width: 760, height: 520),
                                radius: 12, shadowAlpha: 0.42)
checkRadius("小圓角視窗 r=12", smallRadius, expect: 12, tolerance: 2.5)

print("\n── 內容外框 ──")
checkBounds("不透明整張圖", fullyOpaque(800, 600), expect: CGRect(x: 0, y: 0, width: 800, height: 600))
checkBounds("無 alpha 通道", fullyOpaque(800, 600, alpha: false), expect: CGRect(x: 0, y: 0, width: 800, height: 600))
checkBounds("滿版圓角矩形", roundedRect(800, 600, radius: 60), expect: CGRect(x: 0, y: 0, width: 800, height: 600))
checkBounds("去背素材抓中間那塊", logoOnTransparent(800, 600), expect: CGRect(x: 200, y: 150, width: 400, height: 300))

print(failures == 0 ? "\n全部通過" : "\n\(failures) 項失敗")
exit(failures == 0 ? 0 : 1)
