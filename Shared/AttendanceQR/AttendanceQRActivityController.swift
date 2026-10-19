#if !TOOLBOX_WIDGET_EXTENSION
import ActivityKit
import Foundation

@MainActor
enum AttendanceQRActivityController {
    // At most the latest handle is retained for best-effort replacement. This
    // controller writes no files or logs; WidgetKit itself retains configuration
    // and ActivityKit retains its content as part of their system-managed state.
    private static var retainedActivities: [String: Activity<AttendanceQRActivityAttributes>] = [:]
    private static var isStarting = false

    static func show(_ configuration: AttendanceQRConfiguration) async throws {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw AttendanceQRError.activitiesDisabled
        }
        // Preflight rendering before replacing an existing card.
        _ = try AttendanceQRRenderer.render(payload: configuration.payload, displayScale: 2)
        await hideAllKnownActivities()

        let startedAt = Date()
        let expiresAt = startedAt.addingTimeInterval(TimeInterval(configuration.durationSeconds))
        let state = AttendanceQRActivityAttributes.ContentState(
            payload: configuration.payload, startedAt: startedAt, expiresAt: expiresAt
        )
        let attributes = AttendanceQRActivityAttributes(label: configuration.label,
                                                       operation: configuration.operation)
        let content = ActivityContent(state: state, staleDate: expiresAt, relevanceScore: 0)
        let activity = try Activity<AttendanceQRActivityAttributes>.request(
            attributes: attributes, content: content, pushType: nil
        )
        retainedActivities[activity.id] = activity

        // iOS 18 has no end(afterDate:) API. End immediately while retaining the
        // final QR content on the Lock Screen until the OS dismissal date.
        // This also ends Dynamic Island presentation immediately. It deliberately
        // trades a persistent Island for OS-managed removal without a background
        // Task.sleep, timer, push server, scheduled notification or BGTask.
        // https://developer.apple.com/documentation/activitykit/activity/end(_:dismissalpolicy:)
        // https://developer.apple.com/documentation/activitykit/activityuidismissalpolicy/after(_:)
        await activity.end(content, dismissalPolicy: .after(expiresAt))
    }

    static func hide(activityID: String) async -> Bool {
        let activity = retainedActivities[activityID]
            ?? Activity<AttendanceQRActivityAttributes>.activities.first { $0.id == activityID }
        guard let activity else { return false }
        // Do not claim success for an already-ended card. Changing its final
        // content/dismissal a second time is not a documented guarantee.
        switch activity.activityState {
        case .active, .stale: break
        default: return false
        }
        await activity.end(ActivityContent(state: activity.content.state.hidden, staleDate: nil),
                           dismissalPolicy: .immediate)
        retainedActivities[activityID] = nil
        return true
    }

    private static func hideAllKnownActivities() async {
        // Best effort only for ended cards. Following process termination, an
        // earlier ended card may remain until its own OS dismissal date.
        var activities = retainedActivities
        for activity in Activity<AttendanceQRActivityAttributes>.activities {
            activities[activity.id] = activity
        }
        for activity in activities.values {
            await activity.end(ActivityContent(state: activity.content.state.hidden, staleDate: nil),
                               dismissalPolicy: .immediate)
        }
        retainedActivities.removeAll()
    }
}
#endif
