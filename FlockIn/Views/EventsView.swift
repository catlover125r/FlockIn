import SwiftUI

struct EventsView: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var authService: AuthService
    /// nil means "no day filter" — the default, so the list opens showing
    /// everything upcoming rather than a single day's worth.
    @State private var selectedDate: String? = nil
    @State private var searchQuery: String = ""
    @State private var showSearch: Bool = false
    @State private var signupEvent: Event? = nil
    @State private var showSignupAlert: Bool = false
    @State private var signupError: String? = nil

    private let purple = Color(red: 0.545, green: 0.361, blue: 0.965)

    private var filteredEvents: [Event] {
        store.availableEvents.filter { event in
            let matchesDay = selectedDate == nil || event.date == selectedDate
            let matchesSearch = searchQuery.isEmpty
                || event.title.localizedCaseInsensitiveContains(searchQuery)
                || event.task.localizedCaseInsensitiveContains(searchQuery)
            return matchesDay && matchesSearch
        }
    }

    private var emptyStateMessage: String {
        if !searchQuery.isEmpty { return "No events found" }
        if selectedDate != nil { return "No events on this day" }
        return "No events available"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if showSearch {
                        EventSearchBar(text: $searchQuery)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    WeekCalendarView(
                        selectedDate: $selectedDate,
                        daysWithEvents: Set(store.availableEvents.map { $0.date })
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 16)

                    if let error = store.loadError {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.orange)
                            Text("Couldn't load events")
                                .font(.system(size: 16, weight: .semibold))
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 60)
                    } else if store.isLoading {
                        ProgressView()
                            .padding(.top, 60)
                    } else if filteredEvents.isEmpty {
                        Text(emptyStateMessage)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredEvents) { event in
                                AvailableEventCard(event: event) {
                                    signupEvent = event
                                    showSignupAlert = true
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
            .refreshable {
                if let session = authService.session {
                    store.refreshListeners(for: session)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProfileMenuButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSearch.toggle()
                            if !showSearch { searchQuery = "" }
                        }
                    } label: {
                        Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                            .foregroundStyle(purple)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .alert("Sign Up for Event?", isPresented: $showSignupAlert, presenting: signupEvent) { event in
            Button("Sign Up") { performSignup(event: event) }
            Button("Cancel", role: .cancel) {}
        } message: { event in
            Text("\(event.title) — \(event.task)\n\(event.date) at \(event.time)")
        }
        .alert("Sign Up Failed", isPresented: .constant(signupError != nil)) {
            Button("OK") { signupError = nil }
        } message: {
            Text(signupError ?? "")
        }
    }

    private func performSignup(event: Event) {
        guard let session = authService.session else { return }
        let name = authService.displayName
        Task {
            do {
                try await store.signUp(for: event, session: session, displayName: name)
            } catch {
                signupError = error.localizedDescription
            }
        }
    }
}

/// Account button in the navigation bar's leading slot, mirroring the search
/// button opposite it. The profile photo is the app's only route to signing
/// out, so the menu names the signed-in account too — school devices get
/// shared, and a student needs to see whose session they are about to end.
struct ProfileMenuButton: View {
    @EnvironmentObject var authService: AuthService

    private let purple = Color(red: 0.545, green: 0.361, blue: 0.965)

    private var displayName: String { authService.displayName }

    /// Up to two initials for the photoless fallback.
    private var initials: String {
        let letters = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    var body: some View {
        Menu {
            Section {
                Button(role: .destructive) {
                    authService.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } header: {
                Text(authService.currentUser?.email ?? displayName)
            }
        } label: {
            avatar
        }
        .accessibilityLabel("Account: \(displayName)")
    }

    private var avatar: some View {
        Group {
            if let url = authService.currentUser?.photoURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        // .original or the toolbar's tint flattens the photo
                        // into a purple silhouette.
                        image.renderingMode(.original).resizable().scaledToFill()
                    } else {
                        // Covers loading and failure alike — a slow school
                        // network shouldn't leave a hole in the nav bar.
                        initialsCircle
                    }
                }
            } else {
                // Staff and demo accounts sign in with a password and have no
                // Google profile photo to show.
                initialsCircle
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color(.separator), lineWidth: 0.5))
    }

    private var initialsCircle: some View {
        ZStack {
            purple
            Text(initials)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct EventSearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15))
            TextField("Search events...", text: $text)
                .focused($isFocused)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { isFocused = true }
    }
}

struct AvailableEventCard: View {
    let event: Event
    let onSignUp: () -> Void
    private let purple = Color(red: 0.545, green: 0.361, blue: 0.965)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(event.task)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text(event.date).font(.system(size: 13)).foregroundStyle(.secondary)
                    Text(event.time).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
                HStack(spacing: 6) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(purple)
                    Text(event.hoursLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(purple)
                    if event.positions > 0 {
                        Text("·").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("\(event.positions) spots")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 12)
            Button(action: onSignUp) {
                Text("Sign Up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(purple)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}
