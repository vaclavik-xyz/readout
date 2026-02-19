import Testing
@testable import ReadOutIO

@Test
func soakRunnerIsDeterministicForSameSeed() async {
    let base = SoakRunConfiguration(
        sessionID: "deterministic",
        sampleRateHz: 60,
        targetFrames: 80,
        timeoutSeconds: 10,
        reconnectPolicy: ReconnectPolicy(
            enabled: true,
            initialDelaySeconds: 0.02,
            maxDelaySeconds: 0.08,
            multiplier: 2
        ),
        faultProfile: SoakFaultProfile(
            seed: 777,
            openFailureProbability: 0.02,
            disconnectProbabilityPerRead: 0.01,
            readFailureProbabilityPerRead: 0.01,
            slowReadProbabilityPerRead: 0.01,
            slowReadDelaySeconds: 0.005
        ),
        thresholds: SoakThresholds(
            maxTransportErrors: 100,
            maxReconnectAttempts: 100,
            minFramesCaptured: 80
        )
    )

    let first = await SoakRunner.runStreamingSimulation(configuration: base)
    let second = await SoakRunner.runStreamingSimulation(configuration: base)

    #expect(abs(first.framesCaptured - second.framesCaptured) <= 1)
    #expect(first.transportErrors == second.transportErrors)
    #expect(first.reconnectAttempts == second.reconnectAttempts)
    #expect(first.transportFaults == second.transportFaults)
    #expect(first.thresholdFailures == second.thresholdFailures)
    #expect(first.latencyMetrics.p50Ms > 0)
    #expect(first.latencyMetrics.achievedHz > 0)
}

@Test
func soakRunnerCollectsFaultAndRetryMetrics() async {
    let config = SoakRunConfiguration(
        sessionID: "faulty",
        sampleRateHz: 120,
        targetFrames: 100,
        timeoutSeconds: 10,
        reconnectPolicy: ReconnectPolicy(
            enabled: true,
            initialDelaySeconds: 0.01,
            maxDelaySeconds: 0.05,
            multiplier: 2
        ),
        faultProfile: SoakFaultProfile(
            seed: 2026,
            openFailureProbability: 0.04,
            disconnectProbabilityPerRead: 0.02,
            readFailureProbabilityPerRead: 0.02,
            slowReadProbabilityPerRead: 0.03,
            slowReadDelaySeconds: 0.01
        ),
        thresholds: SoakThresholds(
            maxTransportErrors: 400,
            maxReconnectAttempts: 400,
            minFramesCaptured: 100
        )
    )

    let summary = await SoakRunner.runStreamingSimulation(configuration: config)

    #expect(summary.reachedTargetFrames == true)
    #expect(summary.framesCaptured >= 100)
    #expect(summary.transportErrors > 0)
    #expect(summary.reconnectAttempts > 0)
    #expect(summary.transportFaults.disconnectsInjected + summary.transportFaults.readFailuresInjected + summary.transportFaults.openFailuresInjected > 0)
    #expect(summary.latencyMetrics.p50Ms > 0)
    #expect(summary.latencyMetrics.p99Ms > 0)
    #expect(summary.latencyMetrics.achievedHz > 0)
}

@Test
func soakRunnerReportsReasonableLatencyMetrics() async {
    let config = SoakRunConfiguration(
        sessionID: "latency-check",
        sampleRateHz: 100,
        targetFrames: 200,
        timeoutSeconds: 10,
        reconnectPolicy: ReconnectPolicy(
            enabled: true,
            initialDelaySeconds: 0.01,
            maxDelaySeconds: 0.05,
            multiplier: 2
        ),
        faultProfile: SoakFaultProfile(
            seed: 9999,
            openFailureProbability: 0.01,
            disconnectProbabilityPerRead: 0.005,
            readFailureProbabilityPerRead: 0.005,
            slowReadProbabilityPerRead: 0.01,
            slowReadDelaySeconds: 0.005
        ),
        thresholds: SoakThresholds(
            maxTransportErrors: 200,
            maxReconnectAttempts: 200,
            minFramesCaptured: 200,
            maxP99LatencyMs: 500
        )
    )

    let summary = await SoakRunner.runStreamingSimulation(configuration: config)
    let latency = summary.latencyMetrics

    #expect(latency.p50Ms > 0)
    #expect(latency.p50Ms <= latency.p95Ms)
    #expect(latency.p95Ms <= latency.p99Ms)
    #expect(latency.p99Ms <= latency.maxMs)
    #expect(latency.achievedHz > 0)
    #expect(summary.reachedTargetFrames == true)
}
