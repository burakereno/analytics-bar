import Foundation
import SwiftUI

struct SevenDayTrendCard: View {
    enum TrendMetric: String, CaseIterable, Identifiable {
        case users = "Users"
        case sessions = "Sessions"
        case views = "Views"

        var id: String { rawValue }
    }

    let snapshot: CombinedDashboardSnapshot
    let now: Date
    let maximumAge: TimeInterval
    @State private var metric: TrendMetric = .sessions

    private var points: [SevenDayTrendPoint] {
        snapshot.sevenDay.keys.sorted().map { day in
            let totals = snapshot.sevenDay[day] ?? .zero
            let value: Int
            switch metric {
            case .users: value = totals.activeUsers
            case .sessions: value = totals.sessions
            case .views: value = totals.views
            }
            return SevenDayTrendPoint(day: day, value: value)
        }
    }

    private var scale: SevenDayTrendBarScale {
        SevenDayTrendBarScale(values: points.map(\.value))
    }

    private var previewHoveredIndex: Int? {
#if DEBUG
        ProcessInfo.processInfo.environment["ANALYTICS_BAR_HOVER_PREVIEW_INDEX"]
            .flatMap(Int.init)
#else
        nil
#endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "chart.bar")
                        .foregroundStyle(.green)
                    Text("LAST 7 COMPLETE DAYS")
                        .foregroundStyle(.primary)
                }
                .font(.system(size: 11, weight: .bold))

                Spacer()

                Picker("Metric", selection: $metric) {
                    ForEach(TrendMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
                .controlSize(.mini)
                .tint(.orange)
                .accessibilityLabel("Trend metric")
            }

            if snapshot.hasCurrentCore(at: now, maximumAge: maximumAge) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    SevenDayTrendBarView(
                        point: point,
                        metric: metric,
                        scale: scale,
                        tooltipHorizontalOffset: tooltipHorizontalOffset(for: index),
                        startsHovered: previewHoveredIndex == index
                    )
                }
            }
            .frame(height: 86, alignment: .bottom)
            .animation(.snappy(duration: 0.24), value: metric)
            } else {
                Text("Trend unavailable. Check the connection to fetch current data.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }

            Text("Each property uses its Analytics reporting time zone")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .dashboardCard()
    }

    private func tooltipHorizontalOffset(for index: Int) -> CGFloat {
        if index == points.startIndex { return 44 }
        if index == points.index(before: points.endIndex) { return -44 }
        return 0
    }
}

struct SevenDayTrendPoint: Identifiable, Equatable {
    let day: AnalyticsDay
    let value: Int

    var id: AnalyticsDay { day }
}

struct SevenDayTrendBarScale: Equatable {
    static let isolatedOutlierMultiplier = 2.5
    static let displayHeadroomMultiplier = 1.2

    let displayMaximumValue: Int
    let actualMaximumValue: Int
    let hasCappedOutlier: Bool

    init(values: [Int]) {
        let positiveValues = values.filter { $0 > 0 }.sorted(by: >)
        guard let actualMaximum = positiveValues.first else {
            displayMaximumValue = 1
            actualMaximumValue = 0
            hasCappedOutlier = false
            return
        }

        actualMaximumValue = actualMaximum

        guard positiveValues.count > 1 else {
            displayMaximumValue = actualMaximum
            hasCappedOutlier = false
            return
        }

        let secondHighest = positiveValues[1]
        hasCappedOutlier = Double(actualMaximum)
            > Double(secondHighest) * Self.isolatedOutlierMultiplier

        if hasCappedOutlier {
            displayMaximumValue = max(
                Int(ceil(Double(secondHighest) * Self.displayHeadroomMultiplier)),
                1
            )
        } else {
            displayMaximumValue = actualMaximum
        }
    }

    func isCapped(_ value: Int) -> Bool {
        hasCappedOutlier && value > displayMaximumValue
    }
}

enum SevenDayTrendBarMetrics {
    static let plotHeight: CGFloat = 64
    static let maximumHeight: CGFloat = 60
    static let minimumNonzeroHeight: CGFloat = 2
    static let zeroHeight: CGFloat = 2

    static func height(for value: Int, relativeTo maximumValue: Int) -> CGFloat {
        guard value > 0 else { return zeroHeight }
        guard maximumValue > 0 else { return minimumNonzeroHeight }

        let ratio = min(max(CGFloat(value) / CGFloat(maximumValue), 0), 1)
        return max(minimumNonzeroHeight, ratio * maximumHeight)
    }
}

private struct SevenDayTrendBarView: View {
    let point: SevenDayTrendPoint
    let metric: SevenDayTrendCard.TrendMetric
    let scale: SevenDayTrendBarScale
    let tooltipHorizontalOffset: CGFloat
    @State private var isHovered: Bool

    init(
        point: SevenDayTrendPoint,
        metric: SevenDayTrendCard.TrendMetric,
        scale: SevenDayTrendBarScale,
        tooltipHorizontalOffset: CGFloat,
        startsHovered: Bool
    ) {
        self.point = point
        self.metric = metric
        self.scale = scale
        self.tooltipHorizontalOffset = tooltipHorizontalOffset
        _isHovered = State(initialValue: startsHovered)
    }

    private var isCapped: Bool {
        scale.isCapped(point.value)
    }

    private var barHeight: CGFloat {
        SevenDayTrendBarMetrics.height(
            for: point.value,
            relativeTo: scale.displayMaximumValue
        )
    }

    var body: some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(barColor)
                .frame(width: 24, height: barHeight)
                .overlay(alignment: .top) {
                    if isCapped {
                        SevenDayTrendScaleBreakShape()
                            .stroke(
                                Color.black.opacity(0.48),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                            )
                            .frame(width: 12, height: 7)
                            .padding(.top, 5)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: SevenDayTrendBarMetrics.plotHeight, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    if isHovered {
                        Text(tooltipText)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background {
                                Capsule()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .overlay {
                                        Capsule()
                                            .stroke(.white.opacity(0.12), lineWidth: 0.5)
                                    }
                                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                            }
                            .offset(x: tooltipHorizontalOffset, y: -(barHeight + 8))
                    }
                }

            Text(point.day.weekdayAbbreviation)
                .font(.system(size: 9, weight: point.day.isMonday ? .bold : .medium))
                .foregroundStyle(point.day.isMonday ? Color.green : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity, minHeight: 81, maxHeight: 81, alignment: .bottom)
        .overlay(alignment: .leading) {
            if point.day.isMonday {
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 0.5, height: SevenDayTrendBarMetrics.plotHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(x: -2)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .zIndex(isHovered ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(point.day.accessibilityDate)
        .accessibilityValue(accessibilityValue)
    }

    private var barColor: Color {
        if point.value == 0 { return Color.primary.opacity(0.10) }
        if isCapped { return .orange }
        if scale.hasCappedOutlier { return .green }
        if point.value == scale.actualMaximumValue { return .orange }
        return .green
    }

    private var tooltipText: String {
        "\(point.day.tooltipDate) · \(point.value.formatted()) \(metric.rawValue.lowercased())"
    }

    private var accessibilityValue: String {
        let value = "\(point.value.formatted()) \(metric.rawValue.lowercased())"
        return isCapped ? "\(value), exceeds chart scale" : value
    }
}

private struct SevenDayTrendScaleBreakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let segmentWidth = rect.width * 0.36
        path.move(to: CGPoint(x: 0, y: rect.height * 0.35))
        path.addLine(to: CGPoint(x: segmentWidth, y: rect.height * 0.65))
        path.addLine(to: CGPoint(x: segmentWidth * 2, y: rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.65))
        return path
    }
}

private extension AnalyticsDay {
    var date: Date? {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )
    }

    var weekdayAbbreviation: String {
        date?.formatted(.dateTime.weekday(.abbreviated)) ?? gaValue
    }

    var tooltipDate: String {
        date?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? gaValue
    }

    var accessibilityDate: String {
        date?.formatted(date: .complete, time: .omitted) ?? gaValue
    }

    var isMonday: Bool {
        guard let date else { return false }
        return Calendar.current.component(.weekday, from: date) == 2
    }
}
