import Foundation
import UIKit
import AdSupport
import AppTrackingTransparency

enum DebugDeviceConfig {
    private static let registeredIDs: [String] = {
        guard let url = Bundle.main.url(forResource: "debug-config", withExtension: "js"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let pattern = #"VENDOR_IDS\s*:\s*\[([^\]]*)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return [] }
        return content[range]
            .components(separatedBy: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                  .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            }
            .filter { !$0.isEmpty }
    }()

    static var isDebugDevice: Bool {
        let identifier = ATTrackingManager.trackingAuthorizationStatus == .authorized
            ? ASIdentifierManager.shared().advertisingIdentifier.uuidString
            : (UIDevice.current.identifierForVendor?.uuidString ?? "")
        return registeredIDs.contains(identifier)
    }
}
