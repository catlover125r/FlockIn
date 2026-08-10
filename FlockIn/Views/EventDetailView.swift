import SwiftUI
import CoreLocation

struct EventDetailView: View {
    let event: Event

    @EnvironmentObject var store: EventStore
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var locationManager: LocationManager

    @Environment(\.dismiss) private var dismiss

    @State private var isCheckedIn = false
    @State private var isCheckingIn = false
    @State private var checkinError: String? = nil
    @State private var showCancelAlert = false
    @State private var isCancelling = false

    private let purple = Color(red: 0.545, green: 0.361, blue: 0.965)
    private let purpleDark = Color(red: 0.486, green: 0.231, blue: 0.929)

    private var currentEvent: Event {
        store.myEvents.first { $0.signupId == event.signupId } ?? event
    }

    private var canCheckIn: Bool {
        currentEvent.isActive &&
        (!event.hasCoordinate || locationManager.isWithin200m(of: event.coordinate))
    }

    var body: some View {
        VStack(spacing: 0) {
            eventInfoCard
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)

            if event.hasCoordinate {
                ZStack(alignment: .bottom) {
                    EventMapView(
                        eventCoordinate: event.coordinate,
                        userLocation: locationManager.currentLocation
                    )
                    .ignoresSafeArea(edges: .bottom)

                    VStack(spacing: 8) {
                        if !currentEvent.isActive {
                            Text("Check-in available when event starts & you're within 200m")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(.secondaryLabel))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        if let error = checkinError {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        if isCheckedIn || currentEvent.isCheckedIn {
                            checkedInBanner
                        } else {
                            checkInButton
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 34)
                }
            } else {
                VStack(spacing: 8) {
                    if !currentEvent.isActive {
                        Text("Check-in available when event starts")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(.secondaryLabel))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let error = checkinError {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if isCheckedIn || currentEvent.isCheckedIn {
                        checkedInBanner
                    } else {
                        checkInButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationManager.requestPermission()
            locationManager.startUpdating()
            isCheckedIn = currentEvent.isCheckedIn
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
        .alert("Cancel Sign Up?", isPresented: $showCancelAlert) {
            Button("Cancel Sign Up", role: .destructive) { performCancelSignup() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("You will be removed from \(event.title). You can sign up again if spots are available.")
        }
    }

    private var eventInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [purple, purpleDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 48, height: 48)
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 20, weight: .bold))
                        .tracking(-0.4)
                    Text(event.task)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !(isCheckedIn || currentEvent.isCheckedIn) {
                    Button { showCancelAlert = true } label: {
                        if isCancelling {
                            ProgressView().tint(.red).scaleEffect(0.85)
                        } else {
                            Text("Unregister")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            HStack(spacing: 16) {
                Label(event.date, systemImage: "calendar")
                Label(event.time, systemImage: "clock")
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(purple)
                    Text(event.location)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Color(.secondaryLabel))
            HStack(spacing: 8) {
                Label(event.hoursLabel, systemImage: "star.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(purple)
                if event.positions > 0 {
                    Text("·").foregroundStyle(.secondary)
                    Text("\(event.positions) spots")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(purple.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private var checkInButton: some View {
        Button {
            performCheckIn()
        } label: {
            HStack {
                Spacer()
                if isCheckingIn {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                } else {
                    Text(canCheckIn ? "Check In" : "Event Not Started")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(canCheckIn ? .white : Color(.secondaryLabel))
                }
                Spacer()
            }
            .padding(.vertical, 18)
            .background(
                canCheckIn
                    ? AnyShapeStyle(LinearGradient(
                        colors: [purple, purpleDark],
                        startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color(.systemGray5))
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: canCheckIn ? purple.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
        }
        .disabled(!canCheckIn || isCheckingIn)
    }

    private var checkedInBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white)
            Text("You're Checked In!")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color.green)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.green.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    private func performCancelSignup() {
        isCancelling = true
        Task {
            do {
                try await store.cancelSignup(for: event)
                dismiss()
            } catch {
                checkinError = error.localizedDescription
                isCancelling = false
            }
        }
    }

    private func performCheckIn() {
        guard let session = authService.session else { return }
        let name = authService.displayName
        isCheckingIn = true
        checkinError = nil
        Task {
            do {
                try await store.checkIn(for: event, session: session, displayName: name)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isCheckedIn = true
                }
            } catch {
                checkinError = error.localizedDescription
            }
            isCheckingIn = false
        }
    }
}
