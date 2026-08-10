# Project Memory

## macOS 26 Popover 滚轮隔离与动态主题基线 · 2026-08-10 10:48 · Codex

macOS 26 会让非透明 `NSPanel` 中未被 SwiftUI 子视图处理的滚轮事件继续落到桌面或下方窗口；用户报告 macOS 17 没有同样现象。稳定修复边界是在 `HitRetainingHostingView` 中保留现有 `hitTest` 全边界兜底，并在宿主层吸收最终未处理的 `scrollWheel`，而实际 `ScrollView` 等后代仍通过正常命中测试接收滚动。不要通过增加不透明绘制层、改变主题材质或强制 `.glass` 来解决事件穿透，因为事件隔离与视觉渲染必须互不耦合。

本次出现的“修复滚动后 Sun Gold 变粉”并非滚轮补丁改变颜色。第一张期望截图对应 `/Applications/Light Stats.app` 中约在提交 `49ae62a` 后构建的深色动态版本，而重新构建当前源码时启用了提交 `be82e1d` 的浅粉色静态 artwork 重构；该提交曾把 Sun Gold 从深色动态网格和浅色文字改为浅色静态象牙/玫瑰/珊瑚底，并将其首选配色方案从深色改为浅色。以后遇到“改一行后整个 UI 变样”时，应先比较正在运行的 App 构建来源、时间和源码提交，避免把重新构建显露出的既有提交误判为当前补丁的副作用。

当前确认的产品基线是保留 `49ae62a` 风格的深色动态 Sun Gold 与 Ink Night：动态网格、胶片颗粒、浅色文字，以及可持久化的 `filmGrainEnabled`、`filmLightFlow`、`noirGrainEnabled`、`noirLightFlow` 设置。主题应继续覆盖 Popover、About、Toast、Update 和权限提示；不得把这些窗口静默固定为默认玻璃主题。视觉回归应同时检查动态主题截图和 macOS 26 实机滚轮隔离，不能只凭编译成功判断。
