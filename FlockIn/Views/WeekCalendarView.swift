import SwiftUI

struct WeekCalendarView: View {
    /// ISO date string ("yyyy-MM-dd") of the selected day, or nil for "no
    /// filter". Tapping the selected day clears it, so the default view never
    /// hides events the student hasn't chosen to filter out.
    @Binding var selectedDate: String?
    let daysWithEvents: Set<String> // ISO date strings with at least one event

    /// Which week the strip is scrolled to, counted from the week containing
    /// today. Optional because `.scrollPosition` reports nil while a page is
    /// still settling; `displayedWeek` holds the last settled value, which is
    /// what the header and the selection logic read.
    @State private var scrolledWeek: Int? = 0
    @State private var displayedWeek = 0

    private let purple = Color(red: 0.545, green: 0.361, blue: 0.965)

    private static let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    /// EventStore drops every event whose start time has already passed, so a
    /// week earlier than the current one can never hold anything to sign up
    /// for. The strip starts at this week rather than letting students swipe
    /// back into a stretch of guaranteed-empty days.
    private static let weekRange = 0...52

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // Header formatters stay localized — unlike isoFormatter, these are read by
    // a person rather than compared against Firestore's date strings.
    private static func headerFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        return f
    }
    private static let monthYearFormatter = headerFormatter("MMMM yyyy")
    private static let shortMonthFormatter = headerFormatter("MMM")
    private static let shortMonthYearFormatter = headerFormatter("MMM yyyy")
    private static let yearFormatter = headerFormatter("yyyy")

    /// ISO date string for today, used by the "Today" shortcut.
    static var todayDateString: String {
        isoFormatter.string(from: Date())
    }

    /// Monday of the week `offset` weeks after the one containing today.
    private static func monday(weeksFromNow offset: Int) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1 = Sun
        let daysFromMonday = (weekday + 5) % 7
        guard
            let thisMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: today),
            let target = cal.date(byAdding: .weekOfYear, value: offset, to: thisMonday)
        else { return today }
        return target
    }

    /// One cell of the strip. A named type rather than the labelled tuple this
    /// used to be, because ForEach needs a key path into the element and Swift
    /// has none to offer for a tuple member.
    private struct CalendarDay: Identifiable {
        let label: String
        let dayOfMonth: Int
        let dateString: String
        var id: String { dateString }
    }

    // Mon–Sun dates for one week of the strip.
    private static func days(weeksFromNow offset: Int) -> [CalendarDay] {
        let cal = Calendar.current
        let start = monday(weeksFromNow: offset)
        return (0..<7).compactMap { i in
            guard let date = cal.date(byAdding: .day, value: i, to: start) else { return nil }
            return CalendarDay(
                label: dayLabels[i],
                dayOfMonth: cal.component(.day, from: date),
                dateString: isoFormatter.string(from: date)
            )
        }
    }

    /// "August 2026" normally; a week straddling a boundary reads
    /// "Aug – Sep 2026", or "Dec 2026 – Jan 2027" across a new year.
    private static func headerText(weeksFromNow offset: Int) -> String {
        let cal = Calendar.current
        let start = monday(weeksFromNow: offset)
        guard let end = cal.date(byAdding: .day, value: 6, to: start) else {
            return monthYearFormatter.string(from: start)
        }
        if cal.isDate(start, equalTo: end, toGranularity: .month) {
            return monthYearFormatter.string(from: start)
        }
        if cal.isDate(start, equalTo: end, toGranularity: .year) {
            let months = "\(shortMonthFormatter.string(from: start)) – \(shortMonthFormatter.string(from: end))"
            return "\(months) \(yearFormatter.string(from: end))"
        }
        return "\(shortMonthYearFormatter.string(from: start)) – \(shortMonthYearFormatter.string(from: end))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Self.headerText(weeksFromNow: displayedWeek))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))

                Spacer()

                if selectedDate != nil {
                    Button("Show all") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedDate = nil
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(purple)
                } else {
                    // Doubles as the way back from a week the student has
                    // swiped off to — without it the only route home is
                    // swiping the same number of pages in reverse.
                    Button("Today") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            scrolledWeek = 0
                            selectedDate = Self.todayDateString
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(purple)
                }
            }

            // One page per week. Paging (rather than a free-scrolling strip)
            // keeps a whole Mon–Sun on screen at every resting position, so a
            // day is never half-cut at the edge.
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Self.weekRange, id: \.self) { offset in
                        weekRow(weeksFromNow: offset)
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledWeek)
            .scrollIndicators(.hidden)
            .onChange(of: scrolledWeek) { _, week in
                guard let week else { return }
                displayedWeek = week
                // A day picked on one week would otherwise keep filtering the
                // list after the student swipes away, leaving them staring at
                // "No events on this day" with nothing highlighted on screen to
                // explain why. Drop the filter unless the swipe landed back on
                // the week that day belongs to.
                if let selected = selectedDate,
                   !Self.days(weeksFromNow: week).contains(where: { $0.dateString == selected }) {
                    selectedDate = nil
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private func weekRow(weeksFromNow offset: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Self.days(weeksFromNow: offset)) { day in
                let isSelected = selectedDate == day.dateString
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        // Tapping the selected day clears the filter.
                        selectedDate = isSelected ? nil : day.dateString
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(day.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                isSelected
                                    ? Color.white.opacity(0.8)
                                    : Color(.secondaryLabel)
                            )

                        Text("\(day.dayOfMonth)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : Color(.label))

                        Circle()
                            .fill(isSelected ? Color.white : purple)
                            .frame(width: 5, height: 5)
                            .opacity(daysWithEvents.contains(day.dateString) ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? purple : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.dateString)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}
