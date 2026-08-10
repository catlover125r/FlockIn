import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class EventStore: ObservableObject {
    @Published var availableEvents: [Event] = []
    @Published var myEvents: [Event] = []
    @Published var isLoading = true

    /// Set when a Firestore listener fails — a denied read, or no connection on
    /// a cold start. Previously these were discarded, which left the app
    /// spinning forever with nothing on screen to explain why.
    @Published var loadError: String?

    private let service = FirestoreService()
    private var allEvents: [Event] = []
    private var eventsLoaded = false
    private var signupsLoaded = false
    private var eventsListener: ListenerRegistration?
    private var signupsListener: ListenerRegistration?

    /// True once the test account's sample data is in place. Sign-ups made
    /// during a demo session live only in `myEvents`, so re-seeding would throw
    /// them away — and both pull-to-refresh and re-entering the tab come back
    /// through `startListening`.
    private var demoSeeded = false
    private var isDemo = false

    // MARK: - Lifecycle

    /// Attaches both listeners. `showLoading` is false for pull-to-refresh,
    /// where the spinner is already being drawn by the refresh control.
    func startListening(for session: AuthService.Session, showLoading: Bool = true) {
        stopListening()
        if showLoading { isLoading = true }
        loadError = nil

        guard case .firebase(let user) = session else {
            isDemo = true
            if !demoSeeded { seedDemoData() }
            // Nothing to wait for: the sample data is already in memory.
            isLoading = false
            return
        }

        isDemo = false
        eventsLoaded = false
        signupsLoaded = false
        let email = user.email ?? ""

        eventsListener = service.listenForEvents { [weak self] events in
            guard let self else { return }
            self.allEvents = events
            self.eventsLoaded = true
            self.filterAvailable()
            self.updateLoadingState()
        } onError: { [weak self] error in
            self?.handle(error)
        }

        signupsListener = service.listenForMySignups(studentEmail: email) { [weak self] events in
            guard let self else { return }
            self.myEvents = events
            self.signupsLoaded = true
            self.filterAvailable()
            self.updateLoadingState()
        } onError: { [weak self] error in
            self?.handle(error)
        }
    }

    func refreshListeners(for session: AuthService.Session) {
        startListening(for: session, showLoading: false)
    }

    func stopListening() {
        eventsListener?.remove()
        signupsListener?.remove()
        eventsListener = nil
        signupsListener = nil
    }

    // MARK: - Actions

    func signUp(for event: Event, session: AuthService.Session, displayName: String) async throws {
        guard case .firebase(let user) = session else {
            demoSignUp(for: event)
            return
        }
        try await service.signUp(for: event, user: user, displayName: displayName)
    }

    func cancelSignup(for event: Event) async throws {
        guard let signupId = event.signupId else { return }
        guard !isDemo else {
            myEvents.removeAll { $0.signupId == signupId }
            filterAvailable()
            return
        }
        try await service.cancelSignup(signupId: signupId)
    }

    func checkIn(for event: Event, session: AuthService.Session, displayName: String) async throws {
        guard let signupId = event.signupId else { return }
        guard case .firebase(let user) = session else {
            guard let index = myEvents.firstIndex(where: { $0.signupId == signupId }) else { return }
            myEvents[index].isCheckedIn = true
            return
        }
        try await service.checkIn(
            signupId: signupId,
            user: user,
            event: event,
            displayName: displayName
        )
    }

    // MARK: - Private

    private func updateLoadingState() {
        if eventsLoaded && signupsLoaded { isLoading = false }
    }

    private func handle(_ error: Error) {
        loadError = error.localizedDescription
        // Stop waiting on a stream that has already failed.
        isLoading = false
    }

    private func filterAvailable() {
        // Sync isActive from the live events collection into myEvents,
        // since signup docs store isActive at sign-up time and never update it.
        let eventActiveMap = Dictionary(uniqueKeysWithValues: allEvents.map { ($0.id, $0.isActive) })
        myEvents = myEvents.map { signup in
            guard let liveActive = eventActiveMap[signup.id] else { return signup }
            var updated = signup
            updated.isActive = liveActive
            return updated
        }

        let signedUpIds = Set(myEvents.map { $0.id })
        availableEvents = allEvents.filter { !signedUpIds.contains($0.id) && !$0.isPast }
    }

    // MARK: - Test account

    private func seedDemoData() {
        allEvents = DemoData.events
        // Starts with one sign-up already in place so the My Events tab and the
        // check-in flow can be seen without signing up for anything first.
        myEvents = DemoData.events
            .filter { DemoData.preSignedUpIds.contains($0.id) }
            .map(Self.asSignup)
        eventsLoaded = true
        signupsLoaded = true
        demoSeeded = true
        filterAvailable()
    }

    private func demoSignUp(for event: Event) {
        guard !myEvents.contains(where: { $0.id == event.id }) else { return }
        myEvents.append(Self.asSignup(event))
        myEvents.sort { ($0.date, $0.time) < ($1.date, $1.time) }
        filterAvailable()
    }

    /// A real sign-up comes back from Firestore carrying its own document ID,
    /// which cancel and check-in key off. Sample sign-ups have to mint one.
    private static func asSignup(_ event: Event) -> Event {
        Event(
            id: event.id,
            signupId: "demo_signup_\(event.id)",
            title: event.title,
            task: event.task,
            date: event.date,
            time: event.time,
            location: event.location,
            latitude: event.latitude,
            longitude: event.longitude,
            isActive: event.isActive,
            isCheckedIn: false,
            hours: event.hours,
            positions: event.positions
        )
    }

}

/// The test account's sample events. Everything the "admin" login shows comes
/// from here — no Firestore, no dashboard API, no network of any kind, so it
/// behaves identically on a fresh install and in airplane mode.
///
/// Dates are generated relative to today rather than hardcoded, because
/// `Event.isPast` hides anything already over: a fixed date would quietly empty
/// the events list some weeks after the build shipped.
enum DemoData {

    /// Events the demo session starts out already signed up for.
    static let preSignedUpIds: Set<String> = ["demo-concessions"]

    static var events: [Event] {
        [
            Event(
                id: "demo-concessions",
                title: "Homecoming Game",
                task: "Run the concessions stand",
                date: day(offset: 0),
                time: soonTime,
                location: "Terremere Field",
                // Deliberately no coordinates. Check-in on a located event
                // requires standing within 200m of it, which a reviewer sitting
                // at a desk cannot do — this is the one they can complete.
                isActive: true,
                hours: 3,
                positions: 8
            ),
            Event(
                id: "demo-cleanup",
                title: "Campus Cleanup",
                task: "Sort recycling and clear the quad",
                date: day(offset: 1),
                time: "15:30",
                location: "Main Quad",
                latitude: 37.4746,
                longitude: -122.2314,
                hours: 2,
                positions: 12
            ),
            Event(
                id: "demo-blood-drive",
                title: "Blood Drive",
                task: "Check in donors at the front table",
                date: day(offset: 3),
                time: "09:00",
                location: "Small Gym",
                hours: 1.5,
                positions: 6
            ),
            Event(
                id: "demo-book-sale",
                title: "Library Book Sale",
                task: "Set up tables and price donated books",
                date: day(offset: 5),
                time: "13:00",
                location: "Library",
                latitude: 37.4751,
                longitude: -122.2308,
                hours: 2.5,
                positions: 4
            ),
            Event(
                id: "demo-orientation",
                title: "Freshman Orientation",
                task: "Lead campus tours for incoming students",
                date: day(offset: 8),
                time: "08:30",
                location: "Front Steps",
                hours: 4,
                positions: 10
            ),
            Event(
                id: "demo-food-bank",
                title: "Food Bank Drive",
                task: "Pack donation boxes",
                date: day(offset: 12),
                time: "10:00",
                location: "Student Center",
                latitude: 37.4739,
                longitude: -122.2321,
                hours: 3,
                // 0 spots means unlimited, so the card omits the spots count.
                positions: 0
            ),
        ]
    }

    /// The soonest event is placed a couple of hours out. Both halves come from
    /// the same instant so a late-evening launch cannot land the time after
    /// midnight while the date still says today — which would file the event as
    /// already past and hide it.
    private static var soon: Date {
        Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    }

    private static func day(offset: Int) -> String {
        let base = Calendar.current.date(byAdding: .day, value: offset, to: soon) ?? soon
        return format(base, as: "yyyy-MM-dd")
    }

    private static var soonTime: String {
        format(soon, as: "HH:mm")
    }

    private static func format(_ date: Date, as pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = pattern
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
