import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading && viewModel.receiverCards.isEmpty {
                    ProgressView("Loading...")
                        .padding(.top, 100)
                } else if viewModel.receiverCards.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.receiverCards) { card in
                            ReceiverStatusCardView(card: card) {
                                Task { await viewModel.sendOnDemandCheckIn(to: card.id) }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Dashboard")
            .refreshable { await viewModel.loadDashboard() }
            .task { await viewModel.loadDashboard() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Receivers Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add a family member to start receiving daily check-ins.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .padding(.top, 60)
    }
}

struct ReceiverStatusCardView: View {
    let card: ReceiverStatusCard
    let onCheckOn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Avatar
                Circle()
                    .fill(card.status.color.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: card.status.icon)
                            .font(.title2)
                            .foregroundStyle(card.status.color)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.name)
                        .font(.headline)

                    HStack(spacing: 4) {
                        Image(systemName: card.status.icon)
                            .font(.caption)
                        Text(card.status.label)
                            .font(.subheadline)
                    }
                    .foregroundStyle(card.status.color)
                }

                Spacer()

                // Streak
                VStack(spacing: 2) {
                    Text("\(card.streak)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("day streak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Last check-in time
            if let lastCheckIn = card.lastCheckIn {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("Last check-in: \(lastCheckIn.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            // Mood indicator
            if let mood = card.mood {
                HStack {
                    Text("Mood:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(moodEmoji(mood))
                        .font(.body)
                }
            }

            // Check on button
            if card.status != .checkedIn {
                Button {
                    onCheckOn()
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                        Text("Check on \(card.name)")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    private func moodEmoji(_ mood: Mood) -> String {
        switch mood {
        case .happy: return "😊"
        case .neutral: return "😐"
        case .tired: return "😴"
        }
    }
}
