import Foundation
import SwiftUI

/// 介面語言。`.system` 依系統偏好語言自動判斷。
enum Language: String, CaseIterable, Identifiable, Codable {
    case system
    case zhHant = "zh-Hant"
    case zhHans = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    /// 語言名稱一律用該語言自己的寫法，切換時才不會看不懂
    var displayName: String {
        switch self {
        case .system:  return Strings.current.langSystem
        case .zhHant:  return "繁體中文"
        case .zhHans:  return "简体中文"
        case .english: return "English"
        }
    }

    /// 實際採用的字串表
    var strings: Strings {
        switch self {
        case .system:  return Language.fromSystem.strings
        case .zhHant:  return .zhHant
        case .zhHans:  return .zhHans
        case .english: return .english
        }
    }

    /// 依系統偏好語言挑一個。認不出來的一律給英文。
    static var fromSystem: Language {
        guard let tag = Locale.preferredLanguages.first else { return .english }
        let lower = tag.lowercased()
        guard lower.hasPrefix("zh") else { return .english }
        // zh-Hans / zh-CN / zh-SG 走簡體，其餘中文（TW / HK / MO）走繁體
        if lower.contains("hans") || lower.contains("-cn") || lower.contains("-sg") { return .zhHans }
        return .zhHant
    }
}

/// 介面文案。用 struct 而不是字典，讓編譯器保證三個語言都不漏字串。
struct Strings {
    /// 給 Language.displayName 用的當前表（切換語言時由 AppState 更新）
    static var current: Strings = Language.fromSystem.strings

    // 視窗
    let windowTitle: String

    // 工具列
    let open: String, openHelp: String
    let copy: String, copyHelp: String
    let exportPNG: String, exportHelp: String

    // 空狀態與狀態列
    let dropTitle: String, dropSubtitle: String
    let statusHint: String, statusWaiting: String
    let errorRead: String, errorEncode: String
    let errorWrite: (String) -> String
    let exported: (String, String) -> String
    let copied: (String) -> String

    // 面板清單
    let panels: String
    let panelNamed: (Int) -> String
    let add: String, addHelp: String, duplicateHelp: String, deleteHelp: String
    let moveUpHelp: String, moveDownHelp: String
    let noSelection: String, noImage: String

    // 分區標題
    let sectionGlass: String, sectionBorder: String, sectionShadow: String
    let sectionText: String, sectionInfo: String

    // 毛玻璃
    let blurRadius: String, tint: String, tintOpacity: String
    let cornerRadius: String, noise: String

    // 邊框
    let width: String, color: String, opacity: String

    // 陰影
    let shadowEnabled: String, spread: String, strength: String

    // 文字
    let title: String, subtitle: String, font: String, systemFont: String
    let titleBold: String, titleSize: String, subtitleSize: String, textColor: String
    let alignment: String, alignLeft: String, alignCenter: String, alignRight: String
    let lineGap: String, padding: String

    // 資訊
    let originalSize: String, panelSize: String, resetPanel: String
    let imageCorners: String, noneValue: String, contentArea: String
    let detectedCorners: (String) -> String

    // 選單
    let menuPanel: String, newPanel: String, duplicatePanel: String, deletePanel: String
    let bringForward: String, sendBackward: String
    let menuLanguage: String, langSystem: String
}

extension Strings {
    static let zhHant = Strings(
        windowTitle: "毛玻璃疊加",
        open: "開啟", openHelp: "開啟圖片 (⌘O)",
        copy: "複製", copyHelp: "以原圖尺寸合成並複製 (⇧⌘C)",
        exportPNG: "導出 PNG", exportHelp: "以原圖尺寸導出 PNG (⌘S)",
        dropTitle: "把圖片拖進來",
        dropSubtitle: "或按 ⌘O 開啟   •   支援 PNG / JPEG / HEIC / TIFF",
        statusHint: "拖動移動、拖角落縮放，貼近邊緣自動對齊（按住 ⌥ 暫停）· ⌘N 新增面板",
        statusWaiting: "等待圖片",
        errorRead: "無法讀取這個檔案",
        errorEncode: "PNG 編碼失敗",
        errorWrite: { "寫入失敗：\($0)" },
        exported: { size, name in "已導出 \(size) → \(name)" },
        copied: { "已複製 \($0) 到剪貼板" },
        panels: "面板",
        panelNamed: { "面板 \($0)" },
        add: "新增", addHelp: "新增面板 (⌘N)", duplicateHelp: "複製面板 (⌘D)", deleteHelp: "刪除面板 (⌘⌫)",
        moveUpHelp: "上移一層", moveDownHelp: "下移一層",
        noSelection: "沒有選中的面板", noImage: "尚未載入圖片",
        sectionGlass: "毛玻璃", sectionBorder: "邊框", sectionShadow: "陰影",
        sectionText: "文字", sectionInfo: "資訊",
        blurRadius: "模糊半徑", tint: "疊色", tintOpacity: "疊色濃度",
        cornerRadius: "圓角半徑", noise: "雜訊顆粒",
        width: "寬度", color: "顏色", opacity: "透明度",
        shadowEnabled: "啟用外陰影", spread: "擴散", strength: "濃度",
        title: "標題", subtitle: "副標", font: "字型", systemFont: "系統字體",
        titleBold: "標題粗體", titleSize: "標題字級", subtitleSize: "副標字級", textColor: "文字顏色",
        alignment: "對齊", alignLeft: "靠左", alignCenter: "置中", alignRight: "靠右",
        lineGap: "行距", padding: "內縮",
        originalSize: "原始尺寸", panelSize: "面板尺寸", resetPanel: "重設本面板參數",
        imageCorners: "圖片圓角", noneValue: "無", contentArea: "內容範圍",
        detectedCorners: { "偵測到圖片本身有 \($0) px 圓角，已套用為面板預設" },
        menuPanel: "面板", newPanel: "新增面板", duplicatePanel: "複製面板", deletePanel: "刪除面板",
        bringForward: "上移一層", sendBackward: "下移一層",
        menuLanguage: "語言", langSystem: "跟隨系統"
    )

    static let zhHans = Strings(
        windowTitle: "毛玻璃叠加",
        open: "打开", openHelp: "打开图片 (⌘O)",
        copy: "复制", copyHelp: "以原图尺寸合成并复制 (⇧⌘C)",
        exportPNG: "导出 PNG", exportHelp: "以原图尺寸导出 PNG (⌘S)",
        dropTitle: "把图片拖进来",
        dropSubtitle: "或按 ⌘O 打开   •   支持 PNG / JPEG / HEIC / TIFF",
        statusHint: "拖动移动、拖角落缩放，贴近边缘自动对齐（按住 ⌥ 暂停）· ⌘N 新建面板",
        statusWaiting: "等待图片",
        errorRead: "无法读取这个文件",
        errorEncode: "PNG 编码失败",
        errorWrite: { "写入失败：\($0)" },
        exported: { size, name in "已导出 \(size) → \(name)" },
        copied: { "已复制 \($0) 到剪贴板" },
        panels: "面板",
        panelNamed: { "面板 \($0)" },
        add: "新建", addHelp: "新建面板 (⌘N)", duplicateHelp: "复制面板 (⌘D)", deleteHelp: "删除面板 (⌘⌫)",
        moveUpHelp: "上移一层", moveDownHelp: "下移一层",
        noSelection: "没有选中的面板", noImage: "尚未载入图片",
        sectionGlass: "毛玻璃", sectionBorder: "边框", sectionShadow: "阴影",
        sectionText: "文字", sectionInfo: "信息",
        blurRadius: "模糊半径", tint: "叠色", tintOpacity: "叠色浓度",
        cornerRadius: "圆角半径", noise: "噪点颗粒",
        width: "宽度", color: "颜色", opacity: "透明度",
        shadowEnabled: "启用外阴影", spread: "扩散", strength: "浓度",
        title: "标题", subtitle: "副标题", font: "字体", systemFont: "系统字体",
        titleBold: "标题加粗", titleSize: "标题字号", subtitleSize: "副标题字号", textColor: "文字颜色",
        alignment: "对齐", alignLeft: "左对齐", alignCenter: "居中", alignRight: "右对齐",
        lineGap: "行距", padding: "内边距",
        originalSize: "原始尺寸", panelSize: "面板尺寸", resetPanel: "重置本面板参数",
        imageCorners: "图片圆角", noneValue: "无", contentArea: "内容范围",
        detectedCorners: { "检测到图片本身有 \($0) px 圆角，已应用为面板默认值" },
        menuPanel: "面板", newPanel: "新建面板", duplicatePanel: "复制面板", deletePanel: "删除面板",
        bringForward: "上移一层", sendBackward: "下移一层",
        menuLanguage: "语言", langSystem: "跟随系统"
    )

    static let english = Strings(
        windowTitle: "Glassmorphism",
        open: "Open", openHelp: "Open an image (⌘O)",
        copy: "Copy", copyHelp: "Copy at original resolution (⇧⌘C)",
        exportPNG: "Export PNG", exportHelp: "Export PNG at original resolution (⌘S)",
        dropTitle: "Drop an image here",
        dropSubtitle: "or press ⌘O   •   PNG / JPEG / HEIC / TIFF",
        statusHint: "Drag to move, drag a handle to resize — edges snap (hold ⌥ to disable) · ⌘N for a new panel",
        statusWaiting: "No image",
        errorRead: "Could not read that file",
        errorEncode: "PNG encoding failed",
        errorWrite: { "Could not write file: \($0)" },
        exported: { size, name in "Exported \(size) → \(name)" },
        copied: { "Copied \($0) to the clipboard" },
        panels: "Panels",
        panelNamed: { "Panel \($0)" },
        add: "Add", addHelp: "New panel (⌘N)", duplicateHelp: "Duplicate panel (⌘D)", deleteHelp: "Delete panel (⌘⌫)",
        moveUpHelp: "Bring forward", moveDownHelp: "Send backward",
        noSelection: "No panel selected", noImage: "No image loaded",
        sectionGlass: "Glass", sectionBorder: "Border", sectionShadow: "Shadow",
        sectionText: "Text", sectionInfo: "Info",
        blurRadius: "Blur radius", tint: "Tint", tintOpacity: "Tint opacity",
        cornerRadius: "Corner radius", noise: "Noise",
        width: "Width", color: "Color", opacity: "Opacity",
        shadowEnabled: "Drop shadow", spread: "Spread", strength: "Strength",
        title: "Title", subtitle: "Subtitle", font: "Font", systemFont: "System font",
        titleBold: "Bold title", titleSize: "Title size", subtitleSize: "Subtitle size", textColor: "Text color",
        alignment: "Alignment", alignLeft: "Left", alignCenter: "Center", alignRight: "Right",
        lineGap: "Line gap", padding: "Padding",
        originalSize: "Image size", panelSize: "Panel size", resetPanel: "Reset this panel",
        imageCorners: "Image corners", noneValue: "None", contentArea: "Content area",
        detectedCorners: { "Image has \($0) px rounded corners — applied as the panel default" },
        menuPanel: "Panel", newPanel: "New Panel", duplicatePanel: "Duplicate Panel", deletePanel: "Delete Panel",
        bringForward: "Bring Forward", sendBackward: "Send Backward",
        menuLanguage: "Language", langSystem: "System"
    )
}
