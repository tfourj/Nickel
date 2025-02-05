//
//  ShareSheet.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//


import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems,
                                 applicationActivities: [SaveToPhotosActivity()])
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Custom Activity to Save Video to Photos
class SaveToPhotosActivity: UIActivity {
    var videoURL: URL?
    
    override var activityTitle: String? {
        "Save to Photos"
    }
    
    override var activityImage: UIImage? {
        UIImage(systemName: "arrow.down.circle")
    }
    
    override class var activityCategory: UIActivity.Category {
        .action
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        for item in activityItems {
            if let url = item as? URL, url.pathExtension.lowercased() == "mp4" {
                return true
            }
        }
        return false
    }
    
    override func prepare(withActivityItems activityItems: [Any]) {
        for item in activityItems {
            if let url = item as? URL, url.pathExtension.lowercased() == "mp4" {
                self.videoURL = url
                break
            }
        }
    }
    
    override func perform() {
        guard let videoURL = videoURL else {
            activityDidFinish(false)
            return
        }
        UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, self,
                                            #selector(video(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc func video(_ videoPath: String, didFinishSavingWithError error: Error?, contextInfo: UnsafeMutableRawPointer?) {
        activityDidFinish(error == nil)
    }
}
