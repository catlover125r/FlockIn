import SwiftUI

struct ContentView: View {
    private let purple = Color(red: 0.545, green: 0.361, blue: 0.965)

    var body: some View {
        TabView {
            EventsView()
                .tabItem { Label("Sign Up", systemImage: "calendar") }
            MyEventsView()
                .tabItem { Label("My Events", systemImage: "checkmark.square.fill") }
        }
        .tint(purple)
    }
}
