import Foundation
import OSLog
import UserNotifications

enum KeyboardHandoffDiagnosticSource: String, Codable, Sendable {
    case app = "APP"
    case keyboard = "KEYBOARD"
    case bridge = "BRIDGE"
    case notification = "NOTIFICATION"
}

struct KeyboardHandoffDiagnosticEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let source: KeyboardHandoffDiagnosticSource
    let message: String
    let details: String
}

enum KeyboardHandoffDiagnostics {
    private static let storageKey = "handoff.diagnosticEvents"
    private static let maximumEventCount = 60
    private static let lock = NSLock()
    private static let logger = Logger(
        subsystem: "com.fanpit.LazyFlowMobile",
        category: "KeyboardHandoff"
    )

    static func record(
        _ source: KeyboardHandoffDiagnosticSource,
        _ message: String,
        details: String = ""
    ) {
        let renderedMessage = details.isEmpty ? message : "\(message) · \(details)"
        logger.info("\(renderedMessage, privacy: .public)")
        print("[LazyFlow:Handoff:\(source.rawValue)] \(renderedMessage)")

        let event = KeyboardHandoffDiagnosticEvent(
            id: UUID(),
            timestamp: Date(),
            source: source,
            message: message,
            details: details
        )

        lock.lock()
        defer { lock.unlock() }

        var events = decodedEvents()
        events.append(event)
        events = Array(events.suffix(maximumEventCount))
        guard let data = try? JSONEncoder().encode(events) else { return }
        sharedDefaults.set(data, forKey: storageKey)
        sharedDefaults.synchronize()
    }

    static func recentEvents() -> [KeyboardHandoffDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return decodedEvents().sorted { $0.timestamp > $1.timestamp }
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        sharedDefaults.removeObject(forKey: storageKey)
        sharedDefaults.synchronize()
    }

    static func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        let lines = recentEvents().reversed().map { event in
            let details = event.details.isEmpty ? "" : " · \(event.details)"
            return "\(formatter.string(from: event.timestamp)) [\(event.source.rawValue)] \(event.message)\(details)"
        }
        return (["LazyFlow keyboard handoff diagnostics"] + lines).joined(separator: "\n")
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: SharedDictationStore.appGroupID) ?? .standard
    }

    private static func decodedEvents() -> [KeyboardHandoffDiagnosticEvent] {
        guard let data = sharedDefaults.data(forKey: storageKey),
              let events = try? JSONDecoder().decode(
                [KeyboardHandoffDiagnosticEvent].self,
                from: data
              ) else {
            return []
        }
        return events
    }
}

enum KeyboardHandoffNotification {
    static let requestIdentifier = "lazyflow.keyboard-handoff"

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            KeyboardHandoffDiagnostics.record(
                .notification,
                "Notification permission already resolved",
                details: authorizationDescription(settings.authorizationStatus)
            )
            return
        }

        KeyboardHandoffDiagnostics.record(.notification, "Requesting notification permission")
        do {
            let granted = try await center.requestAuthorization(options: [.alert])
            KeyboardHandoffDiagnostics.record(
                .notification,
                "Notification permission response",
                details: granted ? "granted" : "denied"
            )
        } catch {
            KeyboardHandoffDiagnostics.record(
                .notification,
                "Notification permission request failed",
                details: error.localizedDescription
            )
        }
    }

    static func schedule() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized,
              settings.alertSetting == .enabled else {
            KeyboardHandoffDiagnostics.record(
                .notification,
                "Open-app notification unavailable",
                details: "authorization=\(authorizationDescription(settings.authorizationStatus)), alerts=\(settings.alertSetting.rawValue)"
            )
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Open LazyFlow"
        content.body = "Tap to start listening, then swipe back to keep typing."
        content.categoryIdentifier = requestIdentifier
        content.threadIdentifier = requestIdentifier

        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        do {
            try await center.add(request)
            KeyboardHandoffDiagnostics.record(
                .notification,
                "Scheduled Open LazyFlow notification"
            )
            return true
        } catch {
            KeyboardHandoffDiagnostics.record(
                .notification,
                "Failed to schedule Open LazyFlow notification",
                details: error.localizedDescription
            )
            return false
        }
    }

    private static func authorizationDescription(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "not determined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown (\(status.rawValue))"
        }
    }
}
