import SwiftUI

/// 面板的可拖動控制點
private enum Handle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var unit: CGPoint {   // 在面板矩形內的相對位置
        switch self {
        case .topLeft:     return CGPoint(x: 0,   y: 0)
        case .top:         return CGPoint(x: 0.5, y: 0)
        case .topRight:    return CGPoint(x: 1,   y: 0)
        case .right:       return CGPoint(x: 1,   y: 0.5)
        case .bottomRight: return CGPoint(x: 1,   y: 1)
        case .bottom:      return CGPoint(x: 0.5, y: 1)
        case .bottomLeft:  return CGPoint(x: 0,   y: 1)
        case .left:        return CGPoint(x: 0,   y: 0.5)
        }
    }

    var movesLeft: Bool   { unit.x == 0 }
    var movesRight: Bool  { unit.x == 1 }
    var movesTop: Bool    { unit.y == 0 }
    var movesBottom: Bool { unit.y == 1 }

    var cursor: NSCursor {
        switch self {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }
}

struct CanvasView: View {
    @ObservedObject var state: AppState

    /// 拖曳開始時的面板，用來計算累積位移
    @State private var dragOrigin: CGRect?

    /// 手勢一律在這個固定的座標空間裡量位移。
    /// 若用預設的 .local，量測基準會跟著被拖動的面板一起移動，
    /// 位移量被重複扣掉，面板就只跟著游標走一半 —— 也就是「不跟手」。
    private static let canvasSpace = "canvas"

    /// 這次拖動吸住的參考線位置（歸一化）。沒吸住就是 nil，拖完清掉。
    @State private var guideX: Double?
    @State private var guideY: Double?

    private let minSize: CGFloat = 0.02   // 面板最小邊長（歸一化）

    /// 按住 ⌥ 暫時關掉磁吸，要微調時用
    private var snappingOn: Bool { !NSEvent.modifierFlags.contains(.option) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if let preview = state.preview {
                    let fitted = fittedRect(imageSize: state.imageSize, in: geo.size)

                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)

                    overlay(fitted: fitted)
                } else {
                    DropHint(s: state.s)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .coordinateSpace(name: Self.canvasSpace)
        }
    }

    // MARK: - 選取框與控制點

    @ViewBuilder
    private func overlay(fitted: CGRect) -> some View {
        // 依陣列順序疊放，後面的在上層（點擊時也會先命中上層，與渲染順序一致）
        ForEach(state.panels) { panel in
            let r = viewRect(panel.rect, in: fitted)
            let selected = panel.id == state.selection

            ZStack {
                Rectangle().fill(Color.white.opacity(0.001))   // 可命中但看不見
                if selected {
                    Rectangle().strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1)
                } else {
                    Rectangle().strokeBorder(Color.white.opacity(0.55),
                                             style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .frame(width: max(r.width, 1), height: max(r.height, 1))
            .position(x: r.midX, y: r.midY)
            .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
            .gesture(moveGesture(id: panel.id, fitted: fitted))
        }

        // 控制點畫在最後，確保永遠在所有面板之上
        if let i = state.selectedIndex {
            let r = viewRect(state.panels[i].rect, in: fitted)
            ForEach(Array(Handle.allCases.enumerated()), id: \.offset) { _, handle in
                HandleDot()
                    .position(x: r.minX + r.width * handle.unit.x,
                              y: r.minY + r.height * handle.unit.y)
                    .onHover { inside in (inside ? handle.cursor : NSCursor.arrow).set() }
                    .gesture(resizeGesture(index: i, handle: handle, fitted: fitted))
            }
        }

        // 吸附參考線。用洋紅色而不是 accent，才不會跟選取框混在一起。
        if let gx = guideX {
            Rectangle()
                .fill(Self.guideColor)
                .frame(width: 1, height: fitted.height)
                .position(x: fitted.minX + gx * fitted.width, y: fitted.midY)
                .allowsHitTesting(false)
        }
        if let gy = guideY {
            Rectangle()
                .fill(Self.guideColor)
                .frame(width: fitted.width, height: 1)
                .position(x: fitted.midX, y: fitted.minY + gy * fitted.height)
                .allowsHitTesting(false)
        }
    }

    private static let guideColor = Color(red: 1.0, green: 0.19, blue: 0.55)

    private func moveGesture(id: UUID, fitted: CGRect) -> some Gesture {
        // minimumDistance 0：按下當下就選中，不用先拖動
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                if state.selection != id { state.selection = id }
                guard let i = state.panels.firstIndex(where: { $0.id == id }) else { return }
                let start = dragOrigin ?? state.panels[i].rect
                if dragOrigin == nil { dragOrigin = start }
                let dx = value.translation.width / fitted.width
                let dy = value.translation.height / fitted.height
                var p = start
                p.origin.x = min(max(0, start.minX + dx), 1 - start.width)
                p.origin.y = min(max(0, start.minY + dy), 1 - start.height)

                if snappingOn {
                    let targets = Snapping.targets(excluding: id, panels: state.panels, content: state.contentRect)
                    let (tx, ty) = thresholds(in: fitted)

                    if let hit = Snapping.snapSpan(min: p.minX, max: p.maxX,
                                                   to: targets.x, threshold: tx) {
                        let snapped = p.minX + hit.offset
                        let clamped = min(max(0, snapped), 1 - p.width)
                        p.origin.x = clamped
                        // 被邊界夾回去就代表其實沒對齊上，別畫誤導人的參考線
                        guideX = abs(clamped - snapped) < 1e-9 ? hit.guide : nil
                    } else {
                        guideX = nil
                    }

                    if let hit = Snapping.snapSpan(min: p.minY, max: p.maxY,
                                                   to: targets.y, threshold: ty) {
                        let snapped = p.minY + hit.offset
                        let clamped = min(max(0, snapped), 1 - p.height)
                        p.origin.y = clamped
                        guideY = abs(clamped - snapped) < 1e-9 ? hit.guide : nil
                    } else {
                        guideY = nil
                    }
                } else {
                    guideX = nil; guideY = nil
                }

                state.panels[i].rect = p
                state.refreshPreview()
            }
            .onEnded { _ in endDrag() }
    }

    private func resizeGesture(index i: Int, handle: Handle, fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                guard state.panels.indices.contains(i) else { return }
                let start = dragOrigin ?? state.panels[i].rect
                if dragOrigin == nil { dragOrigin = start }
                let dx = value.translation.width / fitted.width
                let dy = value.translation.height / fitted.height

                var left = start.minX, right = start.maxX
                var top = start.minY, bottom = start.maxY

                if handle.movesLeft   { left   = min(max(0, start.minX + dx), right - minSize) }
                if handle.movesRight  { right  = max(min(1, start.maxX + dx), left + minSize) }
                if handle.movesTop    { top    = min(max(0, start.minY + dy), bottom - minSize) }
                if handle.movesBottom { bottom = max(min(1, start.maxY + dy), top + minSize) }

                if snappingOn {
                    let id = state.panels[i].id
                    let targets = Snapping.targets(excluding: id, panels: state.panels, content: state.contentRect)
                    let (tx, ty) = thresholds(in: fitted)

                    // 每個控制點最多只動一條 X 邊、一條 Y 邊，所以兩軸各吸一次就夠
                    guideX = nil
                    if handle.movesLeft, let v = Snapping.snap(left, to: targets.x, threshold: tx) {
                        let clamped = min(max(0, v), right - minSize)
                        left = clamped
                        guideX = abs(clamped - v) < 1e-9 ? v : nil
                    } else if handle.movesRight, let v = Snapping.snap(right, to: targets.x, threshold: tx) {
                        let clamped = max(min(1, v), left + minSize)
                        right = clamped
                        guideX = abs(clamped - v) < 1e-9 ? v : nil
                    }

                    guideY = nil
                    if handle.movesTop, let v = Snapping.snap(top, to: targets.y, threshold: ty) {
                        let clamped = min(max(0, v), bottom - minSize)
                        top = clamped
                        guideY = abs(clamped - v) < 1e-9 ? v : nil
                    } else if handle.movesBottom, let v = Snapping.snap(bottom, to: targets.y, threshold: ty) {
                        let clamped = max(min(1, v), top + minSize)
                        bottom = clamped
                        guideY = abs(clamped - v) < 1e-9 ? v : nil
                    }
                } else {
                    guideX = nil; guideY = nil
                }

                state.panels[i].rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
                state.refreshPreview()
            }
            .onEnded { _ in endDrag() }
    }

    private func endDrag() {
        dragOrigin = nil
        guideX = nil
        guideY = nil
    }

    /// 把「畫面上 8 個點」換算成兩軸各自的歸一化門檻
    private func thresholds(in fitted: CGRect) -> (Double, Double) {
        (Double(Snapping.distance / max(fitted.width, 1)),
         Double(Snapping.distance / max(fitted.height, 1)))
    }

    // MARK: - 座標換算

    /// 圖片在畫布中 aspect-fit 後的實際位置
    private func fittedRect(imageSize: CGSize, in canvas: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let inset: CGFloat = 32
        let available = CGSize(width: max(1, canvas.width - inset * 2),
                               height: max(1, canvas.height - inset * 2))
        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h)
    }

    private func viewRect(_ normalized: CGRect, in fitted: CGRect) -> CGRect {
        CGRect(x: fitted.minX + normalized.minX * fitted.width,
               y: fitted.minY + normalized.minY * fitted.height,
               width: normalized.width * fitted.width,
               height: normalized.height * fitted.height)
    }
}

private struct HandleDot: View {
    var body: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
            .frame(width: 11, height: 11)
            .shadow(radius: 1)
            .frame(width: 24, height: 24)      // 放大命中範圍
            .contentShape(Rectangle())
    }
}

private struct DropHint: View {
    let s: Strings

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .thin))
            Text(s.dropTitle)
                .font(.title3)
            Text(s.dropSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
    }
}
