//
//  CameraPreviewView.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/26/26.
//

import SwiftUI
import UIKit

public struct CameraPreviewView: UIViewRepresentable {
    public let connector: CameraPreviewConnector

    public init(connector: CameraPreviewConnector) {
        self.connector = connector
    }

    public func makeUIView(context: Context) -> some UIView {
        let view = PreviewUIView()
        view.connector = connector
        connector.attach(to: view)
        return view
    }

    public func updateUIView(_ uiView: UIViewType, context: Context) {
        guard let view = uiView as? PreviewUIView else { return }
        if view.connector != connector {
            view.connector?.detach(from: view)
        }
        view.connector = connector
        connector.attach(to: view)
    }

    public static func dismantleUIView(_ uiView: UIViewType, coordinator: ()) {
        guard let view = uiView as? PreviewUIView else { return }
        view.connector?.detach(from: view)
        view.connector = nil
    }
}

private final class PreviewUIView: UIView {
    var connector: CameraPreviewConnector?

    override func layoutSubviews() {
        super.layoutSubviews()
        connector?.updateLayout(in: self)
    }
}
