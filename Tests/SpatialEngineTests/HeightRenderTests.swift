import AudioToolbox
import Foundation
import Testing
import simd
@testable import SpatialEngine

@Suite("Binaural renderer", .serialized)
struct HeightRenderTests {
    @Test("Both stereo channels render the zenith without flattening the height")
    func heightChangesRealOutput() throws {
        let level = try render(elevation: 0, distance: 0.65)
        let elevated = try render(elevation: 45.125, distance: 0.65)
        let almostTop = try render(elevation: 89.5, distance: 0.65)
        let top = try render(elevation: 90, distance: 0.65)
        let bottom = try render(elevation: -90, distance: 0.65)
        let farTop = try render(elevation: 90, distance: 2)
        #expect(abs(top.elevations[0] - 90) < 0.001 && abs(top.elevations[1] - 90) < 0.001)
        #expect(abs(bottom.elevations[0] + 90) < 0.001 && abs(bottom.elevations[1] + 90) < 0.001)
        #expect(abs(almostTop.elevations[0]) < 90 && almostTop.elevations[0] > elevated.elevations[0])
        #expect(level.samples != elevated.samples)
        #expect(level.samples != top.samples)
        #expect(top.samples != bottom.samples)
        #expect(top.samples != farTop.samples)
        #expect(top.samples.contains { abs($0) > 1e-5 })
    }

    @Test("Left and right routing remain separate across multiple independently positioned points")
    func independentlyRoutedPoints() throws {
        let left = StereoPoint(position: SourcePosition(azimuth: -50, elevation: 12), channel: .left)
        let right = StereoPoint(position: SourcePosition(azimuth: 50, elevation: -15), channel: .right)
        let extra = StereoPoint(position: SourcePosition(azimuth: 155, elevation: 30), channel: .stereo)
        let original = [left, right, extra]
        var moveRight = original
        moveRight[1].position.elevation = 87.5
        var moveExtra = original
        moveExtra[2].position.elevation = -78.75
        let inputL = try render(elevation: 0, distance: 1, points: original, impulses: (0.4, 0)).samples
        let inputR = try render(elevation: 0, distance: 1, points: original, impulses: (0, 0.4)).samples
        let leftAfterRightMoves = try render(elevation: 0, distance: 1, points: moveRight, impulses: (0.4, 0)).samples
        let rightAfterRightMoves = try render(elevation: 0, distance: 1, points: moveRight, impulses: (0, 0.4)).samples
        let leftAfterExtraMoves = try render(elevation: 0, distance: 1, points: moveExtra, impulses: (0.4, 0)).samples
        #expect(inputL.contains { abs($0) > 1e-5 })
        #expect(inputR.contains { abs($0) > 1e-5 })
        #expect(zip(inputL, leftAfterRightMoves).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(zip(inputR, rightAfterRightMoves).contains { abs($0 - $1) > 1e-5 })
        #expect(zip(inputL, leftAfterExtraMoves).contains { abs($0 - $1) > 1e-5 })
    }

    @Test("Dragging follows screen axes while preserving camera depth, including at the visual center")
    func directDragInCameraPlane() {
        for yaw in [0.0, -0.7, 2.3] {
            let right = SIMD3<Double>(cos(yaw), 0, -sin(yaw))
            let up = SIMD3<Double>(-sin(yaw) * 0.5, sqrt(0.75), -cos(yaw) * 0.5)
            let depth = simd_cross(right, up)
            for azimuth in [-87.0, -48.0, -125.0, 80.0] {
                let p = SourcePosition(azimuth: azimuth, elevation: 12, distance: 0.85)
                let start = p.direction * SourcePosition.sceneRadius(p.distance)
                var before = start
                for i in 0...60 {
                    let t = Double(i) / 60
                    let x = simd_dot(start, right)
                    let y = simd_dot(start, up)
                    let moved = p.dragged(right: right, up: up, horizontal: -x * t, vertical: -y * t)
                    let projected = moved.direction * SourcePosition.sceneRadius(moved.distance)
                    #expect(abs(simd_dot(projected, right) - x * (1 - t)) < 1e-7)
                    #expect(abs(simd_dot(projected, up) - y * (1 - t)) < 1e-7)
                    #expect(abs(simd_dot(projected - start, depth)) < 1e-7)
                    #expect(simd_length(projected - before) < 0.02)
                    before = projected
                }
            }
        }
    }

    @Test("Stereo at the center retains original left and right and never folds down")
    func inHeadPreservesStereo() throws {
        let position = SourcePosition(azimuth: 120, elevation: 30, distance: 0)
        let center = StereoPoint(position: position, channel: .stereo, gain: 0)
        let left = try render(elevation: 0, distance: 0, points: [center], impulses: (0.4, 0)).samples
        let right = try render(elevation: 0, distance: 0, points: [center], impulses: (0, 0.2)).samples
        let transition = try render(elevation: 0, distance: 0.18,
            points: [StereoPoint(position: SourcePosition(azimuth: 120, elevation: 30, distance: 0.18),
                                channel: .stereo, gain: 0)], impulses: (0.4, 0)).samples
        #expect(abs(left[0] - 0.4) < 1e-5)
        #expect(abs(right[256 + 11] - 0.2) < 1e-5)
        #expect(stride(from: 0, to: left.count, by: 512).allSatisfy { offset in
            left[(offset + 256)..<(offset + 512)].allSatisfy { abs($0) < 1e-8 }
        })
        #expect(stride(from: 0, to: right.count, by: 512).allSatisfy { offset in
            right[offset..<(offset + 256)].allSatisfy { abs($0) < 1e-8 }
        })
        #expect(transition.contains { abs($0) > 1e-5 })
        #expect(transition != left)
    }

    @Test("Solo matches a single point without changing the configured stereo route")
    func soloRestoresSinglePointCues() throws {
        let left = StereoPoint(position: .init(azimuth: -48, elevation: 8, distance: 0.85), channel: .stereo)
        let right = StereoPoint(position: .init(azimuth: 48, elevation: 8, distance: 0.85), channel: .stereo)
        let one = try render(elevation: 0, distance: 1, points: [left], impulses: (0.2, 0.2), rightSample: 0).samples
        let both = try render(elevation: 0, distance: 1, points: [left, right],
                              impulses: (0.2, 0.2), rightSample: 0).samples
        let solo = try render(elevation: 0, distance: 1, points: [left, right],
                              impulses: (0.2, 0.2), rightSample: 0, soloID: left.id).samples
        #expect(one == solo)
        #expect(interauralDifference(solo) > 12)
        #expect(abs(interauralDifference(both)) < 2)
    }

    @Test("Near-field correction gives the ear a different response after level matching")
    func nearFieldChangesEarCues() throws {
        func at(_ d: Double, _ azimuth: Double = -90) -> StereoPoint {
            StereoPoint(position: .init(azimuth: azimuth, elevation: 0, distance: d), channel: .stereo)
        }
        func capture(_ point: StereoPoint, near: Bool) throws -> [Float] {
            try render(elevation: 0, distance: 1, points: [point],
                       impulses: (0.2, 0.2), rightSample: 0, nearField: near).samples
        }

        let close = try capture(at(0.28), near: true)
        let further = try capture(at(0.35), near: true)
        let baselineClose = try capture(at(0.28), near: false)
        let baselineFurther = try capture(at(0.35), near: false)
        let baseError = matchedError(baselineClose, baselineFurther)
        let correctedError = matchedError(close, further)
        let closeILD = interauralDifference(close)
        let furtherILD = interauralDifference(further)
        print("28 cm vs 35 cm: normalized wave error \(baseError) -> \(correctedError); interaural L-R dB \(closeILD) vs \(furtherILD)")
        #expect(baseError < 0.0001)
        #expect(correctedError > 0.01)
        #expect(closeILD > furtherILD + 0.4)
        let finite = close.allSatisfy { $0.isFinite }
        #expect(finite)

        let reference = at(0.85)
        #expect(try capture(reference, near: true) == capture(reference, near: false))
        let center = at(0)
        #expect(try capture(center, near: true) == capture(center, near: false))
    }

    private func interauralDifference(_ data: [Float]) -> Double {
        var energy = SIMD2<Double>.zero
        for (i, s) in data.enumerated() { energy[(i / 256) % 2] += Double(s) * Double(s) }
        return 10 * log10(energy.x / energy.y)
    }

    private func matchedError(_ a: [Float], _ b: [Float]) -> Double {
        func norm(_ x: [Float]) -> Double { sqrt(x.reduce(0) { $0 + Double($1) * Double($1) }) }
        let aNorm = norm(a), bNorm = norm(b)
        return sqrt(zip(a, b).reduce(0) {
            let delta = Double($1.0) / aNorm - Double($1.1) / bNorm
            return $0 + delta * delta
        })
    }

    private func render(elevation: Float, distance: Float, points: [StereoPoint] = [],
                        impulses: (Float, Float) = (0.4, 0.2), rightSample: Int = 11,
                        soloID: UUID? = nil, nearField: Bool = false) throws -> (samples: [Float], elevations: [Float]) {
        let block: UInt32 = 256
        let ctx = Ctx(channels: 2)
        ctx.spatialDualPoint = true
        ctx.pointRouting = !points.isEmpty
        ctx.spatialMaxFrames = 4096
        ctx.dmL = .allocate(capacity: 4096)
        ctx.dmR = .allocate(capacity: 4096)
        defer { ctx.dmL?.deallocate(); ctx.dmR?.deallocate() }

        let mixer = try #require(makeSpatialMixer(
            ctxPtr: Unmanaged.passUnretained(ctx).toOpaque(), maxFrames: 4096,
            mode: .dualPointStereo, algo: SpatAlgorithm.hrtfHQ.rawValue,
            algoName: "HRTF HQ", outputType: OutputType.headphones.rawValue,
            outputTypeName: "Headphones", hrtfMode: HRTFMode.off.rawValue, hrtfModeName: "Off",
            headTrack: 0, inputSampleRate: 48_000,
            renderFlags: kRenderFlagInterAuralDelay | kRenderFlagDistanceAtten,
            distanceParams: DistanceParams(referenceDistance: 0.35, maxDistance: 6, maxAttenuation: 24),
            attenCurve: AttenuationCurve.inverse.rawValue,
            pointCount: points.count, reverbEnabled: false, reverbRoomType: 0
        ))
        defer { AudioUnitUninitialize(mixer); AudioComponentInstanceDispose(mixer) }
        let engine = SpatialEngine()
        engine.config.elevation = elevation
        engine.config.distance = distance
        engine.config.stereoWidth = 22
        engine.config.points = points
        engine.config.soloPointID = soloID
        engine.config.nearFieldEnabled = nearField
        engine.applySourceParams(mixer: mixer)
        ctx.nearField.update(engine.config.nearFieldShelf)
        ctx.spatialize = true
        ctx.spatialMixer = mixer
        let heights = (0..<2).map { bus -> Float in
            var value: Float = .nan
            let status = AudioUnitGetParameter(mixer, kParamElevation, kAudioUnitScope_Input, UInt32(bus), &value)
            #expect(status == noErr)
            return value
        }

        let input = makeCaptureABL(maxFrames: block, channels: 2)
        let output = makeCaptureABL(maxFrames: block, channels: 2)
        defer {
            for list in [input, output] {
                for buf in list { buf.mData?.deallocate() }
                free(list.unsafeMutablePointer)
            }
        }
        input[0].mData!.assumingMemoryBound(to: Float.self)[0] = impulses.0
        input[1].mData!.assumingMemoryBound(to: Float.self)[rightSample] = impulses.1

        var result: [Float] = []
        for i in 0..<12 {
            ctx.ring.writeAll(from: input, frameCount: block)
            if i == 0 {
                input[0].mData!.assumingMemoryBound(to: Float.self)[0] = 0
                input[1].mData!.assumingMemoryBound(to: Float.self)[rightSample] = 0
            }
            var ts = AudioTimeStamp()
            ts.mSampleTime = Double(i) * Double(block)
            ts.mFlags = .sampleTimeValid
            for ch in 0..<2 { output[ch].mDataByteSize = block * 4 }
            var flags: AudioUnitRenderActionFlags = []
            try #require(playbackRenderCallback(Unmanaged.passUnretained(ctx).toOpaque(), &flags, &ts,
                                                0, block, output.unsafeMutablePointer) == noErr)
            for ch in 0..<2 {
                result.append(contentsOf: UnsafeBufferPointer(
                    start: output[ch].mData!.assumingMemoryBound(to: Float.self), count: Int(block)))
            }
        }
        return (result, heights)
    }
}
