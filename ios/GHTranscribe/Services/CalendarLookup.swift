import EventKit
import Foundation

enum CalendarLookup {
    /// Returns the title of a calendar event overlapping `date`..<`date +
    /// duration`, or the closest event within an hour if nothing overlaps
    /// directly. Returns nil if access is denied or nothing is nearby.
    static func matchingEventTitle(around date: Date, duration: TimeInterval) async -> String? {
        let store = EKEventStore()
        guard let granted = try? await store.requestFullAccessToEvents(), granted else {
            return nil
        }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return nil
        }

        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let events = store.events(matching: predicate)
        guard !events.isEmpty else { return nil }

        let recordingEnd = date.addingTimeInterval(max(duration, 60))

        func overlap(_ event: EKEvent) -> TimeInterval {
            let start = max(event.startDate, date)
            let end = min(event.endDate, recordingEnd)
            return max(0, end.timeIntervalSince(start))
        }

        if let best = events.filter({ overlap($0) > 0 }).max(by: { overlap($0) < overlap($1) }) {
            return best.title
        }

        let closest = events.min {
            abs($0.startDate.timeIntervalSince(date)) < abs($1.startDate.timeIntervalSince(date))
        }
        if let closest, abs(closest.startDate.timeIntervalSince(date)) <= 3600 {
            return closest.title
        }
        return nil
    }
}
