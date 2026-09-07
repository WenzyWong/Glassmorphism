import AppKit

// 拖放的路由（第一張當底圖、之後都變拼貼層）是使用者最有感、
// 又沒辦法用滑鼠自動測的部分，所以在這裡把邏輯釘住。

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func image(_ w: Int, _ h: Int) -> CGImage {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(NSColor.white.cgColor)
    c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return c.makeImage()!
}

var failures = 0
func flag(_ name: String, _ ok: Bool) {
    if !ok { failures += 1 }
    print("\(ok ? "✓" : "✗") \(name)")
}

MainActor.assumeIsolated {
    let state = AppState()

    // 還沒有底圖時，第一張進來的圖要成為底圖
    flag("初始沒有底圖", !state.hasImage)
    state.addPhoto(image: image(1200, 800), name: "base.png")
    flag("第一張成為底圖", state.hasImage && state.photos.isEmpty)
    flag("底圖載入後自帶一塊面板", state.panels.count == 1)

    // 之後拖進來的都是拼貼層
    state.addPhoto(image: image(600, 400), name: "a.png")
    flag("第二張成為拼貼層", state.photos.count == 1)
    flag("底圖沒有被換掉", state.sourceName == "base.png")
    flag("新加的圖片會被選中", state.selection == state.photos[0].id)
    flag("選中的是圖片而不是面板", state.selectedPhotoIndex == 0 && state.selectedIndex == nil)

    state.addPhoto(image: image(300, 900), name: "b.png")
    flag("第三張再疊一層", state.photos.count == 2)
    flag("多張會錯開，不完全重疊", state.photos[0].center != state.photos[1].center)

    // 複製／刪除要作用在選中的那一種物件上
    state.duplicateSelected()
    flag("複製圖片層", state.photos.count == 3 && state.panels.count == 1)
    flag("複本插在原件正上方",
         state.layerOrder.firstIndex { $0.id == state.selection! }
         == (state.layerOrder.firstIndex { $0.id == state.photos[1].id } ?? -9) + 1)
    state.deleteSelected()
    flag("刪除圖片層，面板不受影響", state.photos.count == 2 && state.panels.count == 1)

    state.selection = state.panels[0].id
    state.duplicateSelected()
    flag("選中面板時複製的是面板", state.panels.count == 2 && state.photos.count == 2)
    state.deleteSelected()
    flag("選中面板時刪除的是面板", state.panels.count == 1 && state.photos.count == 2)

    // 疊放層級：面板與圖片共用一份順序，可以跨種類調
    flag("順序涵蓋所有物件", state.layerOrder.count == state.panels.count + state.photos.count)
    let panelID = state.panels[0].id
    let photoIDs = state.photos.map(\.id)
    // 載入底圖時先有面板，之後加的圖片都疊在它上面
    flag("面板在最底層", state.layerOrder.first?.id == panelID)

    state.selection = panelID
    state.moveSelected(up: true)
    flag("面板可以往上穿過圖片", state.layerOrder[1].id == panelID
         && state.layerOrder[0].id == photoIDs[0])
    state.sendSelected(toTop: true)
    flag("面板可以直接送到最上層", state.layerOrder.last?.id == panelID)
    flag("此時面板疊在所有圖片之上",
         state.spec.items.last.map { if case .panel = $0 { return true } else { return false } } == true)

    state.selection = photoIDs[1]
    state.sendSelected(toTop: true)
    flag("圖片也可以疊到面板之上", state.layerOrder.last?.id == photoIDs[1])
    flag("渲染堆疊最上層是圖片",
         state.spec.items.last.map { if case .photo = $0 { return true } else { return false } } == true)

    state.selection = photoIDs[1]
    state.sendSelected(toTop: false)
    flag("送到最下層", state.layerOrder.first?.id == photoIDs[1])

    state.selection = state.layerOrder.first?.id
    flag("最下層不能再往下", !state.canMoveDown)
    state.selection = state.layerOrder.last?.id
    flag("最上層不能再往上", !state.canMoveUp)

    // 換底圖要清掉拼貼層
    state.load(image: image(800, 600), name: "new.png")
    flag("換底圖後拼貼層清空", state.photos.isEmpty)
    flag("換底圖後回到一塊面板", state.panels.count == 1)
    flag("換底圖後順序也重置", state.layerOrder.count == 1)

    // spec 要把兩種物件都帶上
    flag("spec 帶上底圖尺寸", state.spec.baseSize == CGSize(width: 800, height: 600))
}

print(failures == 0 ? "\n全部通過" : "\n\(failures) 項失敗")
exit(failures == 0 ? 0 : 1)
