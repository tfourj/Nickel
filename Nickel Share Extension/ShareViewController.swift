import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    
    // In viewDidLoad we simply do setup.
    override func viewDidLoad() {
        super.viewDidLoad()
        print("viewDidLoad")
    }
    
    // Process the shared content in viewDidAppear.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedURL()
    }
    
    private func handleSharedURL() {
        print("checking url")
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = item.attachments?.first else {
            dismissExtension()
            return
        }
        
        // Check if the attachment conforms to the URL type.
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (loadedItem, error) in
                if let url = loadedItem as? URL {
                    print("Shared URL: \(url)")
                    self?.sendURLToMainApp(url: url)
                } else {
                    self?.dismissExtension()
                }
            }
        } else {
            dismissExtension()
        }
    }
    
    private func sendURLToMainApp(url: URL) {
        // Save the URL into the shared container for your main app to pick up.
        let sharedDefaults = UserDefaults(suiteName: "group.com.tfourj.nickel")
        sharedDefaults?.set(url.absoluteString, forKey: "sharedURL")
        sharedDefaults?.synchronize()
        
        // Construct the URL that should open your main app.
        guard let appURL = URL(string: "nickel://download") else {
            dismissExtension()
            return
        }
        
        // Grab the window scene from our view so we have a reference.
        guard let windowScene = self.view.window?.windowScene else {
            dismissExtension()
            return
        }
        
        // Dismiss the share extension and then, after a short delay, open the main app.
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: { _ in
            // Delay to ensure the extension UI is fully dismissed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                windowScene.open(appURL, options: UIScene.OpenExternalURLOptions(), completionHandler: { success in
                    if success {
                        print("✅ Main app opened")
                    } else {
                        print("❌ Failed to open main app")
                    }
                })
            }
        })
    }
    
    private func dismissExtension() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
