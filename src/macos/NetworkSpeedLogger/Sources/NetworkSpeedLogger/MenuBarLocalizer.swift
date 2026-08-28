import AppKit

@MainActor
enum MenuBarLocalizer {
    private struct Translation {
        let english: String
        let chinese: String
        let alternatives: Set<String>

        init(_ english: String, _ chinese: String, alternatives: [String] = []) {
            self.english = english
            self.chinese = chinese
            self.alternatives = Set([english, chinese] + alternatives)
        }
    }

    private static let translations = [
        Translation("File", "文件"),
        Translation("Edit", "编辑"),
        Translation("View", "显示", alternatives: ["视图"]),
        Translation("Window", "窗口"),
        Translation("Help", "帮助"),
        Translation("Session", "记录"),
        Translation("Settings…", "设置…", alternatives: ["Preferences…", "偏好设置…"]),
        Translation("Services", "服务"),
        Translation("Hide Others", "隐藏其他"),
        Translation("Show All", "全部显示"),
        Translation("New Window", "新建窗口"),
        Translation("Close", "关闭"),
        Translation("Undo", "撤销"),
        Translation("Redo", "重做"),
        Translation("Cut", "剪切"),
        Translation("Copy", "拷贝", alternatives: ["复制"]),
        Translation("Paste", "粘贴"),
        Translation("Paste and Match Style", "粘贴并匹配样式"),
        Translation("Delete", "删除"),
        Translation("Select All", "全选"),
        Translation("Find", "查找"),
        Translation("Find…", "查找…"),
        Translation("Spelling and Grammar", "拼写和语法"),
        Translation("Substitutions", "替换"),
        Translation("Transformations", "转换"),
        Translation("Speech", "语音"),
        Translation("Start Speaking", "开始朗读"),
        Translation("Stop Speaking", "停止朗读"),
        Translation("Show Sidebar", "显示边栏"),
        Translation("Hide Sidebar", "隐藏边栏"),
        Translation("Enter Full Screen", "进入全屏幕"),
        Translation("Exit Full Screen", "退出全屏幕"),
        Translation("Minimize", "最小化"),
        Translation("Zoom", "缩放"),
        Translation("Bring All to Front", "前置全部窗口"),
        Translation("Start Logging", "开始记录"),
        Translation("Stop Logging", "结束记录"),
        Translation("Reveal Output Folder", "在访达中显示保存目录")
    ]

    static func apply(usesChinese: Bool) {
        guard let mainMenu = NSApp.mainMenu else { return }
        translate(menu: mainMenu, usesChinese: usesChinese)

        guard let applicationMenu = mainMenu.items.first?.submenu else { return }
        for item in applicationMenu.items {
            if item.title.hasPrefix("About ") || item.title.hasPrefix("关于 ") {
                item.title = usesChinese ? "关于 Network Speed Logger" : "About Network Speed Logger"
            } else if item.title.hasPrefix("Hide Network Speed Logger") || item.title.hasPrefix("隐藏 Network Speed Logger") {
                item.title = usesChinese ? "隐藏 Network Speed Logger" : "Hide Network Speed Logger"
            } else if item.title.hasPrefix("Quit Network Speed Logger") || item.title.hasPrefix("退出 Network Speed Logger") {
                item.title = usesChinese ? "退出 Network Speed Logger" : "Quit Network Speed Logger"
            }
        }
    }

    private static func translate(menu: NSMenu, usesChinese: Bool) {
        for item in menu.items {
            if let translation = translations.first(where: { $0.alternatives.contains(item.title) }) {
                item.title = usesChinese ? translation.chinese : translation.english
            }
            if let submenu = item.submenu {
                translate(menu: submenu, usesChinese: usesChinese)
            }
        }
    }
}
