import SwiftUI

/// A segmented per-digit code entry field (one box per digit) backed by a single
/// hidden text field. Easier to read and fill than a single monospaced field —
/// especially for seniors — and shows live entry progress. Supports paste and
/// one-time-code autofill via `.textContentType(.oneTimeCode)`.
struct SegmentedCodeField: View {
    @Binding var code: String
    var length: Int = 6
    /// Called when the field reaches `length` digits.
    var onComplete: (() -> Void)? = nil
    /// Whether to grab keyboard focus on appear. Hosts set this false when the
    /// field is disabled (e.g. locked out) so the keyboard doesn't pop uselessly.
    var autoFocus: Bool = true

    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Scale the boxes with Dynamic Type so digits stay legible for low-vision
    // users, but cap the growth and let inter-box spacing shrink so six boxes
    // still fit on a phone (US-IOS105).
    @ScaledMetric(relativeTo: .title) private var boxWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .title) private var boxHeight: CGFloat = 56

    private var boxSpacing: CGFloat { dynamicTypeSize.isAccessibilitySize ? 4 : 10 }

    var body: some View {
        ZStack {
            // Hidden field captures the keyboard, paste, and OTP autofill — and
            // is the focusable, EDITABLE accessibility element. The visible boxes
            // below merely mirror its value and are hidden from VoiceOver.
            TextField("", text: Binding(
                get: { code },
                set: { newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(length))
                    if filtered != code { code = filtered }
                    if filtered.count == length { onComplete?() }
                }
            ))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($focused)
            .opacity(0.02) // near-invisible but still focusable/tappable
            .frame(height: 1)
            .accessibilityLabel("Verification code")
            .accessibilityValue("\(code.count) of \(length) digits entered")
            .accessibilityHint("Enter the \(length)-digit code")

            HStack(spacing: boxSpacing) {
                ForEach(0..<length, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityHidden(true) // decorative mirror of the field above
        }
        .onAppear { if autoFocus { focused = true } }
    }

    private func digitBox(at index: Int) -> some View {
        let characters = Array(code)
        let character = index < characters.count ? String(characters[index]) : ""
        let isCurrent = index == code.count
        let isActive = isCurrent && focused

        return Text(character)
            .font(.title.monospaced().weight(.semibold))
            // Cap the digit's own scaling so it can't overflow the box.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .minimumScaleFactor(0.6)
            .frame(width: boxWidth, height: boxHeight)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isActive ? DailyOKColor.green500 : Color.gray.opacity(0.3),
                        lineWidth: isActive ? 2 : 1
                    )
            )
    }
}
