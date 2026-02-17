import Foundation

struct ChartPipelineMetric: Equatable {
    let sourcePointCount: Int
    let filteredPointCount: Int
    let renderedPointCount: Int
    let processingMilliseconds: Double
}

struct ChartPipelineResult {
    let samples: [ChartSample]
    let metric: ChartPipelineMetric
}

enum ChartPipelineService {
    static func process(
        samples: [ChartSample],
        range: ChartRangePreset,
        now: Date,
        maxPoints: Int
    ) -> ChartPipelineResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let filtered = ChartSamplingService.filtered(samples: samples, range: range, now: now)
        let rendered = ChartSamplingService.downsampleMinMax(samples: filtered, maxPoints: maxPoints)
        let elapsedMs = max(0, (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)

        return ChartPipelineResult(
            samples: rendered,
            metric: ChartPipelineMetric(
                sourcePointCount: samples.count,
                filteredPointCount: filtered.count,
                renderedPointCount: rendered.count,
                processingMilliseconds: elapsedMs
            )
        )
    }
}
