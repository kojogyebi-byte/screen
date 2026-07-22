//
//  ContentView.swift
//  Expanse (ScreenExtend target)
//

import SwiftUI

private enum Brand {
    static let deep = Color(red: 0.047, green: 0.078, blue: 0.200)
    static let blue = Color(red: 0.164, green: 0.360, blue: 0.816)
    static let accent = Color(red: 0.353, green: 0.627, blue: 1.0)
    static var gradient: LinearGradient {
        LinearGradient(colors: [deep, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            displayCard
            connectionCard
            permissionsCard
            Spacer(minLength: 0)
            controlBar
            if let err = model.lastError {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 600)
        .onAppear { model.refreshPermissions() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Brand.gradient)
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(.white)
                )
                .shadow(color: Brand.blue.opacity(0.35), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Expanse").font(.system(size: 30, weight: .bold))
                Text("Use your Android tablet as a second Mac display")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Display card

    private var displayCard: some View {
        Card(title: "Display", systemImage: "display") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $model.autoResolution) {
                    Text("Automatic").tag(true)
                    Text("Manual").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.isRunning)

                if model.autoResolution {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(Brand.accent)
                        Text("Expanse detects your tablet and picks the sharpest resolution that streams smoothly.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !model.tabletNativeText.isEmpty {
                        detail("Tablet", model.tabletName.isEmpty ? "Detected" : model.tabletName)
                        detail("Native", model.tabletNativeText)
                    }
                    if !model.activeResolutionText.isEmpty {
                        detail("Streaming", model.activeResolutionText)
                    }
                } else {
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
                        .frame(width: 210)
                        .disabled(model.isRunning)
                        Toggle("HiDPI", isOn: $model.hiDPI)
                            .disabled(model.isRunning)
                    }
                }
            }
        }
    }

    // MARK: Connection card

    private var connectionCard: some View {
        Card(title: "Connection", systemImage: "wifi") {
            VStack(alignment: .leading, spacing: 12) {
                if model.discoveredTablets.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching for tablets on your network…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Pick a tablet to connect:")
                        .font(.callout).foregroundStyle(.secondary)
                    VStack(spacing: 6) {
                        ForEach(model.discoveredTablets) { tablet in
                            tabletRow(tablet)
                        }
                    }
                }

                Divider()

                if model.ipAddresses.isEmpty {
                    Text("No network address found. Connect to Wi-Fi or Ethernet.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Or type this address into the tablet manually:")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Text(model.ipAddresses.first ?? "")
                            .font(.system(.body, design: .monospaced)).bold()
                        Text("· \(String(model.port))")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if model.clientConnected && !model.tabletName.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Connected: \(model.tabletName)").font(.callout)
                    }
                }
            }
        }
    }

    private func tabletRow(_ tablet: DiscoveredTablet) -> some View {
        let selected = model.selectedTabletID == tablet.id
        return Button {
            model.selectedTabletID = selected ? nil : tablet.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "ipad.landscape")
                    .foregroundStyle(selected ? Brand.accent : .secondary)
                Text(tablet.name).foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.accent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Brand.accent.opacity(0.12) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Permissions card

    private var permissionsCard: some View {
        Card(title: "Permissions", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 10) {
                permissionLine(granted: model.hasScreenRecording,
                               title: "Screen Recording",
                               detail: "Required to capture the extended display.",
                               open: { Permissions.openScreenRecordingSettings() })
                permissionLine(granted: model.hasAccessibility,
                               title: "Accessibility",
                               detail: "Lets tablet taps move the Mac cursor.",
                               open: { Permissions.openAccessibilitySettings() })
                Button("Re-check") { model.refreshPermissions() }
                    .controlSize(.small)
            }
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

    // MARK: Control bar

    private var controlBar: some View {
        HStack(spacing: 14) {
            if model.isRunning {
                Button(role: .destructive) { model.stop() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(width: 130)
                }
                .controlSize(.large)
            } else {
                Button { model.start() } label: {
                    Label("Start", systemImage: "play.fill").frame(width: 130)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            statusPill
            Spacer()
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.clientConnected ? Color.green
                      : (model.isRunning ? Color.orange : Color.gray))
                .frame(width: 10, height: 10)
            Text(model.statusText).foregroundStyle(.secondary)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.callout).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
            Text(value).font(.system(.callout, design: .monospaced))
            Spacer()
        }
    }
}

/// A titled rounded card used throughout the window.
private struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Brand.accent)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
