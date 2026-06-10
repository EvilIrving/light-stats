import SwiftUI

struct CleanupTabView: View {
    @StateObject private var appManager = AppMemoryManager.shared
    @State private var showForceTerminateAlert = false
    @State private var appToTerminate: RunningApp?
    @State private var terminatingApps: Set<Int32> = []
    @Environment(\.appTheme) private var theme
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 8) {
            memorySummaryCard
            appListHeader
            appListContent
        }
        .alert("cleanup.appNotResponding".localized, isPresented: $showForceTerminateAlert) {
            Button("cleanup.forceQuit".localized, role: .destructive) {
                if let app = appToTerminate {
                    _ = appManager.forceTerminateApp(app)
                }
            }
            Button("cleanup.cancel".localized, role: .cancel) {}
        } message: {
            Text("cleanup.forceQuitMessage".localized)
        }
        .onAppear { appManager.startMonitoring() }
        .onDisappear { appManager.stopMonitoring() }
    }

    // MARK: - Memory Summary

    private var memorySummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "memorychip.fill")
                    .font(.system(size: 10)).foregroundColor(theme.accent)
                Text("cleanup.memoryUsage".localized)
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.secondaryText)
            }

            HStack {
                Text("\(ByteFormatter.format(appManager.totalMemoryUsed)) / \(ByteFormatter.format(appManager.totalMemory))")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.primaryText)
                Spacer()
                Text(String(format: "%.0f%%", memoryUsagePercent))
                    .font(.system(size: 13, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(memoryBarColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.primaryText.opacity(0.06))
                    Capsule()
                        .fill(memoryBarColor)
                        .frame(width: geo.size.width * CGFloat(min(memoryUsagePercent / 100.0, 1.0)))
                }
            }
            .frame(height: 6)

            if swapUsed > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text("Swap \(ByteFormatter.format(swapUsed))")
                        .font(.system(size: 9, design: theme.fontDesign))
                }
                .foregroundColor(swapUsed < 1024 * 1024 * 1024 ? theme.warning : theme.danger)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(theme.card.opacity(theme.cardOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .stroke(theme.primaryText.opacity(0.05), lineWidth: 0.5)
        )
        .padding(.horizontal, layoutPadding)
        .padding(.top, 4)
    }

    // MARK: - App List Header

    private var appListHeader: some View {
        HStack {
            Text("cleanup.runningApps".localized)
                .font(.system(size: 10, weight: .bold, design: theme.fontDesign))
                .foregroundColor(theme.secondaryText)
            Spacer()
            Text(String(format: "cleanup.appCount".localized, appManager.runningApps.filter(\.isTerminable).count))
                .font(.system(size: 9, design: theme.fontDesign))
                .foregroundColor(theme.secondaryText.opacity(0.7))
        }
        .padding(.horizontal, layoutPadding + 4)
        .padding(.top, 4)
    }

    // MARK: - App List

    @ViewBuilder
    private var appListContent: some View {
        if appManager.runningApps.isEmpty {
            VStack {
                Spacer()
                Text("cleanup.noApps".localized)
                    .font(.system(size: 12, design: theme.fontDesign))
                    .foregroundColor(theme.secondaryText)
                Spacer()
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(appManager.runningApps) { app in
                        AppCardView(
                            app: app,
                            isTerminating: terminatingApps.contains(app.id),
                            appManager: appManager
                        ) {
                            terminateApp(app)
                        }
                    }
                }
                .padding(.horizontal, layoutPadding)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Helpers

    private var layoutPadding: CGFloat {
        settings.appearancePreset.layout.horizontalPadding
    }

    private var memoryUsagePercent: Double {
        guard appManager.totalMemory > 0 else { return 0 }
        return Double(appManager.totalMemoryUsed) / Double(appManager.totalMemory) * 100
    }

    private var memoryBarColor: Color {
        switch appManager.memoryPressure {
        case .normal: return theme.success
        case .warning: return theme.warning
        case .critical: return theme.danger
        }
    }

    private var swapUsed: UInt64 {
        appManager.detailedMemory?.swapUsed ?? 0
    }

    private func terminateApp(_ app: RunningApp) {
        guard app.isTerminable, !terminatingApps.contains(app.id) else { return }
        terminatingApps.insert(app.id)
        Task {
            let success = await appManager.terminateAppAsync(app)
            await MainActor.run {
                terminatingApps.remove(app.id)
                if !success, appManager.isProcessAlive(app.id) {
                    appToTerminate = app
                    showForceTerminateAlert = true
                }
            }
        }
    }
}
