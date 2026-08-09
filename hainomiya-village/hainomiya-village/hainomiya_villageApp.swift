//
//  hainomiya_villageApp.swift
//  hainomiya-village
//
//  Created by eiki ogawa on 2026/07/26.
//

import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency
import AdSupport

@main
struct hainomiya_villageApp: App {
    init() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)

        let identifier = ATTrackingManager.trackingAuthorizationStatus == .authorized
            ? ASIdentifierManager.shared().advertisingIdentifier.uuidString
            : (UIDevice.current.identifierForVendor?.uuidString ?? "")
        print("[DebugBadge] Identifier: \(identifier)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                            ATTrackingManager.requestTrackingAuthorization { _ in }
                        }
                    }
                }
        }
    }
}
