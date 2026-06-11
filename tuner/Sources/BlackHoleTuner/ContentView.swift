import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ShaderStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Specs.grouped(store.params), id: \.0) { group, members in
                        GroupBox {
                            VStack(spacing: 6) {
                                ForEach(members) { param in
                                    ParamRow(name: param.name)
                                }
                            }
                            .padding(6)
                        } label: {
                            Text(group).font(.headline)
                        }
                    }
                    if store.params.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "circle.dashed")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No shader loaded")
                                .font(.headline)
                            Text("Open blackhole.glsl to start tuning.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                }
                .padding(12)
            }
            Divider()
            HStack {
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let url = store.shaderURL {
                    Text(url.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 520, idealHeight: 860)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    ForEach(Specs.presets, id: \.0) { name, values in
                        Button(name) { store.apply(preset: values) }
                    }
                } label: {
                    Label("Presets", systemImage: "sparkles")
                }
                Button {
                    store.reloadGhostty()
                    store.status = "sent SIGUSR2 to Ghostty"
                } label: {
                    Label("Reload Ghostty", systemImage: "arrow.clockwise")
                }
                .help("Force a Ghostty config + shader reload")
                Button {
                    store.chooseShader()
                } label: {
                    Label("Open…", systemImage: "folder")
                }
                .help("Pick a different blackhole.glsl")
            }
        }
    }
}

struct ParamRow: View {
    @EnvironmentObject var store: ShaderStore
    let name: String

    private var spec: ParamSpec { Specs.spec(for: name, value: store.current(name)) }

    private var binding: Binding<Double> {
        Binding(
            get: { store.current(name) },
            set: { store.set(name, to: $0) })
    }

    var body: some View {
        let spec = self.spec
        HStack(spacing: 8) {
            Text(name)
                .font(.system(.body, design: .monospaced))
                .frame(width: 150, alignment: .leading)
            Slider(value: binding, in: spec.range)
            TextField("", value: binding, format: .number.precision(.fractionLength(0...4)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 86)
            Button {
                store.set(name, to: spec.def)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Reset to \(spec.def.formatted())")
        }
        .help(spec.help)
    }
}
