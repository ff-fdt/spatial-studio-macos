import AppKit
import SwiftUI
import SpatialEngine

struct DeskView: View {
    @ObservedObject var audio: DeskAudio
    @State private var points: [StereoPoint] = [
        StereoPoint(position: SourcePosition(azimuth: -48, elevation: 8, distance: 0.30), channel: .stereo)
    ]
    @State private var selected: UUID?
    @State private var soloID: UUID?
    @State private var showDetails = false
    @State private var showMovements = false
    @State private var viewRequest = ViewRequest()
    @State private var zoom = SceneZoom.initial
    @State private var movements: [UUID: ActiveSourceMovement] = [:]
    @State private var rightEndOfAzimuth: Set<UUID> = []
    @FocusState private var sceneHasFocus: Bool
    @FocusState private var focusedMovement: SourceMovement?
    @FocusState private var detailsHeadingFocused: Bool
    private let limit = 8
    private let gainRange = -72.0...18.0

    private var config: SpatialConfig {
        var c = SpatialConfig()
        c.algorithm = .hrtfHQ
        c.hrtfMode = .auto
        c.headTracking = false
        c.points = points
        c.soloPointID = soloID
        c.nearFieldEnabled = true
        c.distanceAttenuation = true
        c.distanceRef = 0.35
        c.distanceMaxAtten = 24
        c.reverbEnabled = false
        return c
    }

    var body: some View {
        SoundField(points: $points, selected: $selected, zoom: $zoom, viewRequest: viewRequest, soloID: soloID,
                   inputNames: Dictionary(uniqueKeysWithValues: audio.inputs.map { ($0.id, $0.name) }),
                   contextMenu: pointContextMenu(for:), onManualMove: manualMove,
                   onDistanceChange: changeDistance(_:to:), onPlace: place(_:at:),
                   exitEarView: { setView(.overview) })
            .focusable()
            .focused($sceneHasFocus)
            .focusEffectDisabled()
            .overlay(alignment: .leading) {
                if let selected { movementMenu(for: selected).padding(.leading, 14) }
            }
            .overlay(alignment: .trailing) { viewControls.padding(.trailing, 14) }
            .overlay(alignment: .topLeading) {
                if viewRequest.preset.earSide != nil {
                    VStack(alignment: .leading, spacing: 7) {
                        Button(tr("退出近看")) { setView(.overview) }
                            .buttonStyle(.glass(.regular.interactive()))
                            .buttonBorderShape(.capsule)
                            .keyboardShortcut(.escape, modifiers: [])
                        Text(tr("选中光点后，⌘ 点耳廓定位；⇧ 拖动画面"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
            }
            .overlay(alignment: .topTrailing) { playControl.padding(.top, 13).padding(.trailing, 16) }
            .overlay(alignment: .bottom) { controls.padding(.bottom, 20) }
            .overlay(alignment: .bottomTrailing) { zoomControls.padding(.trailing, 16).padding(.bottom, 20) }
            .overlay(alignment: .bottomLeading) {
                if let message = audio.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .glassEffect(in: .rect(cornerRadius: 12))
                        .padding(16).padding(.bottom, 54)
                }
            }
            .background(Color(white: 0.07).ignoresSafeArea())
            .defaultFocus($sceneHasFocus, true)
            .onDeleteCommand { if let selected { deletePoint(selected) } }
            .onChange(of: selected) { _, value in
                if value == nil { showMovements = false }
                if !showDetails { sceneHasFocus = true }
            }
            .onChange(of: zoom) { _, value in
                if viewRequest.preset.earSide != nil, value < SceneZoom.earExitThreshold { setView(.overview) }
            }
            .onChange(of: config) { _, value in audio.apply(value) }
            .task(id: movements.isEmpty) { await animateMovements() }
    }

    private var viewControls: some View {
        GlassEffectContainer(spacing: 5) {
            VStack(spacing: 6) {
                ForEach(SceneViewPreset.allCases.filter { $0 != .overview }) { preset in
                    Button { setView(preset) } label: {
                        Text(tr(preset.rawValue)).frame(minWidth: 31)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(preset.key)), modifiers: .command)
                    .help(tr(preset.rawValue) + " · ⌘\(preset.key)")
                }
            }
            .font(.caption)
            .buttonStyle(.glass(.regular.interactive()))
            .buttonBorderShape(.capsule)
        }
    }

    private func setView(_ preset: SceneViewPreset) {
        let leavingEarView = viewRequest.preset.earSide != nil
        viewRequest = ViewRequest(preset: preset, revision: viewRequest.revision + 1)
        if preset.earSide != nil { zoom = 12 }
        else if preset == .overview || leavingEarView { zoom = SceneZoom.initial }
    }

    private var playControl: some View {
        Button {
            audio.setEnabled(!audio.running, config: config)
        } label: {
            Label(audio.running ? tr("恢复原声") : tr("开始处理"), systemImage: audio.running ? "power.circle.fill" : "power")
                .padding(.horizontal, 3)
        }
        .buttonStyle(.glass(.regular.interactive()))
        .buttonBorderShape(.capsule)
        .help(audio.device.isEmpty ? tr("系统声音") : tr("系统声音") + " → " + audio.device)
    }

    private var zoomControls: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                Button { zoom = SceneZoom.clamped(zoom / SceneZoom.step) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .accessibilityLabel(tr("缩小声场"))
                .keyboardShortcut("-", modifiers: .command)
                .disabled(zoom <= SceneZoom.minimum)
                Button { zoom = SceneZoom.clamped(zoom * SceneZoom.step) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .accessibilityLabel(tr("放大声场"))
                .keyboardShortcut("=", modifiers: .command)
                .disabled(zoom >= SceneZoom.maximum)
            }
            .buttonStyle(.glass(.regular.interactive()))
            .buttonBorderShape(.circle)
            .help(tr("缩放声场 · 滚轮或双指捏合"))
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 9) {
                Button {
                    addPoint()
                } label: {
                    Image(systemName: "plus").frame(width: 23, height: 25)
                }
                .buttonStyle(.glass(.regular.interactive()))
                .buttonBorderShape(.circle)
                .accessibilityLabel(tr("添加光点"))
                .help(tr("添加光点"))
                .disabled(points.count >= limit)

                if let index = points.firstIndex(where: { $0.id == selected }) {
                    if points.count > 1 || soloID != nil {
                        Button { toggleSolo(points[index].id) } label: {
                            Label(soloID == points[index].id ? tr("取消独听") : tr("独听"),
                                  systemImage: soloID == points[index].id ? "headphones.circle.fill" : "headphones")
                        }
                        .buttonStyle(.glass(.regular.interactive()))
                        .buttonBorderShape(.capsule)
                        .help(tr("只播放当前光点"))
                    }

                    Button {
                        showDetails.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                            Text(channelTitle(points[index].channel))
                        }.frame(minWidth: 62, minHeight: 25)
                    }
                    .buttonStyle(.glass(.regular.interactive()))
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel(tr("光点设置"))
                    .help(tr("声道、位置与音量"))
                    .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                        if let index = points.firstIndex(where: { $0.id == selected }) {
                            pointDetails(at: index)
                        }
                    }
                }

                Button {
                    setView(.overview)
                } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 23, height: 25)
                }
                .buttonStyle(.glass(.regular.interactive()))
                .buttonBorderShape(.circle)
                .accessibilityLabel(tr("复位视角"))
                .keyboardShortcut("0", modifiers: .command)
                .help(tr("复位视角"))
            }
        }
    }

    private func pointDetails(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(tr("光点设置"))
                .font(.callout.weight(.semibold))
                .focusable()
                .focused($detailsHeadingFocused)
                .focusEffectDisabled()
            inputMenu(at: index)
            Picker(tr("声道"), selection: $points[index].channel) {
                Text(tr("左")).tag(StereoChannel.left)
                Text(tr("右")).tag(StereoChannel.right)
                Text(tr("立体声")).tag(StereoChannel.stereo)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .neutralFocus()

            let id = points[index].id
            let moving = movements[id] != nil
            control(moving ? tr("基准方位") : tr("方位"), value: azimuthBinding(for: id), range: 0...360, unit: "°")
            control(moving ? tr("基准高度") : tr("高度"), value: positionValue(id, \.elevation), range: -90...90, unit: "°")
            control(moving ? tr("基准距离") : tr("距离"), value: positionValue(id, \.distance), range: 0...6, unit: " m", digits: 2)
            if moving {
                control(tr("移动速度"), value: movementSpeed(for: id), range: 0.25...2, unit: "×", digits: 2)
            }
            volumeControl(for: id)
            HStack {
                Spacer()
                Button(role: .destructive) { deletePoint(points[index].id) } label: {
                    Image(systemName: "trash")
                }
                .help(tr("删除光点"))
            }.buttonStyle(.borderless)
        }
        .padding(17)
        .frame(width: 260)
        .defaultFocus($detailsHeadingFocused, true)
        .tint(.white)
    }

    private func place(_ pointID: UUID, at preset: ListeningPosition) {
        guard let index = points.firstIndex(where: { $0.id == pointID }) else { return }
        manualMove(pointID)
        points[index].position = preset.placed(from: points[index].position)
    }

    private func deletePoint(_ pointID: UUID) {
        guard let index = points.firstIndex(where: { $0.id == pointID }) else { return }
        showDetails = false
        manualMove(pointID)
        points.remove(at: index)
        if soloID == pointID { soloID = nil }
        if selected == pointID { selected = points.indices.contains(index) ? points[index].id : points.last?.id }
    }

    private func duplicatePoint(_ pointID: UUID) {
        guard points.count < limit, let source = points.first(where: { $0.id == pointID }) else { return }
        var next = source.position
        next.azimuth = (next.azimuth + 198).truncatingRemainder(dividingBy: 360) - 180
        if abs(next.elevation) > 75 { next.elevation *= 0.8 }
        if next.distance < 0.12 { next.distance = 0.40 }
        let duplicate = StereoPoint(position: next, channel: source.channel, gain: source.gain, inputID: source.inputID)
        points.append(duplicate)
        selected = duplicate.id
    }

    private func toggleSolo(_ pointID: UUID) {
        guard points.contains(where: { $0.id == pointID }) else { return }
        soloID = soloID == pointID ? nil : pointID
    }

    private func pointContextMenu(for pointID: UUID) -> NSMenu? {
        guard points.contains(where: { $0.id == pointID }) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(PointMenuAction.item(tr("光点设置")) {
            selected = pointID
            showDetails = true
        })
        menu.addItem(PointMenuAction.item(soloID == pointID ? tr("取消独听") : tr("独听此光点")) { toggleSolo(pointID) })
        menu.addItem(PointMenuAction.item(tr("复制光点"), enabled: points.count < limit) { duplicatePoint(pointID) })
        let positions = NSMenu(title: tr("快速定位"))
        positions.autoenablesItems = false
        for preset in ListeningPosition.allCases {
            positions.addItem(PointMenuAction.item(tr(preset.rawValue)) { place(pointID, at: preset) })
        }
        let list = NSMenuItem(title: tr("快速定位"), action: nil, keyEquivalent: "")
        list.submenu = positions
        menu.addItem(list)
        let motions = NSMenu(title: tr("自动移动"))
        motions.autoenablesItems = false
        if let running = movements[pointID]?.pattern {
            motions.addItem(PointMenuAction.item(tr("正在运行：") + tr(running.rawValue), enabled: false) {})
            motions.addItem(.separator())
        }
        for motion in SourceMovement.allCases {
            let item = PointMenuAction.item(tr(motion.rawValue)) { startMovement(motion, for: pointID) }
            item.state = movements[pointID]?.pattern == motion ? .on : .off
            motions.addItem(item)
        }
        motions.addItem(.separator())
        motions.addItem(PointMenuAction.item(tr("停止移动"), enabled: movements[pointID] != nil) { stopMovement(pointID) })
        let movement = NSMenuItem(title: tr("自动移动"), action: nil, keyEquivalent: "")
        movement.submenu = motions
        menu.addItem(movement)
        menu.addItem(.separator())
        menu.addItem(PointMenuAction.item(tr("删除光点")) { deletePoint(pointID) })
        return menu
    }

    private func movementMenu(for pointID: UUID) -> some View {
        let active = movements[pointID]?.pattern
        return Button {
            showMovements.toggle()
        } label: {
            Label(active.map { tr($0.rawValue) } ?? tr("自动"), systemImage: active == nil ? "arrow.clockwise" : "arrow.clockwise.circle.fill")
                .font(.caption.weight(.medium))
                .frame(minHeight: 24)
        }
        .buttonStyle(.glass(.regular.interactive()))
        .buttonBorderShape(.capsule)
        .accessibilityLabel(tr("自动移动"))
        .accessibilityValue(active.map { tr($0.rawValue) } ?? tr("静止"))
        .help(active.map { tr($0.rawValue) } ?? tr("自动移动"))
        .popover(isPresented: $showMovements, arrowEdge: .trailing) {
            if let selected { movementPanel(for: selected) }
        }
    }

    private func movementPanel(for id: UUID) -> some View {
        let active = movements[id]?.pattern
        return VStack(alignment: .leading, spacing: 9) {
            Text(active.map { tr("正在运行：") + tr($0.rawValue) } ?? tr("自动移动"))
                .font(.callout.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(SourceMovement.Group.allCases) { group in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr(group.rawValue)).font(.caption).foregroundStyle(.secondary)
                            ForEach(SourceMovement.allCases.filter { $0.group == group }) { motion in
                                Button {
                                    if motion != active { startMovement(motion, for: id) }
                                } label: {
                                    HStack {
                                        Text(tr(motion.rawValue))
                                        Spacer(minLength: 8)
                                        if motion == active { Image(systemName: "checkmark") }
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(.white.opacity(active == motion ? 0.14 : focusedMovement == motion ? 0.09 : 0),
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .focused($focusedMovement, equals: motion)
                                .focusEffectDisabled()
                                .accessibilityAddTraits(motion == active ? .isSelected : [])
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 326)
            if active != nil {
                Button(tr("停止移动")) { stopMovement(id) }
                    .buttonStyle(.glass(.regular.interactive()))
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(14)
        .frame(width: 197)
    }

    private func startMovement(_ preset: SourceMovement, for id: UUID) {
        guard let point = points.first(where: { $0.id == id }) else { return }
        rightEndOfAzimuth.remove(id)
        movements[id] = ActiveSourceMovement(pattern: preset, from: point.position,
                                             now: ProcessInfo.processInfo.systemUptime)
    }

    private func stopMovement(_ id: UUID) {
        if movements[id] != nil { movements.removeValue(forKey: id) }
    }

    private func animateMovements() async {
        while !Task.isCancelled && !movements.isEmpty {
            let now = ProcessInfo.processInfo.systemUptime
            var updated = points
            for i in updated.indices {
                guard let movement = movements[updated[i].id] else { continue }
                updated[i].position = movement.position(now: now)
            }
            if updated != points { points = updated }
            do { try await Task.sleep(for: .milliseconds(22)) }
            catch { return }
        }
    }

    private func manualMove(_ id: UUID) {
        stopMovement(id)
        if rightEndOfAzimuth.contains(id) { rightEndOfAzimuth.remove(id) }
    }

    private func azimuthBinding(for id: UUID) -> Binding<Double> {
        Binding {
            let current = movements[id]?.reference ?? points.first(where: { $0.id == id })?.position
            let angle = current?.azimuth360 ?? 0
            return angle == 0 && rightEndOfAzimuth.contains(id) ? 360 : angle
        } set: { value in
            guard let index = points.firstIndex(where: { $0.id == id }) else { return }
            if value >= 360 { rightEndOfAzimuth.insert(id) }
            else { rightEndOfAzimuth.remove(id) }
            if var movement = movements[id] {
                movement.reference.azimuth360 = value
                movements[id] = movement
            } else {
                points[index].position.azimuth360 = value
            }
        }
    }

    private func positionValue(_ pointID: UUID, _ field: WritableKeyPath<SourcePosition, Double>) -> Binding<Double> {
        Binding {
            let current = movements[pointID]?.reference ?? points.first(where: { $0.id == pointID })?.position
            return current?[keyPath: field] ?? 0
        } set: { value in
            guard let index = points.firstIndex(where: { $0.id == pointID }) else { return }
            if var movement = movements[pointID] {
                movement.reference[keyPath: field] = value
                movements[pointID] = movement
            } else {
                points[index].position[keyPath: field] = value
            }
        }
    }

    private func changeDistance(_ id: UUID, to distance: Double) {
        guard let index = points.firstIndex(where: { $0.id == id }) else { return }
        if var movement = movements[id] {
            movement.setInstantaneousDistance(distance, now: ProcessInfo.processInfo.systemUptime)
            movements[id] = movement
        } else {
            points[index].position.distance = distance
        }
    }

    private func movementSpeed(for id: UUID) -> Binding<Double> {
        Binding {
            movements[id]?.speed ?? 1
        } set: { value in
            guard var movement = movements[id] else { return }
            movement.setSpeed(value, now: ProcessInfo.processInfo.systemUptime)
            movements[id] = movement
        }
    }

    private func volumeControl(for id: UUID) -> some View {
        let gain = Binding<Double> {
            Double(points.first(where: { $0.id == id })?.gain ?? 0)
        } set: { value in
            guard value.isFinite, let i = points.firstIndex(where: { $0.id == id }) else { return }
            let db = min(gainRange.upperBound, max(gainRange.lowerBound, value))
            points[i].gain = Float((db * 10).rounded() / 10)
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(tr("音量"))
                Spacer()
                TextField(tr("音量数值"), value: gain, format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 49)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                    .neutralFocus()
                Text("dB").foregroundStyle(.secondary)
            }
            .font(.caption)
            GainSlider(value: gain, range: gainRange, label: tr("音量"))
                .frame(height: 20)
        }
    }

    private func inputMenu(at index: Int) -> some View {
        let current = points[index].inputID
        let name = current.map { id in audio.inputs.first(where: { $0.id == id })?.name ?? tr("等待输入") } ?? tr("系统声音")
        return HStack(spacing: 14) {
            Text(tr("输入")).font(.callout)
            Menu {
                Button {
                    points[index].inputID = nil
                } label: {
                    if current == nil { Label(tr("系统声音"), systemImage: "checkmark") }
                    else { Text(tr("系统声音")) }
                }
                ForEach(audio.inputs) { input in
                    Button {
                        points[index].inputID = input.id
                    } label: {
                        if current == input.id { Label(input.name, systemImage: "checkmark") }
                        else { Text(input.name) }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(name).lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel(tr("输入"))
            .accessibilityValue(name)
            .neutralFocus()
            .onAppear { audio.refreshInputs() }
        }
    }

    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                         unit: String, digits: Int = 1) -> some View {
        let current = value.wrappedValue.formatted(.number.precision(.fractionLength(digits))) + unit
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(current).monospacedDigit().foregroundStyle(.secondary)
            }.font(.caption)
            Slider(value: value, in: range) { Text(title) }
                .labelsHidden().accessibilityValue(current).neutralFocus()
        }
    }

    private func addPoint() {
        guard points.count < limit else { return }
        let new = StereoPoint(
            position: SourcePosition(azimuth: -125 + Double(max(0, points.count - 2)) * 34, elevation: 30, distance: 1.1),
            channel: .stereo
        )
        points.append(new)
        selected = new.id
    }

}

func channelTitle(_ channel: StereoChannel) -> String {
    switch channel {
    case .left: tr("左声道")
    case .right: tr("右声道")
    case .stereo: tr("立体声")
    }
}


@MainActor
private final class PointMenuAction: NSObject {
    let perform: () -> Void

    init(_ perform: @escaping () -> Void) { self.perform = perform }

    @objc func select() { perform() }

    static func item(_ title: String, enabled: Bool = true, perform: @escaping () -> Void) -> NSMenuItem {
        let target = PointMenuAction(perform)
        let item = NSMenuItem(title: title, action: #selector(select), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        item.isEnabled = enabled
        return item
    }
}
