import Foundation
import Testing
@testable import ReadOutMacApp
@testable import ReadOutCore

private func alarmMarker(_ seconds: TimeInterval, _ state: MeasurementAlertState) -> AlarmTimelineMarker {
    AlarmTimelineMarker(
        timestamp: Date(timeIntervalSince1970: seconds),
        state: state,
        message: DashboardAlertService.text(for: state)
    )
}

private func connectionMarker(_ seconds: TimeInterval, _ state: ConnectionOverlayState) -> ConnectionOverlayMarker {
    ConnectionOverlayMarker(
        timestamp: Date(timeIntervalSince1970: seconds),
        state: state,
        message: state.rawValue
    )
}

@Test
func nearestAlarmMarkerReturnsClosestWithinDistance() {
    let selected = Date(timeIntervalSince1970: 100)
    let markers = [
        alarmMarker(94, .short),
        alarmMarker(101, .highAlarm),
        alarmMarker(112, .lowAlarm)
    ]

    let nearest = ChartMarkerSelectionService.nearestAlarmMarker(
        to: selected,
        markers: markers,
        maxDistanceSeconds: 3
    )

    #expect(nearest?.state == .highAlarm)
}

@Test
func nearestAlarmMarkerReturnsNilWhenOutsideDistance() {
    let selected = Date(timeIntervalSince1970: 100)
    let markers = [
        alarmMarker(85, .short),
        alarmMarker(120, .highAlarm)
    ]

    let nearest = ChartMarkerSelectionService.nearestAlarmMarker(
        to: selected,
        markers: markers,
        maxDistanceSeconds: 4
    )

    #expect(nearest == nil)
}

@Test
func nearestConnectionMarkerReturnsClosestWithinDistance() {
    let selected = Date(timeIntervalSince1970: 200)
    let markers = [
        connectionMarker(195, .error),
        connectionMarker(201, .restored),
        connectionMarker(208, .reconnecting)
    ]

    let nearest = ChartMarkerSelectionService.nearestConnectionMarker(
        to: selected,
        markers: markers,
        maxDistanceSeconds: 2
    )

    #expect(nearest?.state == .restored)
}
