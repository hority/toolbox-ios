#if !TOOLBOX_WIDGET_EXTENSION
import ActivityKit
import Foundation

@MainActor
enum AttendanceQRActivityController {
    // Coordinate operations with a Sendable value only. Activity is not
    // Sendable in the iOS 18 SDK: never cache a handle on this actor and pass it
    // across isolation to the SDK's nonisolated async end() method.
    private static var isOperating = false

    static func show(_ configuration: AttendanceQRConfiguration) async throws {
        guard !isOperating else { return }
        isOperating = true
        defer { isOperating = false }
        try await requestAndScheduleDismissal(configuration)
    }

    static func hide(activityID: String) async -> Bool {
        guard !isOperating else { return false }
        isOperating = true
        defer { isOperating = false }
        return await endActiveActivity(activityID: activityID)
    }

    // Each helper owns its non-Sendable Activity handles within one nonisolated
    // async task. Only Sendable configuration, IDs and results cross MainActor.
    // No handle is retained, captured in a child task or returned to the actor.
    private nonisolated static func requestAndScheduleDismissal(
        _ configuration: AttendanceQRConfiguration
    ) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw AttendanceQRError.activitiesDisabled
        }
        // Preflight rendering before replacing an existing card.
        _ = try AttendanceQRRenderer.render(payload: configuration.payload, displayScale: 2)
        await endKnownActivities()

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

        // iOS 18 has no end(afterDate:) API. End immediately while retaining the
        // final QR content on the Lock Screen until the OS dismissal date.
        // This also ends Dynamic Island presentation immediately. It deliberately
        // trades a persistent Island for OS-managed removal without a background
        // Task.sleep, timer, push server, scheduled notification or BGTask.
        // https://developer.apple.com/documentation/activitykit/activity/end(_:dismissalpolicy:)
        // https://developer.apple.com/documentation/activitykit/activityuidismissalpolicy/after(_:)
        await activity.end(content, dismissalPolicy: .after(expiresAt))
    }

    private nonisolated static func endActiveActivity(activityID: String) async -> Bool {
        guard let activity = Activity<AttendanceQRActivityAttributes>.activities.first(where: {
            $0.id == activityID
        }) else { return false }
        // Do not claim success for an already-ended card. Changing its final
        // content/dismissal a second time is not a documented guarantee.
        switch activity.activityState {
        case .active, .stale: break
        default: return false
        }
        await activity.end(ActivityContent(state: activity.content.state.hidden, staleDate: nil),
                           dismissalPolicy: .immediate)
        return true
    }

    private nonisolated static func endKnownActivities() async {
        // Best effort only for ended cards. Following process termination, an
        // earlier ended card may remain until its own OS dismissal date.
        for activity in Activity<AttendanceQRActivityAttributes>.activities {
            await activity.end(ActivityContent(state: activity.content.state.hidden, staleDate: nil),
                               dismissalPolicy: .immediate)
        }
    }
}
#endif
