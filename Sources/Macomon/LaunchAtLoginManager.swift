import AppKit
import ServiceManagement

final class LaunchAtLoginManager {
    private let service = SMAppService.mainApp
    private let defaults = UserDefaults.standard
    private let preferenceKey = "launchAtLoginRequested"

    var status: SMAppService.Status { service.status }

    var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }

    init() {
        if defaults.object(forKey: preferenceKey) == nil {
            defaults.set(true, forKey: preferenceKey)
        }
        enableIfRequestedAndInstalled()
    }

    func setEnabled(_ enabled: Bool) throws {
        defaults.set(enabled, forKey: preferenceKey)

        if enabled {
            guard isInstalledInApplications else {
                throw LaunchAtLoginError.appNotInstalled
            }
            if service.status == .notRegistered || service.status == .notFound {
                try service.register()
            }
        } else if service.status != .notRegistered {
            try service.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func enableIfRequestedAndInstalled() {
        guard
            defaults.bool(forKey: preferenceKey),
            isInstalledInApplications,
            service.status == .notRegistered || service.status == .notFound
        else { return }

        try? service.register()
    }
}

enum LaunchAtLoginError: LocalizedError {
    case appNotInstalled

    var errorDescription: String? {
        "Autostart wird aktiviert, sobald Macomon im Programme-Ordner liegt."
    }
}
