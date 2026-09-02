import AppKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText

/// 唯一的合成實作。預覽與導出都走這裡，差別只在 base 的解析度與 scale。
enum GlassRenderer {

    static let ciContext: CIContext = {
        CIContext(options: [.useSoftwareRenderer: false,
                            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    }()

    // MARK: - 主流程

    /// - Parameters:
    ///   - base: 要繪製的底圖（原圖或預覽縮圖）
    ///   - spec: 面板清單（位置歸一化，像素參數以原圖為基準）
    ///   - scale: base.width / 原圖寬。預覽時 < 1，導出時 = 1
    static func render(base: CGImage, spec: RenderSpec, scale: CGFloat) -> CGImage? {
        let w = base.width, h = base.height
        guard w > 0, h > 0 else { return nil }
        let fullRect = CGRect(x: 0, y: 0, width: w, height: h)

        guard let ctx = CGContext(data: nil,
                                  width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(base, in: fullRect)

        // 依陣列順序疊加，後面的蓋在前面的之上
        for panel in spec.panels {
            draw(panel: panel, ctx: ctx, base: base, fullRect: fullRect, scale: scale)
        }
        return ctx.makeImage()
    }

    private static func draw(panel: GlassPanel, ctx: CGContext, base: CGImage,
                             fullRect: CGRect, scale: CGFloat) {
        // 歸一化（左上原點）→ CGContext 座標（左下原點）
        let p = panel.rect
        let rect = CGRect(x: p.minX * fullRect.width,
                          y: (1 - p.maxY) * fullRect.height,
                          width: p.width * fullRect.width,
                          height: p.height * fullRect.height).integral
        guard rect.width >= 2, rect.height >= 2 else { return }

        let style = panel.style
        let corner = min(style.cornerRadius * scale, min(rect.width, rect.height) / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        // 注意：模糊取樣的來源是「原始底圖」，不是已經畫上前幾塊面板的畫布。
        // 兩塊面板重疊時，上面那塊看到的是原圖的模糊，不會把下面那塊的疊色再模糊一次。
        drawShadow(ctx: ctx, path: path, fullRect: fullRect, style: style, scale: scale)
        drawGlass(ctx: ctx, base: base, path: path, rect: rect, fullRect: fullRect, style: style, scale: scale)
        drawBorder(ctx: ctx, rect: rect, corner: corner, style: style, scale: scale)
        drawText(ctx: ctx, rect: rect, text: panel.text, scale: scale)
    }

    // MARK: - 各層

    /// 只畫面板外側的投影：先把繪製區域裁成「整張圖扣掉面板」，再填面板路徑。
    private static func drawShadow(ctx: CGContext, path: CGPath, fullRect: CGRect,
                                   style: GlassStyle, scale: CGFloat) {
        guard style.shadowEnabled, style.shadowOpacity > 0.001, style.shadowRadius > 0.1 else { return }
        ctx.saveGState()
        ctx.addRect(fullRect)
        ctx.addPath(path)
        ctx.clip(using: .evenOdd)
        let blur = style.shadowRadius * scale
        ctx.setShadow(offset: CGSize(width: 0, height: -blur * 0.25),
                      blur: blur,
                      color: NSColor.black.withAlphaComponent(style.shadowOpacity).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawGlass(ctx: CGContext, base: CGImage, path: CGPath, rect: CGRect,
                                  fullRect: CGRect, style: GlassStyle, scale: CGFloat) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        // 關鍵：貼的是「整張圖的模糊版」且鋪滿 fullRect，
        // 所以玻璃底下的內容與原圖位置完全對齊，不會位移或縮邊。
        if let blurred = blurred(base: base, radius: style.blurRadius * scale) {
            ctx.draw(blurred, in: fullRect)
        }

        if style.tintOpacity > 0.001 {
            ctx.setFillColor(cgColor(style.tintColor, alpha: style.tintOpacity))
            ctx.fill(rect)
        }

        if style.noiseAmount > 0.001,
           let n = noise(in: rect, amount: style.noiseAmount, scale: scale) {
            ctx.setBlendMode(.overlay)
            ctx.draw(n, in: rect)
            ctx.setBlendMode(.normal)
        }
        ctx.restoreGState()
    }

    private static func drawBorder(ctx: CGContext, rect: CGRect, corner: CGFloat,
                                   style: GlassStyle, scale: CGFloat) {
        let lw = style.borderWidth * scale
        guard lw > 0.05, style.borderOpacity > 0.001 else { return }
        let inset = rect.insetBy(dx: lw / 2, dy: lw / 2)
        guard inset.width > 0, inset.height > 0 else { return }
        let r = max(0, min(corner - lw / 2, min(inset.width, inset.height) / 2))
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: inset, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setLineWidth(lw)
        ctx.setStrokeColor(cgColor(style.borderColor, alpha: style.borderOpacity))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawText(ctx: CGContext, rect: CGRect, text: TextStyle, scale: CGFloat) {
        let attr = attributedString(text, scale: scale)
        guard attr.length > 0 else { return }

        let pad = text.padding * scale
        let box = rect.insetBy(dx: pad, dy: pad)
        guard box.width > 4, box.height > 4 else { return }

        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: box.width, height: .greatestFiniteMagnitude), nil)

        let height = min(ceil(suggested.height) + 1, box.height)
        // 垂直置中
        let textRect = CGRect(x: box.minX,
                              y: box.midY - height / 2,
                              width: box.width,
                              height: height)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             CGPath(rect: textRect, transform: nil), nil)
        ctx.saveGState()
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    // MARK: - 文字組裝

    private static func attributedString(_ t: TextStyle, scale: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let color = NSColor(t.color)

        func paragraph(spacingAfter: CGFloat) -> NSParagraphStyle {
            let ps = NSMutableParagraphStyle()
            ps.alignment = t.align.ctAlignment
            ps.paragraphSpacing = spacingAfter
            ps.lineBreakMode = .byWordWrapping
            return ps
        }

        let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = t.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if !title.isEmpty {
            let size = max(1, t.titleSize * scale)
            out.append(NSAttributedString(string: title + (subtitle.isEmpty ? "" : "\n"), attributes: [
                .font: font(family: t.fontFamily, size: size, bold: t.titleBold),
                .foregroundColor: color,
                .paragraphStyle: paragraph(spacingAfter: subtitle.isEmpty ? 0 : t.lineGap * scale)
            ]))
        }
        if !subtitle.isEmpty {
            let size = max(1, t.subtitleSize * scale)
            out.append(NSAttributedString(string: subtitle, attributes: [
                .font: font(family: t.fontFamily, size: size, bold: false),
                .foregroundColor: color,
                .paragraphStyle: paragraph(spacingAfter: 0)
            ]))
        }
        return out
    }

    private static func font(family: String, size: CGFloat, bold: Bool) -> NSFont {
        let base: NSFont
        if family.isEmpty {
            base = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            return base
        }
        base = NSFont(name: family, size: size)
            ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
            ?? NSFont.systemFont(ofSize: size)
        guard bold else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
    }

    // MARK: - CoreImage 輔助

    /// 模糊整張底圖。多塊面板常用不同半徑，所以快取要能同時放好幾張，
    /// 否則每塊面板都會把上一塊的結果擠掉、每幀重算。
    private static var blurCache: [BlurKey: CGImage] = [:]
    private static var blurCacheOrder: [BlurKey] = []
    private static let blurCacheLimit = 8

    private struct BlurKey: Hashable {
        let base: ObjectIdentifier
        let radius: Int          // 取到小數點後兩位，避免浮點微差造成 miss
    }

    static func invalidateCache() {
        blurCache.removeAll()
        blurCacheOrder.removeAll()
    }

    private static func blurred(base: CGImage, radius: CGFloat) -> CGImage? {
        guard radius > 0.1 else { return base }
        let key = BlurKey(base: ObjectIdentifier(base), radius: Int((radius * 100).rounded()))
        if let hit = blurCache[key] { return hit }

        let ci = CIImage(cgImage: base)
        // clampedToExtent 避免邊緣被透明像素稀釋成暗角
        let out = ci.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius))
            .cropped(to: ci.extent)
        guard let cg = ciContext.createCGImage(out, from: ci.extent) else { return nil }

        blurCache[key] = cg
        blurCacheOrder.append(key)
        if blurCacheOrder.count > blurCacheLimit {
            blurCache.removeValue(forKey: blurCacheOrder.removeFirst())
        }
        return cg
    }

    private static func noise(in rect: CGRect, amount: Double, scale: CGFloat) -> CGImage? {
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let gray = random.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: amount)
        ])
        let s = max(scale, 0.05)
        let area = CGRect(x: 0, y: 0,
                          width: (rect.width / s).rounded(),
                          height: (rect.height / s).rounded())
        return ciContext.createCGImage(gray.cropped(to: area), from: area)
    }

    // MARK: - 通用

    static func downscale(_ image: CGImage, maxSide: CGFloat) -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let longest = max(w, h)
        guard longest > maxSide else { return image }
        let f = maxSide / longest
        let nw = max(1, Int((w * f).rounded())), nh = max(1, Int((h * f).rounded()))
        guard let ctx = CGContext(data: nil, width: nw, height: nh,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage() ?? image
    }

    private static func cgColor(_ color: Color, alpha: Double) -> CGColor {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return ns.withAlphaComponent(alpha).cgColor
    }
}
