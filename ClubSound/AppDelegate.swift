//
//  AppDelegate.swift
//  ClubSound
//
//  Created by Kirk Elliott on 12/6/24.
//


import UIKit

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
