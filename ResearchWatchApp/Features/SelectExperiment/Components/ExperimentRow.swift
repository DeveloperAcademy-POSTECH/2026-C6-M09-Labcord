//
//  ExperimentRow.swift
//  Researchers
//
//  Created by 정홍섭 on 11/16/26.
//

import LabcordDesignSystem
import SwiftUI

struct ExperimentRow: View {
    let title: String

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Color(.Colors.Grays.white))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)

            Spacer(minLength: 6)

            Image(systemName: "play.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color("General/Brand/Primary"), in: Circle())
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 9.5)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(Color("General/LiveActivity/Secondary"))
        .cornerRadius(8.5)
    }
}

#Preview {
    ExperimentRow(title: "새 실험(1)")
}
