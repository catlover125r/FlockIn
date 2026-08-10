import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @State private var isSigningIn = false
    @State private var showStaffSignIn = false

    // Explicit colors: this screen is always the light, washed-photo treatment,
    // so it must not follow the system light/dark appearance.
    private let ink = Color(red: 0.059, green: 0.090, blue: 0.165)
    private let inkMuted = Color(red: 0.294, green: 0.333, blue: 0.388)

    var body: some View {
        ZStack {
            campusBackground

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                Image("SchoolLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 118, height: 118)
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)

                Text("Flock In")
                    .font(.system(size: 46, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 10)

                // Error banner
                if let error = authService.authError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(ink)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Google Sign-In button
                Button(action: signInWithGoogle) {
                    HStack(spacing: 12) {
                        if isSigningIn {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(inkMuted)
                                .frame(width: 24, height: 24)
                        } else {
                            GoogleGLogo()
                                .frame(width: 24, height: 24)
                        }
                        Text(isSigningIn ? "Signing in…" : "Continue with Google")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 19)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 4)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isSigningIn)
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .animation(.easeInOut(duration: 0.2), value: isSigningIn)

                Button {
                    authService.authError = nil
                    showStaffSignIn = true
                } label: {
                    Text("Staff sign-in")
                        .font(.system(size: 16))
                        .underline()
                        .foregroundStyle(inkMuted)
                }
                .padding(.top, 16)

                Spacer(minLength: 24)
            }
            .animation(.easeInOut(duration: 0.2), value: authService.authError)
        }
        .safeAreaInset(edge: .bottom) {
            Text("Use your @\(AuthService.schoolDomain) school account.")
                .font(.system(size: 13))
                .foregroundStyle(inkMuted)
                .padding(.bottom, 10)
        }
        .sheet(isPresented: $showStaffSignIn) {
            StaffSignInView()
                .environmentObject(authService)
        }
    }

    /// Full-bleed campus photo behind a white wash that keeps the text legible.
    private var campusBackground: some View {
        GeometryReader { geo in
            Image("CampusBackground")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(
                    // Heavier wash across the middle band, where the logo, title
                    // and button sit on top of the busy field markings.
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.48), location: 0),
                            .init(color: .white.opacity(0.68), location: 0.42),
                            .init(color: .white.opacity(0.68), location: 0.78),
                            .init(color: .white.opacity(0.60), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .ignoresSafeArea()
    }

    private func signInWithGoogle() {
        isSigningIn = true
        Task {
            await authService.signInWithGoogle()
            isSigningIn = false
        }
    }
}

/// Slight shrink on press — the button sits on a photo, so it needs its own
/// touch feedback rather than relying on a background color change.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Username + password sign-in for ASB staff and for Apple's App Review team,
/// neither of whom can complete a Google Workspace sign-in for this school.
struct StaffSignInView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    // Prefilled with the test account. A reviewer opening this sheet can just
    // tap Sign In, and there is no way for a typo, an autocapitalized first
    // letter, or a missed instruction to lock them out of the demo.
    @State private var username = AuthService.demoUsername
    @State private var password = AuthService.demoPassword
    @State private var isSigningIn = false
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit(signIn)
                } footer: {
                    Text("Test account — username **\(AuthService.demoUsername)**, password **\(AuthService.demoPassword)**. It shows sample events, not real student data. Students sign in with their school Google account instead.")
                }

                if let error = authService.authError {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.system(size: 14))
                        }
                    }
                }

                Section {
                    Button(action: signIn) {
                        HStack {
                            Spacer()
                            if isSigningIn {
                                ProgressView()
                            } else {
                                Text("Sign In").font(.system(size: 17, weight: .semibold))
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSigningIn || username.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("Staff Sign-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        authService.authError = nil
                        dismiss()
                    }
                }
            }
            .onAppear { focusedField = .username }
        }
    }

    private func signIn() {
        guard !isSigningIn, !username.isEmpty, !password.isEmpty else { return }
        isSigningIn = true
        Task {
            await authService.signInWithUsername(username, password: password)
            isSigningIn = false
            if authService.isSignedIn { dismiss() }
        }
    }
}

// MARK: - Google "G" mark

/// The official four-color Google mark, traced from Google's 24×24 SVG so the
/// button meets the "Sign in with Google" branding guidelines.
struct GoogleGLogo: View {
    var body: some View {
        ZStack {
            GoogleGSegment(.blue).fill(Color(red: 0.259, green: 0.522, blue: 0.957))
            GoogleGSegment(.green).fill(Color(red: 0.204, green: 0.659, blue: 0.325))
            GoogleGSegment(.yellow).fill(Color(red: 0.984, green: 0.737, blue: 0.020))
            GoogleGSegment(.red).fill(Color(red: 0.918, green: 0.263, blue: 0.208))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct GoogleGSegment: Shape {
    enum Segment { case blue, green, yellow, red }

    let segment: Segment

    init(_ segment: Segment) { self.segment = segment }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch segment {
        case .blue:
            path.move(to: CGPoint(x: 22.56, y: 12.25))
            path.addCurve(to: CGPoint(x: 22.36, y: 10), control1: CGPoint(x: 22.56, y: 11.47), control2: CGPoint(x: 22.49, y: 10.72))
            path.addLine(to: CGPoint(x: 12, y: 10))
            path.addLine(to: CGPoint(x: 12, y: 14.26))
            path.addLine(to: CGPoint(x: 17.92, y: 14.26))
            path.addCurve(to: CGPoint(x: 15.71, y: 17.57), control1: CGPoint(x: 17.66, y: 15.63), control2: CGPoint(x: 16.88, y: 16.79))
            path.addLine(to: CGPoint(x: 15.71, y: 20.34))
            path.addLine(to: CGPoint(x: 19.28, y: 20.34))
            path.addCurve(to: CGPoint(x: 22.56, y: 12.25), control1: CGPoint(x: 21.36, y: 18.42), control2: CGPoint(x: 22.56, y: 15.6))
            path.closeSubpath()

        case .green:
            path.move(to: CGPoint(x: 12, y: 23))
            path.addCurve(to: CGPoint(x: 19.28, y: 20.34), control1: CGPoint(x: 14.97, y: 23), control2: CGPoint(x: 17.46, y: 22.02))
            path.addLine(to: CGPoint(x: 15.71, y: 17.57))
            path.addCurve(to: CGPoint(x: 12, y: 18.63), control1: CGPoint(x: 14.73, y: 18.23), control2: CGPoint(x: 13.48, y: 18.63))
            path.addCurve(to: CGPoint(x: 5.84, y: 14.1), control1: CGPoint(x: 9.14, y: 18.63), control2: CGPoint(x: 6.71, y: 16.7))
            path.addLine(to: CGPoint(x: 2.18, y: 14.1))
            path.addLine(to: CGPoint(x: 2.18, y: 16.94))
            path.addCurve(to: CGPoint(x: 12, y: 23), control1: CGPoint(x: 3.99, y: 20.53), control2: CGPoint(x: 7.7, y: 23))
            path.closeSubpath()

        case .yellow:
            path.move(to: CGPoint(x: 5.84, y: 14.09))
            path.addCurve(to: CGPoint(x: 5.49, y: 12), control1: CGPoint(x: 5.62, y: 13.43), control2: CGPoint(x: 5.49, y: 12.73))
            path.addCurve(to: CGPoint(x: 5.84, y: 9.91), control1: CGPoint(x: 5.49, y: 11.27), control2: CGPoint(x: 5.62, y: 10.57))
            path.addLine(to: CGPoint(x: 5.84, y: 7.07))
            path.addLine(to: CGPoint(x: 2.18, y: 7.07))
            path.addCurve(to: CGPoint(x: 1, y: 12), control1: CGPoint(x: 1.43, y: 8.55), control2: CGPoint(x: 1, y: 10.22))
            path.addCurve(to: CGPoint(x: 2.18, y: 16.93), control1: CGPoint(x: 1, y: 13.78), control2: CGPoint(x: 1.43, y: 15.45))
            path.addLine(to: CGPoint(x: 5.03, y: 14.71))
            path.addLine(to: CGPoint(x: 5.84, y: 14.09))
            path.closeSubpath()

        case .red:
            path.move(to: CGPoint(x: 12, y: 5.38))
            path.addCurve(to: CGPoint(x: 16.21, y: 7.02), control1: CGPoint(x: 13.62, y: 5.38), control2: CGPoint(x: 15.06, y: 5.94))
            path.addLine(to: CGPoint(x: 19.36, y: 3.87))
            path.addCurve(to: CGPoint(x: 12, y: 1), control1: CGPoint(x: 17.45, y: 2.09), control2: CGPoint(x: 14.97, y: 1))
            path.addCurve(to: CGPoint(x: 2.18, y: 7.07), control1: CGPoint(x: 7.7, y: 1), control2: CGPoint(x: 3.99, y: 3.47))
            path.addLine(to: CGPoint(x: 5.84, y: 9.91))
            path.addCurve(to: CGPoint(x: 12, y: 5.38), control1: CGPoint(x: 6.71, y: 7.31), control2: CGPoint(x: 9.14, y: 5.38))
            path.closeSubpath()
        }

        // Fit the 24×24 source viewBox into `rect`.
        let scale = min(rect.width, rect.height) / 24
        return path
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(
                dx: rect.minX + (rect.width - 24 * scale) / 2,
                dy: rect.minY + (rect.height - 24 * scale) / 2
            )
    }
}
