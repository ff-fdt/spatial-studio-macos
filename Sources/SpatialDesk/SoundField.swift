import AppKit
import SwiftUI
import SpatialEngine
import simd

private let fieldPreset = SceneViewPreset.overview.angles
private let silver = Color(white: 0.91)
private let guideRadius = SourcePosition.sceneRadius(0.60)

private struct Camera {
    let size: CGSize
    let orientation: SIMD2<Double>
    var zoom: Double
    var focus: SIMD3<Double>
    var pan: CGSize
    var scale: Double { min(size.width, size.height) * 0.36 * zoom }
    var right: SIMD3<Double> {
        let a = orientation.x * .pi / 180
        return SIMD3(cos(a), 0, -sin(a))
    }
    var up: SIMD3<Double> {
        let a = orientation.x * .pi / 180
        let e = orientation.y * .pi / 180
        return SIMD3(sin(a) * sin(e), cos(e), cos(a) * sin(e))
    }
    // Acoustic +Z is the direction the listener faces, making these axes
    // left-handed when viewed over the listener's shoulder.
    var towardCamera: SIMD3<Double> { simd_cross(up, right) }

    func project(_ p: SIMD3<Double>) -> CGPoint {
        CGPoint(x: size.width * 0.5 + pan.width + scale * simd_dot(p - focus, right),
                y: size.height * 0.5 + pan.height - scale * simd_dot(p - focus, up))
    }
    var modelProjection: SIMD4<Float> {
        let center = project(.zero)
        let w = max(1, size.width), h = max(1, size.height)
        return SIMD4(Float(2 * scale / w), Float(2 * scale / h),
                     Float(2 * center.x / w - 1), Float(1 - 2 * center.y / h))
    }

}

private enum FieldDrag {
    case orbit(SIMD2<Double>)
    case pan(CGSize)
    case surface(UUID, Double)
    case point(UUID, SourcePosition, Camera, Bool)
    case marker(UUID, ListeningPosition)
}

struct SoundField: View {
    @Binding var points: [StereoPoint]
    @Binding var selected: UUID?
    @Binding var zoom: Double
    var viewRequest: ViewRequest
    var soloID: UUID?
    var inputNames: [String: String]
    var contextMenu: (UUID) -> NSMenu?
    var onManualMove: (UUID) -> Void
    var onDistanceChange: (UUID, Double) -> Void
    var onPlace: (UUID, ListeningPosition) -> Void
    var exitEarView: () -> Void
    @State private var appliedView = ViewRequest()
    @State private var earContacts: [UUID: SourcePosition] = [:]
    @State private var pan = CGSize.zero
    @State private var orientation = fieldPreset
    @State private var drag: FieldDrag?
    @State private var hover: CGPoint?

    var body: some View {
        GeometryReader { g in
            let changingView = appliedView != viewRequest
            let earSide = viewRequest.preset.earSide
            let focus = earSide.map { SIMD3($0 * 0.145, -0.009, -0.018) } ?? .zero
            let camera = Camera(size: g.size,
                                orientation: changingView ? viewRequest.preset.angles : orientation,
                                zoom: zoom, focus: focus, pan: earSide == nil || changingView ? .zero : pan)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in drawGuides(ctx, camera: camera) }
                Mannequin(right: camera.right, up: camera.up, toward: camera.towardCamera,
                          projection: camera.modelProjection)
                    .frame(width: g.size.width, height: g.size.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Canvas { ctx, _ in drawPoints(ctx, camera: camera) }.allowsHitTesting(false)
            }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { event in updateDrag(event, camera: camera) }
                    .onEnded { event in
                        finishDrag(event, camera: camera)
                        drag = nil; NSCursor.arrow.set()
                    })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        hover = p
                        if drag == nil {
                            let hit = closest(to: p, camera: camera)
                            let head = camera.project(.zero)
                            if hit != nil {
                                NSCursor.openHand.set()
                            } else if selected != nil, marker(at: p, camera: camera) != nil {
                                NSCursor.pointingHand.set()
                            } else if hypot(p.x - head.x, p.y - head.y) < max(30, camera.scale * 0.25) {
                                NSCursor.openHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                    case .ended:
                        hover = nil
                        if drag == nil { NSCursor.arrow.set() }
                    }
                }
                .background(FieldPointerEvents(onZoom: { factor, cursor in
                    guard drag == nil else { return }
                    let next = SceneZoom.clamped(zoom * factor)
                    if earSide != nil {
                        let delta = 1 - next / zoom
                        let center = camera.project(.zero)
                        pan.width += (cursor.x - center.x) * delta
                        pan.height += (cursor.y - center.y) * delta
                    }
                    zoom = next
                }, contextMenu: { location in
                    guard drag == nil, let hit = closest(to: location, camera: camera, preferSelection: true) else {
                        return nil
                    }
                    selected = hit.id
                    return contextMenu(hit.id)
                }))
                .accessibilityLabel(tr("三维声场"))
                .accessibilityChildren {
                    ForEach(points) { p in
                        Button(channelTitle(p.channel)) { selected = p.id }
                            .accessibilityValue(selected == p.id ? tr("已选中") : "")
                    }
                }

        }
        .clipped()
        .onChange(of: viewRequest) { _, request in
            orientation = request.preset.angles
            pan = .zero
            hover = nil
            drag = nil
            appliedView = request
        }
        .onChange(of: points.map(\.id)) { _, ids in
            earContacts = earContacts.filter { ids.contains($0.key) }
        }
    }

    private func location(_ point: StereoPoint, camera: Camera) -> CGPoint {
        camera.project(point.position.direction * SourcePosition.sceneRadius(point.position.distance))
    }

    private func closest(to p: CGPoint, camera: Camera, preferSelection: Bool = false) -> StereoPoint? {
        points.compactMap { point -> (StereoPoint, Double)? in
            let loc = location(point, camera: camera)
            let distance = hypot(loc.x - p.x, loc.y - p.y)
            return distance <= 22 ? (point, distance) : nil
        }.min {
            if abs($0.1 - $1.1) < 0.01 && $0.0.id != $1.0.id {
                if $0.0.id == selected { return preferSelection }
                if $1.0.id == selected { return !preferSelection }
            }
            return $0.1 < $1.1
        }?.0
    }

    private func updateDrag(_ event: DragGesture.Value, camera: Camera) {
        if drag == nil {
            let flags = NSEvent.modifierFlags
            if flags.contains(.shift), viewRequest.preset.earSide != nil {
                drag = .pan(pan)
                NSCursor.closedHand.set()
                return
            }
            if flags.contains(.command), let selected, let side = viewRequest.preset.earSide {
                drag = .surface(selected, side)
                return
            }
            let hit = closest(to: event.startLocation, camera: camera)
            if let selected, let label = marker(at: event.startLocation, camera: camera),
               (hit.map { distance(to: location($0, camera: camera), from: event.startLocation) } ?? .infinity)
                 > distance(to: label.position, from: event.startLocation) {
                drag = .marker(selected, label.preset)
                return
            }
            if let hit {
                selected = hit.id
                drag = .point(hit.id, hit.position, camera, NSEvent.modifierFlags.contains(.option))
                NSCursor.closedHand.set()
            } else {
                let head = camera.project(.zero)
                let distance = hypot(event.startLocation.x - head.x, event.startLocation.y - head.y)
                if distance < max(30, camera.scale * 0.25) {
                    drag = .orbit(orientation)
                    NSCursor.closedHand.set()
                } else {
                    selected = nil
                    drag = .orbit(orientation)
                }
            }
        }

        let dx = event.translation.width
        let dy = event.translation.height
        switch drag {
        case .orbit(let from):
            orientation = SIMD2((from.x - dx * 0.55).truncatingRemainder(dividingBy: 360),
                                min(max(from.y + dy * 0.55, -90), 90))
        case .pan(let from):
            pan = CGSize(width: from.width + dx, height: from.height + dy)
        case .point(let id, let from, let anchor, let radial):
            guard let index = points.firstIndex(where: { $0.id == id }), hypot(dx, dy) >= 2 else { return }
            if radial {
                let distance = min(6, max(0, (from.distance + 0.06) * exp(-dy / (95 * max(1, sqrt(anchor.zoom)))) - 0.06))
                onDistanceChange(id, distance)
                return
            }
            onManualMove(id)
            points[index].position = from.dragged(right: anchor.right, up: anchor.up,
                                                  horizontal: dx / anchor.scale, vertical: -dy / anchor.scale)
        case .marker, .surface, .none: break
        }
    }

    private func isInHeadDropZone(_ point: StereoPoint, camera: Camera) -> Bool {
        guard viewRequest.preset.earSide == nil else { return false }
        let loc = location(point, camera: camera)
        let head = camera.project(.zero)
        return hypot(loc.x - head.x, loc.y - head.y) < 17
    }

    private func finishDrag(_ event: DragGesture.Value, camera: Camera) {
        if case .orbit = drag, let side = viewRequest.preset.earSide {
            let updated = Camera(size: camera.size, orientation: orientation, zoom: zoom,
                                 focus: camera.focus, pan: pan)
            if updated.towardCamera.x * side < 0.55 { exitEarView() }
            return
        }
        if case .surface(let id, let side) = drag {
            guard hypot(event.translation.width, event.translation.height) < 5,
                  camera.towardCamera.x * side > 0.55,
                  let i = points.firstIndex(where: { $0.id == id }) else { return }
            let center = camera.project(.zero)
            let uv = SIMD2((event.location.x - center.x) / camera.scale, (center.y - event.location.y) / camera.scale)
            if let hit = EarSurface.hit(side: side, uv: uv, right: camera.right, up: camera.up,
                                        toward: camera.towardCamera) {
                onManualMove(id)
                let position = SourcePosition(scenePoint: hit)
                points[i].position = position
                earContacts[id] = position
            }
            return
        }
        if case .marker(let id, let preset) = drag {
            if hypot(event.translation.width, event.translation.height) < 7 { onPlace(id, preset) }
            return
        }
        guard case .point(let id, _, _, false) = drag,
              hypot(event.translation.width, event.translation.height) > 4,
              let i = points.firstIndex(where: { $0.id == id }),
              isInHeadDropZone(points[i], camera: camera) else { return }
        points[i].position.distance = 0
    }

    private func distance(to p: CGPoint, from q: CGPoint) -> Double {
        hypot(p.x - q.x, p.y - q.y)
    }

    private func marker(at location: CGPoint, camera: Camera) -> DirectionMarker? {
        directionMarkers(camera: camera)
            .filter { abs($0.position.x - location.x) <= ($0.title.count > 1 ? 20 : 14) &&
                      abs($0.position.y - location.y) <= 11 }
            .min { distance(to: $0.position, from: location) < distance(to: $1.position, from: location) }
    }

    private func drawGuides(_ ctx: GraphicsContext, camera: Camera) {
        drawSphereGuide(ctx, camera: camera, center: camera.project(.zero))
        let highlighted = selected == nil ? nil : hover.flatMap { marker(at: $0, camera: camera)?.preset }
        for marker in directionMarkers(camera: camera) {
            let active = highlighted == marker.preset
            if active {
                let w = marker.title.count > 1 ? 37.0 : 25.0
                let rect = CGRect(x: marker.position.x - w / 2, y: marker.position.y - 10, width: w, height: 20)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 10), with: .color(.white.opacity(0.09)))
            }
            ctx.draw(
                Text(marker.title).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(active ? 0.96 : selected == nil ? 0.46 : 0.69)),
                at: marker.position
            )
        }
    }

    private func directionMarkers(camera: Camera) -> [DirectionMarker] {
        let center = camera.project(.zero)
        if viewRequest.preset.earSide != nil, zoom >= 8 { return [] }
        let axes: [(SIMD3<Double>, String, ListeningPosition)] = [
            (SIMD3(-1, 0, 0), tr("左耳"), .leftEar), (SIMD3(1, 0, 0), tr("右耳"), .rightEar),
            (SIMD3(0, 0, 1), tr("前"), .front), (SIMD3(0, 0, -1), tr("后"), .back),
            (SIMD3(0, 1, 0), tr("上"), .above), (SIMD3(0, -1, 0), tr("下"), .below)
        ]
        var labels: [DirectionMarker] = []
        for (end, title, preset) in axes {
            let pt = camera.project(end * (guideRadius + 0.19))
            let inside = CGPoint(x: min(camera.size.width - 79, max(33, pt.x)),
                                 y: min(camera.size.height - 69, max(41, pt.y)))
            guard hypot(pt.x - center.x, pt.y - center.y) > 37,
                  !labels.contains(where: { hypot($0.position.x - inside.x, $0.position.y - inside.y) < 22 }) else { continue }
            labels.append(DirectionMarker(title: title, preset: preset, position: inside))
        }
        return labels
    }

    private func drawSphereGuide(_ ctx: GraphicsContext, camera: Camera, center: CGPoint) {
        let radius = camera.scale * guideRadius
        let shell = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: 2 * radius, height: 2 * radius))
        ctx.stroke(shell, with: .color(Color.white.opacity(0.16)), lineWidth: 0.9)

        // Project one equatorial ring. Fade it where it reads as a straight line
        // or almost completely overlaps the sphere silhouette.
        let aspect = abs(camera.towardCamera.y)
        let fade = max(0, min(1, (aspect - 0.12) / 0.22, (0.985 - aspect) / 0.12))
        guard fade > 0 else { return }
        let halfHeight = radius * aspect
        let equator = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - halfHeight,
                                            width: 2 * radius, height: 2 * halfHeight))
        ctx.stroke(equator, with: .color(Color.white.opacity(0.105 * fade)), lineWidth: 0.85)
    }

    private func drawPoints(_ ctx: GraphicsContext, camera: Camera) {
        for p in points.sorted(by: {
            ($0.id == selected ? 3 : simd_dot($0.position.direction, camera.towardCamera)) <
            ($1.id == selected ? 3 : simd_dot($1.position.direction, camera.towardCamera))
        }) {
            let loc = location(p, camera: camera)
            let focused = p.id == selected
            let dimmed = soloID != nil && soloID != p.id
            let pointColor = silver.opacity(dimmed ? 0.30 : 1)
            let highlighted = focused || (hover.map { hypot($0.x - loc.x, $0.y - loc.y) < 19 } ?? false)
            let ring = Path(ellipseIn: CGRect(x: loc.x - 12, y: loc.y - 12, width: 24, height: 24))
            let dot = Path(ellipseIn: CGRect(x: loc.x - 4, y: loc.y - 4, width: 8, height: 8))
            if highlighted {
                ctx.fill(ring, with: .color(pointColor.opacity(0.10)))
                ctx.stroke(ring, with: .color(pointColor.opacity(0.64)), lineWidth: 0.9)
            }
            let earContact = earContacts[p.id] == p.position
            if earContact {
                let diamond = Path {
                    $0.move(to: CGPoint(x: loc.x, y: loc.y - 6))
                    $0.addLine(to: CGPoint(x: loc.x + 6, y: loc.y))
                    $0.addLine(to: CGPoint(x: loc.x, y: loc.y + 6))
                    $0.addLine(to: CGPoint(x: loc.x - 6, y: loc.y))
                    $0.closeSubpath()
                }
                ctx.fill(diamond, with: .color(.black.opacity(0.62)))
                ctx.stroke(diamond, with: .color(pointColor), lineWidth: 1.4)
                if focused {
                    ctx.draw(Text(tr("耳廓表面")).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(pointColor), at: CGPoint(x: loc.x, y: loc.y - 22))
                }
            } else {
                ctx.fill(dot, with: .color(pointColor))
            }
            let headTarget: Bool
            if case .point(let id, _, _, false) = drag {
                headTarget = id == p.id && isInHeadDropZone(p, camera: camera)
            } else { headTarget = false }
            if focused && !earContact && (p.position.distance < 0.12 || headTarget) {
                ctx.draw(Text(tr("脑内")).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(silver), at: CGPoint(x: loc.x, y: loc.y - 21))
            }
            let label = p.channel == .left ? "L" : p.channel == .right ? "R" : "L·R"
            let title = p.inputID.flatMap { inputNames[$0] }
            let caption = title.map { "\($0.prefix(18)) · \(label)" } ?? label
            ctx.draw(Text(caption).font(.system(size: 10, weight: .medium))
                .foregroundStyle(pointColor.opacity(0.83)), at: CGPoint(x: loc.x, y: loc.y + 20))
        }
    }
}


private struct DirectionMarker: Identifiable {
    let title: String
    let preset: ListeningPosition
    let position: CGPoint
    var id: ListeningPosition { preset }
}
