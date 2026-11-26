import ActivityKit
import AudioToolbox
import Foundation
import Observation
import UIKit
import UserNotifications

/// The running live workout of the active person. Kept in a JSON file on the
/// phone (written on every change, so killing the app never loses a set), like
/// the web app keeps it in localStorage. A leftover server draft is picked up
/// once when this phone has no session; finishing or discarding removes it.
@MainActor
@Observable
final class LiveStore {
    private(set) var session: LiveSession?
    private(set) var personId: String?
    /// The live tab is on screen (keeps the display awake while training).
    var presented = false { didSet { updateIdleTimer() } }

    var defaultRest: Int {
        didSet { UserDefaults.standard.set(defaultRest, forKey: Keys.defaultRest) }
    }
    var haptics: Bool {
        didSet { UserDefaults.standard.set(haptics, forKey: Keys.haptics) }
    }
    var sound: Bool {
        didSet { UserDefaults.standard.set(sound, forKey: Keys.sound) }
    }
    var defaultTimerMode: TimedSetMode {
        didSet { UserDefaults.standard.set(defaultTimerMode.rawValue, forKey: Keys.defaultTimerMode) }
    }

    /// Exercise name lookup (set by the app from the exercise library).
    @ObservationIgnored var exerciseName: @MainActor (String) -> String = { $0 }

    private enum Keys {
        static let defaultRest = "preworkout.live.defaultRest"
        static let haptics = "preworkout.live.haptics"
        static let sound = "preworkout.live.sound"
        static let defaultTimerMode = "preworkout.live.timerMode.default"
        static let timerMode = "preworkout.live.timerMode."
        static let countdownTarget = "preworkout.live.countdownTarget."
        static let askedNotifications = "preworkout.live.askedNotifications"
    }

    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var hydrated: Set<String> = []
    @ObservationIgnored private var scheduledRest: String?
    @ObservationIgnored private var scheduledSetTimer: String?
    @ObservationIgnored private let notificationSilencer = ForegroundNotificationSilencer()
    @ObservationIgnored private var activity: Activity<WorkoutActivityAttributes>?
    @ObservationIgnored private var lastContent: WorkoutActivityAttributes.ContentState?
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        let d = UserDefaults.standard
        defaultRest = d.object(forKey: Keys.defaultRest) as? Int ?? LiveSession.defaultRestSeconds
        haptics = d.object(forKey: Keys.haptics) as? Bool ?? true
        sound = d.object(forKey: Keys.sound) as? Bool ?? true
        if let raw = d.string(forKey: Keys.defaultTimerMode), let mode = TimedSetMode(rawValue: raw) {
            defaultTimerMode = mode
        } else {
            defaultTimerMode = .stopwatch
        }
        activity = Activity<WorkoutActivityAttributes>.activities.first
        UNUserNotificationCenter.current().delegate = notificationSilencer
    }

    // MARK: Timer mode

    func timerMode(for exerciseId: String) -> TimedSetMode {
        if let raw = UserDefaults.standard.string(forKey: Keys.timerMode + exerciseId),
           let mode = TimedSetMode(rawValue: raw) {
            return mode
        }
        return defaultTimerMode
    }

    func setTimerMode(_ mode: TimedSetMode, for exerciseId: String) {
        UserDefaults.standard.set(mode.rawValue, forKey: Keys.timerMode + exerciseId)
        if mode == .countdown { prepareCountdownNotifications() }
    }

    func savedCountdownTarget(for exerciseId: String) -> Double? {
        guard UserDefaults.standard.object(forKey: Keys.countdownTarget + exerciseId) != nil else { return nil }
        let value = UserDefaults.standard.double(forKey: Keys.countdownTarget + exerciseId)
        guard Limits.durationSeconds.contains(value), value >= 1 else { return nil }
        return value
    }

    func setCountdownTarget(_ seconds: Double, for exerciseId: String) {
        UserDefaults.standard.set(Limits.durationSeconds.clamp(max(1, seconds)), forKey: Keys.countdownTarget + exerciseId)
    }

    /// Remembered goal first, then the previous set, plan hold target, pending value, seed.
    func countdownPrefill(for e: LiveExercise, field: LiveSession.TimerField) -> Double {
        if let saved = savedCountdownTarget(for: e.item.exerciseId) { return saved }
        if let last = e.item.sets.last {
            if field == .hold, let value = last.holdSeconds, value >= 1 {
                return Limits.durationSeconds.clamp(value)
            }
            if field == .duration, let value = last.durationSeconds, value >= 1 {
                return Limits.durationSeconds.clamp(Double(value))
            }
        }
        if field == .hold, let target = e.target?["targetHoldMax"] ?? e.target?["targetHoldMin"], target >= 1 {
            return Limits.durationSeconds.clamp(target)
        }
        if field == .hold, let pending = e.pending.holdSeconds, pending >= 1 {
            return Limits.durationSeconds.clamp(pending)
        }
        if field == .duration, let pending = e.pending.durationSeconds, pending >= 1 {
            return Limits.durationSeconds.clamp(Double(pending))
        }
        return field == .hold ? SetField.hold.seed : SetField.duration.seed
    }

    /// Prompt once, the first time the user picks or starts a countdown.
    /// Denial is fine: in-app sound still plays in the foreground.
    func prepareCountdownNotifications() {
        guard UserDefaults.standard.object(forKey: Keys.askedNotifications) == nil else { return }
        UserDefaults.standard.set(true, forKey: Keys.askedNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Lifecycle

    /// Loads the session of `person` (file first, then a leftover server draft once).
    func load(person: String) async {
        if personId != person {
            personId = person
            session = Self.read(person)
            afterChange(save: false)
        }
        guard session == nil, !hydrated.contains(person) else { return }
        hydrated.insert(person)
        guard let draft = try? await api.liveDraft(person: person), personId == person, session == nil else { return }
        session = draft.data
        afterChange()
    }

    /// Starts a session, empty or with exercises (e.g. a repeated workout).
    func start(exercises: [LiveExercise] = [], title: String = "") {
        guard personId != nil else { return }
        var fresh = LiveSession(date: DayString.today, now: LiveSession.nowMs)
        fresh.exercises = exercises
        fresh.title = title
        session = fresh
        afterChange()
        Analytics.send("Workout.liveStarted")
    }

    /// Applies a change with the current time and persists it.
    func update(_ change: (inout LiveSession, Double) -> Void) {
        guard var s = session else { return }
        change(&s, LiveSession.nowMs)
        session = s
        afterChange()
    }

    /// Discards an unfinished session (including one restored after the app was killed).
    func discard() {
        if let session {
            let completedExercises = session.exercises.filter { !$0.item.sets.isEmpty }.count
            Analytics.send("Workout.liveAbandoned", [
                "exerciseCount": Analytics.exerciseCountBucket(completedExercises),
                "setCount": Analytics.countBucket(session.loggedSetCount),
                "duration": Analytics.durationBucket(seconds: session.elapsedMs(LiveSession.nowMs) / 1000),
            ])
        }
        clear()
    }

    /// Ends the session (after saving or discarding): removes local and server copies.
    func clear() {
        session = nil
        afterChange()
        if let personId {
            let api = api
            Task { try? await api.deleteLiveDraft(person: personId) }
        }
    }

    /// Bumped after a live workout was saved (the workout list reloads).
    private(set) var savedCount = 0

    /// After the workout was saved: switch to the workout list first, then
    /// end the session once the live tab is off screen, so the finish screen
    /// is never re-rendered (or its fields written) without a session.
    func didSave(sessionId: String) {
        savedCount += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.session?.id == sessionId else { return }
            self.clear()
        }
    }

    func restore(_ snapshot: LiveSession) {
        session = snapshot
        afterChange()
    }

    func unload() {
        personId = nil
        session = nil
        hydrated.removeAll()
        presented = false
        afterChange(save: false)
    }

    static func deleteAllLocalSessions() {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("live", isDirectory: true))
    }

    // MARK: Feedback

    func tap() {
        if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    func success() {
        if haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func signal() {
        if haptics { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        if sound { AudioServicesPlaySystemSound(1005) }
    }

    // MARK: Side effects

    private func afterChange(save: Bool = true) {
        if save, let personId { Self.write(session, person: personId) }
        updateTicker()
        updateIdleTimer()
        scheduleRestNotification()
        scheduleSetTimerNotification()
        updateActivity()
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = presented && session != nil && session?.isPaused == false
    }

    /// Fires the end-of-rest / set-timer-target signal once while the app is open.
    private func updateTicker() {
        if session == nil {
            ticker?.cancel()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let s = session, !s.isPaused else { return }
        let now = LiveSession.nowMs
        if let r = s.rest, !r.alerted, r.remaining(now) <= 0 {
            signal()
            update { s, _ in s.rest?.alerted = true }
        }
        if let t = s.setTimer, t.shouldAlert(now) {
            // If we returned after the background notification already fired,
            // don't play the in-app signal a second time.
            let late = t.elapsed(now) - (t.targetSec ?? 0) >= 1.5
            if !late { signal() }
            update { s, _ in s.setTimer?.alerted = true }
        }
    }

    /// Local notification at the end of the rest (shown when the app is in the background).
    private func scheduleRestNotification() {
        let center = UNUserNotificationCenter.current()
        let now = LiveSession.nowMs
        guard let s = session, let r = s.rest, !s.isPaused, !r.alerted, r.remaining(now) > 1 else {
            if scheduledRest != nil {
                center.removePendingNotificationRequests(withIdentifiers: [PhaseNotification.restId])
                scheduledRest = nil
            }
            return
        }
        let key = "\(r.itemId)-\(r.setIndex)-\(r.startedAt)-\(r.durationSec)"
        guard key != scheduledRest else { return }
        scheduledRest = key
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Koniec przerwy")
        if let e = s.currentExercise {
            content.body = String(localized: "Czas na serię: \(name(of: e))")
        }
        content.sound = sound ? .default : nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: r.remaining(now), repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [PhaseNotification.restId])
        center.add(UNNotificationRequest(identifier: PhaseNotification.restId, content: content, trigger: trigger))
    }

    /// Local notification at the absolute end of a set countdown (lock screen / background).
    private func scheduleSetTimerNotification() {
        guard let s = session, let t = s.setTimer, t.countsDown, !s.isPaused, !t.alerted,
              let end = t.endDate(), end.timeIntervalSinceNow > 1 else {
            if scheduledSetTimer != nil {
                PhaseNotification.cancel(id: PhaseNotification.setTimerId)
                scheduledSetTimer = nil
            }
            return
        }
        let key = "\(t.startedAt)-\(t.targetSec ?? 0)-\(end.timeIntervalSince1970)"
        guard key != scheduledSetTimer else { return }
        scheduledSetTimer = key
        let body: String
        if let e = s.currentExercise {
            body = String(localized: "\(name(of: e)). Kontynuuj albo zatrzymaj serię.")
        } else {
            body = String(localized: "Kontynuuj albo zatrzymaj serię.")
        }
        PhaseNotification.schedule(
            id: PhaseNotification.setTimerId,
            at: end,
            title: String(localized: "Czas minął"),
            body: body,
            sound: sound
        )
    }

    func name(of e: LiveExercise) -> String {
        e.item.sequence.count > 1
            ? e.item.sequence.map(exerciseName).joined(separator: " → ")
            : exerciseName(e.item.exerciseId)
    }

    // MARK: Live Activity

    private func content(_ s: LiveSession) -> WorkoutActivityAttributes.ContentState {
        let now = LiveSession.nowMs
        let date = { (ms: Double) in Date(timeIntervalSince1970: ms / 1000) }
        var restEnd: Date?
        var restPaused: Int?
        if let r = s.rest {
            if let p = r.pausedRemaining { restPaused = p.safeSeconds }
            else { restEnd = date(r.startedAt + r.durationSec * 1000) }
        }
        var exercise = String(localized: "Brak ćwiczeń")
        var detail = ""
        if let e = s.currentExercise {
            exercise = name(of: e)
            let n = e.item.sets.count + 1
            let total = max(e.plannedSets, n)
            detail = String(localized: "Seria \(n) z \(total)")
        }
        var setStopwatchStart: Date?
        var setCountdownEnd: Date?
        var setOvertimeStart: Date?
        var setPausedSeconds: Int?
        if let t = s.setTimer {
            if s.isPaused || t.pausedElapsed != nil {
                setPausedSeconds = t.displaySeconds(now).safeInt
            } else if t.countsDown, let end = t.endDate() {
                if t.isOvertime(now) {
                    setOvertimeStart = end
                } else {
                    setCountdownEnd = end
                }
            } else {
                setStopwatchStart = date(t.startedAt)
            }
        }
        return .init(
            clockStart: date(s.startedAt + s.pausedMs),
            pausedElapsed: s.isPaused ? (s.elapsedMs(now) / 1000).safeInt : nil,
            restEnd: restEnd,
            restPausedRemaining: restPaused,
            exercise: exercise,
            detail: detail,
            setStopwatchStart: setStopwatchStart,
            setCountdownEnd: setCountdownEnd,
            setOvertimeStart: setOvertimeStart,
            setPausedSeconds: setPausedSeconds
        )
    }

    private func updateActivity() {
        Task { await applyActivity() }
    }

    /// Ends or updates the Live Activity without sending the main-actor
    /// stored handle into Activity.update, which is @concurrent in the iOS 27 SDK.
    private func applyActivity() async {
        guard let s = session else {
            lastContent = nil
            activity = nil
            for a in Activity<WorkoutActivityAttributes>.activities {
                await a.end(nil, dismissalPolicy: .immediate)
            }
            return
        }
        let state = content(s)
        guard state != lastContent else { return }
        lastContent = state
        if let current = activity, current.activityState == .active || current.activityState == .stale {
            // Activity.update is @concurrent in the iOS 27 SDK, so the compiler
            // won't take a main-actor handle directly. This handle is only used
            // to update our own Live Activity.
            nonisolated(unsafe) let current = current
            await current.update(ActivityContent(state: state, staleDate: nil))
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let title = s.title.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Trening") : s.title
        activity = try? Activity.request(
            attributes: WorkoutActivityAttributes(title: title),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    // MARK: Storage

    private static func url(_ person: String) -> URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        let folder = dir.appendingPathComponent("live", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = person.replacingOccurrences(of: "/", with: "_")
        return folder.appendingPathComponent("\(safe).json")
    }

    private static func read(_ person: String) -> LiveSession? {
        guard let url = url(person), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LiveSession.self, from: data)
    }

    private static func write(_ session: LiveSession?, person: String) {
        guard let url = url(person) else { return }
        if let session, let data = try? JSONEncoder().encode(session) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
