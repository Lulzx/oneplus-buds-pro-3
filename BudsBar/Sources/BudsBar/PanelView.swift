import SwiftUI

struct PanelView: View {
    @Environment(Buds.self) private var buds

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeaderView()
            if buds.link == .connected {
                BatteryRow()
                NoiseControlSection()
                SoundSection()
                FeaturesSection()
            } else {
                DisconnectedView()
            }
            FooterView()
        }
        .padding(16)
        .frame(width: 348)
        .animation(.smooth(duration: 0.25), value: buds.link)
        .onAppear { buds.refresh() }
    }
}

// MARK: - Header

private struct HeaderView: View {
    @Environment(Buds.self) private var buds

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "earbuds")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(buds.deviceName).font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var statusText: String {
        switch buds.link {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .disconnected: "Not connected"
        case .searching: "Not paired"
        }
    }

    private var statusColor: Color {
        switch buds.link {
        case .connected: .green
        case .connecting: .orange
        case .disconnected, .searching: .secondary
        }
    }
}

// MARK: - Battery

private struct BatteryRow: View {
    @Environment(Buds.self) private var buds

    var body: some View {
        HStack(spacing: 8) {
            BatteryTile(title: "Left", symbol: "l.circle", battery: buds.left, detail: buds.leftWear?.label)
            BatteryTile(title: "Right", symbol: "r.circle", battery: buds.right, detail: buds.rightWear?.label)
            BatteryTile(title: "Case", symbol: "earbuds.case", battery: buds.caseBattery, detail: nil)
        }
    }
}

private struct BatteryTile: View {
    let title: String
    let symbol: String
    let battery: Battery?
    let detail: String?

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Gauge(value: Double(battery?.level ?? 0), in: 0...100) {
                    Image(systemName: symbol)
                } currentValueLabel: {
                    Text(battery.map { "\($0.level)" } ?? "–")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(tint)
                if battery?.charging == true {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(3)
                        .glassEffect(.regular, in: .circle)
                        .offset(x: 4, y: -4)
                }
            }
            VStack(spacing: 0) {
                Text(title).font(.caption.weight(.medium))
                Text(detail ?? (battery == nil ? "Unavailable" : " "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        .opacity(battery == nil ? 0.5 : 1)
    }

    private var tint: Color {
        guard let level = battery?.level else { return .secondary }
        return level <= 15 ? .red : level <= 30 ? .orange : .green
    }
}

// MARK: - Noise control

private struct NoiseControlSection: View {
    @Environment(Buds.self) private var buds
    @Namespace private var glass

    nonisolated private enum Choice: CaseIterable { case off, transparency, adaptive, anc }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Noise Control")
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Choice.allCases, id: \.self) { choice in
                        ModeButton(
                            title: title(choice), symbol: symbol(choice),
                            selected: current == choice
                        ) { select(choice) }
                        .glassEffectID(choice, in: glass)
                    }
                }
            }
            .disabled(!buds.anyBudInEar)

            if current == .anc, let noise = buds.noise {
                Picker("Depth", selection: Binding(get: { noise }, set: { buds.setNoise($0) })) {
                    ForEach([NoiseMode.light, .moderate, .deep]) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let notice = buds.notice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
                    .transition(.opacity)
            } else if !buds.anyBudInEar {
                Text("Wear at least one bud to change noise control.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .animation(.smooth(duration: 0.25), value: buds.noise)
        .animation(.smooth(duration: 0.25), value: buds.notice)
    }

    private var current: Choice? {
        switch buds.noise {
        case .off: .off
        case .transparency: .transparency
        case .smart: .adaptive
        case .deep, .moderate, .light: .anc
        case nil: nil
        }
    }

    private func select(_ c: Choice) {
        switch c {
        case .off: buds.setNoise(.off)
        case .transparency: buds.setNoise(.transparency)
        case .adaptive: buds.setNoise(.smart)
        case .anc: if current != .anc { buds.setNoise(.deep) }
        }
    }

    private func title(_ c: Choice) -> String {
        switch c { case .off: "Off"; case .transparency: "Aware"; case .adaptive: "Adaptive"; case .anc: "ANC" }
    }

    private func symbol(_ c: Choice) -> String {
        switch c {
        case .off: "circle.slash"
        case .transparency: "ear"
        case .adaptive: "sparkles"
        case .anc: "waveform.badge.minus"
        }
    }
}

private struct ModeButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                Text(title).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 14))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Sound

private struct SoundSection: View {
    @Environment(Buds.self) private var buds

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Sound")
            Row("Equalizer", symbol: "slider.vertical.3") {
                Picker("Equalizer", selection: Binding(get: { buds.eq ?? .balanced }, set: { buds.setEQ($0) })) {
                    ForEach(EQPreset.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("Spatial Audio", systemImage: "move.3d").font(.callout)
                Picker("Spatial Audio", selection: Binding(get: { buds.spatial ?? .off }, set: { buds.setSpatial($0) })) {
                    ForEach(SpatialMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if buds.has(.bassWave) {
                FeatureToggle("BassWave", symbol: "speaker.wave.3", feature: .bassWave)
                if buds.isOn(.bassWave), let level = buds.bassLevel {
                    HStack(spacing: 8) {
                        Image(systemName: "minus").font(.caption2).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { Double(level) }, set: { buds.setBassLevel(Int($0.rounded())) }),
                               in: -5...5, step: 1)
                        Image(systemName: "plus").font(.caption2).foregroundStyle(.secondary)
                        Text(level > 0 ? "+\(level)" : "\(level)")
                            .font(.caption.monospacedDigit()).frame(width: 22, alignment: .trailing)
                    }
                    .padding(.leading, 26)
                }
            }
        }
    }
}

// MARK: - Features

private struct FeaturesSection: View {
    @Environment(Buds.self) private var buds

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Controls")
            if buds.has(.gameMode) { FeatureToggle("Game Mode", symbol: "gamecontroller", feature: .gameMode) }
            if buds.has(.wearDetection) { FeatureToggle("In-Ear Detection", symbol: "ear.badge.checkmark", feature: .wearDetection) }
            if buds.has(.dualConnection) { FeatureToggle("Dual Connection", symbol: "laptopcomputer.and.iphone", feature: .dualConnection) }
            Row("Find My Buds", symbol: "speaker.wave.2.bubble") {
                Button(buds.findingBuds ? "Stop" : "Play Sound") { buds.toggleFindBuds() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(buds.anyBudInEar && !buds.findingBuds)
                    .help(buds.anyBudInEar ? "Take the buds out first. The tone is loud." : "Plays a loud tone on both buds")
            }
        }
    }
}

// MARK: - Disconnected / footer

private struct DisconnectedView: View {
    @Environment(Buds.self) private var buds

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "earbuds.case")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(buds.link == .searching ? "Pair your buds in Bluetooth settings." : "Open the case near your Mac to connect.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Retry") { buds.refresh() }.buttonStyle(.glass)
                Button("Bluetooth Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct FooterView: View {
    @Environment(Buds.self) private var buds
    @State private var autoStart = AutoStart.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
        Divider()
        Toggle(isOn: $autoStart) {
            Label("Open when buds connect", systemImage: "bolt.horizontal.circle").font(.callout)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .onChange(of: autoStart) { _, on in AutoStart.set(on) }
        .help("Runs BudsBar quietly at login; the icon appears when your buds connect.")
        HStack {
            if let fw = buds.firmware, buds.link == .connected {
                Text("Firmware \(fw)").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button { buds.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                        .help("Quit BudsBar")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
            }
        }
        }
    }
}

// MARK: - Building blocks

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }
}

private struct Row<Trailing: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let trailing: Trailing

    init(_ title: String, symbol: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.symbol = symbol; self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Label(title, systemImage: symbol).font(.callout)
            Spacer()
            trailing
        }
    }
}

private struct FeatureToggle: View {
    @Environment(Buds.self) private var buds
    let title: String
    let symbol: String
    let feature: Feature

    init(_ title: String, symbol: String, feature: Feature) {
        self.title = title; self.symbol = symbol; self.feature = feature
    }

    var body: some View {
        Toggle(isOn: Binding(get: { buds.isOn(feature) }, set: { buds.set(feature, $0) })) {
            Label(title, systemImage: symbol).font(.callout)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }
}
