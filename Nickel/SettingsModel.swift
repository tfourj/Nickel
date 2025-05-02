import Foundation
import Combine

class SettingsModel: ObservableObject {
    @Published var customAPIURL: String {
        didSet { UserDefaults.standard.set(customAPIURL, forKey: "customAPIURL") }
    }
    @Published var customAPIKey: String {
        didSet { UserDefaults.standard.set(customAPIKey, forKey: "customAPIKey") }
    }
    @Published var authMethod: String {
        didSet { UserDefaults.standard.set(authMethod, forKey: "authMethod") }
    }
    @Published var autoSaveToPhotos: Bool {
        didSet { UserDefaults.standard.set(autoSaveToPhotos, forKey: "autoSaveToPhotos") }
    }
    @Published var enableConsole: Bool {
        didSet { UserDefaults.standard.set(enableConsole, forKey: "enableConsole") }
    }
    @Published var autoClearErrorMessage: Bool {
        didSet { UserDefaults.standard.set(autoClearErrorMessage, forKey: "autoClearErrorMessage") }
    }
    @Published var autoOpenHome: Bool {
        didSet { UserDefaults.standard.set(autoOpenHome, forKey: "autoOpenHome") }
    }
    @Published var disableAutoPasteRun: Bool {
        didSet { UserDefaults.standard.set(disableAutoPasteRun, forKey: "disableAutoPasteRun") }
    }
    @Published var disableBGDownloads: Bool {
        didSet { UserDefaults.standard.set(disableBGDownloads, forKey: "disableBGDownloads") }
    }
    @Published var disableNotifications: Bool {
        didSet { UserDefaults.standard.set(disableNotifications, forKey: "disableNotifications") }
    }
    @Published var customAuthServerURL: String {
        didSet { UserDefaults.standard.set(customAuthServerURL, forKey: "customAuthServerURL") }
    }
    @Published var rememberPickerDownloadOption: Bool {
        didSet { UserDefaults.standard.set(rememberPickerDownloadOption, forKey: "rememberPickerDownloadOption") }
    }
    @Published var enableDebugTab: Bool {
        didSet { UserDefaults.standard.set(enableDebugTab, forKey: "enableDebugTab") }
    }

    init() {
        self.customAPIURL = UserDefaults.standard.string(forKey: "customAPIURL") ?? ""
        self.customAPIKey = UserDefaults.standard.string(forKey: "customAPIKey") ?? ""
        self.authMethod = UserDefaults.standard.string(forKey: "authMethod") ?? "Nickel-Auth"
        self.autoSaveToPhotos = UserDefaults.standard.object(forKey: "autoSaveToPhotos") as? Bool ?? true
        self.enableConsole = UserDefaults.standard.object(forKey: "enableConsole") as? Bool ?? false
        self.autoClearErrorMessage = UserDefaults.standard.object(forKey: "autoClearErrorMessage") as? Bool ?? false
        self.autoOpenHome = UserDefaults.standard.object(forKey: "autoOpenHome") as? Bool ?? false
        self.disableAutoPasteRun = UserDefaults.standard.object(forKey: "disableAutoPasteRun") as? Bool ?? false
        self.disableBGDownloads = UserDefaults.standard.object(forKey: "disableBGDownloads") as? Bool ?? false
        self.disableNotifications = UserDefaults.standard.object(forKey: "disableNotifications") as? Bool ?? false
        self.customAuthServerURL = UserDefaults.standard.string(forKey: "customAuthServerURL") ?? ""
        self.rememberPickerDownloadOption = UserDefaults.standard.object(forKey: "rememberPickerDownloadOption") as? Bool ?? true
        self.enableDebugTab = UserDefaults.standard.object(forKey: "enableDebugTab") as? Bool ?? false
    }
}
