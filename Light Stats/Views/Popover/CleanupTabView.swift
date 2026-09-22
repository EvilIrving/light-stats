//
//  CleanupTabView.swift
//  Light Stats
//
//  Memory readout + running-app list. Instrument layout.
//

import SwiftUI

struct CleanupTabView: View {
    @Environment(\.theme) private var theme
    @StateObject private var appManager = AppMemoryManager.shared
    @State private var showForceTerminateAlert = false
    @State private var appToTerminate: RunningApp?
    @State private var terminatingApps: Set<Int32> = []
    @State private var isPinnedExpanded = false
    @State private var isPinnedDropTargeted = false
    @State private var isPinnedBatchTerminating = false

    var body: some View {
        VStack(spacing: 0) {
            memoryHeader
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)

            runningAppsHeader
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if appManager.runningApps.isEmpty {
                emptyStateView
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

    private var runningAppsHeader: some View {
        HStack {
            Text("cleanup.runningApps".localized.uppercased())
            .font(theme.chromeStyle.sectionTitleFont)
            .tracking(theme.chromeStyle.sectionTracking)
            .foregroundStyle(
                theme.chromeStyle.usesIlluminatedTreatment ? theme.accent : theme.inkFaint
            )
            Spacer()
            Text(String(
                format: "cleanup.appCount".localized,
                appManager.runningApps.filter(\.isTerminable).count
                    + appManager.pinnedRunningApps.filter(\.isTerminable).count
            ))
            .font(theme.chromeStyle.compactValueFont)
            .foregroundStyle(theme.inkSecondary)
        }
    }

    /// Instrument themes share row geometry; ThemeChromeStyle controls visual treatment.
    private var instrumentAppList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(appManager.runningApps) { app in
                    if app.id == AppGroup.pinnedGroupId {
                        pinnedGroupSection(stub: app)
                    } else {
                        draggableAppRow(app)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func draggableAppRow(_ app: RunningApp) -> some View {
        let row = AppCardView(
            app: app,
            isTerminating: terminatingApps.contains(app.id),
            appManager: appManager
        ) {
            terminateApp(app)
        }

        if CleanupPinnedGroupPolicy.canPin(app),
           let key = CleanupPinnedGroupPolicy.memberKey(for: app) {
            row.draggable(key)
        } else {
            row
        }
    }

    private func pinnedGroupSection(stub: RunningApp) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            pinnedGroupHeader(stub: stub)
            if isPinnedExpanded {
                ForEach(appManager.pinnedRunningApps) { app in
                    AppCardView(
                        app: app,
                        isTerminating: terminatingApps.contains(app.id),
                        appManager: appManager,
                        showsUnpinControl: true,
                        onUnpin: { appManager.unpinApp(app) }
                    ) {
                        terminateApp(app)
                    }
                }
            }
        }
    }

    private func pinnedGroupHeader(stub: RunningApp) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isPinnedExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.inkSecondary)
                .frame(width: 10, height: 10)

            Image(nsImage: stub.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)

            Text(stub.name)
                .font(theme.chromeStyle.compactValueFont)
                .foregroundStyle(theme.inkPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(String(format: "cleanup.appCount".localized, stub.processCount))
                .font(theme.chromeStyle.compactValueFont)
                .foregroundStyle(theme.inkSecondary)

            pinnedBatchButton(count: stub.processCount)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isPinnedDropTargeted ? theme.rowHoverFill.opacity(0.55) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isPinnedExpanded.toggle()
            }
        }
        .dropDestination(for: String.self, action: { keys, _ in
            guard let key = keys.first else { return false }
            let accepted = appManager.acceptPinnedDrop(payload: key)
            if accepted {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isPinnedExpanded = true
                }
            }
            return accepted
        }, isTargeted: { targeted in
            isPinnedDropTargeted = targeted
        })
    }

    @ViewBuilder
    private func pinnedBatchButton(count: Int) -> some View {
        if isPinnedBatchTerminating {
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        } else {
            Button {
                terminatePinnedBatch()
            } label: {
                Image(systemName: "power.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        count > 0 ? theme.signalBad.opacity(0.9) : theme.inkFaint.opacity(0.45)
                    )
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            .help("cleanup.pinnedGroup.quitAll".localized)
        }
    }

    private var memoryHeader: some View {
        PanelSection(title: "cleanup.memoryUsage".localized) {
            memoryHeaderBody
        }
    }

    private var memoryHeaderBody: some View {
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text("\(ByteFormatter.format(appManager.totalMemoryUsed)) / \(ByteFormatter.format(appManager.totalMemory))")
                    .font(theme.chromeStyle.metricValueFont)
                    .foregroundStyle(theme.inkPrimary)
                Spacer()
                Text(String(format: "%.0f%%", memoryUsagePercent))
                    .font(theme.chromeStyle.metricValueFont)
                    .foregroundStyle(memoryBarColor)
                    .shadow(
                        color: theme.chromeStyle.usesIlluminatedTreatment
                            ? memoryBarColor.opacity(
                                theme.chromeStyle.usesNightBarTreatment ? 0.72 : 0.65
                            )
                            : .clear,
                        radius: theme.chromeStyle.signalGlowRadius
                    )
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(
                        cornerRadius: theme.chromeStyle.usesNightBarTreatment ? 3 : 100
                    )
                    .fill(theme.wellFill)
                    RoundedRectangle(
                        cornerRadius: theme.chromeStyle.usesNightBarTreatment ? 3 : 100
                    )
                    .fill(memoryBarColor)
                    .frame(width: geometry.size.width * CGFloat(min(memoryUsagePercent / 100.0, 1.0)))
                }
            }
            .frame(height: 6)

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

    private func terminatePinnedBatch() {
        guard !isPinnedBatchTerminating else { return }
        let plan = CleanupPinnedGroupPolicy.batchTerminationPlan(from: appManager.pinnedRunningApps)
        guard !plan.isEmpty else { return }

        isPinnedBatchTerminating = true
        for app in plan {
            terminatingApps.insert(app.id)
        }

        Task {
            let result = await appManager.terminatePinnedAppsAsync()
            await MainActor.run {
                for app in plan {
                    terminatingApps.remove(app.id)
                }
                isPinnedBatchTerminating = false
                if result.failed > 0,
                   let survivor = appManager.pinnedRunningApps.first(where: {
                       appManager.isProcessAlive($0.id)
                   }) {
                    appToTerminate = survivor
                    showForceTerminateAlert = true
                }
            }
        }
    }
}
