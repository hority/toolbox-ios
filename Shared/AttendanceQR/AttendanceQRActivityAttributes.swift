import ActivityKit
import Foundation

struct AttendanceQRActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let payload: String?
        let startedAt: Date
        let expiresAt: Date

        func shouldDisplayQR(at date: Date, isStale: Bool) -> Bool {
            guard !isStale, let payload,
                  (try? AttendanceQRConfiguration.validatePayload(payload)) != nil else { return false }
            let duration = expiresAt.timeIntervalSince(startedAt)
            return (duration == 30 || duration == 60) && date >= startedAt && date < expiresAt
        }

        var hidden: Self { Self(payload: nil, startedAt: startedAt, expiresAt: expiresAt) }
    }

    let label: String
    let operation: AttendanceQROperation
}
