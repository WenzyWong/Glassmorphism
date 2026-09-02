import AppKit
import CoreImage

// 用 App 自己的 GlassRenderer 生成圖示：底層漸層 + 一塊毛玻璃面板，
// 最後裁成 macOS 的圓角方形。輸出 1024px PNG，再由 iconutil 打包成 .icns。

let side = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])!
}
func newContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// 底圖：帶層次的漸層加細節，讓玻璃有東西可以模糊
let bg = newContext(side, side)
let grad = CGGradient(colorsSpace: cs, colors: [
    rgb(96, 116, 138), rgb(139, 146, 145), rgb(186, 170, 150), rgb(214, 204, 190)
] as CFArray, locations: [0, 0.4, 0.75, 1])!
bg.drawLinearGradient(grad, start: CGPoint(x: 0, y: side), end: CGPoint(x: CGFloat(side), y: 0), options: [])
for (x, y, r, c) in [(700.0, 720.0, 300.0, rgb(236, 231, 222, 0.42)),
                     (250.0, 300.0, 260.0, rgb(78, 96, 116, 0.40)),
                     (820.0, 240.0, 170.0, rgb(206, 190, 172, 0.35))] {
    bg.setFillColor(c)
    bg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}
bg.setLineWidth(7)
for i in 0..<15 {
    bg.setStrokeColor(rgb(255, 255, 255, 0.22))
    let y = CGFloat(i) * 72 + 16
    bg.move(to: CGPoint(x: 0, y: y)); bg.addLine(to: CGPoint(x: CGFloat(side), y: y + 96))
    bg.strokePath()
}
for x in stride(from: 40, to: side, by: 84) {          // 圓點，讓玻璃底下的模糊看得出來
    for y in stride(from: 40, to: side, by: 84) {
        bg.setFillColor(rgb(46, 54, 62, 0.20))
        bg.fillEllipse(in: CGRect(x: x, y: y, width: 16, height: 16))
    }
}
let base = bg.makeImage()!

// 疊上毛玻璃面板
var style = GlassStyle()
style.blurRadius = 26
style.tintOpacity = 0.16
style.cornerRadius = 74
style.borderWidth = 6
style.borderOpacity = 0.6
style.shadowRadius = 60
style.shadowOpacity = 0.32
let panel = GlassPanel(rect: CGRect(x: 0.20, y: 0.32, width: 0.60, height: 0.36),
                       style: style, text: TextStyle())
let composed = GlassRenderer.render(base: base, spec: RenderSpec(panels: [panel]), scale: 1)!

// 裁成 macOS 圓角方形（內容約佔畫布 82%，四周留白給系統陰影）
let out = newContext(side, side)
let inset = CGFloat(side) * 0.09
let shape = CGRect(x: inset, y: inset, width: CGFloat(side) - inset * 2, height: CGFloat(side) - inset * 2)
let radius = shape.width * 0.2246          // macOS Big Sur 之後的圓角比例
out.addPath(CGPath(roundedRect: shape, cornerWidth: radius, cornerHeight: radius, transform: nil))
out.clip()
out.draw(composed, in: CGRect(x: 0, y: 0, width: side, height: side))

let png = NSBitmapImageRep(cgImage: out.makeImage()!)
try! png.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("icon master → \(CommandLine.arguments[1]) (\(side)×\(side))")
