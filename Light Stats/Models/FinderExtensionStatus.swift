//
//  FinderExtensionStatus.swift
//  Light Stats
//
//  FinderSync 扩展在系统 pkd 中的注册 / 启用状态。宿主侧用 pluginkit 探测后填充，
//  设置页据此提示用户「扩展是否真正生效」——app 的总开关只是其中一道门，OS 层
//  那道勾（系统设置 → 登录项与扩展 → 访达扩展）才决定 Finder 是否加载扩展。
//

import Foundation

enum FinderExtensionStatus: Sendable {
    /// 已在系统设置中勾选启用——菜单应当出现。
    case enabled
    /// 已被 pkd 注册，但用户尚未在系统设置中勾选。
    case disabled
    /// 系统尚未注册该扩展（appex 未被 pkd 发现）。
    case notRegistered
    /// 无法确定（pluginkit 调用失败等）。
    case unknown
}
