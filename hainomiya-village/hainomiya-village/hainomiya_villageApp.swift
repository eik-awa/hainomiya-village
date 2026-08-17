//
//  hainomiya_villageApp.swift
//  hainomiya-village
//
//  Created by eiki ogawa on 2026/07/26.
//

import SwiftUI
import AppTrackingTransparency

@main
struct hainomiya_villageApp: App {
    init() {
        LevelPlayAdsController.shared.initialize()
        print("[DebugBadge] Identifier: \(DebugDeviceConfig.persistentDeviceID)")
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
