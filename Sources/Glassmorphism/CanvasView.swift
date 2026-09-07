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
    static let canvasSpace = "canvas"

    /// 這次拖動吸住的參考線位置（歸一化）。沒吸住就是 nil，拖完清掉。
    @State var guideX: Double?
    @State var guideY: Double?

    /// 圖片層拖曳的起始狀態
    @State var dragCenter: CGPoint?
    @State var dragDistance: Double?
    @State var dragWidthFraction: Double?

    private let minSize: CGFloat = 0.02   // 面板最小邊長（歸一化）

    /// 按住 ⌥ 暫時關掉磁吸，要微調時用
    var snappingOn: Bool { !NSEvent.modifierFlags.contains(.option) }

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
        // 依 layerOrder 疊放，後面的在上層。這裡的順序必須和渲染器完全一致，
        // 否則點擊命中的會是看起來被蓋住的那一個。
        ForEach(state.layerOrder) { ref in
            switch ref.kind {
            case .photo:
                if let photo = state.photo(ref.id) {
                    photoFrame(photo, fitted: fitted)
                }
            case .panel:
                if let panel = state.panel(ref.id) {
                    panelFrame(panel, fitted: fitted)
                }
            }
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

        // 圖片層的控制點：四角等比縮放 + 一個旋轉把手
        if let i = state.selectedPhotoIndex {
            photoHandles(index: i, fitted: fitted)
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

    @ViewBuilder
    private func panelFrame(_ panel: GlassPanel, fitted: CGRect) -> some View {
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
                    let targets = Snapping.targets(excluding: id, panels: state.panels, photos: state.photos,
                                                    baseSize: state.imageSize, content: state.contentRect)
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
                    let targets = Snapping.targets(excluding: id, panels: state.panels, photos: state.photos,
                                                    baseSize: state.imageSize, content: state.contentRect)
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
    func thresholds(in fitted: CGRect) -> (Double, Double) {
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

    func viewRect(_ normalized: CGRect, in fitted: CGRect) -> CGRect {
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

// MARK: - 圖片層的選取框與控制點

extension CanvasView {

    /// 選取框跟著圖片一起旋轉，才看得出目前的角度
    @ViewBuilder
    func photoFrame(_ photo: PhotoLayer, fitted: CGRect) -> some View {
        let r = viewRect(photo.rect(inBase: state.imageSize), in: fitted)
        let selected = photo.id == state.selection

        ZStack {
            Rectangle().fill(Color.white.opacity(0.001))   // 可命中但看不見
            if selected {
                Rectangle().strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1)
            } else {
                Rectangle().strokeBorder(Color.white.opacity(0.45),
                                         style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            }
        }
        .frame(width: max(r.width, 1), height: max(r.height, 1))
        .rotationEffect(.degrees(photo.rotation))
        .position(x: r.midX, y: r.midY)
        .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
        .gesture(photoMoveGesture(id: photo.id, fitted: fitted))
    }

    @ViewBuilder
    func photoHandles(index i: Int, fitted: CGRect) -> some View {
        let photo = state.photos[i]
        let r = viewRect(photo.rect(inBase: state.imageSize), in: fitted)
        let center = CGPoint(x: r.midX, y: r.midY)
        let degrees = photo.rotation
        // 控制點的位置要跟著圖片一起繞中心旋轉
        let corners = [
            Self.rotate(CGPoint(x: r.minX, y: r.minY), around: center, degrees: degrees),
            Self.rotate(CGPoint(x: r.maxX, y: r.minY), around: center, degrees: degrees),
            Self.rotate(CGPoint(x: r.minX, y: r.maxY), around: center, degrees: degrees),
            Self.rotate(CGPoint(x: r.maxX, y: r.maxY), around: center, degrees: degrees)
        ]
        let stemBase = Self.rotate(CGPoint(x: r.midX, y: r.minY), around: center, degrees: degrees)
        let stemTip = Self.rotate(CGPoint(x: r.midX, y: r.minY - 28), around: center, degrees: degrees)

        // 四個角：等比縮放
        ForEach(0..<corners.count, id: \.self) { k in
            HandleDot()
                .position(corners[k])
                .onHover { inside in (inside ? NSCursor.crosshair : NSCursor.arrow).set() }
                .gesture(photoScaleGesture(index: i, fitted: fitted))
        }

        // 旋轉把手：從上緣中點再往外一段
        Path { path in
            path.move(to: stemBase)
            path.addLine(to: stemTip)
        }
        .stroke(Color.accentColor.opacity(0.9), lineWidth: 1)
        .allowsHitTesting(false)

        RotateHandle(snapped: Snapping.snapAngle(degrees) != nil)
            .position(stemTip)
            .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
            .gesture(photoRotateGesture(index: i, fitted: fitted))
    }

    /// 把一點繞著另一點旋轉
    static func rotate(_ point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        let dx = point.x - center.x, dy = point.y - center.y
        return CGPoint(x: center.x + dx * cos(a) - dy * sin(a),
                       y: center.y + dx * sin(a) + dy * cos(a))
    }

    // MARK: 手勢

    func photoMoveGesture(id: UUID, fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                if state.selection != id { state.selection = id }
                guard let i = state.photos.firstIndex(where: { $0.id == id }) else { return }
                let start = dragCenter ?? state.photos[i].center
                if dragCenter == nil { dragCenter = start }

                var center = CGPoint(x: start.x + value.translation.width / fitted.width,
                                     y: start.y + value.translation.height / fitted.height)

                if snappingOn {
                    // 用旋轉後的外接矩形去吸，跟畫面上看到的範圍一致
                    var probe = state.photos[i]
                    probe.center = center
                    let box = probe.boundingRect(inBase: state.imageSize)
                    let targets = Snapping.targets(excluding: id, panels: state.panels,
                                                   photos: state.photos, baseSize: state.imageSize,
                                                   content: state.contentRect)
                    let (tx, ty) = thresholds(in: fitted)

                    if let hit = Snapping.snapSpan(min: box.minX, max: box.maxX,
                                                   to: targets.x, threshold: tx) {
                        center.x += hit.offset
                        guideX = hit.guide
                    } else { guideX = nil }

                    if let hit = Snapping.snapSpan(min: box.minY, max: box.maxY,
                                                   to: targets.y, threshold: ty) {
                        center.y += hit.offset
                        guideY = hit.guide
                    } else { guideY = nil }
                } else {
                    guideX = nil; guideY = nil
                }

                state.photos[i].center = center
                state.refreshPreview()
            }
            .onEnded { _ in endPhotoDrag() }
    }

    /// 等比縮放，以中心為錨點：倍率就是「游標到中心的距離」相對按下時的比值，
    /// 這樣不必管圖片轉了幾度。
    func photoScaleGesture(index i: Int, fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                guard state.photos.indices.contains(i) else { return }
                let photo = state.photos[i]
                let r = viewRect(photo.rect(inBase: state.imageSize), in: fitted)
                let center = CGPoint(x: r.midX, y: r.midY)

                func distance(_ p: CGPoint) -> Double {
                    let dx = p.x - center.x, dy = p.y - center.y
                    return (dx * dx + dy * dy).squareRoot()
                }
                let startDistance = dragDistance ?? max(distance(value.startLocation), 1)
                if dragDistance == nil {
                    dragDistance = startDistance
                    dragWidthFraction = photo.widthFraction
                }
                guard let baseWidth = dragWidthFraction else { return }

                let factor = max(distance(value.location), 1) / startDistance
                state.photos[i].widthFraction = min(max(baseWidth * factor,
                                                        PhotoLayer.Range.widthFraction.lowerBound),
                                                    PhotoLayer.Range.widthFraction.upperBound)
                state.refreshPreview()
            }
            .onEnded { _ in endPhotoDrag() }
    }

    func photoRotateGesture(index i: Int, fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                guard state.photos.indices.contains(i) else { return }
                let r = viewRect(state.photos[i].rect(inBase: state.imageSize), in: fitted)
                let center = CGPoint(x: r.midX, y: r.midY)

                // 把手在正上方時角度為 0，所以基準要轉 90°
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                var degrees = atan2(dy, dx) * 180 / .pi + 90
                if degrees > 180 { degrees -= 360 }
                if degrees < -180 { degrees += 360 }

                if snappingOn, let snapped = Snapping.snapAngle(degrees) {
                    degrees = snapped
                }
                state.photos[i].rotation = degrees
                state.refreshPreview()
            }
            .onEnded { _ in endPhotoDrag() }
    }

    func endPhotoDrag() {
        dragCenter = nil
        dragDistance = nil
        dragWidthFraction = nil
        guideX = nil
        guideY = nil
    }
}

/// 旋轉把手。吸在刻度上時填成洋紅，跟吸附參考線同一套語彙。
private struct RotateHandle: View {
    let snapped: Bool

    var body: some View {
        Circle()
            .fill(snapped ? Color(red: 1.0, green: 0.19, blue: 0.55) : Color.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
            .frame(width: 11, height: 11)
            .shadow(radius: 1)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }
}
