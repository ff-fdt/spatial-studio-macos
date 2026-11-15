import AppKit
import CoreAudio
import SwiftUI
import SpatialEngine

@MainActor
private final class InputGraph {
    let route: InputRoute
    let engine = SpatialEngine()
    let tap = ProcessTap()
    var previousFrames: UInt64 = 0

    init(route: InputRoute) { self.route = route }

    func start(config: SpatialConfig, output: AudioDeviceID) throws {
        engine.config = config
        let input = try tap.start(including: route.including, excluding: route.excluding, bundleIDs: route.bundles)
        do { try engine.start(outputDeviceID: output, captureDeviceID: input) }
        catch { stop(); throw error }
    }

    func stop() {
        engine.onFormatChange = nil
        engine.stop()
        tap.stop()
    }
}

@MainActor
final class DeskAudio: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var device = SpatialEngine.currentDefaultOutput().name
    @Published private(set) var message: String?
    @Published private(set) var inputs: [AudioInput] = []

    private var graphs: [InputGraph] = []
    private var config = SpatialConfig()
    private var output = SpatialEngine.currentDefaultOutput().id
    private var lastTraffic = Date()
    private var lastDiscovery = Date.distantPast

    func refreshInputs() {
        lastDiscovery = Date()
        let found = AudioInputs.current(keeping: Set(config.points.compactMap(\.inputID)))
        if found != inputs { inputs = found }
    }

    func setEnabled(_ enabled: Bool, config: SpatialConfig) {
        if !enabled { stop(); return }
        guard !running else { return }
        message = nil
        self.config = config
        if config.points.contains(where: { $0.inputID != nil }) { refreshInputs() }
        let current = SpatialEngine.currentDefaultOutput()
        output = current.id
        device = current.name
        do {
            try syncGraphs()
            running = true
        } catch {
            stop(tr("音频接入失败，请检查系统音频录制权限。"))
        }
    }

    func apply(_ config: SpatialConfig) {
        self.config = config
        guard running else { return }
        do { try syncGraphs() }
        catch { stop(tr("切换输入失败，已恢复原声。")) }
    }

    func poll() {
        let current = SpatialEngine.currentDefaultOutput()
        if current.name != device { device = current.name }
        if current.id != output {
            output = current.id
            if running { stop(tr("输出已切换。点「开始处理」重新连接。")) }
        }
        let now = Date()
        if running, config.points.contains(where: { $0.inputID != nil }),
           now.timeIntervalSince(lastDiscovery) >= 1.25 {
            refreshInputs()
            do { try syncGraphs() }
            catch { stop(tr("音频输入已断开，请重新开始处理。")) }
        }
        guard running, !graphs.isEmpty else { return }
        for graph in graphs {
            let state = graph.engine.pollState()
            if state.totalCaptured != graph.previousFrames, state.totalPlayed > 0 {
                graph.previousFrames = state.totalCaptured
                lastTraffic = now
            }
        }
        if now.timeIntervalSince(lastTraffic) > 5 {
            stop(tr("没有收到音频。允许系统音频录制后，播放一段声音再试。"))
        }
    }

    private func syncGraphs() throws {
        let endpoints = inputs.map { InputEndpoint(id: $0.id, bundle: $0.bundle, processes: $0.pids) }
        let plan = InputRoute.plan(for: config.points, endpoints: endpoints)
        let graphChanges = graphs.map(\.route) != plan
        if graphChanges {
            // Stop the previous system tap before starting dedicated taps to
            // avoid briefly monitoring the same app through both paths.
            stopGraphs()
            lastTraffic = Date()
        }
        let routesToMix: Float = config.soloPointID == nil ? Float(max(1, plan.count)) : 1
        let headroom: Float = -20 * log10(routesToMix)
        for (i, route) in plan.enumerated() {
            var inputConfig = config
            inputConfig.points = config.points.filter { $0.inputID == route.id }
            inputConfig.inputHeadroomDB = headroom
            inputConfig.outputPeakCeiling = 0.98 / routesToMix
            if graphChanges {
                let graph = InputGraph(route: route)
                graph.engine.onFormatChange = { [weak self] ok in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if ok { self.lastTraffic = Date() }
                        else { self.stop(tr("音频格式变更，请重新开始处理。")) }
                    }
                }
                try graph.start(config: inputConfig, output: output)
                graphs.append(graph)
            } else if graphs[i].engine.config != inputConfig {
                let countChanged = graphs[i].engine.config.points.count != inputConfig.points.count
                try graphs[i].engine.reconfigure(inputConfig)
                if countChanged {
                    graphs[i].previousFrames = 0
                    lastTraffic = Date()
                }
            }
        }
    }

    private func stopGraphs() {
        graphs.forEach { $0.stop() }
        graphs.removeAll()
    }

    func stop(_ reason: String? = nil) {
        stopGraphs()
        running = false
        message = reason
    }
}

@main
struct DeskApp: App {
    @StateObject private var audio = DeskAudio()

    var body: some Scene {
        Window("Spatial Studio", id: "spatial-desk") {
            DeskView(audio: audio)
                .frame(minWidth: 500, minHeight: 440)
                .preferredColorScheme(.dark)
                .onReceive(Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()) { _ in
                    audio.poll()
                }
                .onDisappear { audio.stop() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    audio.stop()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 820, height: 640)
    }
}
