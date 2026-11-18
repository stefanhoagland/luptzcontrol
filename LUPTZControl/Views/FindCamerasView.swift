import SwiftUI

/// Scans the network and lets the user add the cameras it finds.
struct FindCamerasView: View {
    var onAdded: ([Camera]) -> Void = { _ in }

    @EnvironmentObject private var store: CameraStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = CameraScanner()
    @State private var selected = Set<String>()
    @State private var username = ""
    @State private var password = ""
    @State private var showLogin = false
    @State private var manualHost = ""
    @State private var manualMessage: String?
    @State private var hasScanned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Find Cameras").font(.title2.bold())

            HStack {
                Text("Network")
                TextField("192.168.0", text: $scanner.subnet)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                Text(".1 – .254").foregroundStyle(.secondary)
                if scanner.subnets.count > 1 {
                    Menu("This Mac's networks") {
                        ForEach(scanner.subnets, id: \.self) { prefix in
                            Button(prefix) { scanner.subnet = prefix }
                        }
                    }
                    .fixedSize()
                }
                Spacer()
                Button(scanner.isScanning ? "Scanning…" : "Scan") { startScan() }
                    .disabled(scanner.isScanning)
            }

            DisclosureGroup("Camera login (only if your cameras ask for one)", isExpanded: $showLogin) {
                HStack {
                    TextField("User name", text: $username).textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                }
                .padding(.top, 4)
            }

            if scanner.isScanning {
                ProgressView(value: scanner.progress)
            }

            List(scanner.found, selection: $selected) { camera in
                HStack {
                    Image(systemName: camera.needsLogin ? "lock.fill" : "video.fill")
                        .foregroundStyle(camera.needsLogin ? Color.orange : Color.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text(camera.model).font(.headline)
                        Text(camera.name.isEmpty ? camera.host : "\(camera.name) · \(camera.host)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.contains(host: camera.host) {
                        Text("Added").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 200)
            .overlay {
                if scanner.found.isEmpty && !scanner.isScanning {
                    VStack(spacing: 6) {
                        Text(hasScanned ? "No cameras found" : "Not scanned yet").foregroundStyle(.secondary)
                        Text(hasScanned
                             ? "Check the network numbers above match your cameras, then press Scan again."
                             : "Check the network numbers above match your cameras, then press Scan.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if scanner.found.contains(where: \.needsLogin) {
                Text("Cameras with a lock need a login. Enter it above and scan again. Some may be other devices, not cameras.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                TextField("Add by IP address", text: $manualHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { addManual() }
                Button("Add") { addManual() }
                    .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                if let manualMessage {
                    Text(manualMessage).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add \(selected.count) Camera\(selected.count == 1 ? "" : "s")") { addSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 540)
    }

    private func startScan() {
        selected = []
        hasScanned = true
        Task {
            await scanner.scan(username: username, password: password)
            // Pre-select everything that isn't already added.
            selected = Set(scanner.found.filter { !store.contains(host: $0.host) }.map(\.host))
        }
    }

    private func addSelected() {
        let added = scanner.found
            .filter { selected.contains($0.host) }
            .map { store.add(host: $0.host, model: $0.needsLogin ? "Camera" : $0.model,
                             name: $0.name, username: username, password: password) }
        onAdded(added)
        dismiss()
    }

    private func addManual() {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        manualMessage = "Checking \(host)…"
        Task {
            let result = await CameraScanner.probe(host: host, username: username, password: password)
            let camera = store.add(host: host,
                                   model: result.map { $0.needsLogin ? "Camera" : $0.model } ?? "Camera",
                                   name: result?.name ?? "",
                                   username: username, password: password)
            manualMessage = result == nil ? "Added, but it didn't answer yet." : "Added \(camera.displayName)."
            manualHost = ""
            onAdded([camera])
        }
    }
}
