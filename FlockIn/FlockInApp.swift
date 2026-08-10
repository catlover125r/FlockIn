import SwiftUI
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn
import UserNotifications

@main
struct FlockInApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService()
    @StateObject private var store = EventStore()
    @StateObject private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .environmentObject(store)
                .environmentObject(locationManager)
                .onReceive(NotificationCenter.default.publisher(for: .fcmTokenReceived)) { note in
                    if let token = note.object as? String,
                       let email = authService.currentUser?.email,
                       !authService.isStaffSession {
                        FirestoreService().saveFCMToken(token, email: email)
                    }
                }
        }
    }
}

// MARK: - Root view: shows login or main app based on auth state

struct RootView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var store: EventStore

    var body: some View {
        Group {
            if authService.isLoading {
                Color(.systemBackground).ignoresSafeArea()
            } else if authService.isSignedIn && !authService.isAuthorizing {
                VStack(spacing: 0) {
                    if authService.isStaffSession {
                        TestAccountBanner(username: authService.staffUsername ?? "test")
                    }
                    ContentView()
                }
                .onAppear {
                    if let session = authService.session {
                        store.startListening(for: session)
                    }
                }
                .onDisappear {
                    store.stopListening()
                }
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.isSignedIn)
    }
}

/// Always-visible bar during a staff/demo session, so an App Review tester is
/// never left wondering whether they are looking at real student data.
struct TestAccountBanner: View {
    let username: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
            Text("TEST ACCOUNT — “\(username)”. Sample data, not a real student.")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.85, green: 0.44, blue: 0.05))
    }
}

// MARK: - AppDelegate: Firebase + Push Notifications

class AppDelegate: NSObject, UIApplicationDelegate,
                   UNUserNotificationCenterDelegate,
                   MessagingDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { _, _ in }
        application.registerForRemoteNotifications()

        Messaging.messaging().delegate = self
        return true
    }

    // Pass Google Sign-In redirect back to the SDK
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // Forward the FCM token to Firestore so the admin can push to this device
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        NotificationCenter.default.post(name: .fcmTokenReceived, object: token)
    }

    // Show notifications while app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

extension Notification.Name {
    static let fcmTokenReceived = Notification.Name("fcmTokenReceived")
}
