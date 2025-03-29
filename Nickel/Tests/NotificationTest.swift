//
//  NotificationTest.swift
//  Nickel
//
//  Created by TfourJ on 29. 3. 25.
//

import UIKit
import UserNotifications
import Foundation

func TestNotification() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        guard granted else { return }
        
        // Force display notifications when app is in foreground by setting delegate
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        
        // Now send your notification
        NotificationManager.sendDownloadCompleteNotification(text: "Test Notification", forceNotification: true)
    }
}

class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])  // Use .alert for <IOS13
    }
}
