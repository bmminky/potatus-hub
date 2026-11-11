import AppKit
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L.t(ko: "로그인 시 자동 실행을 변경할 수 없습니다", en: "Unable to change Launch at Login", ja: "ログイン時の自動起動を変更できません", zh: "无法更改登录时启动")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
