//
//  AppSwitcherSession.swift
//  Light Stats
//

import Foundation

/// Selection state for the window switcher.
///
/// Pure, and time-free: the whole keyboard model — what starts selected, how Tab wraps, how the
/// window selection moves inside an application, what a commit returns, and that cancelling returns
/// nothing — is decided here and covered by tests. The event tap above it only translates key
/// events into these four calls, which is the part that cannot be tested anyway.
nonisolated struct AppSwitcherSession {

    /// Which panel shape this session belongs to. Chosen once, when the session starts.
    private(set) var mode: AppSwitcherMode
    /// Applications in most-recently-used order, with their windows.
    private(set) var groups: [ApplicationWindowGroup]
    /// Every window in that same order, flattened. This is what the grid mode shows and moves
    /// through, so the two modes differ in presentation and key meaning, not in what exists.
    private(set) var flatWindows: [WindowPreviewItem]
    private(set) var groupIndex: Int = 0
    /// Which window of the selected application commit would use.
    private(set) var windowIndex: Int = 0
    /// Which window of `flatWindows` the grid mode has selected.
    private(set) var flatIndex: Int = 0

    var isShowing: Bool { !groups.isEmpty }

    init(groups: [ApplicationWindowGroup], mode: AppSwitcherMode = .twoLevel) {
        self.mode = mode
        self.groups = groups.filter { !$0.windows.isEmpty }
        self.flatWindows = self.groups.flatMap(\.windows)
        selectInitialGroup(backwards: false)
    }

    mutating func selectInitialGroup(backwards: Bool) {
        groupIndex = backwards ? max(groups.count - 1, 0) : min(1, max(groups.count - 1, 0))
        windowIndex = 0
        flatIndex = backwards
            ? max(flatWindows.count - 1, 0)
            : min(1, max(flatWindows.count - 1, 0))
    }

    var selectedGroup: ApplicationWindowGroup? {
        groups.indices.contains(groupIndex) ? groups[groupIndex] : nil
    }

    var selectedWindow: WindowPreviewItem? {
        if mode == .grid {
            return flatWindows.indices.contains(flatIndex) ? flatWindows[flatIndex] : nil
        }
        guard let group = selectedGroup, group.windows.indices.contains(windowIndex) else { return nil }
        return group.windows[windowIndex]
    }

    /// Moves the application selection. Positive wraps forward, so holding ⌘ and tapping Tab cycles
    /// rather than stopping at the end.
    mutating func advance(by offset: Int) {
        guard !groups.isEmpty else { return }
        if mode == .grid {
            guard !flatWindows.isEmpty else { return }
            flatIndex = wrapped(flatIndex + offset, count: flatWindows.count)
            return
        }
        groupIndex = wrapped(groupIndex + offset, count: groups.count)
        // Each application has its own window list, so the window selection cannot survive the move.
        windowIndex = 0
    }

    /// Moves within the selected application's windows.
    mutating func moveWindow(by offset: Int) {
        if mode == .grid {
            advance(by: offset)
            return
        }
        guard let group = selectedGroup, group.windows.count > 1 else { return }
        windowIndex = wrapped(windowIndex + offset, count: group.windows.count)
    }

    mutating func selectGroup(at index: Int) {
        guard groups.indices.contains(index) else { return }
        groupIndex = index
        windowIndex = 0
        if mode == .grid, let first = flatWindows.firstIndex(where: { $0.processID == groups[index].processID }) {
            flatIndex = first
        }
    }

    /// Pointer target. In the grid mode `index` addresses `flatWindows`; in the two-level mode it
    /// addresses the selected application's own window list.
    mutating func selectWindow(at index: Int) {
        if mode == .grid {
            guard flatWindows.indices.contains(index) else { return }
            flatIndex = index
            return
        }
        guard let group = selectedGroup, group.windows.indices.contains(index) else { return }
        windowIndex = index
    }

    /// The window the user settled on, and the end of the session.
    mutating func commit() -> WindowPreviewItem? {
        let window = selectedWindow
        groups = []
        flatWindows = []
        groupIndex = 0
        windowIndex = 0
        flatIndex = 0
        return window
    }

    /// Abandons the session without a selection.
    mutating func cancel() {
        groups = []
        flatWindows = []
        groupIndex = 0
        windowIndex = 0
        flatIndex = 0
    }

    /// Whether the pointer is over the given point, in Accessibility space — the panel stops
    /// dismissing itself while the pointer is on it.
    private func wrapped(_ value: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((value % count) + count) % count
    }
}

/// Ordering for the switcher's application list.
nonisolated enum ApplicationOrdering {

    /// Most-recently-used first, with anything the tracker has never seen appended in the order
    /// `NSWorkspace` returns so a never-activated application cannot be silently dropped.
    static func mostRecentlyUsed(
        groups: [ApplicationWindowGroup],
        recency: [pid_t]
    ) -> [ApplicationWindowGroup] {
        let rank = Dictionary(uniqueKeysWithValues: recency.enumerated().map { ($0.element, $0.offset) })
        return groups.enumerated().sorted { lhs, rhs in
            switch (rank[lhs.element.processID], rank[rhs.element.processID]) {
            case let (.some(leftRank), .some(rightRank)):
                return leftRank < rightRank
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}
