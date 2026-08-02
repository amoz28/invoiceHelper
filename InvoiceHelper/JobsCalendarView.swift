import SwiftUI
import UIKit

/// Hosts `UICalendarView` with a vertical scale so the month grid uses less height while staying full width.
@available(iOS 16.0, *)
final class JobsCalendarContainerView: UIView {
    let calendarView = UICalendarView()
    /// Visual height multiplier (e.g. 2/3 of natural month height).
    var verticalScale: CGFloat = 2 / 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(calendarView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        guard w > 0 else { return }

        calendarView.transform = .identity
        let naturalH = calendarView.sizeThatFits(CGSize(width: w, height: CGFloat.greatestFiniteMagnitude)).height
        let h = max(naturalH, 200)

        calendarView.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        calendarView.layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        calendarView.layer.position = CGPoint(x: w / 2, y: 0)
        calendarView.transform = CGAffineTransform(scaleX: 1, y: verticalScale)
    }
}

/// Month calendar with dot decorations for days that have jobs, and single-date selection (matches RN `Calendar` + `markedDates`).
@available(iOS 16.0, *)
struct JobsCalendarView: UIViewRepresentable {
    @Binding var selectedDate: Date?
    var markedDayStrings: Set<String>
    var calendar: Calendar
    /// Vertical scale for layout height (default 2/3 of system month height).
    var verticalScale: CGFloat = 2 / 3

    func makeCoordinator() -> Coordinator {
        Coordinator(binding: $selectedDate, calendar: calendar, markedDayStrings: markedDayStrings)
    }

    func makeUIView(context: Context) -> JobsCalendarContainerView {
        let container = JobsCalendarContainerView()
        container.verticalScale = verticalScale
        let v = container.calendarView
        v.calendar = context.coordinator.calendar
        v.locale = Locale.current
        v.fontDesign = .rounded
        v.clipsToBounds = true
        v.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        v.selectionBehavior = selection
        context.coordinator.calendarView = v
        context.coordinator.selection = selection
        context.coordinator.applySelection()
        return container
    }

    func updateUIView(_ uiView: JobsCalendarContainerView, context: Context) {
        uiView.verticalScale = verticalScale
        context.coordinator.binding = $selectedDate
        context.coordinator.calendar = calendar
        context.coordinator.markedDayStrings = markedDayStrings
        let v = uiView.calendarView
        v.calendar = calendar
        context.coordinator.applySelection()
        let comps = markedDayStrings.compactMap { ymdString -> DateComponents? in
            let p = ymdString.split(separator: "-")
            guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
            var dc = DateComponents()
            dc.year = y
            dc.month = m
            dc.day = d
            return dc
        }
        v.reloadDecorations(forDateComponents: comps, animated: true)
        uiView.setNeedsLayout()
    }

    @available(iOS 17.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: JobsCalendarContainerView, context: Context) -> CGSize? {
        let fallback = UIScreen.main.bounds.width - 48
        let width: CGFloat
        if let w = proposal.width, w > 0, w.isFinite {
            width = w
        } else {
            width = fallback
        }
        let natural = uiView.calendarView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        let h = max(natural, 200) * verticalScale
        return CGSize(width: width, height: h)
    }

    @available(iOS 16.0, *)
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var binding: Binding<Date?>
        var calendar: Calendar
        var markedDayStrings: Set<String>
        weak var calendarView: UICalendarView?
        weak var selection: UICalendarSelectionSingleDate?

        init(binding: Binding<Date?>, calendar: Calendar, markedDayStrings: Set<String>) {
            self.binding = binding
            self.calendar = calendar
            self.markedDayStrings = markedDayStrings
        }

        func applySelection() {
            guard let selection else { return }
            if let date = binding.wrappedValue {
                let dc = calendar.dateComponents([.year, .month, .day], from: date)
                selection.setSelected(dc, animated: false)
            } else {
                selection.setSelected(nil, animated: false)
            }
        }

        func dateSelection(_ sel: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dc = dateComponents,
                  let date = calendar.date(from: dc)
            else {
                binding.wrappedValue = nil
                return
            }
            let start = calendar.startOfDay(for: date)
            if let prev = binding.wrappedValue, calendar.isDate(prev, inSameDayAs: start) {
                binding.wrappedValue = nil
                sel.setSelected(nil, animated: true)
            } else {
                binding.wrappedValue = start
            }
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            let y = dateComponents.year ?? 0
            let m = dateComponents.month ?? 0
            let d = dateComponents.day ?? 0
            guard y > 0, m > 0, d > 0 else { return nil }
            let key = String(format: "%04d-%02d-%02d", y, m, d)
            if markedDayStrings.contains(key) {
                return .default(color: UIColor.systemBlue, size: .small)
            }
            return nil
        }
    }
}
