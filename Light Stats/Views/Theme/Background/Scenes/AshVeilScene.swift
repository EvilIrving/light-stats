//
//  AshVeilScene.swift
//  Light Stats
//
//  Static photo background. No grain, blur, motion, or light-field.
//  Only a fixed vertical reading wash so instrument ink stays legible on the
//  photo's pale top/bottom bands (measured ~L228 vs center ~L37).
//

import SwiftUI

struct AshVeilScene: View {
    /// Asset catalog imageset name for the monochrome texture photo.
    static let imageName = "AshVeilBackground"

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(Self.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                // Fixed contrast wash only — darkens pale top/bottom so near-white
                // instrument text remains readable; center stays open so the photo's
                // dark core still reads. Not grain, blur, veil motion, or flow.
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.62), location: 0.00),
                        .init(color: Color.black.opacity(0.42), location: 0.18),
                        .init(color: Color.black.opacity(0.22), location: 0.38),
                        .init(color: Color.black.opacity(0.18), location: 0.50),
                        .init(color: Color.black.opacity(0.22), location: 0.62),
                        .init(color: Color.black.opacity(0.42), location: 0.82),
                        .init(color: Color.black.opacity(0.62), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}
