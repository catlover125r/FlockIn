import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

@MainActor
class AuthService: ObservableObject {

    // ── Change this to your school's Google Workspace domain ──────────────
    static let schoolDomain = "seq.org"
    // ──────────────────────────────────────────────────────────────────────

    // ── Test account ──────────────────────────────────────────────────────
    // The credentials behind "Staff sign-in", checked here in the app rather
    // than by Firebase.
    //
    // This account is deliberately self-contained: it signs in with no network,
    // no Firebase Auth user record, and no Firestore access, and everything it
    // shows is the sample data in EventStore. That is the whole point of it —
    // the earlier version handed these credentials to Firebase, so the login
    // only worked on a project where someone had also created a matching user
    // in the console and enabled the email/password provider. When that record
    // was missing there was nothing in the code that could fix it, and the
    // tester just saw "Incorrect username or password".
    //
    // For App Review and testers only. It is not a route into real student
    // data: a demo session never authenticates, so the security rules would
    // reject it even if it tried.
    static let demoUsername = "admin"
    static let demoPassword = "password"
    // ──────────────────────────────────────────────────────────────────────

    /// Remembers a demo session across relaunches, the way Firebase persists a
    /// real one. Without it the tester is bounced back to the login screen
    /// every time the app restarts.
    private static let demoSessionKey = "flockin.demoSessionActive"

    // Staff sign-in. Firebase Auth only accepts email addresses, so usernames
    // are mapped onto a non-routable domain that nobody sees or types.
    // "reviewer" becomes "reviewer@flockin.local" on the way to Firebase.
    static let staffDomain = "flockin.local"

    /// Usernames permitted to skip the school-domain and whitelist checks.
    /// These are real Firebase accounts an advisor has to create by hand;
    /// `demoUsername` is not among them because it never reaches Firebase.
    static let staffUsernames: Set<String> = [
        "reviewer",
        "student1",
        "student2"
    ]

    @Published var currentUser: FirebaseAuth.User?
    @Published var isSignedIn = false
    @Published var isLoading = true
    @Published var authError: String?

    /// True when signed in via a staff account rather than a student's Google
    /// account. Staff have no `students` record, so student-scoped writes skip.
    @Published var isStaffSession = false

    /// The username of the current staff session, shown in the test banner.
    @Published var staffUsername: String?

    /// True for the built-in test account. Stronger than `isStaffSession`:
    /// there is no Firebase user behind this session at all, so every data
    /// path has to serve it from the local sample set instead of Firestore.
    @Published var isDemoSession = false

    /// True between the Firebase sign-in and the whitelist verdict. Firebase
    /// reports the user as signed in the moment the credential lands, so the
    /// root view holds on the login screen until this clears — otherwise a
    /// non-whitelisted student sees the event list flash before being ejected.
    @Published var isAuthorizing = false

    /// Who the app is acting as. Everything that reads or writes data takes one
    /// of these rather than a `FirebaseAuth.User`, so the demo case cannot be
    /// forgotten at a call site — it has to be handled to compile.
    enum Session {
        case firebase(FirebaseAuth.User)
        case demo
    }

    var session: Session? {
        if isDemoSession { return .demo }
        if let currentUser { return .firebase(currentUser) }
        return nil
    }

    /// Name shown in the profile menu and recorded on sign-ups.
    var displayName: String {
        if isStaffSession { return staffUsername ?? "Test Account" }
        return currentUser?.displayName
            ?? currentUser?.email?.components(separatedBy: "@").first
            ?? "Student"
    }

    private let db = Firestore.firestore()
    private var authHandle: AuthStateDidChangeListenerHandle?

    init() {
        // Restored before the listener is attached, so the first callback
        // already sees the flag and leaves the session alone.
        if UserDefaults.standard.bool(forKey: Self.demoSessionKey) {
            applyDemoSession()
        }

        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // A demo session has no Firebase user, so Firebase reports nil
                // here. Letting that through would clear isSignedIn and drop
                // the tester straight back onto the login screen.
                guard !self.isDemoSession else { return }

                self.currentUser = user
                self.isSignedIn = user != nil

                // A session restored on relaunch never passes through
                // signInWithUsername, so the staff flag has to be recovered
                // from the address. Without this the TEST ACCOUNT banner
                // silently disappears after an app restart, and the app starts
                // writing an FCM token for a demo account that has no student
                // record.
                let isStaff = user?.email?
                    .lowercased()
                    .hasSuffix("@\(Self.staffDomain)") ?? false
                self.isStaffSession = isStaff
                self.staffUsername = isStaff
                    ? user?.email?.components(separatedBy: "@").first
                    : nil

                self.isLoading = false
            }
        }
    }

    deinit {
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signInWithGoogle() async {
        authError = nil
        do {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                authError = "App configuration error. Contact your ASB advisor."
                return
            }

            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config

            guard
                let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                let rootVC = scene.keyWindow?.rootViewController
            else {
                authError = "Cannot present sign-in screen."
                return
            }

            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            let googleUser = result.user

            // 1. Verify school email domain
            guard
                let email = googleUser.profile?.email,
                email.lowercased().hasSuffix("@\(Self.schoolDomain)")
            else {
                GIDSignIn.sharedInstance.signOut()
                authError = "Only @\(Self.schoolDomain) accounts are allowed."
                return
            }

            // 2. Sign in to Firebase Auth.
            //    This has to happen before any Firestore call. A Google sign-in
            //    only yields a Google ID token — Firestore still sees the request
            //    as unauthenticated until that token is exchanged for a Firebase
            //    credential, so reading the whitelist first fails the rules with
            //    "Missing or insufficient permissions" no matter who is signing in.
            guard let idToken = googleUser.idToken?.tokenString else {
                authError = "Authentication token error. Try again."
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: googleUser.accessToken.tokenString
            )
            isAuthorizing = true
            let authResult = try await Auth.auth().signIn(with: credential)

            // 3. Check student whitelist in Firestore
            let sanitized = Self.sanitize(email)
            let doc = try await db.collection("students").document(sanitized).getDocument()
            guard doc.exists, doc.get("isWhitelisted") as? Bool == true else {
                signOut()
                authError = "Your account is not registered. See your ASB advisor."
                return
            }

            // 4. Update student profile record. `email` and `isWhitelisted` are
            //    the advisor's to set — a student writing them trips the rules.
            let name = googleUser.profile?.name
                ?? email.components(separatedBy: "@").first
                ?? "Student"
            try await db.collection("students").document(sanitized).setData([
                "displayName": name,
                "uid": authResult.user.uid,
                "lastSignIn": FieldValue.serverTimestamp()
            ], merge: true)

            isAuthorizing = false

        } catch {
            // A throw after the Firebase sign-in would otherwise strand the user
            // in a half-authorized session, so tear the whole thing down.
            if isAuthorizing { signOut() }

            // User cancelled sign-in (error code 12501) — don't show an error
            let nsError = error as NSError
            if nsError.domain == "com.google.GIDSignIn" && nsError.code == -5 { return }
            authError = error.localizedDescription
        }
    }

    /// Signs in a staff account by username. These accounts deliberately skip
    /// the school-domain check, the whitelist lookup, and the student profile
    /// write — they exist for ASB staff and for Apple's App Review team, who
    /// cannot complete a Google Workspace sign-in from an unrecognized device.
    func signInWithUsername(_ username: String, password: String) async {
        authError = nil

        let name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Trimmed and compared case-insensitively: an iOS keyboard will happily
        // autocapitalize or leave a trailing space in a password field, and a
        // tester locked out of a fixed demo credential by an invisible space
        // has no way to tell what went wrong.
        let secret = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !secret.isEmpty else {
            authError = "Enter a username and password."
            return
        }

        // The test account is resolved entirely here — no Firebase round trip,
        // so it works on a fresh install, offline, and on any Firebase project.
        if name == Self.demoUsername,
           secret.caseInsensitiveCompare(Self.demoPassword) == .orderedSame {
            applyDemoSession()
            UserDefaults.standard.set(true, forKey: Self.demoSessionKey)
            return
        }

        guard Self.staffUsernames.contains(name) else {
            authError = "Incorrect username or password."
            return
        }

        do {
            _ = try await Auth.auth().signIn(
                withEmail: "\(name)@\(Self.staffDomain)",
                password: password
            )
            isStaffSession = true
            staffUsername = name
        } catch {
            // Firebase's error enum has shifted between SDK versions, so match
            // on the NSError domain rather than a version-specific case.
            let nsError = error as NSError
            authError = nsError.domain == NSURLErrorDomain
                ? "Network error. Check your connection."
                : "Incorrect username or password."
        }
    }

    /// Opens the built-in test session. No Firebase user is created or signed
    /// in — `isSignedIn` is set here directly, and the auth-state listener is
    /// told to keep its hands off it.
    private func applyDemoSession() {
        isDemoSession = true
        isStaffSession = true
        staffUsername = Self.demoUsername
        currentUser = nil
        authError = nil
        isAuthorizing = false
        isLoading = false
        isSignedIn = true
    }

    func signOut() {
        // Cleared before Firebase is touched: a demo session produces no
        // auth-state callback, so nothing else would ever close it.
        let wasDemo = isDemoSession
        isDemoSession = false
        UserDefaults.standard.removeObject(forKey: Self.demoSessionKey)
        isStaffSession = false
        staffUsername = nil
        isAuthorizing = false
        if wasDemo {
            currentUser = nil
            isSignedIn = false
        }

        do {
            GIDSignIn.sharedInstance.signOut()
            try Auth.auth().signOut()
        } catch {
            authError = error.localizedDescription
        }
    }

    // Firestore document IDs can't contain . or @ — sanitize the email.
    // nonisolated so FirestoreService can share this one implementation rather
    // than keeping a second copy in sync; the security rules rebuild the same
    // ID from the auth token, so all three have to agree.
    nonisolated static func sanitize(_ email: String) -> String {
        email.lowercased()
            .replacingOccurrences(of: "@", with: "_at_")
            .replacingOccurrences(of: ".", with: "_")
    }
}
