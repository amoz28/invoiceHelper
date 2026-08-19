import SwiftUI

/// Semantic colors aligned with the React Native `INVOICE_STATUS_COLORS` / `JOB_STATUS_COLORS` palette,
/// adapted for light and dark mode.
enum AppTheme {
    static let accent = Color.accentColor

    static let revenueGreen = Color(red: 0.29, green: 0.63, blue: 0.31)
    static let outstandingRed = Color(red: 0.96, green: 0.26, blue: 0.21)
    static let pendingOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
    static let infoBlue = Color(red: 0.13, green: 0.59, blue: 0.95)

    static func invoiceStatusColor(_ status: InvoiceStatus) -> Color {
        switch status {
        case .draft: return Color(white: 0.62)
        case .sent: return infoBlue
        case .partially_paid: return pendingOrange
        case .paid: return revenueGreen
        case .overdue: return outstandingRed
        case .cancelled: return Color(white: 0.26)
        }
    }

    static func estimateStatusColor(_ status: EstimateStatus) -> Color {
        switch status {
        case .pending: return pendingOrange
        case .accepted: return revenueGreen
        case .rejected: return outstandingRed
        case .expired: return Color(white: 0.62)
        }
    }

    static func jobStatusColor(_ status: JobStatus) -> Color {
        switch status {
        case .pending: return pendingOrange
        case .in_progress: return infoBlue
        case .completed: return revenueGreen
        case .cancelled: return Color(white: 0.62)
        }
    }

    static let metricCardCorner: CGFloat = 14
    static let metricCardShadow: CGFloat = 0.06
    static let surfaceCorner: CGFloat = 16
}

/// Rounded surface used across list cards and detail panels.
struct AppSurfaceCard: View {
    var cornerRadius: CGFloat = AppTheme.surfaceCorner

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }
}

/// Larger, tappable segment control for detail screens (Invoices / Jobs / Details, etc.).
struct AppSegmentedTabs<Tag: Hashable>: View {
    let tabs: [(tag: Tag, title: String)]
    @Binding var selection: Tag

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.tag) { item in
                let selected = selection == item.tag
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = item.tag
                    }
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Button styles (forms & toolbars)

struct PrimaryFormButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.infoBlue.opacity(configuration.isPressed ? 0.85 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SecondaryFormButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
