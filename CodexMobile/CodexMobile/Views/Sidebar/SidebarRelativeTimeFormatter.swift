// FILE: SidebarRelativeTimeFormatter.swift
// Purpose: Provides compact relative timing labels for sidebar rows.
// Layer: View Helper
// Exports: SidebarRelativeTimeFormatter

import Foundation

enum SidebarRelativeTimeFormatter {
    static func compactLabel(for thread: CodexThread, now: Date = Date()) -> String? {
        guard let referenceDate = thread.updatedAt ?? thread.createdAt else {
            return nil
        }
        return compactRelativeTime(from: referenceDate, to: now)
    }

    static func compactRelativeTime(from date: Date, to now: Date) -> String {
        let interval = max(0, now.timeIntervalSince(date))

        let minute: TimeInterval = 60
        let hour: TimeInterval = 60 * minute
        let day: TimeInterval = 24 * hour
        let week: TimeInterval = 7 * day
        let month: TimeInterval = 30 * day
        let year: TimeInterval = 365 * day

        if interval >= year {
            return L10n.string("%dy", Int(interval / year))
        }
        if interval >= month {
            return L10n.string("%dmo", Int(interval / month))
        }
        if interval >= week {
            return L10n.string("%dw", Int(interval / week))
        }
        if interval >= day {
            return L10n.string("%dd", Int(interval / day))
        }
        if interval >= hour {
            return L10n.string("%dh", Int(interval / hour))
        }
        if interval >= minute {
            return L10n.string("%dm", Int(interval / minute))
        }
        return L10n.string("now")
    }
}
