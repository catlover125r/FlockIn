import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Base URL of the admin dashboard's API (the deployed Next.js app).
///
/// Sign-ups go through it rather than straight to Firestore, because an event's
/// spot limit can only be enforced somewhere that is allowed to count the
/// event's existing sign-ups.
enum AppConfig {
    static let apiBaseURL = URL(string: "https://flock-in-admin-dashboard.vercel.app")!
}

/// Sign-up failures worth explaining to the student rather than surfacing as a
/// raw HTTP status or Firestore permission error.
enum SignupError: LocalizedError {
    case alreadySignedUp
    case eventFull
    case notWhitelisted
    case eventNotFound
    case server

    var errorDescription: String? {
        switch self {
        case .alreadySignedUp:
            return "You're already signed up for this event."
        case .eventFull:
            return "This event is full."
        case .notWhitelisted:
            return "Your account is not registered. See your ASB advisor."
        case .eventNotFound:
            return "This event is no longer available."
        case .server:
            return "Couldn't sign you up. Please try again."
        }
    }
}

class FirestoreService {
    private let db = Firestore.firestore()

    /// Document ID for a student's sign-up to an event.
    ///
    /// Deterministic on purpose: a student cannot hold two sign-ups for the
    /// same event, because the second write lands on the same document and is
    /// rejected. The security rules require this exact shape, so both sides
    /// have to agree on it.
    static func signupId(eventId: String, uid: String) -> String {
        "\(eventId)_\(uid)"
    }

    // MARK: - Live Listeners

    /// Streams all events from /events, ordered by date.
    func listenForEvents(
        onChange: @escaping ([Event]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("events")
            .order(by: "date")
            .addSnapshotListener { snapshot, error in
                // A denied read or a cold offline start used to be swallowed
                // here, which left the app on a spinner with nothing to show.
                if let error {
                    DispatchQueue.main.async { onError(error) }
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let events = docs.compactMap { Event(from: $0.data(), id: $0.documentID) }
                DispatchQueue.main.async { onChange(events) }
            }
    }

    /// Streams the current student's signups from /signups.
    func listenForMySignups(
        studentEmail: String,
        onChange: @escaping ([Event]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("signups")
            .whereField("studentEmail", isEqualTo: studentEmail)
            .addSnapshotListener { snapshot, error in
                if let error {
                    DispatchQueue.main.async { onError(error) }
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let events = docs.compactMap {
                    Event(fromSignup: $0.data(), signupId: $0.documentID)
                }
                DispatchQueue.main.async { onChange(events) }
            }
    }

    // MARK: - Writes

    /// Signs the student up for an event via the dashboard API.
    ///
    /// Not a direct Firestore write: the server has to count existing sign-ups
    /// to honour the event's spot limit, and it builds the event snapshot from
    /// the event document so the recorded hours can't be chosen by the client.
    /// firestore.rules denies client-side creates on /signups to match.
    func signUp(
        for event: Event,
        user: FirebaseAuth.User,
        displayName: String
    ) async throws {
        let token = try await user.getIDToken()

        var request = URLRequest(
            url: AppConfig.apiBaseURL.appendingPathComponent("api/signup")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "eventId": event.id,
            "studentName": displayName
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SignupError.server }

        if (200...299).contains(http.statusCode) { return }

        let json = try? JSONSerialization.jsonObject(with: data)
        let code = (json as? [String: Any])?["error"] as? String

        switch code {
        case "already_signed_up": throw SignupError.alreadySignedUp
        case "event_full":        throw SignupError.eventFull
        case "not_whitelisted":   throw SignupError.notWhitelisted
        case "event_not_found":   throw SignupError.eventNotFound
        default:                  throw SignupError.server
        }
    }

    /// Marks the signup as checked-in and writes a checkin record.
    func checkIn(
        signupId: String,
        user: FirebaseAuth.User,
        event: Event,
        displayName: String
    ) async throws {
        let batch = db.batch()

        // Update the signup doc
        let signupRef = db.collection("signups").document(signupId)
        batch.updateData([
            "isCheckedIn": true,
            "checkedInAt": FieldValue.serverTimestamp()
        ], forDocument: signupRef)

        // Create a standalone checkin record (used by admin for hours).
        //
        // Keyed by the signup ID so one sign-up can yield at most one check-in.
        // With a random ID a student could replay this write and mint hours on
        // every repeat; the security rules enforce the same pairing.
        let checkinRef = db.collection("checkins").document(signupId)
        batch.setData([
            "signupId": signupId,
            "eventId": event.id,
            "eventTitle": event.title,
            "eventDate": event.date,
            "eventLocation": event.location,
            "studentUid": user.uid,
            "studentEmail": user.email ?? "",
            "studentName": displayName,
            "checkedInAt": FieldValue.serverTimestamp(),
            "hoursEarned": event.hours
        ], forDocument: checkinRef)

        try await batch.commit()
    }

    /// Deletes a signup document so the student is no longer signed up.
    func cancelSignup(signupId: String) async throws {
        try await db.collection("signups").document(signupId).delete()
    }

    /// Saves the FCM device token for push notification delivery.
    func saveFCMToken(_ token: String, email: String) {
        let doc = db.collection("students").document(AuthService.sanitize(email))
        doc.updateData(["fcmToken": token]) { _ in }
    }
}
