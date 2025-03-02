//
//  AppDelegate.swift
//  ClubSound
//
//  Created by Kirk Elliott on 12/6/24.
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if let window = UIApplication.shared.windows.first {
            window.backgroundColor = UIColor.systemBackground // Set your fallback color here
        }
        return true
    }
}
