//
//  hainomiya_villageApp.swift
//  hainomiya-village
//
//  Created by eiki ogawa on 2026/07/26.
//

import SwiftUI
import AppTrackingTransparency
import IronSource

@main
struct hainomiya_villageApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var didRequestTracking = false

    init() {
        print("[DebugBadge] Identifier: \(DebugDeviceConfig.persistentDeviceID)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                requestTrackingThenStartAds()
            }
        }
    }

    private func requestTrackingThenStartAds() {
        guard !didRequestTracking else { return }
        didRequestTracking = true

        Task {
            // UI が完全にアクティブになるまで少し待ってからダイアログを表示する。
            try? await Task.sleep(nanoseconds: 500_000_000)
            await ATTrackingManager.requestTrackingAuthorization()

            // 子ども向けアプリではないことを明示する。未設定だと広告が制限される。
            LPMPrivacySettings.setCOPPA(false)

            LevelPlayAdsController.shared.initialize()
        }
    }
}
