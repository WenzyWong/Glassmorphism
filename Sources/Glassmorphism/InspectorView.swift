import SwiftUI

struct InspectorView: View {
    @ObservedObject var state: AppState

    /// 滑桿上限依圖片尺寸自適應：小圖不需要 300px 的模糊半徑
    private var unit: Double { ParamRange.unit(state.imageSize) }

    var body: some View {
        VStack(spacing: 0) {
            PanelListView(state: state)
            Divider()
            PhotoListView(state: state)
            Divider()

            if let index = state.selectedIndex {
                parameters(index: index)
            } else if let index = state.selectedPhotoIndex {
                photoParameters(index: index)
            } else {
                Spacer()
                Text(state.hasImage ? state.s.noSelection : state.s.noImage)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
            }
        }
        .frame(width: 300)
    }

    // MARK: - 選中面板的參數

    @ViewBuilder
    private func parameters(index i: Int) -> some View {
        let panel = $state.panels[i]

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(state.s.sectionGlass) {
                    slider(state.s.blurRadius, panel.style.blurRadius, ParamRange.blur(unit), unit: "px")
                    ColorPicker(state.s.tint, selection: panel.style.tintColor, supportsOpacity: false)
                    slider(state.s.tintOpacity, panel.style.tintOpacity, ParamRange.ratio, percent: true)
                    slider(state.s.cornerRadius, panel.style.cornerRadius, ParamRange.corner(unit), unit: "px")
                    slider(state.s.noise, panel.style.noiseAmount, ParamRange.noise, percent: true)
                }

                section(state.s.sectionBorder) {
                    slider(state.s.width, panel.style.borderWidth, ParamRange.borderWidth(unit), unit: "px")
                    ColorPicker(state.s.color, selection: panel.style.borderColor, supportsOpacity: false)
                    slider(state.s.opacity, panel.style.borderOpacity, ParamRange.ratio, percent: true)
                }

                section(state.s.sectionShadow) {
                    Toggle(state.s.shadowEnabled, isOn: panel.style.shadowEnabled)
                    slider(state.s.spread, panel.style.shadowRadius, ParamRange.shadowRadius(unit), unit: "px")
                        .disabled(!state.panels[i].style.shadowEnabled)
                    slider(state.s.strength, panel.style.shadowOpacity, ParamRange.ratio, percent: true)
                        .disabled(!state.panels[i].style.shadowEnabled)
                }

                section(state.s.sectionText) {
                    LabeledField(state.s.title, text: panel.text.title)
                    LabeledField(state.s.subtitle, text: panel.text.subtitle)
                    FontPicker(family: panel.text.fontFamily,
                               panelID: state.panels[i].id,
                               index: i,
                               current: state.panels[i].text.fontFamily,
                               label: state.s.font,
                               systemFontName: state.s.systemFont)
                        .equatable()
                    Toggle(state.s.titleBold, isOn: panel.text.titleBold)
                    slider(state.s.titleSize, panel.text.titleSize, ParamRange.titleSize(unit), unit: "px")
                    slider(state.s.subtitleSize, panel.text.subtitleSize, ParamRange.subtitleSize(unit), unit: "px")
                    ColorPicker(state.s.textColor, selection: panel.text.color, supportsOpacity: false)
                    Picker(state.s.alignment, selection: panel.text.align) {
                        ForEach(TextAlign.allCases) { Text($0.name(state.s)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    slider(state.s.lineGap, panel.text.lineGap, ParamRange.lineGap(unit), unit: "px")
                    slider(state.s.padding, panel.text.padding, ParamRange.padding(unit), unit: "px")
                }

                section(state.s.sectionInfo) {
                    LabeledContent(state.s.originalSize) {
                        Text("\(Int(state.imageSize.width)) × \(Int(state.imageSize.height))")
                            .monospacedDigit()
                    }
                    LabeledContent(state.s.panelSize) {
                        let r = state.panels[i].rect
                        Text("\(Int((r.width * state.imageSize.width).rounded())) × \(Int((r.height * state.imageSize.height).rounded()))")
                            .monospacedDigit()
                    }
                    // 只在內容小於整張圖時顯示（視窗截圖那類），平常沒必要佔一行
                    if state.contentIsInset {
                        LabeledContent(state.s.contentArea) {
                            let c = state.contentRect
                            Text("\(Int((c.width * state.imageSize.width).rounded())) × \(Int((c.height * state.imageSize.height).rounded()))")
                                .monospacedDigit()
                        }
                    }
                    LabeledContent(state.s.imageCorners) {
                        Text(state.detectedCornerRadius > 0
                             ? "\(Int(state.detectedCornerRadius)) px"
                             : state.s.noneValue)
                            .monospacedDigit()
                    }
                    Button(state.s.resetPanel) {
                        state.panels[i].style = GlassStyle.defaults(for: state.imageSize,
                                                                    cornerRadius: state.detectedCornerRadius)
                        let old = state.panels[i].text
                        var t = TextStyle.defaults(for: state.imageSize)
                        t.title = old.title; t.subtitle = old.subtitle   // 保留已輸入的文字
                        state.panels[i].text = t
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - 選中圖片的參數

    @ViewBuilder
    private func photoParameters(index i: Int) -> some View {
        let photo = $state.photos[i]
        let unitValue = unit

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(state.s.sectionPhoto) {
                    slider(state.s.photoSize, photo.widthFraction,
                           PhotoLayer.Range.widthFraction, percent: true)
                    slider(state.s.rotation, photo.rotation,
                           PhotoLayer.Range.rotation, unit: "°")
                    HStack(spacing: 6) {
                        Button(state.s.rotateLeft) { turn(i, by: -90) }
                        Button(state.s.rotateRight) { turn(i, by: 90) }
                        Button(state.s.resetRotation) { state.photos[i].rotation = 0 }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    slider(state.s.photoOpacity, photo.opacity,
                           PhotoLayer.Range.opacity, percent: true)
                }

                section(state.s.sectionShadow) {
                    Toggle(state.s.shadowEnabled, isOn: photo.shadowEnabled)
                    slider(state.s.spread, photo.shadowRadius,
                           PhotoLayer.Range.shadowRadius(unitValue), unit: "px")
                        .disabled(!state.photos[i].shadowEnabled)
                    slider(state.s.strength, photo.shadowOpacity,
                           PhotoLayer.Range.shadowOpacity, percent: true)
                        .disabled(!state.photos[i].shadowEnabled)
                }

                section(state.s.sectionInfo) {
                    LabeledContent(state.s.originalSize) {
                        Text("\(state.photos[i].image.width) × \(state.photos[i].image.height)")
                            .monospacedDigit()
                    }
                    LabeledContent(state.s.panelSize) {
                        let px = state.photos[i].pixelSize(inBase: state.imageSize)
                        Text("\(Int(px.width.rounded())) × \(Int(px.height.rounded()))")
                            .monospacedDigit()
                    }
                }
            }
            .padding(16)
        }
    }

    /// 以 90° 為單位轉，並收攏到 -180…180
    private func turn(_ i: Int, by degrees: Double) {
        var next = (state.photos[i].rotation + degrees).truncatingRemainder(dividingBy: 360)
        if next > 180 { next -= 360 }
        if next <= -180 { next += 360 }
        state.photos[i].rotation = next
    }

    // MARK: - 小元件

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        Divider()
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        unit: String = "", percent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(percent ? "\(Int((value.wrappedValue * 100).rounded()))%"
                             : "\(Int(value.wrappedValue.rounded())) \(unit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

/// 系統有 246 個字型家族。若直接寫在 InspectorView 的 body 裡，
/// 拖曳面板時每個滑鼠事件都會重建這 246 個項目 —— 這是拖曳卡頓的主因。
/// 這裡包成 EquatableView：只要選中的面板和字型沒變，就整個跳過不重建。
private struct FontPicker: View, Equatable {
    @Binding var family: String
    let panelID: UUID
    let index: Int
    let current: String
    let label: String
    let systemFontName: String

    private static let families: [String] = NSFontManager.shared.availableFontFamilies

    /// 必須連 panelID 和 index 一起比。跳過重建時會沿用舊的 Binding，
    /// 而那個 Binding 綁死在 panels[index] 上：
    ///   * 換選另一塊面板 → panelID 變，要重建
    ///   * 調整疊放層級或刪除面板導致索引位移 → index 變，也要重建
    /// 少比其中一個，就會改到別塊面板的字型。
    static func == (lhs: FontPicker, rhs: FontPicker) -> Bool {
        lhs.panelID == rhs.panelID && lhs.index == rhs.index
            && lhs.current == rhs.current && lhs.label == rhs.label
    }

    var body: some View {
        Picker(label, selection: $family) {
            Text(systemFontName).tag("")
            ForEach(Self.families, id: \.self) { family in
                Text(family).tag(family)
            }
        }
    }
}

// MARK: - 面板清單

private struct PanelListView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.s.panels).font(.headline)
                Spacer()
                Text("\(state.panels.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 2) {
                    // 由上往下顯示最上層的面板，和畫面上的疊放順序一致
                    ForEach(Array(state.panels.enumerated().reversed()), id: \.element.id) { index, panel in
                        row(index: index, panel: panel)
                    }
                }
            }
            .frame(height: 96)

            HStack(spacing: 6) {
                Button { state.addPanel() } label: { Label(state.s.add, systemImage: "plus") }
                    .help(state.s.addHelp)
                Button { state.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                    .help(state.s.duplicateHelp)
                    .disabled(state.selectedIndex == nil)
                Button { state.deleteSelected() } label: { Image(systemName: "trash") }
                    .help(state.s.deleteHelp)
                    .disabled(state.selectedIndex == nil)
                Spacer()
                Button { state.moveSelected(up: true) } label: { Image(systemName: "arrow.up") }
                    .help(state.s.moveUpHelp)
                    .disabled(state.selectedIndex == nil || state.selectedIndex == state.panels.count - 1)
                Button { state.moveSelected(up: false) } label: { Image(systemName: "arrow.down") }
                    .help(state.s.moveDownHelp)
                    .disabled(state.selectedIndex == nil || state.selectedIndex == 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!state.hasImage)
        }
        .padding(12)
    }

    private func row(index: Int, panel: GlassPanel) -> some View {
        let selected = panel.id == state.selection
        return HStack(spacing: 6) {
            Image(systemName: "square.on.square.dashed")
                .foregroundStyle(selected ? Color.white : Color.secondary)
            Text(state.s.panelNamed(index + 1))
                .lineLimit(1)
            if !panel.text.title.isEmpty {
                Text(panel.text.title)
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .contentShape(Rectangle())
        .onTapGesture { state.selection = panel.id }
    }
}

/// 拼貼圖片的清單
private struct PhotoListView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.s.photos).font(.headline)
                Spacer()
                Text("\(state.photos.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }

            if state.photos.isEmpty {
                Text(state.s.dropAddsPhoto)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        // 由上往下顯示最上層的，和畫面上的疊放順序一致
                        ForEach(Array(state.photos.enumerated().reversed()), id: \.element.id) { index, photo in
                            row(index: index, photo: photo)
                        }
                    }
                }
                .frame(height: 72)
            }

            HStack(spacing: 6) {
                Button { addPhoto() } label: { Label(state.s.addPhoto, systemImage: "photo.badge.plus") }
                    .help(state.s.addPhotoHelp)
                Button { state.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(state.selectedPhotoIndex == nil)
                Button { state.deleteSelected() } label: { Image(systemName: "trash") }
                    .disabled(state.selectedPhotoIndex == nil)
                Spacer()
                Button { state.moveSelected(up: true) } label: { Image(systemName: "arrow.up") }
                    .disabled(state.selectedPhotoIndex == nil
                              || state.selectedPhotoIndex == state.photos.count - 1)
                Button { state.moveSelected(up: false) } label: { Image(systemName: "arrow.down") }
                    .disabled(state.selectedPhotoIndex == nil || state.selectedPhotoIndex == 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!state.hasImage)
        }
        .padding(12)
    }

    private func row(index: Int, photo: PhotoLayer) -> some View {
        let selected = photo.id == state.selection
        return HStack(spacing: 6) {
            Image(systemName: "photo")
                .foregroundStyle(selected ? Color.white : Color.secondary)
            Text(photo.name).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .contentShape(Rectangle())
        .onTapGesture { state.selection = photo.id }
    }

    private func addPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { state.addPhoto(url: url) }
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.callout)
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
        }
    }
}
