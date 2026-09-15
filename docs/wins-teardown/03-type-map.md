# Wins 类型表 —— 类、ivar 与字段

从 `/Applications/Wins.app/Contents/MacOS/Wins` 生成：ObjC 运行期元数据给出类名、继承关系与 ivar **名字与顺序**；Swift 反射段（`__swift5_types` + `__swift5_fieldmd`）给出**字段名与类型**。两者按声明顺序合并。

## 关于字节大小（重要）

`otool -oV` 输出的 ivar `offset` / `size` 两列**对 Swift 类不可靠**：同一个类里前若干个 ivar 的 offset 是正确的，之后会突然跳到另一片内存、值全部变成 0；`size` 列也存在整体错位一格的情况（实测 `SnappingIslandWindowAnimator.targetAlpha` 报 9、`motion` 报 32，而真实布局是 16 / 9+padding）。

**因此本表不列字节大小。** 只列能从两处独立来源互相印证的内容：

- 类名、继承关系（ObjC 元数据）

- ivar 名字与声明顺序（ObjC 元数据与 `__swift5_fieldmd` 逐一对齐验证过）

- Swift 字段类型（`__swift5_fieldmd` → `__swift5_typeref`，未能解析的记为 `—`）

需要精确字节布局时，重新导出并逐个核对偏移，不要直接信 otool 的列。

共 190 个 Wins 类、598 个 ivar。


## 其它 Other

### `ActivationWindow`  ·  继承 `NSWindow`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `ActivationWindowController`  ·  继承 `NSWindowController`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `compactWindowSize` | `—` |
| 1 | `expandedWindowHeight` | `—` |
| 2 | `isDockIconRetained` | `Sb` |
| 3 | `forgetTopToEmailConstraint` | `So18NSLayoutConstraintCSg` |
| 4 | `forgetTopToStatusConstraint` | `So18NSLayoutConstraintCSg` |
| 5 | `forgetTopToErrorConstraint` | `So18NSLayoutConstraintCSg` |
| 6 | `forgetTopToRenewalConstraint` | `So18NSLayoutConstraintCSg` |
| 7 | `forgetTopToSeatUpgradeConstraint` | `So18NSLayoutConstraintCSg` |
| 8 | `pendingRenewalContext` | `—` |
| 9 | `pendingSeatUpgradeContext` | `—` |
| 10 | `logoImageView` | `So11NSImageViewC` |
| 11 | `titleLabel` | `So11NSTextFieldC` |
| 12 | `subtitleLabel` | `So11NSTextFieldC` |
| 13 | `licenseField` | `So11NSTextFieldC` |
| 14 | `emailField` | `So11NSTextFieldC` |
| 15 | `forgetLicenseButton` | `So8NSButtonC` |
| 16 | `activateButton` | `So8NSButtonC` |
| 17 | `statusLabel` | `So11NSTextFieldC` |
| 18 | `errorLabel` | `So11NSTextFieldC` |
| 19 | `renewalPrefixLabel` | `So11NSTextFieldC` |
| 20 | `renewalButton` | `So8NSButtonC` |
| 21 | `renewalSuffixLabel` | `So11NSTextFieldC` |
| 22 | `renewalContainer` | `So11NSStackViewC` |
| 23 | `seatUpgradePrefixLabel` | `So11NSTextFieldC` |
| 24 | `seatUpgradeButton` | `So8NSButtonC` |
| 25 | `seatUpgradeSuffixLabel` | `So11NSTextFieldC` |
| 26 | `seatUpgradeContainer` | `So11NSStackViewC` |

### `BackgroundThreadWithRunLoop`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `thread` | `So8NSThreadCSg` |
| 1 | `runLoop` | `—` |
| 2 | `hasSentSemaphoreSignal` | `Sb` |

### `DragShakeChecker`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `ReverseAllManager`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_


## Cmd-Tab Plus 切换器

### `CommandTabNumberBadgeView`  ·  继承 `NSView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `text` | `SS` |

### `CommandTabPlus`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `eventTap` | `—` |
| 1 | `runLoopSource` | `—` |
| 2 | `isActive` | `Sb` |
| 3 | `isCommandTabActive` | `Sb` |
| 4 | `lastSelectedApp` | `So20NSRunningApplicationCSg` |
| 5 | `lastSwitchKeyDownTime` | `Sd` |
| 6 | `lastDetectionStartTime` | `Sd` |
| 7 | `endedByPreviewCommit` | `Sb` |
| 8 | `mouseEventTap` | `—` |
| 9 | `mouseRunLoopSource` | `—` |
| 10 | `lastMouseHoverAppBundleId` | `SSSg` |
| 11 | `lastMouseEventTime` | `Sd` |
| 12 | `mouseEventThrottle` | `Sd` |
| 13 | `mouseHoverDetectionQueue` | `So17OS_dispatch_queueC` |
| 14 | `pendingHoverDetection` | `—` |
| 15 | `latestMouseLocation` | `—` |
| 16 | `lastMouseMoveDetectionTime` | `Sd` |
| 17 | `mouseMoveDetectionThrottle` | `Sd` |
| 18 | `pendingSelectedAppDetection` | `—` |
| 19 | `fastDetectToken` | `—` |
| 20 | `fastDetectSatisfiedToken` | `—` |
| 21 | `lastSwitchEventTS` | `Sd` |
| 22 | `lastScrollEventReceivedTS` | `Sd` |
| 23 | `scrollEventThrottle` | `Sd` |
| 24 | `appTitleExactCache` | `SDySSSo20NSRunningApplicationC3app_Sd2tstG` |
| 25 | `appTitleCacheQueue` | `So17OS_dispatch_queueC` |
| 26 | `appTitleCacheTTL` | `Sd` |
| 27 | `cachedDockApp` | `So20NSRunningApplicationCSg` |
| 28 | `cachedDockAppTs` | `Sd` |
| 29 | `dockAppCacheTTL` | `Sd` |
| 30 | `cachedProcessSwitcherPath` | `SaySiG` |
| 31 | `lastCacheTime` | `Sd` |
| 32 | `cacheValidDuration` | `Sd` |

### `CommandTabPreviewBackportView`  ·  继承 `NSVisualEffectView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `appName` | `So11NSTextFieldCSg` |
| 1 | `stripView` | `—` |

### `CommandTabPreviewHorizontalStripView`  ·  继承 `NSView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `scrollView` | `So12NSScrollViewC` |
| 1 | `documentView` | `—` |
| 2 | `scrollViewWidthConstraint` | `So18NSLayoutConstraintCSg` |
| 3 | `scrollViewHeightConstraint` | `So18NSLayoutConstraintCSg` |
| 4 | `windows` | `—` |
| 5 | `visibleCount` | `Si` |
| 6 | `selectedIndex` | `SiSg` |
| 7 | `scrollStartIndex` | `Si` |
| 8 | `hoveredIndex` | `SiSg` |
| 9 | `pendingAutoScrollTask` | `—` |
| 10 | `pendingAutoScrollTargetIndex` | `SiSg` |
| 11 | `pendingShortcutBadgeRevealTask` | `—` |
| 12 | `shortcutBadgesVisible` | `Sb` |
| 13 | `lastHoverOwnerView` | `So6NSViewCSgXw` |
| 14 | `lastHoverLocationInOwner` | `t_!` |

### `CommandTabPreviewItemContainerView`  ·  继承 `NSView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `timer` | `So7NSTimerCSg` |
| 1 | `closeBtn` | `—` |
| 2 | `windowTitle` | `So11NSTextFieldCSg` |
| 3 | `imageButton` | `So8NSButtonCSg` |
| 4 | `numberBadge` | `—` |
| 5 | `isKeyboardSelected` | `Sb` |
| 6 | `delegate` | `—` |
| 7 | `windowsControlSize` | `—` |
| 8 | `delayShowCloseButtonTask` | `—` |
| 9 | `trackingArea` | `So14NSTrackingAreaCSg` |
| 10 | `highlightOverlay` | `So6NSViewCSg` |
| 11 | `isMouseInside` | `Sb` |

### `CommandTabPreviewItemView`  ·  继承 `NSView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `containerView` | `—` |
| 1 | `itemWindow` | `—` |
| 2 | `keyboardSelected` | `Sb` |
| 3 | `previewIndex` | `Si` |
| 4 | `showsShortcutBadge` | `Sb` |

### `CommandTabPreviewScrollContentView`  ·  继承 `NSView`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `CommandTabPreviewVisualEffectView`  ·  继承 `NSGlassEffectView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `appName` | `So11NSTextFieldCSg` |
| 1 | `stripView` | `—` |

### `CommandTabPreviewWC`  ·  继承 `NSWindowController`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `selectedApp` | `So20NSRunningApplicationCSg` |
| 1 | `items` | `—` |
| 2 | `log` | `So9OS_os_logC` |
| 3 | `delayHideTask` | `—` |
| 4 | `globalMouseMonitor` | `ypSg` |
| 5 | `globalMouseMoveMonitor` | `ypSg` |
| 6 | `mouseEventTap` | `—` |
| 7 | `mouseRunLoopSource` | `—` |
| 8 | `lastAnchorPosition` | `t_!` |
| 9 | `lastDisplayedWindowsCount` | `Si` |
| 10 | `isRefreshingAfterClose` | `Sb` |
| 11 | `pendingRefreshAfterClose` | `Sb` |
| 12 | `needsEnterSelectionAfterRefresh` | `Sb` |
| 13 | `lastShowPreviewStartTS` | `Sd` |
| 14 | `isWindowSelectionMode` | `Sb` |
| 15 | `lastSelectionSource` | `—` |
| 16 | `$__lazy_storage_$_glassEffectView` | `So6NSViewCSgSg` |
| 17 | `$__lazy_storage_$_visualEffectView` | `—` |

### `CommandTabPreviewWindow`  ·  继承 `NSWindow`
_无 ivar（纯静态工具类，或只有方法的计算类）_


## Dock 集成 Dock integration

### `DockDisplayLockController`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `manager` | `—` |
| 1 | `defaults` | `So14NSUserDefaultsC` |
| 2 | `healthInterval` | `Sd` |
| 3 | `displayConfigurationRetryDelay` | `Sd` |
| 4 | `automaticRetryDelay` | `Sd` |
| 5 | `successfulMoveCooldown` | `Sd` |
| 6 | `automaticPointerIdleInterval` | `Sd` |
| 7 | `isStarted` | `Sb` |
| 8 | `isMoveInFlight` | `Sb` |
| 9 | `operationGeneration` | `Su` |
| 10 | `lastSuccessfulMove` | `—` |
| 11 | `lastRealMouseMovement` | `—` |
| 12 | `nextAutomaticRetry` | `—` |
| 13 | `restoreWorkItem` | `—` |
| 14 | `scheduledRestoreReason` | `SSSg` |
| 15 | `healthTimer` | `So7NSTimerCSg` |
| 16 | `screenObserver` | `So8NSObject_pSg` |
| 17 | `workspaceObservers` | `SaySo8NSObject_pG` |
| 18 | `unlockObserver` | `So8NSObject_pSg` |
| 19 | `isObservingDockPreferences` | `Sb` |
| 20 | `observedDockPID` | `—` |
| 21 | `eventTap` | `—` |
| 22 | `eventTapSource` | `—` |
| 23 | `blockingZones` | `—` |
| 24 | `suspendedPrerequisites` | `—` |

### `DockDisplayManager`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `moveQueue` | `So17OS_dispatch_queueC` |
| 1 | `adjacencyTolerance` | `—` |
| 2 | `minimumTriggerLength` | `—` |
| 3 | `relocationEdgeInset` | `—` |
| 4 | `relocationPointCount` | `Si` |
| 5 | `relocationPointIncrement` | `—` |
| 6 | `relocationInitialDelay` | `Sd` |
| 7 | `relocationPointInterval` | `Sd` |
| 8 | `verificationInterval` | `Sd` |
| 9 | `verificationTimeout` | `Sd` |
| 10 | `orientationTransitionInterval` | `Sd` |
| 11 | `orientationTransitionTimeout` | `Sd` |

### `DockEvents`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `DockItem`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `name` | `SS` |
| 1 | `rect` | `—` |
| 2 | `bundleURL` | `—` |
| 3 | `windows` | `—` |
| 4 | `runningApp` | `So20NSRunningApplicationC` |

### `DockItemWindow`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `cgWindowId` | `—` |
| 1 | `title` | `SSSg` |
| 2 | `thumbnail` | `So7NSImageCSg` |
| 3 | `sourceImage` | `4^!` |
| 4 | `sourceImageSize` | `—` |
| 5 | `thumbnailID` | `SS` |
| 6 | `thumbnailFullSize` | `T_!` |
| 7 | `isHidden` | `Sb` |
| 8 | `isFullscreen` | `Sb` |
| 9 | `isMinimized` | `Sb` |
| 10 | `position` | `t_!` |
| 11 | `size` | `T_!` |
| 12 | `bundleIdentifier` | `SS` |
| 13 | `application` | `—` |
| 14 | `axUiElement` | `—` |
| 15 | `closeButton` | `—` |

### `DockLockAlertBackgroundView`  ·  继承 `NSVisualEffectView`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `DockLockAlertIconView`  ·  继承 `NSView`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `DockLockPrerequisiteHUDController`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `panel` | `—` |
| 1 | `contentStack` | `So11NSStackViewC` |
| 2 | `requirementGroup` | `—` |
| 3 | `requirementStack` | `So11NSStackViewC` |
| 4 | `noteLabel` | `So11NSTextFieldC` |
| 5 | `primaryButton` | `So8NSButtonC` |
| 6 | `secondaryButton` | `So8NSButtonC` |
| 7 | `windowWidth` | `—` |
| 8 | `rowHeight` | `—` |
| 9 | `separatorHeight` | `—` |
| 10 | `fixedWindowHeight` | `—` |
| 11 | `requirementHeightConstraint` | `So18NSLayoutConstraintCSg` |

### `DockLockPrerequisitePanel`  ·  继承 `NSPanel`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `DockLockRequirementGroupView`  ·  继承 `NSView`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `DockLockRequirementRowView`  ·  继承 `NSView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `action` | `yyc` |
| 1 | `trackingArea` | `So14NSTrackingAreaCSg` |
| 2 | `isHovered` | `Sb` |
| 3 | `isPressed` | `Sb` |

### `DockPreferences`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `DockPreviewBackgroundWork`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `DockPreviewBackportView`  ·  继承 `NSVisualEffectView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `appName` | `So11NSTextFieldCSg` |
| 1 | `windows` | `—` |

### `DockPreviewItemContainerView`  ·  继承 `NSView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `timer` | `So7NSTimerCSg` |
| 1 | `closeBtn` | `—` |
| 2 | `windowTitle` | `So11NSTextFieldCSg` |
| 3 | `imageButton` | `So8NSButtonCSg` |
| 4 | `delegate` | `—` |
| 5 | `windowsControlSize` | `—` |
| 6 | `delayShowCloseButtonTask` | `—` |
| 7 | `trackingArea` | `So14NSTrackingAreaCSg` |
| 8 | `isMouseInside` | `Sb` |

### `DockPreviewItemView`  ·  继承 `NSView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `conatinerView` | `—` |
| 1 | `itemWindow` | `—` |

### `DockPreviewVisualEffectView`  ·  继承 `NSGlassEffectView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `appName` | `So11NSTextFieldCSg` |
| 1 | `windows` | `—` |

### `DockPreviewWindow`  ·  继承 `NSPanel`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `DockPreviewerWC`  ·  继承 `NSWindowController`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `dockItem` | `—` |
| 1 | `items` | `—` |
| 2 | `log` | `So9OS_os_logC` |
| 3 | `dockItemPositionValue` | `—` |
| 4 | `dockItemPosition` | `—` |
| 5 | `delayHideTask` | `—` |
| 6 | `globalMouseMonitor` | `ypSg` |
| 7 | `mousePositionTimer` | `So7NSTimerCSg` |
| 8 | `$__lazy_storage_$_glassEffectView` | `So6NSViewCSgSg` |
| 9 | `$__lazy_storage_$_visualEffectView` | `—` |

### `DockRelocationCursorShield`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `panel` | `So7NSPanelC` |
| 1 | `isVisible` | `Sb` |

### `DockUtil`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `DockWindow`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `cgWindowId` | `—` |
| 1 | `lastFocusOrder` | `Si` |
| 2 | `creationOrder` | `Si` |
| 3 | `title` | `SSSg` |
| 4 | `thumbnail` | `So7NSImageCSg` |
| 5 | `thumbnailFullSize` | `T_!` |
| 6 | `shouldShowTheUser` | `Sb` |
| 7 | `isTabbed` | `Sb` |
| 8 | `isFullscreen` | `Sb` |
| 9 | `isMinimized` | `Sb` |
| 10 | `isOnAllSpaces` | `Sb` |
| 11 | `isWindowlessApp` | `Sb` |
| 12 | `position` | `t_!` |
| 13 | `size` | `T_!` |
| 14 | `spaceId` | `—` |
| 15 | `spaceIndex` | `Si` |
| 16 | `axUiElement` | `—` |
| 17 | `application` | `—` |
| 18 | `axObserver` | `$_!` |
| 19 | `row` | `SiSg` |

### `DockWindowPreviewController`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `axObserver` | `$_!` |
| 1 | `throttler` | `—` |
| 2 | `log` | `So9OS_os_logC` |
| 3 | `globleMouseLoc` | `t_!` |
| 4 | `isShowingDockRightMenu` | `Sb` |
| 5 | `debugLabel` | `SS` |
| 6 | `dockPreviewWC` | `—` |
| 7 | `mouseMovementSubject` | `—` |
| 8 | `mouseMovementCancellable` | `—` |
| 9 | `debounceInterval` | `Sd` |

### `DockWindowPreviewImageStore`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `applicationsCache` | `So7NSCacheCySo8NSStringCSo12NSMutableSetCG` |
| 1 | `windowsCache` | `—` |

### `DockWindowPreviewImageStoreItem`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `refreshDate` | `—` |
| 1 | `image` | `So7NSImageC` |

### `FlickDockController`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `pendingDockClick` | `—` |
| 1 | `lastDockClick` | `—` |
| 2 | `diagnosticClickSequence` | `—` |
| 3 | `activeDiagnosticClick` | `—` |
| 4 | `lastObservedFrontBundleId` | `SSSg` |
| 5 | `lastActivationRecord` | `—` |
| 6 | `appActivationObserver` | `So8NSObject_pSg` |
| 7 | `stateLock` | `So6NSLockC` |
| 8 | `pendingDockClickMaxAge` | `Sd` |
| 9 | `repeatClickTolerance` | `Sd` |
| 10 | `activationEventOrderingTolerance` | `Sd` |

### `FlickDockDiagnosticsPolicy`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `lock` | `So6NSLockC` |
| 1 | `enabledStorage` | `Sb` |


## 悬浮分屏岛 Snapping Island

### `SnappingIslandActivationDetector`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `topOverflowTolerance` | `—` |
| 1 | `horizontalTolerance` | `—` |
| 2 | `collapsedPreviewTopRatio` | `—` |
| 3 | `centerActivationWidthRatio` | `—` |

### `SnappingIslandController`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `window` | `—` |
| 1 | `viewModel` | `Hk!` |
| 2 | `screen` | `So8NSScreenCSg` |
| 3 | `hideAnimationGeneration` | `Si` |
| 4 | `localEditingEventMonitor` | `ypSg` |
| 5 | `globalEditingEventMonitor` | `ypSg` |
| 6 | `editingFocusObserver` | `So8NSObject_pSg` |
| 7 | `gridSelectorController` | `—` |
| 8 | `windowAnimator` | `—` |
| 9 | `activeTransition` | `di!` |
| 10 | `$__lazy_storage_$_editorActions` | `—` |

### `SnappingIslandGridSelectorController`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `window` | `—` |
| 1 | `localEventMonitor` | `ypSg` |
| 2 | `globalEventMonitor` | `ypSg` |
| 3 | `footprintPresenter` | `—` |
| 4 | `selectorSize` | `—` |

### `SnappingIslandGridSelectorPanel`  ·  继承 `NSPanel`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `onCancel` | `yycSg` |

### `SnappingIslandInteractionCoordinator`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `controller` | `—` |
| 1 | `activationDetector` | `—` |
| 2 | `lastActiveScreen` | `So8NSScreenCSg` |

### `SnappingIslandLayoutStore`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `SnappingIslandSavedPlacementStore`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `SnappingIslandViewModel`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `_state` | `—` |
| 1 | `_hoveredType` | `—` |
| 2 | `_hoverLocation` | `—` |
| 3 | `_layouts` | `—` |
| 4 | `_savedPlacements` | `—` |
| 5 | `_currentSize` | `—` |
| 6 | `_visualOpenProgress` | `—` |
| 7 | `_isEditingLayouts` | `—` |
| 8 | `_editorPanel` | `—` |
| 9 | `_draggingActiveLayoutID` | `—` |
| 10 | `_draggingSavedPlacementID` | `—` |
| 11 | `_invalidDropTargetID` | `—` |
| 12 | `_highlightedDropTargetID` | `—` |
| 13 | `_draftLayout` | `—` |

### `SnappingIslandWindow`  ·  继承 `NSPanel`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `isEditorInteractive` | `Sb` |

### `SnappingIslandWindowAnimator`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `window` | `So8NSWindowCSgXw` |
| 1 | `startFrame` | `—` |
| 2 | `targetFrame` | `—` |
| 3 | `topAnchorY` | `—` |
| 4 | `startAlpha` | `—` |
| 5 | `targetAlpha` | `—` |
| 6 | `motion` | `—` |
| 7 | `onFrameUpdate` | `—` |
| 8 | `completion` | `yycSg` |
| 9 | `timer` | `So7NSTimerCSg` |
| 10 | `startTime` | `Sd` |
| 11 | `didFinish` | `Sb` |


## 权限与引导 Permissions & onboarding

### `AccessibilityAuthorization`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `welcomeWindowController` | `—` |

### `AccessibilityElement`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `underlyingElement` | `—` |

### `AuthorizationViewController`  ·  继承 `NSViewController`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `authorizationIcon` | `So11NSImageViewCSgXw` |
| 1 | `authorizationScreenRecordIcon` | `So11NSImageViewCSgXw` |
| 2 | `backgroundView` | `So6NSViewCSgXw` |
| 3 | `continueButton` | `So8NSButtonCSgXw` |
| 4 | `authorizationText` | `So11NSTextFieldCSgXw` |
| 5 | `authorizScreenRecordText` | `So11NSTextFieldCSgXw` |

### `FirstGuideHostingController`  ·  继承 `NSWindowController`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `hostingWindow` | `So8NSWindowCSg` |
| 1 | `contentView` | `—` |
| 2 | `isDockIconRetained` | `Sb` |

### `FirstGuideViewController`  ·  继承 `NSViewController`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `delegate` | `—` |

### `FirstGuideWindowController`  ·  继承 `NSWindowController`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `isDockIconRetained` | `Sb` |

### `FirstGuideWrappingViewController`  ·  继承 `NSViewController`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `firstGuideViewController` | `—` |
| 1 | `authorizationViewController` | `—` |

### `MoveWinsViewController`  ·  继承 `NSViewController`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `MoveWinsWindowController`  ·  继承 `NSWindowController`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `ThemeAwareContentView`  ·  继承 `NSView`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `onAppearanceChange` | `yycSg` |

### `ViewController`  ·  继承 `NSViewController`
_无 ivar（纯静态工具类，或只有方法的计算类）_


## 布局计算 Layout calculations

### `AlmostMaximizeCalculation`  ·  继承 `0x1002972d8`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `almostMaximizeHeight` | `—` |
| 1 | `almostMaximizeWidth` | `—` |

### `BottomCenterLeftEighthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomCenterNinthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomCenterRightEighthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomCenterSixthCalculation`  ·  继承 `0x1002972d8`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `bottomRightTwoSixths` | `—` |
| 1 | `bottomLeftTwoSixths` | `—` |
| 2 | `topRightTwoSixths` | `—` |

### `BottomHalfCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomLeftEighthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomLeftNinthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomLeftSixthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomLeftThirdCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomLeftTwoSixthsCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomRightEighthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomRightNinthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomRightSixthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomRightThirdCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BottomRightTwoSixthsCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `CenterCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `CenterHalfCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `CenterThirdCalculation`  ·  继承 `0x1002972d8`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `params` | `—` |

### `ChangeSizeCalculation`  ·  继承 `0x1002972d8`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `minimumWindowWidth` | `—` |
| 1 | `minimumWindowHeight` | `—` |
| 2 | `screenEdgeGapSize` | `—` |
| 3 | `sizeOffsetAbs` | `—` |
| 4 | `curtainChangeSize` | `Sb` |

### `FirstFourthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `FirstThirdCalculation`  ·  继承 `0x1002972d8`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `params` | `—` |

### `FirstThreeFourthsCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `FirstTwoThirdsCalculation`  ·  继承 `0x1002972d8`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `params` | `—` |

### `GapCalculation`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `LastFourthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `LastThirdCalculation`  ·  继承 `0x1002972d8`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `params` | `—` |

### `LastThreeFourthsCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `LastTwoThirdsCalculation`  ·  继承 `0x1002972d8`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `params` | `—` |

### `LeftRightHalfCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `LowerLeftCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `LowerRightCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `MaximizeCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `MaximizeHeightCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `MiddleCenterNinthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `MiddleLeftNinthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `MiddleRightNinthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `MoveLeftRightCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `MoveUpDownCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `NextPrevDisplayCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `SecondFourthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `SpecifiedCalculation`  ·  继承 `0x1002972d8`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `specifiedHeight` | `—` |
| 1 | `specifiedWidth` | `—` |

### `ThirdFourthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopCenterLeftEighthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopCenterNinthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopCenterRightEighthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopCenterSixthCalculation`  ·  继承 `0x1002972d8`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `topRightTwoSixths` | `—` |
| 1 | `topLeftTwoSixths` | `—` |
| 2 | `bottomLeftTwoSixths` | `—` |

### `TopHalfCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopLeftEighthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopLeftNinthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopLeftSixthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopLeftThirdCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopLeftTwoSixthsCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopRightEighthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopRightNinthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopRightSixthCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopRightThirdCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TopRightTwoSixthsCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `UpperLeftCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `UpperRightCalculation`  ·  继承 `0x1002972d8`
_无 ivar（纯静态工具类，或只有方法的计算类）_


## 基础设施 Infrastructure

### `AppActivationTracker`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `currentFrontIdentifier` | `SSSg` |
| 1 | `minimizedBundles` | `ShySSG` |

### `AppDelegate`  ·  继承 `NSObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `accessibilityAuthorization` | `—` |
| 1 | `defaults` | `—` |
| 2 | `windowManager` | `—` |
| 3 | `shortcutManager` | `—` |
| 4 | `windowCalculationFactory` | `—` |
| 5 | `snappingManager` | `—` |
| 6 | `missionControlPro` | `—` |
| 7 | `commandTabPlus` | `—` |
| 8 | `appVersion` | `SSSg` |
| 9 | `preferenceNotificationCenter` | `—` |
| 10 | `appUpdateController` | `—` |
| 11 | `pandle` | `—` |
| 12 | `dockIconRequestCounts` | `—` |
| 13 | `isDockIconVisible` | `Sb` |

### `Application`  ·  继承 `NSObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `kvObservers` | `—` |
| 1 | `runningApplication` | `So20NSRunningApplicationC` |
| 2 | `axUiElement` | `—` |
| 3 | `axObserver` | `$_!` |
| 4 | `isReallyFinishedLaunching` | `Sb` |
| 5 | `isHidden` | `SbSg` |
| 6 | `hasBeenActiveOnce` | `SbSg` |
| 7 | `icon` | `So7NSImageCSg` |
| 8 | `dockLabel` | `SSSg` |
| 9 | `pid` | `—` |
| 10 | `focusedWindow` | `—` |
| 11 | `alreadyRequestedToQuit` | `Sb` |

### `Applications`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BackgroundWork`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `BoolDefault`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `defaultValue` | `Sb` |
| 1 | `key` | `SS` |
| 2 | `initialized` | `Sb` |
| 3 | `enabled` | `Sb` |

### `Debouncer`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `queue` | `So17OS_dispatch_queueC` |
| 1 | `interval` | `Sd` |
| 2 | `semaphore` | `—` |
| 3 | `workItem` | `—` |

### `Defaults`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `DemoGo`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `xMarkWindow` | `So8NSWindowCSg` |
| 1 | `eventTap` | `—` |
| 2 | `windowElement` | `—` |

### `EventMonitor`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `globalMonitor` | `ypSg` |
| 1 | `localMonitor` | `ypSg` |
| 2 | `mask` | `—` |
| 3 | `handler` | `ySo7NSEventCSgc` |

### `ExclusionApp`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `FloatDefault`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `key` | `SS` |
| 1 | `initialized` | `Sb` |
| 2 | `value` | `Sf` |

### `HardwareUtil`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `ImageUtils`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `IntDefault`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `key` | `SS` |
| 1 | `initialized` | `Sb` |
| 2 | `value` | `Si` |

### `IntOptionDefault`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `key` | `SS` |
| 1 | `initialized` | `Sb` |
| 2 | `value` | `SiSg` |

### `KeyRepeatTimer`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `LogCategorys`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `MouseMovementMonitor`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `eventTap` | `—` |
| 1 | `xMarkWindow` | `So8NSWindowCSg` |

### `OptionalBoolDefault`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `key` | `SS` |
| 1 | `initialized` | `Sb` |
| 2 | `enabled` | `SbSg` |

### `PreferenceNotificationCenter`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `appDelegate` | `—` |
| 1 | `paddle` | `—` |
| 2 | `preferenceChanged` | `—` |
| 3 | `openCustomLayoutEditor` | `—` |
| 4 | `preferencePanelPackage` | `SS` |
| 5 | `tiledMarginsMonitorTimer` | `So7NSTimerCSg` |
| 6 | `isApplyingMarginFromSystem` | `Sb` |
| 7 | `lastObservedSystemTiledMargins` | `SbSg` |

### `ProcessUtil`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `RunningAppIndex`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `titleToPids` | `—` |
| 1 | `pidToApp` | `—` |
| 2 | `pidMeta` | `—` |
| 3 | `lastBuiltAt` | `Sd` |
| 4 | `lastAppsCount` | `Si` |
| 5 | `ttl` | `Sd` |
| 6 | `queue` | `So17OS_dispatch_queueC` |

### `ScreenUtil`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `StorageUtil`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `applicationID` | `—` |

### `StringDefault`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `key` | `SS` |
| 1 | `initialized` | `Sb` |
| 2 | `value` | `SSSg` |

### `SubsequentExecutionDefault`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `key` | `SS` |
| 1 | `initialized` | `Sb` |
| 2 | `value` | `—` |

### `SysPreferenceUtil`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `Throttler`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `queue` | `So17OS_dispatch_queueC` |
| 1 | `interval` | `Sd` |
| 2 | `semaphore` | `—` |
| 3 | `workItem` | `—` |
| 4 | `lastExecuteTime` | `—` |

### `WorkspaceEvents`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_


## 授权与更新 License & update

### `AppUpdateController`  ·  继承 `NSObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `hostBundle` | `So8NSBundleC` |
| 1 | `dockIconController` | `—` |
| 2 | `alertPresenter` | `—` |
| 3 | `updater` | `So10SPUUpdaterCSg` |
| 4 | `updaterUserDriver` | `—` |
| 5 | `userInitiatedUpdateCheck` | `Sb` |
| 6 | `pendingApprovedUpdatePresentation` | `Sb` |

### `PaddleHelper`  ·  继承 `NSObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `VendorID` | `SS` |
| 1 | `ProductID` | `SS` |
| 2 | `APIKey` | `SS` |
| 3 | `debug` | `Sb` |
| 4 | `sandbox` | `Sb` |
| 5 | `paddle` | `So6PaddleCSg` |
| 6 | `paddleProduct` | `So10PADProductCSg` |
| 7 | `defaults` | `—` |
| 8 | `activationWindowController` | `—` |
| 9 | `refTrialIntervalHour` | `Si` |
| 10 | `maxSilentActivationFailureCount` | `Si` |
| 11 | `silentActivationFailureCount` | `Si` |
| 12 | `timer` | `So24OS_dispatch_source_timer_pSg` |

### `ShortcutManager`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `windowManager` | `—` |
| 1 | `paddleHelper` | `—` |

### `ShortcutsUtil`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `UpdateEntitlementAlertPresenter`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `UpdateEntitlementReleaseNotesNavigationDelegate`  ·  继承 `NSObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `UpdateEntitlementService`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `session` | `So12NSURLSessionC` |
| 1 | `encoder` | `—` |
| 2 | `decoder` | `—` |

### `UpdateEntitlementUserDriver`  ·  继承 `NSObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `standardUserDriver` | `So21SPUStandardUserDriverC` |
| 1 | `entitlementService` | `—` |
| 2 | `denialHandler` | `—` |
| 3 | `dockIconController` | `—` |
| 4 | `currentUpdateItem` | `So13SUAppcastItemCSg` |
| 5 | `approvedUpdateVersion` | `SSSg` |
| 6 | `entitlementWindowController` | `—` |
| 7 | `isStandardUpdateDockIconRetained` | `Sb` |
| 8 | `isStandardUpdateFoundWindowReadyForReleaseNotes` | `Sb` |
| 9 | `pendingStandardReleaseNotes` | `—` |

### `UpdateEntitlementWindowController`  ·  继承 `NSWindowController`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `appcastItem` | `So13SUAppcastItemC` |
| 1 | `decision` | `—` |
| 2 | `presentation` | `—` |
| 3 | `onComplete` | `—` |
| 4 | `dockIconController` | `—` |
| 5 | `didComplete` | `Sb` |
| 6 | `isDockIconRetained` | `Sb` |
| 7 | `isObservingReleaseNotesLoading` | `Sb` |
| 8 | `isPrimaryReleaseNotesLoadInProgress` | `Sb` |
| 9 | `layerUpdaters` | `SayyycG` |
| 10 | `releaseNotesNavigationDelegate` | `—` |
| 11 | `subheadLabel` | `So11NSTextFieldC` |
| 12 | `pillLabel` | `So11NSTextFieldC` |
| 13 | `pillContainer` | `So6NSViewC` |
| 14 | `bannerTitleLabel` | `So11NSTextFieldC` |
| 15 | `bannerBodyTextView` | `—` |
| 16 | `releaseNotesWebView` | `So6NSViewC` |
| 17 | `releaseNotesLoadingIndicator` | `So19NSProgressIndicatorC` |
| 18 | `releaseNotesLoadingLabel` | `So11NSTextFieldC` |

### `UpdateEntitlementWrappingTextView`  ·  继承 `NSTextView`
_无 ivar（纯静态工具类，或只有方法的计算类）_


## 窗口吸附引擎 Snapping engine

### `BestEffortWindowMover`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `CenteringFixedSizedWindowMover`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `FootprintPresenter`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `box` | `—` |

### `FootprintWindow`  ·  继承 `NSWindow`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `closeWorkItem` | `—` |
| 1 | `bgLayer` | `So7CALayerCSg` |
| 2 | `status` | `Si` |
| 3 | `showingType` | `—` |

### `MultiWindowManager`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `QuantizedWindowMover`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `ScreenDetection`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `SnapAreaDetector`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `marginTop` | `—` |
| 1 | `marginBottom` | `—` |
| 2 | `marginLeft` | `—` |
| 3 | `marginRight` | `—` |
| 4 | `ignoredSnapAreas` | `—` |
| 5 | `snapOptionToAction` | `—` |

### `SnappingManager`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `paddleHelper` | `—` |
| 1 | `dockWindowPreviewer` | `—` |
| 2 | `clickDockShowAndMinimumController` | `—` |
| 3 | `snapAreaDetector` | `—` |
| 4 | `cursorNudger` | `—` |
| 5 | `footprintPresenter` | `—` |
| 6 | `snappingIslandCoordinator` | `—` |
| 7 | `unsnapRestorer` | `—` |
| 8 | `eventMonitor` | `—` |
| 9 | `windowElement` | `—` |
| 10 | `windowId` | `SiSg` |
| 11 | `windowIdAttempt` | `Si` |
| 12 | `lastWindowIdAttempt` | `SdSg` |
| 13 | `windowMoving` | `Sb` |
| 14 | `isResizing` | `Sb` |
| 15 | `initialWindowRect` | `—` |
| 16 | `trackedWindowSizeSettable` | `SbSg` |
| 17 | `trackedWindowExclusionResult` | `SbSg` |
| 18 | `currentSnapArea` | `—` |
| 19 | `globleMouseLoc` | `t_!` |
| 20 | `mouseDownLocation` | `t_!` |

### `Spaces`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `StageUtil`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `StandardWindowMover`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `bestEffortWindowMover` | `—` |

### `SystemWindowManager`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `TrafficLightButton`  ·  继承 `NSButton`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `isMouseOver` | `Sb` |
| 1 | `type` | `—` |
| 2 | `dockWindow` | `—` |
| 3 | `delegate` | `—` |

### `UnsnapRestorer`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `WindowCalculation`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `WindowCalculationFactory`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `WindowHistory`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `restoreRects` | `—` |
| 1 | `restoreCenterRects` | `—` |
| 2 | `lastRectangleActions` | `—` |
| 3 | `lastSystemActions` | `—` |

### `WindowManager`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `screenDetection` | `—` |
| 1 | `standardWindowMoverChain` | `—` |
| 2 | `fixedSizeWindowMoverChain` | `—` |

### `Windows`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_


## Mission Control Pro

### `MissionControl`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `MissionControlCloseCoordinator`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `adapter` | `—` |
| 1 | `observationDelays` | `SaySdG` |
| 2 | `requestTimeout` | `Sd` |
| 3 | `callbackQueue` | `So17OS_dispatch_queueC` |
| 4 | `submissionQueue` | `So17OS_dispatch_queueC` |
| 5 | `timerQueue` | `So17OS_dispatch_queueC` |
| 6 | `outcomeHandler` | `—` |
| 7 | `lock` | `So6NSLockC` |
| 8 | `activeRequest` | `—` |
| 9 | `destructiveLease` | `—` |

### `MissionControlCursorNudger`  ·  继承 `SwiftObject`
_无 ivar（纯静态工具类，或只有方法的计算类）_

### `MissionControlDiagnosticsPolicy`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `lock` | `So6NSLockC` |
| 1 | `enabledStorage` | `Sb` |

### `MissionControlPro`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `xMarkWindow` | `So8NSWindowCSg` |
| 1 | `runLoopSource` | `—` |
| 2 | `eventTapRunLoop` | `—` |
| 3 | `sceneDetector` | `—` |
| 4 | `paddleHelper` | `—` |
| 5 | `hoveringElement` | `—` |
| 6 | `hoveringElementRealWindow` | `—` |
| 7 | `hoveringElementFrame` | `—` |
| 8 | `windowServerHoverTarget` | `—` |
| 9 | `lastWindowServerFallbackProbeUptime` | `Sd` |
| 10 | `cachedInteractiveSnapshot` | `—` |
| 11 | `isAwaitingAppExposeTabSnapshot` | `Sb` |
| 12 | `didDragBeforeMouseUp` | `Sb` |
| 13 | `isSuppressingSystemDrag` | `Sb` |
| 14 | `suppressXMarkUntil` | `—` |
| 15 | `dragEndSuppressionInterval` | `Sd` |
| 16 | `closedWindowIds` | `—` |
| 17 | `closedThumbnailCenters` | `—` |
| 18 | `lastPresentedXMarkOrigin` | `t_!` |
| 19 | `isClosing` | `Sb` |
| 20 | `partialCloseVerifyWorkItem` | `—` |
| 21 | `diagnosticSessionID` | `SS` |
| 22 | `diagnosticEpoch` | `—` |
| 23 | `diagnosticCleanupGeneration` | `—` |
| 24 | `diagnosticSessionIsActive` | `Sb` |
| 25 | `diagnosticLastSceneFingerprint` | `SSSg` |
| 26 | `diagnosticLastHoverFingerprint` | `SSSg` |
| 27 | `diagnosticLastResolveFingerprints` | `SDyS2SG` |
| 28 | `diagnosticLastNoHitUptime` | `Sd` |
| 29 | `diagnosticLastNoHitFingerprint` | `SSSg` |
| 30 | `diagnosticLastSessionEndFingerprint` | `SSSg` |
| 31 | `diagnosticActiveCloseTrace` | `—` |
| 32 | `closeStateLock` | `So6NSLockC` |
| 33 | `closeSessionGeneration` | `—` |
| 34 | `closeSessionIsActive` | `Sb` |
| 35 | `activeCoordinatedCloseRequestID` | `—` |
| 36 | `coordinatedCloseContexts` | `—` |
| 37 | `sceneLivenessCancellation` | `—` |
| 38 | `closeSessionLivenessCancellation` | `—` |
| 39 | `closeObservationQueue` | `So17OS_dispatch_queueC` |
| 40 | `$__lazy_storage_$_closeCoordinator` | `—` |

### `MissionControlSceneDetector`  ·  继承 `SwiftObject`
| # | ivar | Swift 类型 |
|--:|------|-----------|
| 0 | `minimumProbeInterval` | `Sd` |
| 1 | `maximumTraversalDepth` | `Si` |
| 2 | `maximumVisitedNodes` | `Si` |
| 3 | `maximumSupplementalTraversalDepth` | `Si` |
| 4 | `maximumSupplementalVisitedNodes` | `Si` |
| 5 | `cachedRoots` | `—` |
| 6 | `lastProbeUptime` | `Sd` |
| 7 | `cachedSnapshot` | `—` |
| 8 | `lastDiagnosticScanFingerprints` | `SDyS2SG` |
| 9 | `lastDiagnosticProviderFingerprints` | `SDyS2SG` |

### `MissionControlXButton`  ·  继承 `NSButton`
_无 ivar（纯静态工具类，或只有方法的计算类）_


---

## 附一：ObjC 不可见的 Swift 结构体 / 枚举（含字段与类型）

共 265 个。

### `EventTypeMask` — struct

| 字段 | 类型 |
|------|------|
| `rawValue` | `—` |

### `Name` — struct

| 字段 | 类型 |
|------|------|
| `_rawValue` | `So8NSStringC` |

### `CGSize` — struct

| 字段 | 类型 |
|------|------|
| `width` | `—` |
| `height` | `—` |

### `CGPoint` — struct

| 字段 | 类型 |
|------|------|
| `x` | `—` |
| `y` | `—` |

### `CGRect` — struct

| 字段 | 类型 |
|------|------|
| `origin` | `—` |
| `size` | `—` |

### `ModifierFlags` — struct

| 字段 | 类型 |
|------|------|
| `rawValue` | `Su` |

### `NSKeyValueChangeKey` — struct

| 字段 | 类型 |
|------|------|
| `_rawValue` | `So8NSStringC` |

### `Key` — struct

| 字段 | 类型 |
|------|------|
| `_rawValue` | `So8NSStringC` |

### `NSDeviceDescriptionKey` — struct

| 字段 | 类型 |
|------|------|
| `_rawValue` | `So8NSStringC` |

### `Name` — struct

| 字段 | 类型 |
|------|------|
| `_rawValue` | `So8NSStringC` |

### `CAMediaTimingFunctionName` — struct

| 字段 | 类型 |
|------|------|
| `_rawValue` | `So8NSStringC` |

### `DockRelocationCursorShield` — class

| 字段 | 类型 |
|------|------|
| `panel` | `So7NSPanelC` |
| `isVisible` | `Sb` |

### `DockDisplayManager` — class

| 字段 | 类型 |
|------|------|
| `moveQueue` | `So17OS_dispatch_queueC` |
| `adjacencyTolerance` | `—` |
| `minimumTriggerLength` | `—` |
| `relocationEdgeInset` | `—` |
| `relocationPointCount` | `Si` |
| `relocationPointIncrement` | `—` |
| `relocationInitialDelay` | `Sd` |
| `relocationPointInterval` | `Sd` |
| `verificationInterval` | `Sd` |
| `verificationTimeout` | `Sd` |
| `orientationTransitionInterval` | `Sd` |
| `orientationTransitionTimeout` | `Sd` |

### `Prerequisite` — enum

| 字段 | 类型 |
|------|------|
| `dockAtBottom` | `—` |
| `dockAutoHideDisabled` | `—` |
| `separateSpacesEnabled` | `—` |

### `BlockingZone` — struct

| 字段 | 类型 |
|------|------|
| `rect` | `—` |
| `edge` | `—` |

### `Interval` — struct

| 字段 | 类型 |
|------|------|
| `start` | `—` |
| `end` | `—` |

### `PrerequisiteStatus` — struct

| 字段 | 类型 |
|------|------|
| `unmet` | `—` |

### `MoveError` — enum

| 字段 | 类型 |
|------|------|
| `prerequisitesNotMet` | `—` |
| `verificationFailed` | `SSSg18currentDisplayName_t` |
| `displayDisconnected` | `—` |
| `accessibilityPermissionRequired` | `—` |
| `noReachableDockEdge` | `—` |
| `eventSourceUnavailable` | `—` |
| `dockProcessChanged` | `—` |

### `Display` — struct

| 字段 | 类型 |
|------|------|
| `id` | `—` |
| `uuid` | `SS` |
| `name` | `SS` |
| `frame` | `—` |
| `isMain` | `Sb` |

### `DockEdge` — enum

| 字段 | 类型 |
|------|------|
| `bottom` | `—` |
| `left` | `—` |
| `right` | `—` |

### `DockDisplayLockController` — class

| 字段 | 类型 |
|------|------|
| `manager` | `—` |
| `defaults` | `So14NSUserDefaultsC` |
| `healthInterval` | `Sd` |
| `displayConfigurationRetryDelay` | `Sd` |
| `automaticRetryDelay` | `Sd` |
| `successfulMoveCooldown` | `Sd` |
| `automaticPointerIdleInterval` | `Sd` |
| `isStarted` | `Sb` |
| `isMoveInFlight` | `Sb` |
| `operationGeneration` | `Su` |
| `lastSuccessfulMove` | `—` |
| `lastRealMouseMovement` | `—` |
| `nextAutomaticRetry` | `—` |
| `restoreWorkItem` | `—` |
| `scheduledRestoreReason` | `SSSg` |
| `healthTimer` | `So7NSTimerCSg` |
| `screenObserver` | `So8NSObject_pSg` |
| `workspaceObservers` | `SaySo8NSObject_pG` |
| `unlockObserver` | `So8NSObject_pSg` |
| `isObservingDockPreferences` | `Sb` |
| `observedDockPID` | `—` |
| `eventTap` | `—` |
| `eventTapSource` | `—` |
| `blockingZones` | `—` |
| `suspendedPrerequisites` | `—` |

### `DockLockRequirementRowView` — class

| 字段 | 类型 |
|------|------|
| `action` | `yyc` |
| `trackingArea` | `So14NSTrackingAreaCSg` |
| `isHovered` | `Sb` |
| `isPressed` | `Sb` |

### `DockLockPrerequisiteHUDController` — class

| 字段 | 类型 |
|------|------|
| `panel` | `—` |
| `contentStack` | `So11NSStackViewC` |
| `requirementGroup` | `—` |
| `requirementStack` | `So11NSStackViewC` |
| `noteLabel` | `So11NSTextFieldC` |
| `primaryButton` | `So8NSButtonC` |
| `secondaryButton` | `So8NSButtonC` |
| `windowWidth` | `—` |
| `rowHeight` | `—` |
| `separatorHeight` | `—` |
| `fixedWindowHeight` | `—` |
| `requirementHeightConstraint` | `So18NSLayoutConstraintCSg` |

### `BottomCenterSixthCalculation` — class

| 字段 | 类型 |
|------|------|
| `bottomRightTwoSixths` | `—` |
| `bottomLeftTwoSixths` | `—` |
| `topRightTwoSixths` | `—` |

### `DockPreviewVisualEffectView` — class

| 字段 | 类型 |
|------|------|
| `appName` | `So11NSTextFieldCSg` |
| `windows` | `—` |

### `SnappingIslandController` — class

| 字段 | 类型 |
|------|------|
| `window` | `—` |
| `viewModel` | `Hk!` |
| `screen` | `So8NSScreenCSg` |
| `hideAnimationGeneration` | `Si` |
| `localEditingEventMonitor` | `ypSg` |
| `globalEditingEventMonitor` | `ypSg` |
| `editingFocusObserver` | `So8NSObject_pSg` |
| `gridSelectorController` | `—` |
| `windowAnimator` | `—` |
| `activeTransition` | `di!` |
| `$__lazy_storage_$_editorActions` | `—` |

### `SnappingIslandState` — enum

| 字段 | 类型 |
|------|------|
| `collapsed` | `—` |
| `open` | `—` |

### `SnappingIslandView` — struct

| 字段 | 类型 |
|------|------|
| `_viewModel` | `—` |
| `editorActions` | `—` |

### `SnapArea` — struct

| 字段 | 类型 |
|------|------|
| `screen` | `So8NSScreenC` |
| `action` | `—` |
| `source` | `—` |
| `executionSource` | `—` |
| `customRect` | `—` |

### `SnapAreaTriggerSource` — enum

| 字段 | 类型 |
|------|------|
| `Snap` | `—` |
| `FloatingWindow` | `—` |

### `SnapAreaOption` — struct

| 字段 | 类型 |
|------|------|
| `rawValue` | `Si` |

### `SnapAreaDetector` — class

| 字段 | 类型 |
|------|------|
| `marginTop` | `—` |
| `marginBottom` | `—` |
| `marginLeft` | `—` |
| `marginRight` | `—` |
| `ignoredSnapAreas` | `—` |
| `snapOptionToAction` | `—` |

### `SnappingIslandActivationDetector` — class

| 字段 | 类型 |
|------|------|
| `topOverflowTolerance` | `—` |
| `horizontalTolerance` | `—` |
| `collapsedPreviewTopRatio` | `—` |
| `centerActivationWidthRatio` | `—` |

### `FootprintPresenter` — class

| 字段 | 类型 |
|------|------|
| `box` | `—` |

### `SnappingIslandWindowAnimator` — class

| 字段 | 类型 |
|------|------|
| `window` | `So8NSWindowCSgXw` |
| `startFrame` | `—` |
| `targetFrame` | `—` |
| `topAnchorY` | `—` |
| `startAlpha` | `—` |
| `targetAlpha` | `—` |
| `motion` | `—` |
| `onFrameUpdate` | `—` |
| `completion` | `yycSg` |
| `timer` | `So7NSTimerCSg` |
| `startTime` | `Sd` |
| `didFinish` | `Sb` |

### `SnappingIslandMotion` — struct

| 字段 | 类型 |
|------|------|
| `response` | `Sd` |
| `dampingFraction` | `—` |
| `duration` | `Sd` |
| `timingFunction` | `So21CAMediaTimingFunctionC` |

### `SnappingIslandTransition` — enum

| 字段 | 类型 |
|------|------|
| `show` | `—` |
| `expand` | `—` |
| `collapse` | `—` |
| `hide` | `—` |
| `resize` | `—` |

### `SnappingIslandWindow` — class

| 字段 | 类型 |
|------|------|
| `isEditorInteractive` | `Sb` |

### `SnappingIslandHoverResult` — struct

| 字段 | 类型 |
|------|------|
| `snap` | `—` |
| `showingType` | `—` |

### `SnappingIslandLayoutDefinition` — struct

| 字段 | 类型 |
|------|------|
| `id` | `SS` |
| `title` | `SS` |
| `isBuiltIn` | `Sb` |
| `segments` | `—` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `id` | `—` |
| `title` | `—` |
| `isBuiltIn` | `—` |
| `segments` | `—` |

### `Item` — struct

| 字段 | 类型 |
|------|------|
| `id` | `SS` |
| `title` | `SS` |
| `action` | `—` |
| `rect` | `—` |

### `SnappingIslandLayoutSegment` — struct

| 字段 | 类型 |
|------|------|
| `id` | `SS` |
| `actionRawValue` | `Si` |
| `legacySplitTypeRawValue` | `SiSg` |
| `rect` | `—` |
| `customRect` | `—` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `id` | `—` |
| `actionRawValue` | `—` |
| `legacySplitTypeRawValue` | `—` |
| `rect` | `—` |
| `customRect` | `—` |

### `NormalizedRect` — struct

| 字段 | 类型 |
|------|------|
| `x` | `—` |
| `y` | `—` |
| `width` | `—` |
| `height` | `—` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `x` | `—` |
| `y` | `—` |
| `width` | `—` |
| `height` | `—` |

### `GridCell` — struct

| 字段 | 类型 |
|------|------|
| `column` | `Si` |
| `row` | `Si` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `column` | `—` |
| `row` | `—` |

### `SnappingIslandLayoutGroup` — struct

| 字段 | 类型 |
|------|------|
| `definition` | `—` |
| `frame` | `—` |
| `targets` | `—` |

### `SnappingIslandTargetFrame` — struct

| 字段 | 类型 |
|------|------|
| `segment` | `—` |
| `action` | `—` |
| `legacySplitType` | `—` |
| `customRect` | `—` |
| `layoutID` | `SS` |
| `groupFrame` | `—` |
| `frame` | `—` |

### `SnappingIslandViewModel` — class

| 字段 | 类型 |
|------|------|
| `_state` | `—` |
| `_hoveredType` | `—` |
| `_hoverLocation` | `—` |
| `_layouts` | `—` |
| `_savedPlacements` | `—` |
| `_currentSize` | `—` |
| `_visualOpenProgress` | `—` |
| `_isEditingLayouts` | `—` |
| `_editorPanel` | `—` |
| `_draggingActiveLayoutID` | `—` |
| `_draggingSavedPlacementID` | `—` |
| `_invalidDropTargetID` | `—` |
| `_highlightedDropTargetID` | `—` |
| `_draftLayout` | `—` |

### `SnappingIslandLayoutDraft` — struct

| 字段 | 类型 |
|------|------|
| `title` | `SS` |
| `selectedItems` | `—` |

### `SnappingIslandEditorPanel` — enum

| 字段 | 类型 |
|------|------|
| `none` | `—` |
| `addLayout` | `—` |

### `SnappingIslandEditorActions` — struct

| 字段 | 类型 |
|------|------|
| `deleteActiveLayout` | `ySSc` |
| `deleteActiveSegment` | `ySS_SStc` |
| `moveActiveLayout` | `ySS_SStc` |
| `resetLayouts` | `yyc` |
| `openGridSelector` | `yyc` |
| `deleteSavedPlacement` | `ySSc` |
| `moveSavedPlacement` | `ySS_SStc` |
| `dropSavedPlacementOnActiveLayout` | `SbSS_S2SSgtc` |
| `createActiveLayoutFromSavedPlacement` | `SbSSc` |
| `finishEditing` | `yyc` |

### `SnappingIslandSolidBackground` — struct

| 字段 | 类型 |
|------|------|
| `topSeamGuardHeight` | `—` |
| `topCornerRadius` | `—` |
| `bottomCornerRadius` | `—` |
| `showsShadow` | `Sb` |
| `shadowProgress` | `—` |

### `SnappingIslandGrid` — struct

| 字段 | 类型 |
|------|------|
| `_viewModel` | `—` |
| `editorActions` | `—` |
| `editorCardSize` | `—` |
| `createDropTargetID` | `SS` |

### `SnappingIslandActiveLayoutDropDelegate` — struct

| 字段 | 类型 |
|------|------|
| `targetID` | `SS` |
| `viewModel` | `Hk!` |
| `editorActions` | `—` |

### `SnappingIslandCreateLayoutDropDelegate` — struct

| 字段 | 类型 |
|------|------|
| `targetID` | `SS` |
| `viewModel` | `Hk!` |
| `editorActions` | `—` |

### `SnappingIslandSavedPlacementsShelf` — struct

| 字段 | 类型 |
|------|------|
| `placements` | `—` |
| `_draggingSavedPlacementID` | `—` |
| `onDelete` | `ySSc` |
| `onMove` | `ySS_SStc` |
| `itemSize` | `—` |

### `SnappingIslandCreateLayoutDropCard` — struct

| 字段 | 类型 |
|------|------|
| `title` | `SS` |
| `subtitle` | `SS` |
| `highlighted` | `Sb` |
| `invalid` | `Sb` |

### `SnappingIslandSavedPlacementReorderDropDelegate` — struct

| 字段 | 类型 |
|------|------|
| `targetID` | `SS` |
| `_draggingSavedPlacementID` | `—` |
| `onMove` | `ySS_SStc` |

### `SnappingIslandSavedPlacementCardView` — struct

| 字段 | 类型 |
|------|------|
| `placement` | `—` |
| `onDelete` | `yyc` |
| `__isHovered` | `—` |

### `SnappingIslandLayoutCardView` — struct

| 字段 | 类型 |
|------|------|
| `group` | `—` |
| `hoveredType` | `—` |
| `hoverLocation` | `t_!` |
| `isEditing` | `Sb` |
| `invalidDrop` | `Sb` |
| `highlightedDrop` | `Sb` |
| `draggingSavedPlacementID` | `SSSg` |
| `onDeleteSegment` | `ySSc` |
| `onDropSavedPlacement` | `SbSS_SSSgtc` |
| `__jiggle` | `—` |
| `__localDropHover` | `—` |

### `SnappingIslandSavedPlacementDropDelegate` — struct

| 字段 | 类型 |
|------|------|
| `replacingSegmentID` | `SSSg` |
| `draggingSavedPlacementID` | `SSSg` |
| `onHoverChanged` | `ySbc` |
| `onDrop` | `SbSS_SSSgtc` |

### `SnappingIslandTargetSegmentView` — struct

| 字段 | 类型 |
|------|------|
| `isHovered` | `Sb` |
| `highlightColor` | `—` |

### `SnappingIslandShape` — struct

| 字段 | 类型 |
|------|------|
| `topCornerRadius` | `—` |
| `bottomCornerRadius` | `—` |

### `SnappingIslandInteractionCoordinator` — class

| 字段 | 类型 |
|------|------|
| `controller` | `—` |
| `activationDetector` | `—` |
| `lastActiveScreen` | `So8NSScreenCSg` |

### `SplitWindowItemType` — enum

| 字段 | 类型 |
|------|------|
| `left1_1` | `—` |
| `left1_2` | `—` |
| `left2_1` | `—` |
| `left2_2` | `—` |
| `right1_1` | `—` |
| `right1_2` | `—` |
| `right1_3` | `—` |
| `right2_1` | `—` |
| `right2_2` | `—` |
| `right2_3` | `—` |
| `right2_4` | `—` |

### `SnappingIslandGridSelectorController` — class

| 字段 | 类型 |
|------|------|
| `window` | `—` |
| `localEventMonitor` | `ypSg` |
| `globalEventMonitor` | `ypSg` |
| `footprintPresenter` | `—` |
| `selectorSize` | `—` |

### `SnappingIslandGridSelectorPanel` — class

| 字段 | 类型 |
|------|------|
| `onCancel` | `yycSg` |

### `HoverTrackingView` — class

| 字段 | 类型 |
|------|------|
| `onMove` | `—` |
| `trackingArea` | `So14NSTrackingAreaCSg` |

### `SnappingIslandGridSelectorView` — struct

| 字段 | 类型 |
|------|------|
| `onCommit` | `—` |
| `onPreview` | `—` |
| `onCancel` | `yyc` |
| `gridSize` | `Si` |
| `previewSize` | `—` |
| `__dragStartCell` | `—` |
| `__dragCurrentCell` | `—` |
| `__hoveringCell` | `—` |

### `GridHoverReader` — struct

| 字段 | 类型 |
|------|------|
| `onMove` | `—` |

### `SnappingIslandSavedPlacement` — struct

| 字段 | 类型 |
|------|------|
| `id` | `SS` |
| `title` | `SS` |
| `rect` | `—` |
| `createdAt` | `Sd` |
| `isBuiltIn` | `Sb` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `id` | `—` |
| `title` | `—` |
| `rect` | `—` |
| `createdAt` | `—` |
| `isBuiltIn` | `—` |

### `DockWindowPreviewController` — class

| 字段 | 类型 |
|------|------|
| `axObserver` | `$_!` |
| `throttler` | `—` |
| `log` | `So9OS_os_logC` |
| `globleMouseLoc` | `t_!` |
| `isShowingDockRightMenu` | `Sb` |
| `debugLabel` | `SS` |
| `dockPreviewWC` | `—` |
| `mouseMovementSubject` | `—` |
| `mouseMovementCancellable` | `—` |
| `debounceInterval` | `Sd` |

### `CommandTabPreviewVisualEffectView` — class

| 字段 | 类型 |
|------|------|
| `appName` | `So11NSTextFieldCSg` |
| `stripView` | `—` |

### `CenterThirdCalculation` — class

| 字段 | 类型 |
|------|------|
| `params` | `—` |

### `PoofConfig` — struct

| 字段 | 类型 |
|------|------|
| `totalDuration` | `Sd` |
| `reduceDuration` | `Sd` |
| `overshootScale` | `—` |
| `collapseScale` | `—` |
| `removeTargetAfter` | `Sb` |
| `hideOriginalDuringAnimation` | `Sb` |
| `originalViewDimmedAlpha` | `—` |
| `fadeOutCurve` | `—` |
| `scaleOutCurve` | `—` |
| `enableParticles` | `Sb` |
| `particleCountMean` | `Si` |
| `particleCountRange` | `Si` |
| `particleLifetime` | `Sd` |
| `particleVelocity` | `—` |
| `particleVelocityRange` | `—` |
| `particleEmissionRange` | `—` |
| `particleUpwardBiasDeg` | `—` |
| `highlightFraction` | `—` |
| `particleScaleRange` | `—` |
| `burstPulse` | `Sd` |
| `totalParticleCount` | `Si` |
| `explosionStrength` | `—` |
| `enableHighQualityTextures` | `Sb` |

### `DockPreviewerWC` — class

| 字段 | 类型 |
|------|------|
| `dockItem` | `—` |
| `items` | `—` |
| `log` | `So9OS_os_logC` |
| `dockItemPositionValue` | `—` |
| `dockItemPosition` | `—` |
| `delayHideTask` | `—` |
| `globalMouseMonitor` | `ypSg` |
| `mousePositionTimer` | `So7NSTimerCSg` |
| `$__lazy_storage_$_glassEffectView` | `So6NSViewCSgSg` |
| `$__lazy_storage_$_visualEffectView` | `—` |

### `AxError` — enum

| 字段 | 类型 |
|------|------|
| `runtimeError` | `—` |

### `Application` — class

| 字段 | 类型 |
|------|------|
| `kvObservers` | `—` |
| `runningApplication` | `So20NSRunningApplicationC` |
| `axUiElement` | `—` |
| `axObserver` | `$_!` |
| `isReallyFinishedLaunching` | `Sb` |
| `isHidden` | `SbSg` |
| `hasBeenActiveOnce` | `SbSg` |
| `icon` | `So7NSImageCSg` |
| `dockLabel` | `SSSg` |
| `pid` | `—` |
| `focusedWindow` | `—` |
| `alreadyRequestedToQuit` | `Sb` |

### `PreferenceNotificationCenter` — class

| 字段 | 类型 |
|------|------|
| `appDelegate` | `—` |
| `paddle` | `—` |
| `preferenceChanged` | `—` |
| `openCustomLayoutEditor` | `—` |
| `preferencePanelPackage` | `SS` |
| `tiledMarginsMonitorTimer` | `So7NSTimerCSg` |
| `isApplyingMarginFromSystem` | `Sb` |
| `lastObservedSystemTiledMargins` | `SbSg` |

### `FootprintWindow` — class

| 字段 | 类型 |
|------|------|
| `closeWorkItem` | `—` |
| `bgLayer` | `So7CALayerCSg` |
| `status` | `Si` |
| `showingType` | `—` |

### `FirstGuideHostingController` — class

| 字段 | 类型 |
|------|------|
| `hostingWindow` | `So8NSWindowCSg` |
| `contentView` | `—` |
| `isDockIconRetained` | `Sb` |

### `FirstGuideRootView` — struct

| 字段 | 类型 |
|------|------|
| `__showAuthorizationView` | `—` |
| `_accessibilityGranted` | `—` |
| `_screenRecordingGranted` | `—` |
| `onGranted` | `yyc` |
| `onScreenRecordGranted` | `yyc` |

### `AuthorizationView` — struct

| 字段 | 类型 |
|------|------|
| `_accessibilityGranted` | `—` |
| `_screenRecordingGranted` | `—` |
| `onAccessibilityGranted` | `yyc` |
| `onScreenRecordGranted` | `yyc` |

### `WelcomeView` — struct

| 字段 | 类型 |
|------|------|
| `onContinue` | `yyc` |

### `FeatureRow` — struct

| 字段 | 类型 |
|------|------|
| `icon` | `SS` |
| `iconColor` | `—` |
| `bgColor` | `—` |
| `title` | `SS` |
| `description` | `SS` |

### `FirstThirdCalculation` — class

| 字段 | 类型 |
|------|------|
| `params` | `—` |

### `ExclusionAppModel` — struct

| 字段 | 类型 |
|------|------|
| `id` | `Si` |
| `appName` | `SS` |
| `appStatus` | `Sb` |
| `appPath` | `SS` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `id` | `—` |
| `appName` | `—` |
| `appStatus` | `—` |
| `appPath` | `—` |

### `CommandTabPlus` — class

| 字段 | 类型 |
|------|------|
| `eventTap` | `—` |
| `runLoopSource` | `—` |
| `isActive` | `Sb` |
| `isCommandTabActive` | `Sb` |
| `lastSelectedApp` | `So20NSRunningApplicationCSg` |
| `lastSwitchKeyDownTime` | `Sd` |
| `lastDetectionStartTime` | `Sd` |
| `endedByPreviewCommit` | `Sb` |
| `mouseEventTap` | `—` |
| `mouseRunLoopSource` | `—` |
| `lastMouseHoverAppBundleId` | `SSSg` |
| `lastMouseEventTime` | `Sd` |
| `mouseEventThrottle` | `Sd` |
| `mouseHoverDetectionQueue` | `So17OS_dispatch_queueC` |
| `pendingHoverDetection` | `—` |
| `latestMouseLocation` | `—` |
| `lastMouseMoveDetectionTime` | `Sd` |
| `mouseMoveDetectionThrottle` | `Sd` |
| `pendingSelectedAppDetection` | `—` |
| `fastDetectToken` | `—` |
| `fastDetectSatisfiedToken` | `—` |
| `lastSwitchEventTS` | `Sd` |
| `lastScrollEventReceivedTS` | `Sd` |
| `scrollEventThrottle` | `Sd` |
| `appTitleExactCache` | `SDySSSo20NSRunningApplicationC3app_Sd2tstG` |
| `appTitleCacheQueue` | `So17OS_dispatch_queueC` |
| `appTitleCacheTTL` | `Sd` |
| `cachedDockApp` | `So20NSRunningApplicationCSg` |
| `cachedDockAppTs` | `Sd` |
| `dockAppCacheTTL` | `Sd` |
| `cachedProcessSwitcherPath` | `SaySiG` |
| `lastCacheTime` | `Sd` |
| `cacheValidDuration` | `Sd` |

### `QueueItem` — struct

| 字段 | 类型 |
|------|------|
| `element` | `—` |
| `depth` | `Si` |
| `path` | `SaySiG` |

### `SelectedAppInfo` — struct

| 字段 | 类型 |
|------|------|
| `app` | `So20NSRunningApplicationC` |
| `position` | `—` |
| `size` | `—` |

### `QueueItem` — struct

| 字段 | 类型 |
|------|------|
| `element` | `—` |
| `depth` | `Si` |
| `path` | `SaySiG` |

### `Throttler` — class

| 字段 | 类型 |
|------|------|
| `queue` | `So17OS_dispatch_queueC` |
| `interval` | `Sd` |
| `semaphore` | `—` |
| `workItem` | `—` |
| `lastExecuteTime` | `—` |

### `Debouncer` — class

| 字段 | 类型 |
|------|------|
| `queue` | `So17OS_dispatch_queueC` |
| `interval` | `Sd` |
| `semaphore` | `—` |
| `workItem` | `—` |

### `DebouncerSemaphore` — struct

| 字段 | 类型 |
|------|------|
| `semaphore` | `So21OS_dispatch_semaphoreC` |

### `BoolDefault` — class

| 字段 | 类型 |
|------|------|
| `defaultValue` | `Sb` |
| `key` | `SS` |
| `initialized` | `Sb` |
| `enabled` | `Sb` |

### `OptionalBoolDefault` — class

| 字段 | 类型 |
|------|------|
| `key` | `SS` |
| `initialized` | `Sb` |
| `enabled` | `SbSg` |

### `StringDefault` — class

| 字段 | 类型 |
|------|------|
| `key` | `SS` |
| `initialized` | `Sb` |
| `value` | `SSSg` |

### `FloatDefault` — class

| 字段 | 类型 |
|------|------|
| `key` | `SS` |
| `initialized` | `Sb` |
| `value` | `Sf` |

### `IntDefault` — class

| 字段 | 类型 |
|------|------|
| `key` | `SS` |
| `initialized` | `Sb` |
| `value` | `Si` |

### `IntOptionDefault` — class

| 字段 | 类型 |
|------|------|
| `key` | `SS` |
| `initialized` | `Sb` |
| `value` | `SiSg` |

### `JSONDefault` — class

| 字段 | 类型 |
|------|------|
| `typeInitialized` | `Sb` |
| `typedValue` | `xSg` |

### `StandardWindowMover` — class

| 字段 | 类型 |
|------|------|
| `bestEffortWindowMover` | `—` |

### `AccessibilityAuthorization` — class

| 字段 | 类型 |
|------|------|
| `welcomeWindowController` | `—` |

### `AlmostMaximizeCalculation` — class

| 字段 | 类型 |
|------|------|
| `almostMaximizeHeight` | `—` |
| `almostMaximizeWidth` | `—` |

### `DockPreviewBackportView` — class

| 字段 | 类型 |
|------|------|
| `appName` | `So11NSTextFieldCSg` |
| `windows` | `—` |

### `AccessibilityElement` — class

| 字段 | 类型 |
|------|------|
| `underlyingElement` | `—` |

### `DockWindow` — class

| 字段 | 类型 |
|------|------|
| `cgWindowId` | `—` |
| `lastFocusOrder` | `Si` |
| `creationOrder` | `Si` |
| `title` | `SSSg` |
| `thumbnail` | `So7NSImageCSg` |
| `thumbnailFullSize` | `T_!` |
| `shouldShowTheUser` | `Sb` |
| `isTabbed` | `Sb` |
| `isFullscreen` | `Sb` |
| `isMinimized` | `Sb` |
| `isOnAllSpaces` | `Sb` |
| `isWindowlessApp` | `Sb` |
| `position` | `t_!` |
| `size` | `T_!` |
| `spaceId` | `—` |
| `spaceIndex` | `Si` |
| `axUiElement` | `—` |
| `application` | `—` |
| `axObserver` | `$_!` |
| `row` | `SiSg` |

### `ElementState` — struct

| 字段 | 类型 |
|------|------|
| `generation` | `—` |
| `isInFlight` | `Sb` |
| `pendingWork` | `—` |

### `PendingWork` — struct

| 字段 | 类型 |
|------|------|
| `session` | `—` |
| `action` | `yyycc` |

### `DockPreviewItemContainerView` — class

| 字段 | 类型 |
|------|------|
| `timer` | `So7NSTimerCSg` |
| `closeBtn` | `—` |
| `windowTitle` | `So11NSTextFieldCSg` |
| `imageButton` | `So8NSButtonCSg` |
| `delegate` | `—` |
| `windowsControlSize` | `—` |
| `delayShowCloseButtonTask` | `—` |
| `trackingArea` | `So14NSTrackingAreaCSg` |
| `isMouseInside` | `Sb` |

### `MissionControlState` — enum

| 字段 | 类型 |
|------|------|
| `showAllWindows` | `—` |
| `showFrontWindows` | `—` |
| `showDesktop` | `—` |
| `inactive` | `—` |

### `MCPDiagnosticCloseTrace` — class

| 字段 | 类型 |
|------|------|
| `actionID` | `SS` |
| `sessionID` | `SS` |
| `epoch` | `—` |
| `cleanupGeneration` | `—` |
| `startedUptime` | `Sd` |
| `windowID` | `—` |
| `ownerPID` | `—` |
| `trigger` | `SS` |
| `lock` | `So6NSLockC` |
| `phaseStorage` | `SS` |

### `MCPDispatchWorkCancellation` — class

| 字段 | 类型 |
|------|------|
| `lock` | `So6NSLockC` |
| `workItem` | `—` |
| `cancelled` | `Sb` |

### `MCPValidatedCloseBaseline` — class

| 字段 | 类型 |
|------|------|
| `lock` | `So6NSLockC` |
| `baseline` | `—` |

### `MissionControlPro` — class

| 字段 | 类型 |
|------|------|
| `xMarkWindow` | `So8NSWindowCSg` |
| `runLoopSource` | `—` |
| `eventTapRunLoop` | `—` |
| `sceneDetector` | `—` |
| `paddleHelper` | `—` |
| `hoveringElement` | `—` |
| `hoveringElementRealWindow` | `—` |
| `hoveringElementFrame` | `—` |
| `windowServerHoverTarget` | `—` |
| `lastWindowServerFallbackProbeUptime` | `Sd` |
| `cachedInteractiveSnapshot` | `—` |
| `isAwaitingAppExposeTabSnapshot` | `Sb` |
| `didDragBeforeMouseUp` | `Sb` |
| `isSuppressingSystemDrag` | `Sb` |
| `suppressXMarkUntil` | `—` |
| `dragEndSuppressionInterval` | `Sd` |
| `closedWindowIds` | `—` |
| `closedThumbnailCenters` | `—` |
| `lastPresentedXMarkOrigin` | `t_!` |
| `isClosing` | `Sb` |
| `partialCloseVerifyWorkItem` | `—` |
| `diagnosticSessionID` | `SS` |
| `diagnosticEpoch` | `—` |
| `diagnosticCleanupGeneration` | `—` |
| `diagnosticSessionIsActive` | `Sb` |
| `diagnosticLastSceneFingerprint` | `SSSg` |
| `diagnosticLastHoverFingerprint` | `SSSg` |
| `diagnosticLastResolveFingerprints` | `SDyS2SG` |
| `diagnosticLastNoHitUptime` | `Sd` |
| `diagnosticLastNoHitFingerprint` | `SSSg` |
| `diagnosticLastSessionEndFingerprint` | `SSSg` |
| `diagnosticActiveCloseTrace` | `—` |
| `closeStateLock` | `So6NSLockC` |
| `closeSessionGeneration` | `—` |
| `closeSessionIsActive` | `Sb` |
| `activeCoordinatedCloseRequestID` | `—` |
| `coordinatedCloseContexts` | `—` |
| `sceneLivenessCancellation` | `—` |
| `closeSessionLivenessCancellation` | `—` |
| `closeObservationQueue` | `So17OS_dispatch_queueC` |
| `$__lazy_storage_$_closeCoordinator` | `—` |

### `CoordinatedCloseContext` — struct

| 字段 | 类型 |
|------|------|
| `thumbnail` | `—` |
| `window` | `—` |
| `trace` | `—` |
| `windowServerFallbackDisplayID` | `—` |

### `WindowServerHoverTarget` — struct

| 字段 | 类型 |
|------|------|
| `windowID` | `—` |
| `ownerPID` | `—` |
| `window` | `—` |
| `frame` | `—` |
| `displayID` | `—` |

### `MCPPrecloseBaseline` — struct

| 字段 | 类型 |
|------|------|
| `windowIDs` | `—` |
| `sceneBaselineIsComplete` | `Sb` |

### `MissionControlDiagnosticsPolicy` — class

| 字段 | 类型 |
|------|------|
| `lock` | `So6NSLockC` |
| `enabledStorage` | `Sb` |

### `MissionControlCloseCoordinator` — class

| 字段 | 类型 |
|------|------|
| `adapter` | `—` |
| `observationDelays` | `SaySdG` |
| `requestTimeout` | `Sd` |
| `callbackQueue` | `So17OS_dispatch_queueC` |
| `submissionQueue` | `So17OS_dispatch_queueC` |
| `timerQueue` | `So17OS_dispatch_queueC` |
| `outcomeHandler` | `—` |
| `lock` | `So6NSLockC` |
| `activeRequest` | `—` |
| `destructiveLease` | `—` |

### `MissionControlCloseResolution` — struct

| 字段 | 类型 |
|------|------|
| `request` | `—` |
| `outcome` | `—` |

### `MissionControlCloseRequest` — struct

| 字段 | 类型 |
|------|------|
| `id` | `—` |
| `session` | `—` |
| `targetWindowID` | `—` |
| `ownerPID` | `—` |
| `targetFrame` | `—` |
| `baselineWindowIDs` | `—` |
| `sceneKind` | `—` |

### `DestructiveLease` — struct

| 字段 | 类型 |
|------|------|
| `requestID` | `—` |
| `session` | `—` |

### `ActiveRequest` — struct

| 字段 | 类型 |
|------|------|
| `request` | `—` |
| `observationCancellation` | `—` |
| `requestTimeoutWorkItem` | `—` |
| `resolutionPending` | `Sb` |
| `consecutiveCompleteAbsences` | `Si` |
| `rolloverCandidateWindowID` | `—` |
| `rolloverCandidateCount` | `Si` |
| `destructiveCommandStarted` | `Sb` |
| `sceneBaselineIsComplete` | `Sb` |
| `observationGeneration` | `—` |

### `MissionControlCloseThumbnail` — struct

| 字段 | 类型 |
|------|------|
| `windowID` | `—` |
| `ownerPID` | `—` |
| `frame` | `—` |

### `MissionControlCloseSnapshot` — struct

| 字段 | 类型 |
|------|------|
| `session` | `—` |
| `isInteractive` | `Sb` |
| `thumbnails` | `—` |
| `unresolvedFrames` | `—` |
| `sceneKind` | `—` |
| `sceneInventoryIsComplete` | `Sb` |
| `liveOwnerWindowIDs` | `—` |
| `windowServerInventoryIsComplete` | `Sb` |

### `MissionControlCloseCommandResult` — enum

| 字段 | 类型 |
|------|------|
| `sent` | `—` |
| `failed` | `—` |
| `preflightRejected` | `—` |
| `notClosable` | `—` |

### `MissionControlCloseRequestDisposition` — enum

| 字段 | 类型 |
|------|------|
| `accepted` | `—` |
| `rejectedAlreadyClosing` | `—` |

### `MissionControlCloseOutcome` — enum

| 字段 | 类型 |
|------|------|
| `rolledOver` | `—` |
| `closed` | `—` |
| `unconfirmed` | `—` |
| `aborted` | `—` |
| `sessionEnded` | `—` |

### `MissionControlCloseSceneKind` — enum

| 字段 | 类型 |
|------|------|
| `missionControl` | `—` |
| `appExpose` | `—` |

### `MissionControlCloseRect` — struct

| 字段 | 类型 |
|------|------|
| `x` | `Sd` |
| `y` | `Sd` |
| `width` | `Sd` |
| `height` | `Sd` |

### `MissionControlCloseSessionToken` — struct

| 字段 | 类型 |
|------|------|
| `rawValue` | `—` |

### `MissionControlSceneDetector` — class

| 字段 | 类型 |
|------|------|
| `minimumProbeInterval` | `Sd` |
| `maximumTraversalDepth` | `Si` |
| `maximumVisitedNodes` | `Si` |
| `maximumSupplementalTraversalDepth` | `Si` |
| `maximumSupplementalVisitedNodes` | `Si` |
| `cachedRoots` | `—` |
| `lastProbeUptime` | `Sd` |
| `cachedSnapshot` | `—` |
| `lastDiagnosticScanFingerprints` | `SDyS2SG` |
| `lastDiagnosticProviderFingerprints` | `SDyS2SG` |

### `CachedRoot` — struct

| 字段 | 类型 |
|------|------|
| `application` | `So20NSRunningApplicationC` |
| `element` | `—` |

### `MissionControlSceneSnapshot` — struct

| 字段 | 类型 |
|------|------|
| `kind` | `—` |
| `thumbnails` | `—` |
| `provider` | `SSSg` |
| `inventoryIsComplete` | `Sb` |

### `QueueItem` — struct

| 字段 | 类型 |
|------|------|
| `element` | `—` |
| `depth` | `Si` |
| `inheritedKind` | `—` |

### `DetectedScene` — struct

| 字段 | 类型 |
|------|------|
| `kind` | `—` |
| `thumbnails` | `—` |
| `provider` | `SS` |
| `inventoryIsComplete` | `Sb` |

### `MissionControlSceneKind` — enum

| 字段 | 类型 |
|------|------|
| `inactive` | `—` |
| `missionControl` | `—` |
| `appExpose` | `—` |
| `showDesktop` | `—` |
| `activeUnknown` | `—` |

### `WindowDragPerfEventToken` — struct

| 字段 | 类型 |
|------|------|
| `sessionID` | `—` |
| `key` | `SS` |
| `sequence` | `—` |
| `startedAt` | `—` |
| `startedOnMainThread` | `Sb` |
| `sampled` | `Sb` |

### `SummarySnapshot` — struct

| 字段 | 类型 |
|------|------|
| `label` | `SS` |
| `sessionID` | `—` |
| `durationNanoseconds` | `—` |
| `eventCounts` | `SDySSSiG` |
| `eventTimings` | `—` |
| `stageTimings` | `—` |
| `counters` | `SDySSSiG` |
| `slowMainEvents` | `Si` |

### `TimingStats` — struct

| 字段 | 类型 |
|------|------|
| `count` | `Si` |
| `totalNanoseconds` | `—` |
| `maximumNanoseconds` | `—` |

### `WindowDragPerfStage` — enum

| 字段 | 类型 |
|------|------|
| `snappingFilter` | `—` |
| `snappingMouseDown` | `—` |
| `snappingMouseUp` | `—` |
| `dragWindowHitTestAX` | `—` |
| `dragWindowIdentifier` | `—` |
| `dragWindowRectAX` | `—` |
| `dragWindowRectAXFallback` | `—` |
| `dragWindowRectWindowServer` | `—` |
| `dragWindowRectWindowListFallback` | `—` |
| `dragSizeSettableAX` | `—` |
| `dragFlickDockPrepare` | `—` |
| `dragFlickDockRelease` | `—` |
| `dragSnapAreaDetection` | `—` |
| `dragStageManager` | `—` |
| `dragExclusionCheck` | `—` |
| `dragCursorNudge` | `—` |
| `dragShake` | `—` |
| `dragEdgeUpdate` | `—` |
| `dragIslandUpdate` | `—` |
| `dragUnsnapRestore` | `—` |
| `dockPreviewForward` | `—` |
| `dockPreviewHandle` | `—` |
| `dockWindowAXObserver` | `—` |
| `dockWindowMainQueueDelay` | `—` |
| `dockWindowMainUpdate` | `—` |
| `islandShow` | `—` |
| `islandHide` | `—` |
| `islandLayoutReload` | `—` |
| `islandLayoutJSON` | `—` |
| `islandLayoutSanitize` | `—` |
| `islandInteractionUpdate` | `—` |
| `islandAnimationFrame` | `—` |
| `footprintTargetRect` | `—` |
| `footprintShow` | `—` |
| `footprintClose` | `—` |
| `screenDetection` | `—` |
| `missionControlHandle` | `—` |
| `missionControlSnapshot` | `—` |
| `missionControlProbe` | `—` |
| `missionControlDockScan` | `—` |
| `missionControlWindowManagerScan` | `—` |
| `windowEnumeration` | `—` |
| `screenshot` | `—` |

### `WindowDragPerfSessionToken` — struct

| 字段 | 类型 |
|------|------|
| `sessionID` | `—` |

### `FirstTwoThirdsCalculation` — class

| 字段 | 类型 |
|------|------|
| `params` | `—` |

### `ThreadSafeArray` — class

| 字段 | 类型 |
|------|------|
| `array` | `SayxG` |
| `lock` | `—` |

### `DockPreviewItemView` — class

| 字段 | 类型 |
|------|------|
| `conatinerView` | `—` |
| `itemWindow` | `—` |

### `WindowManager` — class

| 字段 | 类型 |
|------|------|
| `screenDetection` | `—` |
| `standardWindowMoverChain` | `—` |
| `fixedSizeWindowMoverChain` | `—` |

### `RectangleAction` — struct

| 字段 | 类型 |
|------|------|
| `action` | `—` |
| `subAction` | `—` |
| `rect` | `—` |
| `count` | `Si` |

### `ExecutionParameters` — struct

| 字段 | 类型 |
|------|------|
| `action` | `—` |
| `updateRestoreRect` | `Sb` |
| `screen` | `So8NSScreenCSg` |
| `windowElement` | `—` |
| `windowId` | `SiSg` |
| `source` | `—` |
| `customRect` | `—` |

### `ExecutionSource` — enum

| 字段 | 类型 |
|------|------|
| `keyboardShortcut` | `—` |
| `dragToSnap` | `—` |
| `externalPortraitSideSnap` | `—` |
| `menuItem` | `—` |

### `ChangeSizeCalculation` — class

| 字段 | 类型 |
|------|------|
| `minimumWindowWidth` | `—` |
| `minimumWindowHeight` | `—` |
| `screenEdgeGapSize` | `—` |
| `sizeOffsetAbs` | `—` |
| `curtainChangeSize` | `Sb` |

### `DemoGo` — class

| 字段 | 类型 |
|------|------|
| `xMarkWindow` | `So8NSWindowCSg` |
| `eventTap` | `—` |
| `windowElement` | `—` |

### `MouseMovementMonitor` — class

| 字段 | 类型 |
|------|------|
| `eventTap` | `—` |
| `xMarkWindow` | `So8NSWindowCSg` |

### `WBDockPosition` — enum

| 字段 | 类型 |
|------|------|
| `bottom` | `—` |
| `left` | `—` |
| `right` | `—` |

### `SubsequentExecutionDefault` — class

| 字段 | 类型 |
|------|------|
| `key` | `SS` |
| `initialized` | `Sb` |
| `value` | `—` |

### `SubsequentExecutionMode` — enum

| 字段 | 类型 |
|------|------|
| `resize` | `—` |
| `acrossMonitor` | `—` |
| `none` | `—` |
| `acrossAndResize` | `—` |
| `cycleMonitor` | `—` |

### `DockItem` — class

| 字段 | 类型 |
|------|------|
| `name` | `SS` |
| `rect` | `—` |
| `bundleURL` | `—` |
| `windows` | `—` |
| `runningApp` | `So20NSRunningApplicationC` |

### `UsableScreens` — struct

| 字段 | 类型 |
|------|------|
| `currentScreen` | `So8NSScreenC` |
| `adjacentScreens` | `—` |
| `frameOfCurrentScreen` | `—` |
| `visibleFrameOfCurrentScreen` | `—` |
| `numScreens` | `Si` |

### `AdjacentScreens` — struct

| 字段 | 类型 |
|------|------|
| `prev` | `So8NSScreenC` |
| `next` | `So8NSScreenC` |

### `EventMonitor` — class

| 字段 | 类型 |
|------|------|
| `globalMonitor` | `ypSg` |
| `localMonitor` | `ypSg` |
| `mask` | `—` |
| `handler` | `ySo7NSEventCSgc` |

### `DockWindowPreviewImageStore` — class

| 字段 | 类型 |
|------|------|
| `applicationsCache` | `So7NSCacheCySo8NSStringCSo12NSMutableSetCG` |
| `windowsCache` | `—` |

### `DockWindowPreviewImageStoreItem` — class

| 字段 | 类型 |
|------|------|
| `refreshDate` | `—` |
| `image` | `So7NSImageC` |

### `LastTwoThirdsCalculation` — class

| 字段 | 类型 |
|------|------|
| `params` | `—` |

### `CommandTabPreviewBackportView` — class

| 字段 | 类型 |
|------|------|
| `appName` | `So11NSTextFieldCSg` |
| `stripView` | `—` |

### `RunningAppIndex` — class

| 字段 | 类型 |
|------|------|
| `titleToPids` | `—` |
| `pidToApp` | `—` |
| `pidMeta` | `—` |
| `lastBuiltAt` | `Sd` |
| `lastAppsCount` | `Si` |
| `ttl` | `Sd` |
| `queue` | `So17OS_dispatch_queueC` |

### `Meta` — struct

| 字段 | 类型 |
|------|------|
| `isMainAppBundle` | `Sb` |
| `bundleIdLower` | `SS` |

### `TopCenterSixthCalculation` — class

| 字段 | 类型 |
|------|------|
| `topRightTwoSixths` | `—` |
| `topLeftTwoSixths` | `—` |
| `bottomLeftTwoSixths` | `—` |

### `TrafficLightButton` — class

| 字段 | 类型 |
|------|------|
| `isMouseOver` | `Sb` |
| `type` | `—` |
| `dockWindow` | `—` |
| `delegate` | `—` |

### `TrafficLightButtonType` — enum

| 字段 | 类型 |
|------|------|
| `quit` | `—` |
| `close` | `—` |
| `miniaturize` | `—` |
| `fullscreen` | `—` |

### `DockItemWindow` — class

| 字段 | 类型 |
|------|------|
| `cgWindowId` | `—` |
| `title` | `SSSg` |
| `thumbnail` | `So7NSImageCSg` |
| `sourceImage` | `4^!` |
| `sourceImageSize` | `—` |
| `thumbnailID` | `SS` |
| `thumbnailFullSize` | `T_!` |
| `isHidden` | `Sb` |
| `isFullscreen` | `Sb` |
| `isMinimized` | `Sb` |
| `position` | `t_!` |
| `size` | `T_!` |
| `bundleIdentifier` | `SS` |
| `application` | `—` |
| `axUiElement` | `—` |
| `closeButton` | `—` |

### `WindowMinimizeCandidate` — struct

| 字段 | 类型 |
|------|------|
| `window` | `—` |
| `axElement` | `—` |
| `cgWindowId` | `—` |
| `pid` | `—` |

### `HiddenAllRestoreSnapshotItem` — struct

| 字段 | 类型 |
|------|------|
| `stableKey` | `SS` |
| `window` | `—` |
| `axElement` | `—` |
| `cgWindowId` | `—` |
| `pid` | `—` |
| `frontToBackIndex` | `Si` |

### `HiddenAllRestoreSnapshot` — struct

| 字段 | 类型 |
|------|------|
| `id` | `—` |
| `capturedAt` | `—` |
| `visibleSpaceIds` | `—` |
| `items` | `—` |

### `WindowAction` — enum

| 字段 | 类型 |
|------|------|
| `leftHalf` | `—` |
| `rightHalf` | `—` |
| `maximize` | `—` |
| `maximizeHeight` | `—` |
| `previousDisplay` | `—` |
| `nextDisplay` | `—` |
| `larger` | `—` |
| `smaller` | `—` |
| `bottomHalf` | `—` |
| `topHalf` | `—` |
| `center` | `—` |
| `bottomLeft` | `—` |
| `bottomRight` | `—` |
| `topLeft` | `—` |
| `topRight` | `—` |
| `restore` | `—` |
| `firstThird` | `—` |
| `firstTwoThirds` | `—` |
| `centerThird` | `—` |
| `lastTwoThirds` | `—` |
| `lastThird` | `—` |
| `moveLeft` | `—` |
| `moveRight` | `—` |
| `moveUp` | `—` |
| `moveDown` | `—` |
| `almostMaximize` | `—` |
| `centerHalf` | `—` |
| `firstFourth` | `—` |
| `secondFourth` | `—` |
| `thirdFourth` | `—` |
| `lastFourth` | `—` |
| `firstThreeFourths` | `—` |
| `lastThreeFourths` | `—` |
| `topLeftSixth` | `—` |
| `topCenterSixth` | `—` |
| `topRightSixth` | `—` |
| `bottomLeftSixth` | `—` |
| `bottomCenterSixth` | `—` |
| `bottomRightSixth` | `—` |
| `specified` | `—` |
| `reverseAll` | `—` |
| `topLeftNinth` | `—` |
| `topCenterNinth` | `—` |
| `topRightNinth` | `—` |
| `middleLeftNinth` | `—` |
| `middleCenterNinth` | `—` |
| `middleRightNinth` | `—` |
| `bottomLeftNinth` | `—` |
| `bottomCenterNinth` | `—` |
| `bottomRightNinth` | `—` |
| `topLeftThird` | `—` |
| `topRightThird` | `—` |
| `bottomLeftThird` | `—` |
| `bottomRightThird` | `—` |
| `topLeftEighth` | `—` |
| `topCenterLeftEighth` | `—` |
| `topCenterRightEighth` | `—` |
| `topRightEighth` | `—` |
| `bottomLeftEighth` | `—` |
| `bottomCenterLeftEighth` | `—` |
| `bottomCenterRightEighth` | `—` |
| `bottomRightEighth` | `—` |
| `tileAll` | `—` |
| `cascadeAll` | `—` |
| `hiddenAllWindow` | `—` |
| `shakeingHiddenAllWindow` | `—` |
| `centerRestore` | `—` |
| `hiddenOtherWindows` | `—` |
| `missionControlProStatus` | `—` |
| `missionControlProCloseWindow` | `—` |
| `missionControlProQuitApp` | `—` |
| `moveDockToThisDisplay` | `—` |

### `SubWindowAction` — enum

| 字段 | 类型 |
|------|------|
| `leftThird` | `—` |
| `centerVerticalThird` | `—` |
| `rightThird` | `—` |
| `leftTwoThirds` | `—` |
| `rightTwoThirds` | `—` |
| `topThird` | `—` |
| `centerHorizontalThird` | `—` |
| `bottomThird` | `—` |
| `topTwoThirds` | `—` |
| `bottomTwoThirds` | `—` |
| `leftFourth` | `—` |
| `centerLeftFourth` | `—` |
| `centerRightFourth` | `—` |
| `rightFourth` | `—` |
| `topFourth` | `—` |
| `centerTopFourth` | `—` |
| `centerBottomFourth` | `—` |
| `bottomFourth` | `—` |
| `rightThreeFourths` | `—` |
| `bottomThreeFourths` | `—` |
| `leftThreeFourths` | `—` |
| `topThreeFourths` | `—` |
| `centerVerticalHalf` | `—` |
| `centerHorizontalHalf` | `—` |
| `topLeftSixthLandscape` | `—` |
| `topCenterSixthLandscape` | `—` |
| `topRightSixthLandscape` | `—` |
| `bottomLeftSixthLandscape` | `—` |
| `bottomCenterSixthLandscape` | `—` |
| `bottomRightSixthLandscape` | `—` |
| `topLeftSixthPortrait` | `—` |
| `topRightSixthPortrait` | `—` |
| `leftCenterSixthPortrait` | `—` |
| `rightCenterSixthPortrait` | `—` |
| `bottomLeftSixthPortrait` | `—` |
| `bottomRightSixthPortrait` | `—` |
| `topLeftTwoSixthsLandscape` | `—` |
| `topLeftTwoSixthsPortrait` | `—` |
| `topRightTwoSixthsLandscape` | `—` |
| `topRightTwoSixthsPortrait` | `—` |
| `bottomLeftTwoSixthsLandscape` | `—` |
| `bottomLeftTwoSixthsPortrait` | `—` |
| `bottomRightTwoSixthsLandscape` | `—` |
| `bottomRightTwoSixthsPortrait` | `—` |
| `topLeftNinth` | `—` |
| `topCenterNinth` | `—` |
| `topRightNinth` | `—` |
| `middleLeftNinth` | `—` |
| `middleCenterNinth` | `—` |
| `middleRightNinth` | `—` |
| `bottomLeftNinth` | `—` |
| `bottomCenterNinth` | `—` |
| `bottomRightNinth` | `—` |
| `topLeftThird` | `—` |
| `topRightThird` | `—` |
| `bottomLeftThird` | `—` |
| `bottomRightThird` | `—` |
| `topLeftEighth` | `—` |
| `topCenterLeftEighth` | `—` |
| `topCenterRightEighth` | `—` |
| `topRightEighth` | `—` |
| `bottomLeftEighth` | `—` |
| `bottomCenterLeftEighth` | `—` |
| `bottomCenterRightEighth` | `—` |
| `bottomRightEighth` | `—` |
| `maximize` | `—` |

### `SnappingManager` — class

| 字段 | 类型 |
|------|------|
| `paddleHelper` | `—` |
| `dockWindowPreviewer` | `—` |
| `clickDockShowAndMinimumController` | `—` |
| `snapAreaDetector` | `—` |
| `cursorNudger` | `—` |
| `footprintPresenter` | `—` |
| `snappingIslandCoordinator` | `—` |
| `unsnapRestorer` | `—` |
| `eventMonitor` | `—` |
| `windowElement` | `—` |
| `windowId` | `SiSg` |
| `windowIdAttempt` | `Si` |
| `lastWindowIdAttempt` | `SdSg` |
| `windowMoving` | `Sb` |
| `isResizing` | `Sb` |
| `initialWindowRect` | `—` |
| `trackedWindowSizeSettable` | `SbSg` |
| `trackedWindowExclusionResult` | `SbSg` |
| `currentSnapArea` | `—` |
| `globleMouseLoc` | `t_!` |
| `mouseDownLocation` | `t_!` |

### `StorageUtil` — class

| 字段 | 类型 |
|------|------|
| `applicationID` | `—` |

### `SpecifiedCalculation` — class

| 字段 | 类型 |
|------|------|
| `specifiedHeight` | `—` |
| `specifiedWidth` | `—` |

### `BackgroundThreadWithRunLoop` — class

| 字段 | 类型 |
|------|------|
| `thread` | `So8NSThreadCSg` |
| `runLoop` | `—` |
| `hasSentSemaphoreSignal` | `Sb` |

### `CommandTabNumberBadgeView` — class

| 字段 | 类型 |
|------|------|
| `text` | `SS` |

### `CommandTabPreviewItemContainerView` — class

| 字段 | 类型 |
|------|------|
| `timer` | `So7NSTimerCSg` |
| `closeBtn` | `—` |
| `windowTitle` | `So11NSTextFieldCSg` |
| `imageButton` | `So8NSButtonCSg` |
| `numberBadge` | `—` |
| `isKeyboardSelected` | `Sb` |
| `delegate` | `—` |
| `windowsControlSize` | `—` |
| `delayShowCloseButtonTask` | `—` |
| `trackingArea` | `So14NSTrackingAreaCSg` |
| `highlightOverlay` | `So6NSViewCSg` |
| `isMouseInside` | `Sb` |

### `CommandTabPreviewHorizontalStripView` — class

| 字段 | 类型 |
|------|------|
| `scrollView` | `So12NSScrollViewC` |
| `documentView` | `—` |
| `scrollViewWidthConstraint` | `So18NSLayoutConstraintCSg` |
| `scrollViewHeightConstraint` | `So18NSLayoutConstraintCSg` |
| `windows` | `—` |
| `visibleCount` | `Si` |
| `selectedIndex` | `SiSg` |
| `scrollStartIndex` | `Si` |
| `hoveredIndex` | `SiSg` |
| `pendingAutoScrollTask` | `—` |
| `pendingAutoScrollTargetIndex` | `SiSg` |
| `pendingShortcutBadgeRevealTask` | `—` |
| `shortcutBadgesVisible` | `Sb` |
| `lastHoverOwnerView` | `So6NSViewCSgXw` |
| `lastHoverLocationInOwner` | `t_!` |

### `CommandTabPreviewItemView` — class

| 字段 | 类型 |
|------|------|
| `containerView` | `—` |
| `itemWindow` | `—` |
| `keyboardSelected` | `Sb` |
| `previewIndex` | `Si` |
| `showsShortcutBadge` | `Sb` |

### `CommandTabPreviewWC` — class

| 字段 | 类型 |
|------|------|
| `selectedApp` | `So20NSRunningApplicationCSg` |
| `items` | `—` |
| `log` | `So9OS_os_logC` |
| `delayHideTask` | `—` |
| `globalMouseMonitor` | `ypSg` |
| `globalMouseMoveMonitor` | `ypSg` |
| `mouseEventTap` | `—` |
| `mouseRunLoopSource` | `—` |
| `lastAnchorPosition` | `t_!` |
| `lastDisplayedWindowsCount` | `Si` |
| `isRefreshingAfterClose` | `Sb` |
| `pendingRefreshAfterClose` | `Sb` |
| `needsEnterSelectionAfterRefresh` | `Sb` |
| `lastShowPreviewStartTS` | `Sd` |
| `isWindowSelectionMode` | `Sb` |
| `lastSelectionSource` | `—` |
| `$__lazy_storage_$_glassEffectView` | `So6NSViewCSgSg` |
| `$__lazy_storage_$_visualEffectView` | `—` |

### `SelectionSource` — enum

| 字段 | 类型 |
|------|------|
| `hover` | `—` |
| `keyboard` | `—` |

### `LastThirdCalculation` — class

| 字段 | 类型 |
|------|------|
| `params` | `—` |

### `FlickDockController` — class

| 字段 | 类型 |
|------|------|
| `pendingDockClick` | `—` |
| `lastDockClick` | `—` |
| `diagnosticClickSequence` | `—` |
| `activeDiagnosticClick` | `—` |
| `lastObservedFrontBundleId` | `SSSg` |
| `lastActivationRecord` | `—` |
| `appActivationObserver` | `So8NSObject_pSg` |
| `stateLock` | `So6NSLockC` |
| `pendingDockClickMaxAge` | `Sd` |
| `repeatClickTolerance` | `Sd` |
| `activationEventOrderingTolerance` | `Sd` |

### `AppActivationRecord` — struct

| 字段 | 类型 |
|------|------|
| `previousBundleId` | `SSSg` |
| `currentBundleId` | `SS` |
| `occurredAt` | `—` |
| `occurredAtSystemUptime` | `Sd` |

### `ActiveDiagnosticClick` — struct

| 字段 | 类型 |
|------|------|
| `id` | `—` |
| `startedAt` | `—` |

### `PendingDockClick` — struct

| 字段 | 类型 |
|------|------|
| `clickId` | `—` |
| `bundleId` | `SS` |
| `pid` | `—` |
| `wasFrontmostBeforeMouseDown` | `Sb` |
| `hadVisibleWindowsBeforeMouseDown` | `Sb` |
| `createdAt` | `—` |

### `FlickDockDiagnosticsPolicy` — class

| 字段 | 类型 |
|------|------|
| `lock` | `So6NSLockC` |
| `enabledStorage` | `Sb` |

### `AppActivationTracker` — class

| 字段 | 类型 |
|------|------|
| `currentFrontIdentifier` | `SSSg` |
| `minimizedBundles` | `ShySSG` |

### `RectCalculationParameters` — struct

| 字段 | 类型 |
|------|------|
| `window` | `—` |
| `visibleFrameOfScreen` | `—` |
| `action` | `—` |
| `lastAction` | `—` |
| `screen` | `So8NSScreenCSg` |
| `footerPrint` | `Sb` |
| `source` | `—` |

### `WindowCalculationParameters` — struct

| 字段 | 类型 |
|------|------|
| `window` | `—` |
| `usableScreens` | `—` |
| `action` | `—` |
| `lastAction` | `—` |
| `source` | `—` |

### `Window` — struct

| 字段 | 类型 |
|------|------|
| `id` | `Si` |
| `rect` | `—` |
| `windowElement` | `—` |

### `WindowHistory` — class

| 字段 | 类型 |
|------|------|
| `restoreRects` | `—` |
| `restoreCenterRects` | `—` |
| `lastRectangleActions` | `—` |
| `lastSystemActions` | `—` |

### `FirstGuideWindowController` — class

| 字段 | 类型 |
|------|------|
| `isDockIconRetained` | `Sb` |

### `FirstGuideWrappingViewController` — class

| 字段 | 类型 |
|------|------|
| `firstGuideViewController` | `—` |
| `authorizationViewController` | `—` |

### `FirstGuideViewController` — class

| 字段 | 类型 |
|------|------|
| `delegate` | `—` |

### `AuthorizationViewController` — class

| 字段 | 类型 |
|------|------|
| `authorizationIcon` | `So11NSImageViewCSgXw` |
| `authorizationScreenRecordIcon` | `So11NSImageViewCSgXw` |
| `backgroundView` | `So6NSViewCSgXw` |
| `continueButton` | `So8NSButtonCSgXw` |
| `authorizationText` | `So11NSTextFieldCSgXw` |
| `authorizScreenRecordText` | `So11NSTextFieldCSgXw` |

### `PaddleHelper` — class

| 字段 | 类型 |
|------|------|
| `VendorID` | `SS` |
| `ProductID` | `SS` |
| `APIKey` | `SS` |
| `debug` | `Sb` |
| `sandbox` | `Sb` |
| `paddle` | `So6PaddleCSg` |
| `paddleProduct` | `So10PADProductCSg` |
| `defaults` | `—` |
| `activationWindowController` | `—` |
| `refTrialIntervalHour` | `Si` |
| `maxSilentActivationFailureCount` | `Si` |
| `silentActivationFailureCount` | `Si` |
| `timer` | `So24OS_dispatch_source_timer_pSg` |

### `ActivationWindowController` — class

| 字段 | 类型 |
|------|------|
| `compactWindowSize` | `—` |
| `expandedWindowHeight` | `—` |
| `isDockIconRetained` | `Sb` |
| `forgetTopToEmailConstraint` | `So18NSLayoutConstraintCSg` |
| `forgetTopToStatusConstraint` | `So18NSLayoutConstraintCSg` |
| `forgetTopToErrorConstraint` | `So18NSLayoutConstraintCSg` |
| `forgetTopToRenewalConstraint` | `So18NSLayoutConstraintCSg` |
| `forgetTopToSeatUpgradeConstraint` | `So18NSLayoutConstraintCSg` |
| `pendingRenewalContext` | `—` |
| `pendingSeatUpgradeContext` | `—` |
| `logoImageView` | `So11NSImageViewC` |
| `titleLabel` | `So11NSTextFieldC` |
| `subtitleLabel` | `So11NSTextFieldC` |
| `licenseField` | `So11NSTextFieldC` |
| `emailField` | `So11NSTextFieldC` |
| `forgetLicenseButton` | `So8NSButtonC` |
| `activateButton` | `So8NSButtonC` |
| `statusLabel` | `So11NSTextFieldC` |
| `errorLabel` | `So11NSTextFieldC` |
| `renewalPrefixLabel` | `So11NSTextFieldC` |
| `renewalButton` | `So8NSButtonC` |
| `renewalSuffixLabel` | `So11NSTextFieldC` |
| `renewalContainer` | `So11NSStackViewC` |
| `seatUpgradePrefixLabel` | `So11NSTextFieldC` |
| `seatUpgradeButton` | `So8NSButtonC` |
| `seatUpgradeSuffixLabel` | `So11NSTextFieldC` |
| `seatUpgradeContainer` | `So11NSStackViewC` |

### `AppUpdateController` — class

| 字段 | 类型 |
|------|------|
| `hostBundle` | `So8NSBundleC` |
| `dockIconController` | `—` |
| `alertPresenter` | `—` |
| `updater` | `So10SPUUpdaterCSg` |
| `updaterUserDriver` | `—` |
| `userInitiatedUpdateCheck` | `Sb` |
| `pendingApprovedUpdatePresentation` | `Sb` |

### `LicenseEntitlementDecision` — enum

| 字段 | 类型 |
|------|------|
| `renewalRequired` | `—` |
| `seatUpgradeRequired` | `—` |
| `verificationFailed` | `SS` |
| `allow` | `—` |

### `LicenseSeatUpgradeContext` — struct

| 字段 | 类型 |
|------|------|
| `email` | `SS` |
| `licenseKey` | `SS` |

### `LicenseRenewalContext` — struct

| 字段 | 类型 |
|------|------|
| `email` | `SS` |
| `licenseKey` | `SS` |

### `LicenseActivationPayload` — struct

| 字段 | 类型 |
|------|------|
| `activationId` | `SSSg` |

### `LicenseActivationRecordRequestBody` — struct

| 字段 | 类型 |
|------|------|
| `email` | `SS` |
| `version` | `SS` |
| `licenseCode` | `SS` |
| `deviceModel` | `SSSg` |
| `deviceId` | `SSSg` |
| `deviceInfo` | `SSSg` |

### `LicenseActivationFlowResult` — enum

| 字段 | 类型 |
|------|------|
| `activated` | `SSSg14warningMessage_t` |
| `renewalRequired` | `—` |
| `seatUpgradeRequired` | `—` |
| `failed` | `SS` |

### `LicenseExpirationRequestBody` — struct

| 字段 | 类型 |
|------|------|
| `licenseKey` | `SS` |

### `LicenseExpirationPayload` — struct

| 字段 | 类型 |
|------|------|
| `licenseKey` | `SSSg` |
| `plan` | `SSSg` |
| `expireTime` | `SSSg` |

### `LicenseExpirationInfo` — struct

| 字段 | 类型 |
|------|------|
| `licenseKey` | `SS` |
| `plan` | `SSSg` |
| `expireTime` | `—` |

### `APIEnvelope` — struct

| 字段 | 类型 |
|------|------|
| `code` | `Si` |
| `msg` | `SS` |
| `data` | `xSg` |

### `LicenseEntitlementRequestBody` — struct

| 字段 | 类型 |
|------|------|
| `licenseCode` | `SS` |
| `activationEmail` | `SS` |
| `targetVersion` | `SS` |
| `checkScene` | `SS` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `licenseKey` | `—` |
| `plan` | `—` |
| `expireTime` | `—` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `activationId` | `—` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `email` | `—` |
| `version` | `—` |
| `licenseCode` | `—` |
| `deviceModel` | `—` |
| `deviceId` | `—` |
| `deviceInfo` | `—` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `licenseKey` | `—` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `licenseCode` | `—` |
| `activationEmail` | `—` |
| `targetVersion` | `—` |
| `checkScene` | `—` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `code` | `—` |
| `msg` | `—` |
| `data` | `—` |

### `UpdateEntitlementService` — class

| 字段 | 类型 |
|------|------|
| `session` | `So12NSURLSessionC` |
| `encoder` | `—` |
| `decoder` | `—` |

### `ThemeAwareContentView` — class

| 字段 | 类型 |
|------|------|
| `onAppearanceChange` | `yycSg` |

### `UpdateEntitlementWindowController` — class

| 字段 | 类型 |
|------|------|
| `appcastItem` | `So13SUAppcastItemC` |
| `decision` | `—` |
| `presentation` | `—` |
| `onComplete` | `—` |
| `dockIconController` | `—` |
| `didComplete` | `Sb` |
| `isDockIconRetained` | `Sb` |
| `isObservingReleaseNotesLoading` | `Sb` |
| `isPrimaryReleaseNotesLoadInProgress` | `Sb` |
| `layerUpdaters` | `SayyycG` |
| `releaseNotesNavigationDelegate` | `—` |
| `subheadLabel` | `So11NSTextFieldC` |
| `pillLabel` | `So11NSTextFieldC` |
| `pillContainer` | `So6NSViewC` |
| `bannerTitleLabel` | `So11NSTextFieldC` |
| `bannerBodyTextView` | `—` |
| `releaseNotesWebView` | `So6NSViewC` |
| `releaseNotesLoadingIndicator` | `So19NSProgressIndicatorC` |
| `releaseNotesLoadingLabel` | `So11NSTextFieldC` |

### `UpdateEntitlementStyledButton` — class

| 字段 | 类型 |
|------|------|
| `style` | `—` |
| `isHovering` | `Sb` |
| `trackingArea` | `So14NSTrackingAreaCSg` |

### `Style` — enum

| 字段 | 类型 |
|------|------|
| `primary` | `—` |
| `ghost` | `—` |

### `UpdateEntitlementPresentationModel` — struct

| 字段 | 类型 |
|------|------|
| `subtitle` | `SS` |
| `bannerTitle` | `SS` |
| `bannerBody` | `SS` |
| `inlineLinkLabel` | `SS` |
| `buttonTitle` | `SS` |
| `actionURL` | `—` |

### `UpdateEntitlementUserDriver` — class

| 字段 | 类型 |
|------|------|
| `standardUserDriver` | `So21SPUStandardUserDriverC` |
| `entitlementService` | `—` |
| `denialHandler` | `—` |
| `dockIconController` | `—` |
| `currentUpdateItem` | `So13SUAppcastItemCSg` |
| `approvedUpdateVersion` | `SSSg` |
| `entitlementWindowController` | `—` |
| `isStandardUpdateDockIconRetained` | `Sb` |
| `isStandardUpdateFoundWindowReadyForReleaseNotes` | `Sb` |
| `pendingStandardReleaseNotes` | `—` |

### `StandardReleaseNotesResult` — enum

| 字段 | 类型 |
|------|------|
| `downloaded` | `So15SPUDownloadDataC` |
| `failed` | `—` |

### `AppDelegate` — class

| 字段 | 类型 |
|------|------|
| `accessibilityAuthorization` | `—` |
| `defaults` | `—` |
| `windowManager` | `—` |
| `shortcutManager` | `—` |
| `windowCalculationFactory` | `—` |
| `snappingManager` | `—` |
| `missionControlPro` | `—` |
| `commandTabPlus` | `—` |
| `appVersion` | `SSSg` |
| `preferenceNotificationCenter` | `—` |
| `appUpdateController` | `—` |
| `pandle` | `—` |
| `dockIconRequestCounts` | `—` |
| `isDockIconVisible` | `Sb` |

### `DockIconReason` — enum

| 字段 | 类型 |
|------|------|
| `onboarding` | `—` |
| `activation` | `—` |
| `update` | `—` |

### `ShortcutManager` — class

| 字段 | 类型 |
|------|------|
| `windowManager` | `—` |
| `paddleHelper` | `—` |

### `Mode` — struct

| 字段 | 类型 |
|------|------|
| `_rawValue` | `So8NSStringC` |

### `EventTypeMask` — struct

| 字段 | 类型 |
|------|------|
| `rawValue` | `—` |

### `EventTypeSpec` — struct

| 字段 | 类型 |
|------|------|
| `eventClass` | `—` |
| `eventKind` | `—` |

### `ModifierFlags` — struct

| 字段 | 类型 |
|------|------|
| `rawValue` | `Su` |

### `ConflictBehavior` — enum

| 字段 | 类型 |
|------|------|
| `block` | `—` |
| `warn` | `—` |
| `allow` | `—` |

### `ConflictPolicy` — struct

| 字段 | 类型 |
|------|------|
| `menuItem` | `—` |
| `systemShortcut` | `—` |
| `disallowed` | `—` |

### `HotKey` — class

| 字段 | 类型 |
|------|------|
| `carbonKeyCode` | `Si` |
| `carbonModifiers` | `Si` |
| `onKeyDown` | `yyc` |
| `onKeyUp` | `yyc` |
| `onRegistrationFailed` | `yycSg` |
| `id` | `Si` |
| `eventHotKeyRef` | `—` |

### `HotKeyCenter` — class

| 字段 | 类型 |
|------|------|
| `lastHotKeyId` | `Si` |
| `hotKeys` | `—` |
| `eventHandler` | `—` |
| `openMenuObserver` | `So8NSObject_pSg` |
| `closeMenuObserver` | `So8NSObject_pSg` |
| `isEnabled` | `Sb` |
| `isMenuOpen` | `Sb` |
| `isHotKeyEventHandlingEnabled` | `Sb` |
| `isRawKeyEventHandlingEnabled` | `Sb` |
| `signature` | `—` |
| `hotKeyEventTypes` | `—` |
| `rawKeyEventTypes` | `—` |
| `$__lazy_storage_$_keyEventMonitor` | `—` |
| `mode` | `—` |

### `Mode` — enum

| 字段 | 类型 |
|------|------|
| `disabled` | `—` |
| `normal` | `—` |
| `menuOpen` | `—` |

### `WeakHotKey` — struct

| 字段 | 类型 |
|------|------|
| `value` | `—` |

### `Key` — struct

| 字段 | 类型 |
|------|------|
| `rawValue` | `Si` |

### `ValidationResult` — enum

| 字段 | 类型 |
|------|------|
| `disallow` | `SS6reason_t` |
| `allow` | `—` |

### `EventType` — enum

| 字段 | 类型 |
|------|------|
| `keyDown` | `—` |
| `keyUp` | `—` |

### `RepeatingTaskController` — class

| 字段 | 类型 |
|------|------|
| `$defaultActor` | `BD` |
| `task` | `—` |

### `RepeatState` — class

| 字段 | 类型 |
|------|------|
| `heldShortcut` | `—` |

### `WeakMenuItem` — class

| 字段 | 类型 |
|------|------|
| `value` | `So10NSMenuItemCSgXw` |

### `FallbackShortcut` — struct

| 字段 | 类型 |
|------|------|
| `keyEquivalent` | `SS` |
| `modifierMask` | `—` |

### `Name` — struct

| 字段 | 类型 |
|------|------|
| `rawValue` | `SS` |
| `initialShortcut` | `—` |

### `Coordinator` — class

| 字段 | 类型 |
|------|------|
| `shortcutBinding` | `—` |
| `onChange` | `—` |

### `Recorder` — struct

| 字段 | 类型 |
|------|------|
| `shortcutSource` | `—` |
| `onChange` | `—` |
| `hasLabel` | `Sb` |
| `label` | `—` |
| `validateShortcut` | `—` |

### `ShortcutSource` — enum

| 字段 | 类型 |
|------|------|
| `name` | `—` |
| `binding` | `—` |

### `RecorderCocoa` — class

| 字段 | 类型 |
|------|------|
| `minimumWidth` | `Sd` |
| `onChange` | `—` |
| `storageMode` | `—` |
| `bindingShortcut` | `—` |
| `canBecomeKey` | `Sb` |
| `eventMonitor` | `—` |
| `shortcutBeforeRecording` | `—` |
| `shortcutsNameChangeObserver` | `So8NSObject_pSg` |
| `windowDidResignKeyObserver` | `So8NSObject_pSg` |
| `windowDidBecomeKeyObserver` | `So8NSObject_pSg` |
| `validateShortcut` | `—` |
| `conflictPolicy` | `—` |
| `shortcutName` | `—` |
| `cancelButton` | `So12NSButtonCellCSg` |

### `StorageMode` — enum

| 字段 | 类型 |
|------|------|
| `name` | `—` |
| `binding` | `—` |

### `Shortcut` — struct

| 字段 | 类型 |
|------|------|
| `carbonKeyCode` | `Si` |
| `carbonModifiers` | `Si` |

### `CodingKeys` — enum

| 字段 | 类型 |
|------|------|
| `carbonKeyCode` | `—` |
| `carbonModifiers` | `—` |

### `SpecialKey` — enum

| 字段 | 类型 |
|------|------|
| `return` | `—` |
| `delete` | `—` |
| `deleteForward` | `—` |
| `end` | `—` |
| `escape` | `—` |
| `help` | `—` |
| `home` | `—` |
| `space` | `—` |
| `tab` | `—` |
| `pageUp` | `—` |
| `pageDown` | `—` |
| `upArrow` | `—` |
| `rightArrow` | `—` |
| `downArrow` | `—` |
| `leftArrow` | `—` |
| `f1` | `—` |
| `f2` | `—` |
| `f3` | `—` |
| `f4` | `—` |
| `f5` | `—` |
| `f6` | `—` |
| `f7` | `—` |
| `f8` | `—` |
| `f9` | `—` |
| `f10` | `—` |
| `f11` | `—` |
| `f12` | `—` |
| `f13` | `—` |
| `f14` | `—` |
| `f15` | `—` |
| `f16` | `—` |
| `f17` | `—` |
| `f18` | `—` |
| `f19` | `—` |
| `f20` | `—` |
| `keypad0` | `—` |
| `keypad1` | `—` |
| `keypad2` | `—` |
| `keypad3` | `—` |
| `keypad4` | `—` |
| `keypad5` | `—` |
| `keypad6` | `—` |
| `keypad7` | `—` |
| `keypad8` | `—` |
| `keypad9` | `—` |
| `keypadClear` | `—` |
| `keypadDecimal` | `—` |
| `keypadDivide` | `—` |
| `keypadEnter` | `—` |
| `keypadEquals` | `—` |
| `keypadMinus` | `—` |
| `keypadMultiply` | `—` |
| `keypadPlus` | `—` |

### `LocalEventMonitor` — class

| 字段 | 类型 |
|------|------|
| `events` | `—` |
| `callback` | `So7NSEventCSgABc` |
| `monitor` | `yXlSgXw` |

### `RunLoopLocalEventMonitor` — class

| 字段 | 类型 |
|------|------|
| `runLoopMode` | `—` |
| `callback` | `So7NSEventCSgABc` |
| `observer` | `—` |
| `isStarted` | `Sb` |

### `GlobalKeyboardShortcutViewModifier` — struct

| 字段 | 类型 |
|------|------|
| `__isRecorderActive` | `—` |
| `__triggerRefresh` | `—` |
| `name` | `—` |