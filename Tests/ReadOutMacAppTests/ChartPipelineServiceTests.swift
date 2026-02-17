import Foundation
import Testing
@testable import ReadOutMacApp

private func pipelineSample(_ seconds: TimeInterval, _ value: Double) -> ChartSample {
    ChartSample(
        timestamp: Date(timeIntervalSince1970: seconds),
        value: value
    )
}

@Test
func chartPipelineTracksCountsAndLatency() {
    let samples = (0..<1_000).map { index in
        pipelineSample(TimeInterval(index), sin(Double(index) * 0.05))
    }

    let result = ChartPipelineService.process(
        samples: samples,
        range: .twoMinutes,
        now: Date(timeIntervalSince1970: 1_000),
        maxPoints: 80
    )

    #expect(result.metric.sourcePointCount == 1_000)
    #expect(result.metric.filteredPointCount == 120)
    #expect(result.metric.renderedPointCount <= 80)
    #expect(result.samples.count == result.metric.renderedPointCount)
    #expect(result.metric.processingMilliseconds >= 0)
}

@Test
func chartPipelineKeepsSmallDatasetsWithoutDownsampling() {
    let samples = (0..<10).map { index in
        pipelineSample(TimeInterval(index), Double(index))
    }

    let result = ChartPipelineService.process(
        samples: samples,
        range: .full,
        now: Date(timeIntervalSince1970: 100),
        maxPoints: 120
    )

    #expect(result.metric.sourcePointCount == 10)
    #expect(result.metric.filteredPointCount == 10)
    #expect(result.metric.renderedPointCount == 10)
}
