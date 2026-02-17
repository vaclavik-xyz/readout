import Foundation

enum ChartMarkerSelectionService {
    static func nearestAlarmMarker(
        to timestamp: Date,
        markers: [AlarmTimelineMarker],
        maxDistanceSeconds: TimeInterval
    ) -> AlarmTimelineMarker? {
        nearestMarker(
            timestamp: timestamp,
            markers: markers,
            maxDistanceSeconds: maxDistanceSeconds
        )
    }

    static func nearestConnectionMarker(
        to timestamp: Date,
        markers: [ConnectionOverlayMarker],
        maxDistanceSeconds: TimeInterval
    ) -> ConnectionOverlayMarker? {
        nearestMarker(
            timestamp: timestamp,
            markers: markers,
            maxDistanceSeconds: maxDistanceSeconds
        )
    }

    private static func nearestMarker<T>(
        timestamp: Date,
        markers: [T],
        maxDistanceSeconds: TimeInterval
    ) -> T? where T: ChartTimedMarker {
        guard !markers.isEmpty else {
            return nil
        }

        let nearest = markers.min { left, right in
            let leftDistance = abs(left.timestamp.timeIntervalSince(timestamp))
            let rightDistance = abs(right.timestamp.timeIntervalSince(timestamp))
            return leftDistance < rightDistance
        }

        guard let nearest else {
            return nil
        }

        let distance = abs(nearest.timestamp.timeIntervalSince(timestamp))
        return distance <= max(0, maxDistanceSeconds) ? nearest : nil
    }
}
