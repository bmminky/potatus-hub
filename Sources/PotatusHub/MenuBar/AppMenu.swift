import AppKit

/// Builds the right-click menu and handles its actions. It only asks
/// `PanelCoordinator` to do things; it never touches panels directly.
@MainActor
final class AppMenu: NSObject {
    private let coordinator: PanelCoordinator
    private let monitor: SystemMonitor
    private let settings: AppSettings
    private let onMenuBarKindsChanged: () -> Void

    init(coordinator: PanelCoordinator, monitor: SystemMonitor,
         settings: AppSettings = .shared, onMenuBarKindsChanged: @escaping () -> Void) {
        self.coordinator = coordinator
        self.monitor = monitor
        self.settings = settings
        self.onMenuBarKindsChanged = onMenuBarKindsChanged
        super.init()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let heading = NSMenuItem(title: L.t(ko: "모듈", en: "Modules", ja: "モジュール", zh: "模块"), action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        for kind in MetricKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(toggleModule(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.state = coordinator.isVisible(kind) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(menuBarMenuItem())

        menu.addItem(.separator())
        let hide = NSMenuItem(title: L.t(ko: "숨기기", en: "Hide", ja: "隠す", zh: "隐藏"), action: #selector(hidePanels), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)

        let vertical = NSMenuItem(title: L.t(ko: "세로 정렬", en: "Arrange Vertically", ja: "縦に整列", zh: "纵向排列"), action: #selector(arrangeModulesVertically), keyEquivalent: "")
        vertical.target = self
        menu.addItem(vertical)

        let horizontal = NSMenuItem(title: L.t(ko: "가로 정렬", en: "Arrange Horizontally", ja: "横に整列", zh: "横向排列"), action: #selector(arrangeModulesHorizontally), keyEquivalent: "")
        horizontal.target = self
        menu.addItem(horizontal)

        let combine = NSMenuItem(title: L.t(ko: "결합", en: "Combine", ja: "結合", zh: "合并"), action: #selector(combineAllModules), keyEquivalent: "")
        combine.target = self
        combine.isEnabled = coordinator.panels.count > 1
        menu.addItem(combine)

        let detach = NSMenuItem(title: L.t(ko: "분리", en: "Detach", ja: "分離", zh: "分离"), action: #selector(detachAllModules), keyEquivalent: "")
        detach.target = self
        detach.isEnabled = coordinator.panels.contains { $0.kinds.count > 1 }
        menu.addItem(detach)

        let refresh = NSMenuItem(title: L.t(ko: "새로고침", en: "Refresh", ja: "更新", zh: "刷新"), action: #selector(refresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())
        let launchAtLogin = NSMenuItem(title: L.t(ko: "로그인 시 자동 실행", en: "Launch at Login", ja: "ログイン時に自動起動", zh: "登录时启动"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchAtLogin)

        menu.addItem(languageMenuItem())

        let about = NSMenuItem(title: L.t(ko: "\(AboutPanel.appName) 정보", en: "About \(AboutPanel.appName)", ja: "\(AboutPanel.appName) について", zh: "关于\(AboutPanel.appName)"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: L.t(ko: "potatus hub 종료", en: "Quit potatus hub", ja: "potatus hub を終了", zh: "退出 potatus hub"), action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    func showPanelMenu(_ panel: ModulePanel, event: NSEvent) {
        guard let view = panel.contentView else { return }
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: view)
    }

    private func menuBarMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: L.t(ko: "메뉴바에 표시", en: "Show in Menu Bar", ja: "メニューバーに表示", zh: "在菜单栏显示"),
            action: nil, keyEquivalent: ""
        )
        let submenu = NSMenu()
        let chosen = settings.menuBarKinds
        for kind in MetricKind.allCases {
            let option = NSMenuItem(title: kind.title, action: #selector(toggleMenuBarKind(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = kind.rawValue
            option.state = chosen.contains(kind) ? .on : .off
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    @objc private func toggleMenuBarKind(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let kind = MetricKind(rawValue: rawValue) else { return }
        var chosen = settings.menuBarKinds
        if chosen.contains(kind) { chosen.remove(kind) } else { chosen.insert(kind) }
        settings.menuBarKinds = chosen
        onMenuBarKindsChanged()
    }

    private func languageMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "언어 / Language / 言語 / 语言", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let options: [(L.Language, String)] = [
            (.system, L.t(ko: "시스템 언어 따름", en: "Follow System", ja: "システム言語に従う", zh: "跟随系统语言")),
            (.korean, "한국어"),
            (.english, "English"),
            (.japanese, "日本語"),
            (.chinese, "中文"),
        ]
        for (language, title) in options {
            let option = NSMenuItem(title: title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = language.rawValue
            option.state = L.languagePreference == language ? .on : .off
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    @objc private func hidePanels() {
        coordinator.setPanelPresentation(show: false)
    }

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let kind = MetricKind(rawValue: rawValue) else { return }
        coordinator.toggleModule(kind)
    }

    @objc private func refresh() {
        monitor.refresh()
    }

    @objc private func arrangeModulesHorizontally() {
        coordinator.arrangeModulesHorizontally()
    }

    @objc private func arrangeModulesVertically() {
        coordinator.arrangeModulesVertically()
    }

    @objc private func combineAllModules() {
        coordinator.combineAllModules()
    }

    @objc private func detachAllModules() {
        coordinator.detachAllModules()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = L.Language(rawValue: rawValue) else { return }
        L.languagePreference = language
    }

    @objc private func showAbout() {
        AboutPanel.show()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
