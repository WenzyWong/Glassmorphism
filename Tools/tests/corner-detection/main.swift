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

/// 去背素材：中間一塊不透明，四周全透明
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

// ── 執行 ──
var failures = 0

func check(_ name: String, _ got: Double, expect: Double, tolerance: Double = 2.5) {
    let ok = abs(got - expect) <= tolerance
    if !ok { failures += 1 }
    let gotText = String(format: "%.1f", got)
    let expectText = String(format: "%.1f", expect)
    print("\(ok ? "✓" : "✗") \(name) — 期望 \(expectText)，實測 \(gotText)")
}

check("直角（有 alpha 通道）", CornerDetector.detect(in: fullyOpaque(800, 600)), expect: 0)
check("直角（無 alpha 通道）", CornerDetector.detect(in: fullyOpaque(800, 600, alpha: false)), expect: 0)
check("圓角 r=24", CornerDetector.detect(in: roundedRect(800, 600, radius: 24)), expect: 24)
check("圓角 r=60", CornerDetector.detect(in: roundedRect(800, 600, radius: 60)), expect: 60)
check("圓角 r=120", CornerDetector.detect(in: roundedRect(800, 600, radius: 120)), expect: 120)
check("圓角 r=60，內容是漸層而非純色",
      CornerDetector.detect(in: roundedRect(800, 600, radius: 60, fillPhoto: true)), expect: 60)
check("大圖 2400×1600 圓角 r=48",
      CornerDetector.detect(in: roundedRect(2400, 1600, radius: 48)), expect: 48)
check("極大圓角 r=300", CornerDetector.detect(in: roundedRect(2400, 1600, radius: 300)), expect: 300)
check("正圓形（r 應等於邊長的一半）", CornerDetector.detect(in: circle(600)), expect: 300, tolerance: 4)
check("去背素材，四周全透明", CornerDetector.detect(in: logoOnTransparent(800, 600)), expect: 0)
check("只有單角是圓的，四角不一致", CornerDetector.detect(in: asymmetric(800, 600, radius: 90)), expect: 0)
check("極小圖 12×12", CornerDetector.detect(in: roundedRect(12, 12, radius: 3)), expect: 0)
check("r=1，抗鋸齒等級不算圓角", CornerDetector.detect(in: roundedRect(800, 600, radius: 1)), expect: 0)

print(failures == 0 ? "全部通過" : "\(failures) 項失敗")
exit(failures == 0 ? 0 : 1)
