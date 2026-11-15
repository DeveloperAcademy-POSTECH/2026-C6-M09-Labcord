//
//  SelectExperimentView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/16/26.
//

import SwiftUI
import LabcordDesignSystem

struct SelectExperimentView: View {
    private let experiments = [
        "촉매 반응 조건 비교 실험 A",
        "Catalyst Reaction Temperature Comparison",
        "Catalyst Reaction Temperature Comparison",
        "배양 시간별 세포 상태 관찰"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("내 실험")
                .padding(.horizontal, 9.5)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color("General/Brand/Primary"))

            ScrollView {
                ForEach(experiments, id: \.self) { experiment in
                    HStack(alignment: .center) {
                        Text(experiment)
                            .font(.footnote)
                            .foregroundStyle(Color(.Colors.Grays.white))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )

                        Spacer(minLength: 6)

                        Button {
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(
                                    Color("General/Brand/Primary"),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 9.5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(.gray)
                    .cornerRadius(8.5)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.top, -30)
    }
}

#Preview {
    SelectExperimentView()
}
