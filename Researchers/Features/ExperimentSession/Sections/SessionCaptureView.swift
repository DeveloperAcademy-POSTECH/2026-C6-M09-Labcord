//
//  SessionCaptureView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import SwiftUI

struct SessionCaptureView: View {
    var body: some View {
        VStack(spacing: 20) {
            Color.clear
                .frame(width: 401, height: 215)
                .anchorPreference(key: CameraPreviewAnchorKey.self, value: .bounds) { $0 }
            
            HStack(spacing: 24) {
                Button {
                    
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle")
                        Text("음성 기록")
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .frame(maxWidth: 118)
                .foregroundStyle(.black)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                
                Button {
                    
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.viewfinder")
                        Text("장면 캡쳐")
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .frame(maxWidth: 118)
                .foregroundStyle(.black)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                
                Button {
                    
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                        Text("영상 기록")
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .frame(maxWidth: 118)
                .foregroundStyle(.black)
                .buttonStyle(.borderedProminent)
                .tint(.white)
            }
        }
        .frame(minWidth: 401)
    }
}

#Preview {
    SessionCaptureView()
}
