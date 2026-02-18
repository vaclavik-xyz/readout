import Foundation
import ReadOutCore

@MainActor
final class ChartDataService: ObservableObject {
    @Published var multimeterSamples: [ChartSample] = []
    @Published var usbcSamples: [ChartSample] = []
    @Published var alarmMarkers: [AlarmTimelineMarker] = []

    @Published private(set) var displayedMultimeterSamples: [ChartSample] = []
    @Published private(set) var displayedUsbCSamples: [ChartSample] = []
    @Published private(set) var displayedAlarmMarkers: [AlarmTimelineMarker] = []
    @Published private(set) var displayedMultimeterConnectionMarkers: [ConnectionOverlayMarker] = []
    @Published private(set) var displayedUsbCConnectionMarkers: [ConnectionOverlayMarker] = []

    private(set) var chartRefreshPending = true

    private var chartConnectionTimeline: [ConnectionTimelineEntry] = []
    private var multimeterChartDirty = true
    private var usbCChartDirty = true
    private var chartMarkersDirty = true
    private var pendingRefreshReasons: Set<String> = ["init"]

#if DEBUG
    private(set) var lastMultimeterPipelineMetric = ChartPipelineMetric(
        sourcePointCount: 0,
        filteredPointCount: 0,
        renderedPointCount: 0,
        processingMilliseconds: 0
    )
    private(set) var lastUsbCPipelineMetric = ChartPipelineMetric(
        sourcePointCount: 0,
        filteredPointCount: 0,
        renderedPointCount: 0,
        processingMilliseconds: 0
    )
#endif

    func clearCharts() {
        multimeterSamples.removeAll(keepingCapacity: true)
        usbcSamples.removeAll(keepingCapacity: true)
        alarmMarkers.removeAll(keepingCapacity: true)
        chartConnectionTimeline.removeAll(keepingCapacity: true)
        multimeterChartDirty = true
        usbCChartDirty = true
        chartMarkersDirty = true
        chartRefreshPending = true
        pendingRefreshReasons.insert("charts_cleared")
    }

    func trimChartsIfNeeded(graphHistorySeconds: Int, sampleRateHz: Int) {
        let maxSamples = max(20, graphHistorySeconds * max(1, sampleRateHz))

        if multimeterSamples.count > maxSamples {
            multimeterSamples.removeFirst(multimeterSamples.count - maxSamples)
        }

        if usbcSamples.count > maxSamples {
            usbcSamples.removeFirst(usbcSamples.count - maxSamples)
        }
    }

    func markChartRefresh(
        multimeter: Bool = false,
        usbc: Bool = false,
        markers: Bool = false,
        reason: String
    ) {
        multimeterChartDirty = multimeterChartDirty || multimeter
        usbCChartDirty = usbCChartDirty || usbc
        chartMarkersDirty = chartMarkersDirty || markers
        chartRefreshPending = true
        pendingRefreshReasons.insert(reason)
    }

    func refreshDisplayedCharts(
        selectedChartRange: ChartRangePreset,
        deviceVisibility: DashboardDeviceVisibility,
        maxPoints: Int,
        force: Bool
    ) -> String {
        let reason = pendingRefreshReasons.sorted().joined(separator: ",")
        let effectiveReason = reason.isEmpty ? "coalesced" : reason

        let now = Date()
        let showMultimeter = deviceVisibility != .usbc
        let showUsbC = deviceVisibility != .multimeter

        if force || multimeterChartDirty {
            if showMultimeter {
                let multimeterPipeline = ChartPipelineService.process(
                    samples: multimeterSamples,
                    range: selectedChartRange,
                    now: now,
                    maxPoints: maxPoints
                )
                displayedMultimeterSamples = multimeterPipeline.samples
#if DEBUG
                lastMultimeterPipelineMetric = multimeterPipeline.metric
#endif
            } else {
                displayedMultimeterSamples = []
#if DEBUG
                lastMultimeterPipelineMetric = ChartPipelineMetric(
                    sourcePointCount: multimeterSamples.count,
                    filteredPointCount: 0,
                    renderedPointCount: 0,
                    processingMilliseconds: 0
                )
#endif
            }
        }

        if force || usbCChartDirty {
            if showUsbC {
                let usbCPipeline = ChartPipelineService.process(
                    samples: usbcSamples,
                    range: selectedChartRange,
                    now: now,
                    maxPoints: maxPoints
                )
                displayedUsbCSamples = usbCPipeline.samples
#if DEBUG
                lastUsbCPipelineMetric = usbCPipeline.metric
#endif
            } else {
                displayedUsbCSamples = []
#if DEBUG
                lastUsbCPipelineMetric = ChartPipelineMetric(
                    sourcePointCount: usbcSamples.count,
                    filteredPointCount: 0,
                    renderedPointCount: 0,
                    processingMilliseconds: 0
                )
#endif
            }
        }

        if force || chartMarkersDirty {
            displayedAlarmMarkers = showMultimeter ? alarmMarkersForDisplay(now: now, selectedChartRange: selectedChartRange) : []
            displayedMultimeterConnectionMarkers = showMultimeter
                ? connectionMarkersForDisplay(device: "multimeter", now: now, selectedChartRange: selectedChartRange)
                : []
            displayedUsbCConnectionMarkers = showUsbC
                ? connectionMarkersForDisplay(device: "usbc", now: now, selectedChartRange: selectedChartRange)
                : []
        }

        pendingRefreshReasons.removeAll(keepingCapacity: true)
        chartRefreshPending = false
        multimeterChartDirty = false
        usbCChartDirty = false
        chartMarkersDirty = false

        return effectiveReason
    }

    func appendAlarmMarkerIfNeeded(
        previousAlert: MeasurementAlertState,
        currentAlert: MeasurementAlertState,
        timestamp: Date
    ) {
        guard previousAlert != currentAlert else {
            return
        }
        guard currentAlert != .none else {
            return
        }

        alarmMarkers.append(
            AlarmTimelineMarker(
                timestamp: timestamp,
                state: currentAlert,
                message: DashboardAlertService.text(for: currentAlert)
            )
        )
        if alarmMarkers.count > 120 {
            alarmMarkers.removeFirst(alarmMarkers.count - 120)
        }
    }

    func recordChartConnectionEvent(_ entry: ConnectionTimelineEntry) {
        chartConnectionTimeline.append(entry)
        if chartConnectionTimeline.count > 240 {
            chartConnectionTimeline.removeFirst(chartConnectionTimeline.count - 240)
        }
    }

    private func alarmMarkersForDisplay(now: Date, selectedChartRange: ChartRangePreset) -> [AlarmTimelineMarker] {
        guard let duration = selectedChartRange.durationSeconds else {
            return alarmMarkers
        }
        let threshold = now.addingTimeInterval(-duration)
        return alarmMarkers.filter { $0.timestamp >= threshold }
    }

    private func connectionMarkersForDisplay(device: String, now: Date, selectedChartRange: ChartRangePreset) -> [ConnectionOverlayMarker] {
        let baseEntries = chartConnectionTimeline.filter { $0.device == device }

        let visibleEntries: [ConnectionTimelineEntry]
        if let duration = selectedChartRange.durationSeconds {
            let threshold = now.addingTimeInterval(-duration)
            visibleEntries = baseEntries.filter { $0.timestamp >= threshold }
        } else {
            visibleEntries = baseEntries
        }

        return visibleEntries.compactMap { entry in
            guard let state = connectionOverlayState(for: entry) else {
                return nil
            }

            return ConnectionOverlayMarker(
                timestamp: entry.timestamp,
                state: state,
                message: entry.message ?? state.rawValue
            )
        }
    }

    private func connectionOverlayState(for entry: ConnectionTimelineEntry) -> ConnectionOverlayState? {
        let lowered = entry.message?.lowercased() ?? ""
        if lowered.contains("retrying") {
            return .reconnecting
        }
        if entry.state == .error {
            return .error
        }
        if entry.state == .connected {
            return .restored
        }
        return nil
    }
}
