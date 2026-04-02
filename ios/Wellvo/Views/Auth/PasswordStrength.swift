import SwiftUI

// MARK: - Password Strength

enum PasswordStrength: Int, Comparable {
    case weak = 0, fair, good, strong

    static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .strong: return "Strong"
        }
    }

    var color: Color {
        switch self {
        case .weak: return .red
        case .fair: return .orange
        case .good: return .yellow
        case .strong: return .green
        }
    }

    var progress: Double {
        switch self {
        case .weak: return 0.25
        case .fair: return 0.5
        case .good: return 0.75
        case .strong: return 1.0
        }
    }

    static func evaluate(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return .weak }

        var score = 0

        // Length
        if password.count >= 10 { score += 1 }
        if password.count >= 14 { score += 1 }

        // Character diversity
        if password.contains(where: { $0.isUppercase }) { score += 1 }
        if password.contains(where: { $0.isLowercase }) { score += 1 }
        if password.contains(where: { $0.isNumber }) { score += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { score += 1 }

        // Penalty for common patterns
        let commonPasswords: Set<String> = [
            "password", "123456789", "1234567890", "qwerty1234", "iloveyou1",
            "password1", "password12", "password123",
        ]
        if commonPasswords.contains(password.lowercased()) { return .weak }

        switch score {
        case 0...2: return .weak
        case 3: return .fair
        case 4...5: return .good
        default: return .strong
        }
    }
}

// MARK: - Password Strength Indicator View

struct PasswordStrengthIndicator: View {
    let password: String

    var body: some View {
        let strength = PasswordStrength.evaluate(password)
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(strength.color)
                        .frame(width: geo.size.width * strength.progress, height: 4)
                        .animation(.easeInOut(duration: 0.2), value: strength)
                }
            }
            .frame(height: 4)
            HStack {
                Text(strength.label)
                    .font(.caption2)
                    .foregroundStyle(strength.color)
                Spacer()
            }
        }
    }
}
