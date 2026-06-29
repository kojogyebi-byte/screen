//
//  ContentView.swift
//  ScreenExtend
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            GroupBox("Extended display") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Resolution", selection: $model.selectedPreset) {
                        ForEach(DisplayPreset.all) { preset in
                            Text(preset.name).tag(preset)
                        }
                    }
                    .disabled(model.isRunning)

                    HStack(spacing: 24) {
                        Picker("Frame rate", selection: $model.fps) {
                            Text("24 fps").tag(24)
                            Text("30 fps").tag(30)
                            Text("60 fps").tag(60)
                        }
                        .frame(width: 200)
                        .disabled(model.isRunning)

                        Toggle("HiDPI (experimental)", isOn: $model.hiDPI)
                            .disabled(model.isRunning)
                    }
                }
                .padding(6)
            }

            GroupBox("Connection") {
                VStack(alignment: .leading, spacing: 8) {
                    if model.ipAddresses.isEmpty {
                        Text("No network address found. Connect to Wi-Fi or Ethernet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("On the tablet, enter:")
                            .foregroundStyle(.secondary)
                        ForEach(model.ipAddresses, id: \.self) { ip in
                            HStack {
                                Text("\(ip)")
                                    .font(.system(.title3, design: .monospaced))
                                Text("port \(String(model.port))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(6)
            }

            permissionsRow

            HStack(spacing: 12) {
                if model.isRunning {
                    Button(role: .destructive) { model.stop() } label: {
                        Label("Stop", systemImage: "stop.fill").frame(width: 120)
                    }
                    .controlSize(.large)
                } else {
                    Button { model.start() } label: {
                        Label("Start", systemImage: "play.fill").frame(width: 120)
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }

                statusPill
                Spacer()
            }

            if let err = model.lastError {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 540)
        .onAppear { model.refreshPermissions() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Extend").font(.title2).bold()
                Text("Use your Android tablet as a second Mac display")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.clientConnected ? Color.green :
                        (model.isRunning ? Color.orange : Color.gray))
                .frame(width: 10, height: 10)
            Text(model.statusText).foregroundStyle(.secondary)
        }
    }

    private var permissionsRow: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 10) {
                permissionLine(
                    granted: model.hasScreenRecording,
                    title: "Screen Recording",
                    detail: "Required to capture the extended display.",
                    open: { Permissions.openScreenRecordingSettings() })
                permissionLine(
                    granted: model.hasAccessibility,
                    title: "Accessibility",
                    detail: "Required so tablet taps move the Mac cursor.",
                    open: { Permissions.openAccessibilitySettings() })
                Button("Re-check permissions") { model.refreshPermissions() }
                    .controlSize(.small)
            }
            .padding(6)
        }
    }

    private func permissionLine(granted: Bool, title: String, detail: String,
                                open: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Open Settings", action: open).controlSize(.small)
            }
        }
    }
}
