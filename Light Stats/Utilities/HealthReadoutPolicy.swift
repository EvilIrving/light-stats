//
//  HealthReadoutPolicy.swift
//  Light Stats
//

/// 健康度读数在两个口径之间切换时的滚动方向：新值更小向下滚，更大向上滚。
/// 方向本身就是信息——切到系统值时向上滚，说明系统口径更高，无需额外文字。
nonisolated enum HealthReadoutPolicy {

    /// `showsSystem` 指切换*之后*显示的是哪个口径；另一个值即被换下的旧值。
    static func countsDown(showsSystem: Bool, healthPercent: Int?, systemPercent: Int?) -> Bool {
        guard let healthPercent, let systemPercent else { return false }
        return showsSystem ? systemPercent < healthPercent : healthPercent < systemPercent
    }
}
