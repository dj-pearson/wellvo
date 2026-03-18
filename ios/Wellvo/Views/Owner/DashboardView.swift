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
                        // Pattern Alerts
                        if !viewModel.alerts.isEmpty {
                            AlertsBannerView(alerts: viewModel.alerts) { alert in
                                Task { await viewModel.dismissAlert(alert) }
                            }
                        }

                        // Weekly Summary
                        if let summary = viewModel.weeklySummary {
                            WeeklySummaryCard(summary: summary)
                        }

                        // Today's Timeline
                        if !viewModel.receiverCards.isEmpty {
                            TodayTimelineCard(cards: viewModel.receiverCards)
                        }

                        // Receiver Cards
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

// MARK: - Weekly Summary Card

struct WeeklySummaryCard: View {
    let summary: WeeklySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)

            HStack(spacing: 20) {
                StatBubble(
                    value: "\(Int(summary.consistencyPercentage))%",
                    label: "Consistency",
                    color: summary.consistencyPercentage >= 80 ? .green : summary.consistencyPercentage >= 50 ? .yellow : .red
                )

                StatBubble(
                    value: summary.averageCheckInTime,
                    label: "Avg Time",
                    color: .blue
                )

                StatBubble(
                    value: "\(summary.totalCheckIns)/\(summary.totalExpected)",
                    label: "Check-Ins",
                    color: .green
                )
            }

            // Mood breakdown
            if !summary.moodBreakdown.isEmpty {
                HStack(spacing: 12) {
                    Text("Moods:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(summary.moodBreakdown.keys), id: \.self) { mood in
                        HStack(spacing: 2) {
                            Text(moodEmoji(mood))
                            Text("\(summary.moodBreakdown[mood] ?? 0)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct StatBubble: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Today's Timeline Card

struct TodayTimelineCard: View {
    let cards: [ReceiverStatusCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Timeline")
                .font(.headline)

            ForEach(cards) { card in
                HStack(spacing: 12) {
                    Circle()
                        .fill(card.status.color)
                        .frame(width: 10, height: 10)

                    Text(card.name)
                        .font(.subheadline)

                    Spacer()

                    if let time = card.checkedInTime {
                        Text(time.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(card.status.label)
                            .font(.caption)
                            .foregroundStyle(card.status.color)
                    }

                    // Timeline bar
                    timelineBar(for: card)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func timelineBar(for card: ReceiverStatusCard) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGray5))
                    .frame(height: 4)

                if let time = card.checkedInTime {
                    let calendar = Calendar.current
                    let hour = calendar.component(.hour, from: time)
                    let minute = calendar.component(.minute, from: time)
                    let progress = CGFloat(hour * 60 + minute) / (24 * 60)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(card.status.color)
                        .frame(width: max(4, geometry.size.width * progress), height: 4)
                }
            }
        }
        .frame(width: 60, height: 4)
    }
}

// MARK: - Receiver Status Card

struct ReceiverStatusCardView: View {
    let card: ReceiverStatusCard
    var isReadOnly: Bool = false
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
                    HStack(spacing: 6) {
                        Text(card.name)
                            .font(.headline)

                        // Notification status indicator
                        if !card.hasNotificationsEnabled {
                            Image(systemName: "bell.slash.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .help("Notifications not enabled")
                        }
                    }

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

            // Notification warning (owner-only)
            if !isReadOnly && !card.hasNotificationsEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("\(card.name) hasn't enabled notifications. They may miss check-in reminders.")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
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

            // Check on button (owner-only)
            if !isReadOnly && card.status != .checkedIn {
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
}

private func moodEmoji(_ mood: Mood) -> String {
    switch mood {
    case .happy: return "😊"
    case .neutral: return "😐"
    case .tired: return "😴"
    }
}

// MARK: - Pattern Alerts Banner

struct AlertsBannerView: View {
    let alerts: [WellvoAlert]
    let onDismiss: (WellvoAlert) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(alerts) { alert in
                HStack(spacing: 12) {
                    Image(systemName: alert.type == "time_drift" ? "clock.badge.exclamationmark" : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(alert.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let driftHours = alert.data?["drift_hours"] as? Double {
                            Text("Shifted by \(String(format: "%.1f", driftHours)) hours")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    Spacer()

                    Button {
                        onDismiss(alert)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
}
