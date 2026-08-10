import Foundation
import CoreLocation

struct Event: Identifiable, Hashable {
    let id: String          // Firestore document ID from /events
    let signupId: String?   // Firestore document ID from /signups (non-nil on My Events tab)
    var title: String
    var task: String
    var date: String
    var time: String
    var location: String
    var latitude: Double
    var longitude: Double
    var isActive: Bool
    var isCheckedIn: Bool
    var hours: Double
    var positions: Int      // max sign-ups; 0 = unlimited

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasCoordinate: Bool {
        latitude != 0 || longitude != 0
    }

    var isPast: Bool {
        guard date.count == 10, time.count >= 4 else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let eventDate = formatter.date(from: "\(date) \(time)") else { return false }
        return eventDate < Date()
    }

    // Human-readable hours label
    var hoursLabel: String {
        let h = hours
        if h == floor(h) {
            return h == 1 ? "1 hr" : "\(Int(h)) hrs"
        }
        return "\(h) hrs"
    }

    /// Direct init. The two initializers below decode Firestore documents; this
    /// one exists for the test account's sample events, which never come from
    /// Firestore, and for re-keying one of those as a sign-up.
    init(
        id: String,
        signupId: String? = nil,
        title: String,
        task: String,
        date: String,
        time: String,
        location: String,
        latitude: Double = 0,
        longitude: Double = 0,
        isActive: Bool = false,
        isCheckedIn: Bool = false,
        hours: Double,
        positions: Int = 0
    ) {
        self.id = id
        self.signupId = signupId
        self.title = title
        self.task = task
        self.date = date
        self.time = time
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.isActive = isActive
        self.isCheckedIn = isCheckedIn
        self.hours = hours
        self.positions = positions
    }

    // Init from /events collection
    init?(from data: [String: Any], id: String) {
        guard
            let title = data["title"] as? String,
            let task = data["task"] as? String,
            let date = data["date"] as? String,
            let time = data["time"] as? String,
            let location = data["location"] as? String
        else { return nil }

        self.id = id
        self.signupId = nil
        self.title = title
        self.task = task
        self.date = date
        self.time = time
        self.location = location
        self.latitude = data["latitude"] as? Double ?? 0
        self.longitude = data["longitude"] as? Double ?? 0
        self.isActive = data["isActive"] as? Bool ?? false
        self.isCheckedIn = false
        self.hours = (data["hours"] as? Double) ?? Double(data["hours"] as? Int ?? 1)
        self.positions = data["positions"] as? Int ?? 0
    }

    // Init from /signups collection (event data is denormalized into each signup doc)
    init?(fromSignup data: [String: Any], signupId: String) {
        guard
            let eventId = data["eventId"] as? String,
            let title = data["eventTitle"] as? String,
            let task = data["eventTask"] as? String,
            let date = data["eventDate"] as? String,
            let time = data["eventTime"] as? String,
            let location = data["eventLocation"] as? String
        else { return nil }

        self.id = eventId
        self.signupId = signupId
        self.title = title
        self.task = task
        self.date = date
        self.time = time
        self.location = location
        self.latitude = data["eventLatitude"] as? Double ?? 0
        self.longitude = data["eventLongitude"] as? Double ?? 0
        self.isActive = data["isActive"] as? Bool ?? false
        self.isCheckedIn = data["isCheckedIn"] as? Bool ?? false
        self.hours = (data["eventHours"] as? Double) ?? Double(data["eventHours"] as? Int ?? 1)
        self.positions = data["eventPositions"] as? Int ?? 0
    }

    static func == (lhs: Event, rhs: Event) -> Bool {
        (lhs.signupId ?? lhs.id) == (rhs.signupId ?? rhs.id)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(signupId ?? id)
    }
}
