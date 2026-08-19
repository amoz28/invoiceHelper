import SwiftUI

struct JobListView: View {
    private enum ViewMode: String, CaseIterable {
        case calendar = "Calendar"
        case list = "List"
    }

    /// Deep-link style filter when opening from the dashboard (matches RN `JobList` params).
    enum Filter: Equatable {
        case all
        case today
        case overdue(range: JobDateRange?)
    }

    @EnvironmentObject private var store: AppStore
    var filter: Filter = .all

    @State private var viewMode: ViewMode = .calendar
    @State private var filterMode: JobFilterMode = .none
    @State private var selectedCalendarDate: Date?
    @State private var dateRange: JobDateRange?
    @State private var rangeFrom = Date()
    @State private var rangeTo = Date()
    @State private var showFromPicker = false
    @State private var showToPicker = false
    @State private var didApplyInitialFilter = false
    /// Skips applying the default “next 7 days” list filter when the list mode was opened from a dashboard deep link.
    @State private var suppressNextListDefaultRange = false
    @State private var showJobEditor = false
    @State private var jobEditorSession = UUID()
    @State private var pendingPreviewJobId: String?
    @State private var previewJobId: String?
    @State private var showJobPreview = false

    private var calendar: Calendar { .current }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                AppSegmentedTabs(
                    tabs: ViewMode.allCases.map { ($0, $0.rawValue) },
                    selection: $viewMode
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
                .zIndex(1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if viewMode == .calendar {
                            calendarSection
                        }

                        if viewMode == .list {
                            dateRangeSection
                        }

                        if viewMode == .list, filterSummaryText != nil {
                            Text(filterSummaryText!)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }

                        jobsSection
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 108)
                }
                .refreshable {
                    Haptics.light()
                    store.reloadJobs()
                }
            }

            Button {
                jobEditorSession = UUID()
                showJobEditor = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(AppTheme.infoBlue, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
            .accessibilityLabel("Add job")
            .padding(.trailing, 20)
            .padding(.bottom, 8)
            .safeAreaPadding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didApplyInitialFilter else { return }
            didApplyInitialFilter = true
            switch filter {
            case .all:
                break
            case .today:
                suppressNextListDefaultRange = true
                filterMode = .today
                selectedCalendarDate = nil
                dateRange = nil
                viewMode = .list
            case .overdue(let range):
                suppressNextListDefaultRange = true
                filterMode = .overdue
                dateRange = range
                selectedCalendarDate = nil
                viewMode = .list
            }
        }
        .onChange(of: viewMode) { old, new in
            guard new == .list, old == .calendar else { return }
            if suppressNextListDefaultRange {
                suppressNextListDefaultRange = false
                return
            }
            applyDefaultNextWeekRange()
        }
        .onChange(of: selectedCalendarDate) { _, new in
            if new != nil {
                filterMode = .none
                dateRange = nil
            }
        }
        .sheet(isPresented: $showFromPicker) {
            NavigationStack {
                VStack(spacing: 16) {
                    DatePicker("From", selection: $rangeFrom, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                .padding()
                .navigationTitle("From")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showFromPicker = false }
                    }
                }
            }
            .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showToPicker) {
            NavigationStack {
                VStack(spacing: 16) {
                    DatePicker("To", selection: $rangeTo, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                .padding()
                .navigationTitle("To")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showToPicker = false }
                    }
                }
            }
            .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showJobEditor) {
            NavigationStack {
                JobEditorView(
                    job: nil,
                    initialStartDate: fabInitialStartDate,
                    onJobCreated: { id in
                        pendingPreviewJobId = id
                    }
                )
                .environmentObject(store)
                .id(jobEditorSession)
            }
        }
        .onChange(of: showJobEditor) { _, isOpen in
            guard !isOpen, let id = pendingPreviewJobId else { return }
            pendingPreviewJobId = nil
            previewJobId = id
            showJobPreview = true
        }
        .sheet(isPresented: $showJobPreview) {
            if let id = previewJobId {
                NavigationStack {
                    JobDetailView(jobId: id)
                        .environmentObject(store)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showJobPreview = false
                                    previewJobId = nil
                                }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                JobsCalendarView(
                    selectedDate: $selectedCalendarDate,
                    markedDayStrings: JobSchedulingHelpers.markedDayStrings(from: store.jobs),
                    calendar: calendar
                )
                .frame(maxWidth: .infinity)
            }
            .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            .background(AppSurfaceCard())
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.surfaceCorner, style: .continuous))

            if let d = selectedCalendarDate {
                HStack {
                    Text("Jobs for \(mediumDate(d))")
                        .font(.headline)
                    Spacer()
                    Button("Clear") {
                        selectedCalendarDate = nil
                        filterMode = .none
                    }
                }
            }
        }
    }

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter by date range")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    showFromPicker = true
                } label: {
                    Text("From: \(mediumDate(rangeFrom))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    showToPicker = true
                } label: {
                    Text("To: \(mediumDate(rangeTo))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            HStack(spacing: 12) {
                Button("Apply") {
                    applyDateRangeFilter()
                }
                .buttonStyle(.borderedProminent)
                .disabled(JobSchedulingHelpers.ymdFromDate(rangeFrom, calendar: calendar) > JobSchedulingHelpers.ymdFromDate(rangeTo, calendar: calendar))

                Button("Clear") {
                    dateRange = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var filterSummaryText: String? {
        guard viewMode == .list else { return nil }
        if filterMode == .today {
            return "Showing: Today’s jobs"
        }
        if filterMode == .overdue {
            return "Showing: Overdue jobs"
        }
        if let dr = dateRange {
            return "Showing: \(mediumYMD(dr.from)) – \(mediumYMD(dr.to))"
        }
        return nil
    }

    @ViewBuilder
    private var jobsSection: some View {
        let jobs = filteredJobs
        if jobs.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 12) {
                ForEach(jobs) { job in
                    NavigationLink(destination: JobDetailView(jobId: job.id)) {
                        JobListRowCard(job: job)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text(emptyMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 32)
            if showScheduleFirstCTA {
                Button {
                    jobEditorSession = UUID()
                    showJobEditor = true
                } label: {
                    Label("Schedule your first job", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var showScheduleFirstCTA: Bool {
        selectedCalendarDate == nil && filterMode != .today && dateRange == nil && filterMode != .overdue
    }

    private var emptyMessage: String {
        if selectedCalendarDate != nil || filterMode == .today {
            return "No jobs scheduled for this date"
        }
        if dateRange != nil {
            return "No jobs in this date range"
        }
        if filterMode == .overdue {
            return "No overdue jobs"
        }
        return "No jobs yet"
    }

    private var filteredJobs: [ScheduledJob] {
        let today = JobSchedulingHelpers.todayYMD(calendar: calendar)
        let selectedStr = selectedCalendarDate.map { JobSchedulingHelpers.ymdFromDate($0, calendar: calendar) }
        let raw = JobSchedulingHelpers.filteredJobs(
            store.jobs,
            filterMode: filterMode,
            selectedDate: selectedStr,
            dateRange: dateRange,
            today: today
        )
        return JobSchedulingHelpers.sortedByStartAscending(raw)
    }

    private var fabInitialStartDate: Date? {
        guard let d = selectedCalendarDate else { return nil }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
    }

    private func applyDateRangeFilter() {
        let from = JobSchedulingHelpers.ymdFromDate(rangeFrom, calendar: calendar)
        let to = JobSchedulingHelpers.ymdFromDate(rangeTo, calendar: calendar)
        guard from <= to else { return }
        dateRange = JobDateRange(from: from, to: to)
        filterMode = .none
        selectedCalendarDate = nil
    }

    /// List tab default: jobs from today through the next 7 calendar days (inclusive start, inclusive end).
    private func applyDefaultNextWeekRange() {
        filterMode = .none
        selectedCalendarDate = nil
        let today = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        rangeFrom = today
        rangeTo = end
        let from = JobSchedulingHelpers.ymdFromDate(today, calendar: calendar)
        let to = JobSchedulingHelpers.ymdFromDate(end, calendar: calendar)
        dateRange = JobDateRange(from: from, to: to)
    }

    private func mediumDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private func mediumYMD(_ ymd: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        guard let d = f.date(from: ymd) else { return ymd }
        return mediumDate(d)
    }
}

private struct JobListRowCard: View {
    let job: ScheduledJob

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(job.customerName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(dateLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(job.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.jobStatusColor(job.status))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.jobStatusColor(job.status).opacity(0.15), in: Capsule())
            }
            if job.isRecurring {
                Label("Recurring: \(job.recurringFrequency.rawValue)", systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let addr = job.customerAddress, !addr.isEmpty, let url = mapsURL(address: addr) {
                Link(destination: url) {
                    Label("Open in Maps", systemImage: "map")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurfaceCard())
    }

    private var dateLine: String {
        "\(short(job.startDate)) – \(short(job.endDate))"
    }

    private func short(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        if d == nil {
            f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            d = f.date(from: String(iso.prefix(10)))
        }
        guard let d else { return iso }
        let out = DateFormatter()
        out.dateStyle = .short
        out.timeStyle = .short
        return out.string(from: d)
    }

    private func mapsURL(address: String) -> URL? {
        let q = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "http://maps.apple.com/?q=\(q)")
    }
}

struct JobDetailView: View {
    @EnvironmentObject private var store: AppStore
    let jobId: String
    @State private var showAddNote = false
    @State private var newNoteText = ""
    @State private var jobErrorMessage: String?

    init(job: ScheduledJob) {
        self.jobId = job.id
    }

    init(jobId: String) {
        self.jobId = jobId
    }

    private var job: ScheduledJob? {
        store.jobs.first { $0.id == jobId }
    }

    var body: some View {
        Group {
            if let job {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(job.title)
                                .font(.title2.weight(.bold))
                            Text(job.customerName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            AppSegmentedTabs(
                                tabs: JobStatus.allCases.map {
                                    ($0, $0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                },
                                selection: statusBinding(for: job)
                            )
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppSurfaceCard())

                        sectionCard(title: "Schedule") {
                            labeled("Start", shortDate(job.startDate))
                            labeled("End", shortDate(job.endDate))
                            if job.isRecurring {
                                labeled("Recurring", job.recurringFrequency.rawValue)
                                if let n = job.nextOccurrence {
                                    labeled("Next", shortDate(n))
                                }
                            }
                        }

                        if let d = job.description, !d.isEmpty {
                            sectionCard(title: "Description") { Text(d) }
                        }
                        if let a = job.customerAddress, !a.isEmpty {
                            sectionCard(title: "Address") { Text(a) }
                        }

                        sectionCard(title: "Notes") {
                            let notes = job.noteEntries.sorted(by: { $0.createdAt < $1.createdAt })
                            if notes.isEmpty {
                                Text("No notes yet")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(notes.enumerated()), id: \.element.id) { index, entry in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(noteTimestampLabel(entry.createdAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(entry.text)
                                    }
                                    if index < notes.count - 1 {
                                        Divider().padding(.vertical, 8)
                                    }
                                }
                            }
                            Button {
                                newNoteText = ""
                                showAddNote = true
                            } label: {
                                Label("Add note", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.infoBlue)
                                    .padding(.top, 8)
                            }
                            .buttonStyle(.plain)
                        }

                        sectionCard(title: "Reminder") {
                            Text(job.hasReminder ? "On" : "Off")
                                .font(.body.weight(.medium))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Job")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            JobEditorView(job: job)
                        } label: {
                            Text("Edit").fontWeight(.semibold)
                        }
                    }
                }
                .sheet(isPresented: $showAddNote) {
                    NavigationStack {
                        Form {
                            Section {
                                TextField("Note", text: $newNoteText, axis: .vertical)
                                    .lineLimit(4...12)
                                    .textInputAutocapitalization(.sentences)
                            }
                        }
                        .navigationTitle("New note")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showAddNote = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") { appendNote(to: jobId) }
                                    .fontWeight(.semibold)
                                    .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }
                .alert("Error", isPresented: Binding(
                    get: { jobErrorMessage != nil },
                    set: { if !$0 { jobErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { jobErrorMessage = nil }
                } message: {
                    Text(jobErrorMessage ?? "")
                }
            } else {
                ContentUnavailableView("Job not found", systemImage: "calendar")
            }
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppSurfaceCard())
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.medium))
        }
    }

    private func statusBinding(for job: ScheduledJob) -> Binding<JobStatus> {
        Binding(
            get: { store.jobs.first(where: { $0.id == job.id })?.status ?? job.status },
            set: { newStatus in
                do {
                    try store.updateJob(id: job.id) { $0.status = newStatus }
                } catch {
                    jobErrorMessage = error.localizedDescription
                }
            }
        )
    }

    private func appendNote(to id: String) {
        let trimmed = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = fmt.string(from: Date())
        do {
            try store.updateJob(id: id) { j in
                j.noteEntries.append(JobNoteEntry(id: InvoiceLogic.generateId(), text: trimmed, createdAt: now))
            }
            showAddNote = false
            newNoteText = ""
        } catch {
            jobErrorMessage = error.localizedDescription
        }
    }

    private func noteTimestampLabel(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        guard let d else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: d)
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        if d == nil {
            f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            d = f.date(from: String(iso.prefix(10)))
        }
        guard let d else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: d)
    }
}

struct JobEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var job: ScheduledJob?
    /// When creating a job, optional day/time seed (e.g. selected day on calendar).
    var initialStartDate: Date?
    var onJobCreated: ((String) -> Void)? = nil

    init(job: ScheduledJob? = nil, initialStartDate: Date? = nil, onJobCreated: ((String) -> Void)? = nil) {
        self.job = job
        self.initialStartDate = initialStartDate
        self.onJobCreated = onJobCreated
        let cal = Calendar.current
        if job != nil {
            _startDate = State(initialValue: Date())
            _endDate = State(initialValue: Date())
        } else {
            let start: Date
            if let seed = initialStartDate {
                start = seed
            } else {
                start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
            }
            let end = cal.date(byAdding: .hour, value: 1, to: start) ?? start
            _startDate = State(initialValue: start)
            _endDate = State(initialValue: end)
        }
    }

    @State private var customerId = ""
    @State private var customerName = ""
    @State private var customerSectionExpanded = true
    @State private var title = ""
    @State private var description = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var status: JobStatus = .pending
    @State private var isRecurring = false
    @State private var frequency: RecurringFrequency = .none
    @State private var noteEntries: [JobNoteEntry] = []
    @State private var customerAddress = ""
    @State private var hasReminder = false
    @State private var errorMessage: String?
    @State private var addCustomerSheet: AddCustomerSheetToken?
    @State private var showSavedJobTemplatesPicker = false

    private var selectedCustomerForToolbar: Customer? {
        store.customers.first { $0.id == customerId }
    }

    var body: some View {
        Form {
            Section {
                DisclosureGroup(isExpanded: $customerSectionExpanded) {
                    SearchableCustomerPicker(customerId: $customerId, onRequestAddCustomer: {
                        DispatchQueue.main.async {
                            addCustomerSheet = AddCustomerSheetToken()
                        }
                    })
                } label: {
                    HStack {
                        Text("Customer")
                        Spacer()
                        if let c = selectedCustomerForToolbar {
                            Text(CustomerHeader.primary(c))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(customerName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Section("Job") {
                TextField("Title *", text: $title)
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(2...8)
                    .textInputAutocapitalization(.sentences)
                Button {
                    showSavedJobTemplatesPicker = true
                } label: {
                    Label("Add from job templates", systemImage: "tray.and.arrow.down")
                }
            }
            Section("Schedule") {
                DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                Picker("Status", selection: $status) {
                    ForEach(JobStatus.allCases, id: \.self) { s in
                        Text(s.rawValue.replacingOccurrences(of: "_", with: " ")).tag(s)
                    }
                }
            }
            Section("Recurrence") {
                Toggle("Recurring", isOn: $isRecurring)
                if isRecurring {
                    Picker("Frequency", selection: $frequency) {
                        Text("Monthly").tag(RecurringFrequency.monthly)
                        Text("Every 6 months").tag(RecurringFrequency.sixMonths)
                        Text("Annually").tag(RecurringFrequency.annually)
                        Text("None").tag(RecurringFrequency.none)
                    }
                }
            }
            Section("Extras") {
                TextField("Customer address (optional)", text: $customerAddress, axis: .vertical)
                    .lineLimit(2...4)
                Toggle("Reminder", isOn: $hasReminder)
            }
            Section("Notes") {
                ForEach(Array(noteEntries.enumerated()), id: \.element.id) { index, _ in
                    VStack(alignment: .leading, spacing: 6) {
                        if !noteEntries[index].createdAt.isEmpty {
                            Text(jobEditorNoteTimestamp(noteEntries[index].createdAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        TextField("Note", text: $noteEntries[index].text, axis: .vertical)
                            .lineLimit(2...8)
                            .textInputAutocapitalization(.sentences)
                    }
                }
                .onDelete { noteEntries.remove(atOffsets: $0) }
                Button {
                    let fmt = ISO8601DateFormatter()
                    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    noteEntries.append(JobNoteEntry(id: InvoiceLogic.generateId(), text: "", createdAt: fmt.string(from: Date())))
                } label: {
                    Label("Add note", systemImage: "plus.circle.fill")
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            Section {
                Button(job == nil ? "Create job" : "Save changes") { save() }
                    .buttonStyle(PrimaryFormButtonStyle())
                    .disabled(title.isEmpty || customerName.isEmpty)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Group {
                    if let c = selectedCustomerForToolbar {
                        VStack(spacing: 2) {
                            Text(CustomerHeader.primary(c))
                                .font(.headline)
                                .lineLimit(1)
                            if let sub = CustomerHeader.secondary(c) {
                                Text(sub)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } else if !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(customerName)
                            .font(.headline)
                            .lineLimit(1)
                    } else {
                        Text(job == nil ? "New job" : "Edit job")
                            .font(.headline)
                    }
                }
            }
        }
        .sheet(item: $addCustomerSheet, onDismiss: {
            addCustomerSheet = nil
        }) { _ in
            AddCustomerEditorSheet(customerId: $customerId, onCancel: { addCustomerSheet = nil })
                .environmentObject(store)
        }
        .sheet(isPresented: $showSavedJobTemplatesPicker) {
            NavigationStack {
                SavedJobTemplatesPickerView { templates in
                    appendFromSavedJobTemplates(templates)
                }
                .environmentObject(store)
            }
        }
        .onChange(of: customerId) { _, new in
            if !new.isEmpty {
                customerSectionExpanded = false
                if let c = store.customers.first(where: { $0.id == new }) {
                    customerName = CustomerHeader.primary(c)
                }
            }
        }
        .onAppear {
            if let j = job {
                if let cid = j.customerId {
                    customerId = cid
                    if let c = store.customers.first(where: { $0.id == cid }) {
                        customerName = CustomerHeader.primary(c)
                    } else {
                        customerName = j.customerName
                    }
                } else if let m = store.customers.first(where: { $0.name == j.customerName }) {
                    customerId = m.id
                    customerName = CustomerHeader.primary(m)
                } else {
                    customerId = ""
                    customerName = j.customerName
                }
                title = j.title
                description = j.description ?? ""
                startDate = parseISO(j.startDate) ?? Date()
                endDate = parseISO(j.endDate) ?? Date()
                status = j.status
                isRecurring = j.isRecurring
                frequency = j.recurringFrequency
                noteEntries = j.noteEntries.sorted { $0.createdAt < $1.createdAt }
                customerAddress = j.customerAddress ?? ""
                hasReminder = j.hasReminder
            }
            customerSectionExpanded = customerId.isEmpty && customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Fills title (if empty) and appends text from job-only templates (`SavedJobTemplate`), not invoice line items.
    private func appendFromSavedJobTemplates(_ saved: [SavedJobTemplate]) {
        guard !saved.isEmpty else { return }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = saved[0].name
        }
        let addition: String
        if saved.count == 1 {
            let s = saved[0]
            let catalogDesc = s.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            addition = catalogDesc
        } else {
            addition = saved.map { jobTemplateLineText($0) }.map { "• \($0)" }.joined(separator: "\n")
        }
        guard !addition.isEmpty else { return }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            description = addition
        } else {
            description += "\n\n" + addition
        }
    }

    private func jobTemplateLineText(_ t: SavedJobTemplate) -> String {
        let d = t.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return d.isEmpty ? t.name : d
    }

    private func parseISO(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    private func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    private func save() {
        errorMessage = nil
        let now = ISO8601DateFormatter().string(from: Date())
        let id = job?.id ?? InvoiceLogic.generateId()
        let next: String?
        if isRecurring, frequency != .none {
            next = calculateNext(from: startDate, frequency: frequency).map { iso($0) }
        } else {
            next = nil
        }
        let savedNotes = noteEntries.compactMap { e -> JobNoteEntry? in
            let t = e.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return JobNoteEntry(id: e.id, text: t, createdAt: e.createdAt)
        }
        let j = ScheduledJob(
            id: id,
            customerId: customerId.isEmpty ? nil : customerId,
            customerName: customerName,
            title: title,
            description: description.isEmpty ? nil : description,
            startDate: iso(startDate),
            endDate: iso(endDate),
            status: status,
            isRecurring: isRecurring,
            recurringFrequency: frequency,
            nextOccurrence: next,
            noteEntries: savedNotes,
            customerAddress: customerAddress.isEmpty ? nil : customerAddress,
            hasReminder: hasReminder,
            createdAt: job?.createdAt ?? now,
            updatedAt: now
        )
        do {
            try store.upsertJob(j)
            if job == nil {
                onJobCreated?(j.id)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func calculateNext(from start: Date, frequency: RecurringFrequency) -> Date? {
        switch frequency {
        case .none: return nil
        case .monthly:
            return Calendar.current.date(byAdding: .month, value: 1, to: start)
        case .sixMonths:
            return Calendar.current.date(byAdding: .month, value: 6, to: start)
        case .annually:
            return Calendar.current.date(byAdding: .year, value: 1, to: start)
        }
    }

    private func jobEditorNoteTimestamp(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        guard let d else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: d)
    }
}
