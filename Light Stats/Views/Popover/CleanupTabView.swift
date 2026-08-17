//
//  CleanupTabView.swift
//  Light Stats
//
//  Memory readout + running-app list. Instrument layout, no bento cards.
//

import SwiftUI

struct CleanupTabView: View {
    @Environment(\.theme) private var theme
    @Environment(\.themeLayout) private var layout
    @StateObject private var appManager = AppMemoryManager.shared
    @State private var showForceTerminateAlert = false
    @State private var appToTerminate: RunningApp?
    @State private var terminatingApps: Set<Int32> = []

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if layout.usesBentoLayout {
                    BentoCard(title: "cleanup.memoryUsage".localized, svgIcon: .memory) {
                        memoryHeaderBody
                    }
                } else {
                    memoryHeader
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)

            runningAppsHeader
                .padding(.horizontal, 16)
                .padding(.top, layout.usesBentoLayout ? 12 : 10)
                .padding(.bottom, layout.usesBentoLayout ? 8 : 6)

            if appManager.runningApps.isEmpty {
                emptyStateView
            } else if layout.usesBentoLayout {
                bentoAppList
            } else {
                instrumentAppList
            }
        }
        // Same full-bounds hit claim as Overview — mesh panel backgrounds do not
        // intercept hits (decorative art), so empty chrome must still own the wheel.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
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
        .onAppear {
            appManager.startMonitoring()
        }
        .onDisappear {
            appManager.stopMonitoring()
        }
    }

    private var usesBento: Bool { layout.usesBentoLayout }

    private var runningAppsHeader: some View {
        HStack {
            Text(
                usesBento
                    ? "cleanup.runningApps".localized
                    : "cleanup.runningApps".localized.uppercased()
            )
            .font(.system(
                size: usesBento ? 12 : 10,
                weight: .semibold,
                design: usesBento ? .default : .monospaced
            ))
            .tracking(usesBento ? 0 : 0.9)
            .foregroundStyle(theme.inkFaint)
            Spacer()
            Text(String(
                format: "cleanup.appCount".localized,
                appManager.runningApps.filter(\.isTerminable).count
            ))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(theme.inkSecondary)
        }
    }

    /// Classic card-gap list for Bento Grid.
    private var bentoAppList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
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
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    /// Film / glass / noir: flat readout rows — no well chrome, no inter-row rules.
    private var instrumentAppList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
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
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var memoryHeader: some View {
        // Instrument themes: title only (Bento keeps icon on BentoCard).
        PanelSection(title: "cleanup.memoryUsage".localized) {
            memoryHeaderBody
        }
    }

    private var memoryHeaderBody: some View {
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text("\(ByteFormatter.format(appManager.totalMemoryUsed)) / \(ByteFormatter.format(appManager.totalMemory))")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.inkPrimary)
                Spacer()
                Text(String(format: "%.0f%%", memoryUsagePercent))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(memoryBarColor)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.wellFill)
                    Capsule()
                        .fill(memoryBarColor)
                        .frame(width: geometry.size.width * CGFloat(min(memoryUsagePercent / 100.0, 1.0)))
                }
            }
            .frame(height: layout.usesBentoLayout ? 8 : 6)

            if swapUsed > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text("Swap")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text(ByteFormatter.format(swapUsed))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Spacer()
                }
                .foregroundStyle(
                    swapUsed < 1024 * 1024 * 1024 ? theme.signalWarn : theme.signalBad
                )
            }
        }
    }

    private var memoryUsagePercent: Double {
        guard appManager.totalMemory > 0 else { return 0 }
        return Double(appManager.totalMemoryUsed) / Double(appManager.totalMemory) * 100
    }

    private var memoryBarColor: Color {
        switch appManager.memoryPressure {
        case .normal: return theme.signalGood
        case .warning: return theme.signalWarn
        case .critical: return theme.signalBad
        }
    }

    private var swapUsed: UInt64 {
        appManager.detailedMemory?.swapUsed ?? 0
    }

    private var emptyStateView: some View {
        VStack {
            Spacer()
            Text("cleanup.noApps".localized)
                .font(.system(size: 14))
                .foregroundStyle(theme.inkMuted)
            Spacer()
        }
    }

    private func terminateApp(_ app: RunningApp) {
        guard app.isTerminable else { return }
        guard !terminatingApps.contains(app.id) else { return }

        terminatingApps.insert(app.id)

        Task {
            let success = await appManager.terminateAppAsync(app)

            await MainActor.run {
                terminatingApps.remove(app.id)

                if !success && appManager.isProcessAlive(app.id) {
                    appToTerminate = app
                    showForceTerminateAlert = true
                }
            }
        }
    }
}
