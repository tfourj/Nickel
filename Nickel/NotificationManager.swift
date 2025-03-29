//
//  NotificationManager.swift
//  Nickel
//
//  Created by TfourJ on 24. 2. 25.
//

import UIKit
import UserNotifications

class NotificationManager {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            logOutput("Notification permission granted: \(granted)")
        }
    }
    
    static func sendDownloadCompleteNotification(text: String, forceNotification: Bool = false) {
        // Check if notis are disabled
        let disableNotifications = UserDefaults.standard.bool(forKey: "disableNotifications")
        if disableNotifications && !forceNotification {
            logOutput("Notifications are disabled by user")
            return
        }
        
        // Only send notification if app is in background
        if !forceNotification && UIApplication.shared.applicationState == .active {
            logOutput("User is currently in app, skipping notification send.")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Nickel"
        content.body = "\(text)"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                          content: content,
                                          trigger: nil)
        
        UNUserNotificationCenter.current().add(request)
        logOutput("Notification was sent with output: \(text)")
    }
}
