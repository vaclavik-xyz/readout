import Foundation
import Testing
@testable import ReadOutMacApp

private func chartSample(_ seconds: TimeInterval, _ value: Double) -> ChartSample {
    ChartSample(
        timestamp: Date(timeIntervalSince1970: seconds),
        value: value
    )
}

@Test
func chartRangeFilteringKeepsOnlySelectedWindow() {
    let now = Date(timeIntervalSince1970: 1_000)
    let samples = [
        chartSample(900, 1),
        chartSample(970, 2),
        chartSample(985, 3),
        chartSample(995, 4)
    ]

    let filtered = ChartSamplingService.filtered(
        samples: samples,
        range: .thirtySeconds,
        now: now
    )

    #expect(filtered.count == 3)
    #expect(filtered.allSatisfy { $0.timestamp >= now.addingTimeInterval(-30) })
}

@Test
func downsampleMinMaxCapsPointCountAndRetainsExtremes() {
    let samples = (0..<1_000).map { index in
        chartSample(TimeInterval(index), sin(Double(index) * 0.03))
    }

    let downsampled = ChartSamplingService.downsampleMinMax(samples: samples, maxPoints: 120)

    #expect(downsampled.count <= 120)
    let originalMin = samples.map(\.value).min()
    let originalMax = samples.map(\.value).max()
    let sampledMin = downsampled.map(\.value).min()
    let sampledMax = downsampled.map(\.value).max()
    #expect(sampledMin == originalMin)
    #expect(sampledMax == originalMax)
}
