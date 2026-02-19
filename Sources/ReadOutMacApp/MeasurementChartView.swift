import SwiftUI
import Charts
import ReadOutCore

struct MeasurementChartView: View {
    let title: String
    let color: Color
    let samples: [ChartSample]
    let markers: [AlarmTimelineMarker]
    let reconnectMarkers: [ConnectionOverlayMarker]
    @Binding var selectedTimestamp: Date?
    let highThreshold: Double?
    let lowThreshold: Double?
    let isHighLoad: Bool
    let isChartInspectorEnabled: Bool
    let selectedChartRange: ChartRangePreset
    let palette: DashboardPalette

    var body: some View {
        let showHeavyChartOverlays = !isHighLoad
        let maxVisibleMarkers = isHighLoad ? 6 : 20
        let showAnnotationLabels = !isHighLoad

        let areaGradient = LinearGradient(
            colors: [color.opacity(0.35), color.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
        )

        let visibleAlarmMarkers = Array(markers.suffix(maxVisibleMarkers))
        let visibleReconnectMarkers = Array(reconnectMarkers.suffix(maxVisibleMarkers))

        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(palette.primaryText)

            if samples.isEmpty {
                Text("Waiting for data...")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText.opacity(DesignSystem.Opacity.medium))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                let baseChart = Chart(samples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Value", sample.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: showHeavyChartOverlays ? 2.5 : 2.0,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                    if showHeavyChartOverlays {
                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Value", sample.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(areaGradient)
                    }

                    if let highThreshold {
                        RuleMark(y: .value("High Alarm", highThreshold))
                            .foregroundStyle(.red.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                    }

                    if let lowThreshold {
                        RuleMark(y: .value("Low Alarm", lowThreshold))
                            .foregroundStyle(.yellow.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                    }

                    ForEach(visibleAlarmMarkers) { marker in
                        RuleMark(x: .value("Alarm", marker.timestamp))
                            .foregroundStyle(DashboardUIHelpers.alarmMarkerColor(marker.state).opacity(0.9))
                            .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [3, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                if showAnnotationLabels && visibleAlarmMarkers.count <= 8 {
                                    Text(DashboardUIHelpers.alarmMarkerLabel(marker.state))
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(DashboardUIHelpers.alarmMarkerColor(marker.state))
                                }
                            }
                    }

                    ForEach(visibleReconnectMarkers) { marker in
                        RuleMark(x: .value("Connection Event", marker.timestamp))
                            .foregroundStyle(DashboardUIHelpers.connectionOverlayColor(marker.state).opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [2, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                if showAnnotationLabels && visibleReconnectMarkers.count <= 8 {
                                    Text(DashboardUIHelpers.connectionOverlayLabel(marker.state))
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(DashboardUIHelpers.connectionOverlayColor(marker.state))
                                }
                            }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis(.hidden)

                if isChartInspectorEnabled {
                    baseChart
                        .chartXSelection(value: $selectedTimestamp)
                } else {
                    baseChart
                }

                if isChartInspectorEnabled, let selectedTS = selectedTimestamp {
                    chartSelectionDetails(
                        selectedTimestamp: selectedTS,
                        markers: markers,
                        reconnectMarkers: reconnectMarkers
                    )
                } else if isChartInspectorEnabled, !markers.isEmpty || !reconnectMarkers.isEmpty {
                    Text("Hover or drag across the chart for marker details")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.tertiaryText)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                        .stroke(palette.cardStrokeDefault, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func chartSelectionDetails(
        selectedTimestamp: Date,
        markers: [AlarmTimelineMarker],
        reconnectMarkers: [ConnectionOverlayMarker]
    ) -> some View {
        let maxDistance = selectionDistanceSeconds()
        let nearestAlarm = ChartMarkerSelectionService.nearestAlarmMarker(
            to: selectedTimestamp,
            markers: markers,
            maxDistanceSeconds: maxDistance
        )
        let nearestConnection = ChartMarkerSelectionService.nearestConnectionMarker(
            to: selectedTimestamp,
            markers: reconnectMarkers,
            maxDistanceSeconds: maxDistance
        )

        HStack(spacing: DesignSystem.Spacing.sm) {
            Text(selectedTimestamp, format: .dateTime.hour().minute().second())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))

            if let nearestAlarm {
                markerBadge(
                    title: DashboardUIHelpers.alarmMarkerLabel(nearestAlarm.state),
                    detail: nearestAlarm.message,
                    color: DashboardUIHelpers.alarmMarkerColor(nearestAlarm.state)
                )
            }

            if let nearestConnection {
                markerBadge(
                    title: DashboardUIHelpers.connectionOverlayLabel(nearestConnection.state),
                    detail: nearestConnection.message,
                    color: DashboardUIHelpers.connectionOverlayColor(nearestConnection.state)
                )
            }

            if nearestAlarm == nil, nearestConnection == nil {
                Text("No marker near cursor")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(DesignSystem.Opacity.medium))
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func markerBadge(title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(color, in: Capsule())

            Text(detail)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    private func selectionDistanceSeconds() -> TimeInterval {
        switch selectedChartRange {
        case .thirtySeconds:
            return 2.5
        case .twoMinutes:
            return 8
        case .tenMinutes:
            return 20
        case .full:
            return 60
        }
    }
}
