import SwiftUI

struct MyEventsView: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var authService: AuthService
    @State private var selectedEvent: Event? = nil

    var body: some View {
        NavigationStack {
            Group {
                if store.myEvents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 60))
                            .foregroundStyle(Color(.systemGray3))
                        Text("No Events Yet")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Sign up for events to see them here")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.myEvents) { event in
                                MyEventCard(event: event) { selectedEvent = event }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .refreshable {
                        if let session = authService.session {
                            // refreshListeners, not startListening: the latter
                            // raises isLoading and swaps the list for a spinner
                            // while the refresh control is already spinning.
                            store.refreshListeners(for: session)
                            try? await Task.sleep(nanoseconds: 600_000_000)
                        }
                    }
                }
            }
            .navigationTitle("My Events")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $selectedEvent) { event in
                EventDetailView(event: event)
            }
        }
    }
}

struct MyEventCard: View {
    let event: Event
    let onTap: () -> Void
    private let purple = Color(red: 0.545, green: 0.361, blue: 0.965)

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(event.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)

                        if event.isCheckedIn {
                            Badge(text: "CHECKED IN", color: purple)
                        } else if event.isActive {
                            Badge(text: "ACTIVE", color: .green)
                        }
                    }
                    Text(event.task).font(.system(size: 15)).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Text(event.date).font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(event.time).font(.system(size: 13)).foregroundStyle(.secondary)
                        Label(event.hoursLabel, systemImage: "star.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(purple)
                    }
                    .padding(.top, 6)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.systemGray3))
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
