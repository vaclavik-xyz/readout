import Foundation

enum ChartRangePreset: String, CaseIterable, Identifiable {
    case thirtySeconds
    case twoMinutes
    case tenMinutes
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirtySeconds: return "30s"
        case .twoMinutes: return "2m"
        case .tenMinutes: return "10m"
        case .full: return "Full"
        }
    }

    var durationSeconds: TimeInterval? {
        switch self {
        case .thirtySeconds: return 30
        case .twoMinutes: return 120
        case .tenMinutes: return 600
        case .full: return nil
        }
    }
}

enum ChartSamplingService {
    static func filtered(
        samples: [ChartSample],
        range: ChartRangePreset,
        now: Date
    ) -> [ChartSample] {
        guard let duration = range.durationSeconds else {
            return samples
        }
        let threshold = now.addingTimeInterval(-duration)
        return samples.filter { $0.timestamp >= threshold }
    }

    static func downsampleMinMax(
        samples: [ChartSample],
        maxPoints: Int
    ) -> [ChartSample] {
        let limit = max(8, maxPoints)
        guard samples.count > limit else {
            return samples
        }

        let bucketCount = max(1, limit / 2)
        let stride = Double(samples.count) / Double(bucketCount)

        var result: [ChartSample] = []
        result.reserveCapacity(limit)

        for bucket in 0..<bucketCount {
            let start = Int(Double(bucket) * stride)
            let end = min(samples.count, Int(Double(bucket + 1) * stride))
            guard start < end else {
                continue
            }

            let slice = samples[start..<end]
            guard
                let minSample = slice.min(by: { $0.value < $1.value }),
                let maxSample = slice.max(by: { $0.value < $1.value })
            else {
                continue
            }

            if minSample.timestamp <= maxSample.timestamp {
                result.append(minSample)
                if minSample.id != maxSample.id {
                    result.append(maxSample)
                }
            } else {
                result.append(maxSample)
                if minSample.id != maxSample.id {
                    result.append(minSample)
                }
            }
        }

        if result.count > limit {
            return Array(result.prefix(limit))
        }
        return result
    }
}
