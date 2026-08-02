import Foundation

/// yyyy-MM-dd range for filtering overdue jobs (matches React Native `JobListScreen` + dashboard navigation).
struct JobDateRange: Equatable {
    var from: String
    var to: String
}

enum JobFilterMode: Equatable {
    case none
    case today
    case overdue
}

enum JobSchedulingHelpers {
    /// First 10 chars of ISO start date (yyyy-MM-dd).
    static func calendarDayString(from iso: String) -> String {
        String(iso.prefix(10))
    }

    static func todayYMD(calendar: Calendar = .current) -> String {
        ymd(calendar.startOfDay(for: Date()), calendar: calendar)
    }

    static func yesterdayYMD(calendar: Calendar = .current) -> String {
        let y = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return ymd(calendar.startOfDay(for: y), calendar: calendar)
    }

    static func ymdFromDate(_ date: Date, calendar: Calendar = .current) -> String {
        ymd(calendar.startOfDay(for: date), calendar: calendar)
    }

    private static func ymd(_ date: Date, calendar: Calendar) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Mirrors `JobListScreen` `filteredJobs` logic.
    static func filteredJobs(
        _ jobs: [ScheduledJob],
        filterMode: JobFilterMode,
        selectedDate: String?,
        dateRange: JobDateRange?,
        today: String
    ) -> [ScheduledJob] {
        if filterMode == .overdue {
            var list = jobs.filter { job in
                guard job.status == .pending else { return false }
                let d = calendarDayString(from: job.startDate)
                return d < today
            }
            if let dr = dateRange {
                list = list.filter { job in
                    let d = calendarDayString(from: job.startDate)
                    return d >= dr.from && d <= dr.to
                }
            }
            return list
        }
        if filterMode == .today || selectedDate != nil {
            let d = filterMode == .today ? today : selectedDate!
            return jobs.filter { $0.startDate.hasPrefix(d) }
        }
        if let dr = dateRange {
            return jobs.filter { job in
                let d = calendarDayString(from: job.startDate)
                return d >= dr.from && d <= dr.to
            }
        }
        return jobs
    }

    static func sortedByStartAscending(_ jobs: [ScheduledJob]) -> [ScheduledJob] {
        jobs.sorted { a, b in
            (parseJobStart(a.startDate) ?? .distantPast) < (parseJobStart(b.startDate) ?? .distantPast)
        }
    }

    private static func parseJobStart(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f.date(from: String(iso.prefix(10)))
    }

    /// Days (yyyy-MM-dd) that have at least one job, for calendar dots.
    static func markedDayStrings(from jobs: [ScheduledJob]) -> Set<String> {
        Set(jobs.map { calendarDayString(from: $0.startDate) })
    }

    /// Range passed to job list when opening “overdue jobs” from dashboard (matches RN).
    static func overdueDashboardRange(jobs: [ScheduledJob]) -> JobDateRange? {
        let t = todayYMD()
        let overdue = jobs.filter { job in
            guard job.status == .pending else { return false }
            return calendarDayString(from: job.startDate) < t
        }
        guard !overdue.isEmpty else { return nil }
        let dates = overdue.map { calendarDayString(from: $0.startDate) }
        guard let from = dates.min() else { return nil }
        let to = yesterdayYMD()
        return JobDateRange(from: from, to: to)
    }

    static func overduePendingCount(jobs: [ScheduledJob]) -> Int {
        let t = todayYMD()
        return jobs.filter { job in
            guard job.status == .pending else { return false }
            return calendarDayString(from: job.startDate) < t
        }.count
    }
}
