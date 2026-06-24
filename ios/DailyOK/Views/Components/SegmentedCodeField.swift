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

    var body: some View {
        ZStack {
            // Hidden field captures the keyboard, paste, and OTP autofill. The
            // visible boxes below mirror its value.
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

            HStack(spacing: 10) {
                ForEach(0..<length, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .onAppear { if autoFocus { focused = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verification code")
        .accessibilityValue("\(code.count) of \(length) digits entered")
        .accessibilityHint("Enter the \(length)-digit code")
    }

    private func digitBox(at index: Int) -> some View {
        let characters = Array(code)
        let character = index < characters.count ? String(characters[index]) : ""
        let isCurrent = index == code.count
        let isActive = isCurrent && focused

        return Text(character)
            .font(.title.monospaced().weight(.semibold))
            .frame(width: 44, height: 56)
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
