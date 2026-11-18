//
//  AddTimerView.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 11/17/26.
//

import LabcordDesignSystem
import LabcordWatchOS
import SwiftUI

struct AddTimerView: View {
    private enum Field: Hashable {
        case hours
        case minutes
        case seconds
    }

    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack {
            HStack(alignment: .wheelCenter, spacing: WatchScreenMetrics.scaledWidth(4)) {
                durationPicker("시간", field: .hours, selection: $hours, range: 0..<24)
                
                separator
                
                durationPicker("분", field: .minutes, selection: $minutes, range: 0..<60)
                
                separator
                
                durationPicker("초", field: .seconds, selection: $seconds, range: 0..<60)
            }
            .foregroundStyle(.white)
            
            Button {
                
            } label: {
                Text("타이머 실행")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("General/Brand/Primary"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, WatchScreenMetrics.scaledHeight(3.5))
        .ignoresSafeArea()
        .onAppear {
            if focusedField == nil { focusedField = .hours }
        }
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: 23))
            .alignmentGuide(.wheelCenter) { $0[VerticalAlignment.center] }
    }

    private func durationPicker(
        _ title: String, field: Field, selection: Binding<Int>, range: Range<Int>
    ) -> some View {
        let isFocused = focusedField == field
        let labelSpacing = WatchScreenMetrics.scaledHeight(4)

        return VStack(spacing: labelSpacing) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    Color("General/Brand/Primary"),
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .opacity(isFocused ? 1 : 0)
                .accessibilityHidden(true)

            Picker(title, selection: selection) {
                ForEach(range, id: \.self) { value in
                    Text("\(value)")
                        .font(.system(size: 24))
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .alignmentGuide(.wheelCenter) { $0[VerticalAlignment.center] }
            .focused($focusedField, equals: field)
            .overlay {
                let shape = RoundedRectangle(cornerRadius: 13)
                ZStack {
                    shape.strokeBorder(.black, lineWidth: 3)
                    shape.strokeBorder(
                        isFocused ? Color("General/Brand/Primary") : Color(.Colors.Grays.picker),
                        lineWidth: isFocused ? 1.5 : 1
                    )
                }
                .allowsHitTesting(false)
            }
        }
        .frame(
            width: WatchScreenMetrics.scaledWidth(43.33),
            height: WatchScreenMetrics.scaledHeight(97)
        )
    }
}

private extension VerticalAlignment {
    enum WheelCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let wheelCenter = VerticalAlignment(WheelCenter.self)
}

#Preview {
    AddTimerView()
}
