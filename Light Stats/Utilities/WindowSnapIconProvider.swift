//
//  WindowSnapIconProvider.swift
//  Light Stats
//
//  Loads designer-provided template icons for window-control menu actions.
//

import AppKit

enum WindowSnapIconProvider {
    static func icon(for action: WindowSnapAction) -> NSImage? {
        guard let name = iconNames[action],
              let url = Bundle.main.url(forResource: name, withExtension: "tiff"),
              let icon = NSImage(contentsOf: url) else {
            return nil
        }
        icon.isTemplate = true
        return icon
    }

    private static let iconNames: [WindowSnapAction: String] = [
        .leftHalf: "LeftTemplate",
        .rightHalf: "RightTemplate",
        .topHalf: "UpTemplate",
        .bottomHalf: "DownTemplate",
        .topLeft: "Top_LeftTemplate",
        .topRight: "Top_RightTemplate",
        .bottomLeft: "Bottom_LeftTemplate",
        .bottomRight: "Bottom_RightTemplate",
        .leftThird: "Left1ThirdTemplate",
        .leftTwoThirds: "Left2ThirdsTemplate",
        .centerThird: "MiddleThirdTemplate",
        .rightTwoThirds: "Right2ThirdsTemplate",
        .rightThird: "Right1ThirdTemplate",
        .previousDisplay: "PreviousTemplate",
        .nextDisplay: "NextTemplate",
        .maximize: "MaximizeTemplate",
        .center: "CenterTemplate",
        .restore: "RestoreTemplate"
    ]
}
