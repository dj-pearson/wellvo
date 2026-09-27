import SwiftUI
import Supabase

/// US-IOS016 — shared care notes / timeline for one receiver. Visible to the
/// whole care team (owner + viewers); each caregiver can add notes and
/// edit/delete their own, and the owner can moderate (delete any). Updates
/// stream in realtime so co-caregivers see new context promptly.
struct CareNotesView: View {
    let familyId: UUID
    let receiverId: UUID
    let receiverName: String

    @StateObject private var model: CareNotesViewModel
    @State private var draft: String = ""
    @State private var editingNote: CareNote?
    @State private var noteToDelete: CareNote?
    @FocusState private var composerFocused: Bool
    /// Bumped after posting so the list scrolls to the new (top) note.
    @State private var scrollToTopToken = 0

    init(familyId: UUID, receiverId: UUID, receiverName: String) {
        self.familyId = familyId
        self.receiverId = receiverId
        self.receiverName = receiverName
        _model = StateObject(wrappedValue: CareNotesViewModel(familyId: familyId, receiverId: receiverId))
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.loadFailed && model.notes.isEmpty {
                loadErrorState
            } else if model.notes.isEmpty && model.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Loading notes…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            } else if model.notes.isEmpty {
                emptyState
            } else {
                if model.loadFailed {
                    refreshFailedStrip
                }
                notesList
            }
            composer
        }
        .background(AmbientBackground(tone: .neutral))
        .navigationTitle("Notes · \(receiverName)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .alert(model.errorTitle, isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        // Confirm before a permanent, server-side delete — every other
        // destructive action in the app confirms (US-IOS102).
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { noteToDelete != nil },
                set: { if !$0 { noteToDelete = nil } }
            ),
            presenting: noteToDelete
        ) { note in
            Button("Delete", role: .destructive) {
                Task { await model.delete(note) }
                noteToDelete = nil
            }
            Button("Cancel", role: .cancel) { noteToDelete = nil }
        } message: { _ in
            Text("This permanently removes the note for the whole care team.")
        }
    }

    private var loadErrorState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Couldn't load notes")
                .font(.headline)
            Button("Retry") { Task { await model.retry() } }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Notes are on screen but the latest refresh failed: say so instead of
    /// silently showing a stale list.
    private var refreshFailedStrip: some View {
        Button {
            Task { await model.retry() }
        } label: {
            Label("Couldn't refresh notes — tap to retry", systemImage: "arrow.clockwise")
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .background(.thinMaterial)
        .accessibilityHint("Loads the latest notes again")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No notes yet")
                .font(.headline)
            Text("Share context the whole family can see — a doctor's visit, a trip, or \"left phone at home.\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var notesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.notes) { note in
                        noteRow(note)
                            .id(note.id)
                    }
                }
                .padding()
            }
            // Let the user swipe the list to dismiss the keyboard (US-IOS102).
            .scrollDismissesKeyboard(.interactively)
            // Newest is first; after posting, bring it into view.
            .onChange(of: scrollToTopToken) { _, _ in
                if let first = model.notes.first {
                    withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
        }
    }

    private func noteRow(_ note: CareNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(note.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Visible way in to edit/delete — a long-press menu alone is
                // found by few people.
                if model.canEdit(note) || model.canDelete(note) {
                    Menu {
                        noteActions(note)
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityHidden(true)
                }
            }
            HStack(spacing: 6) {
                Text(note.authorName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if note.wasEdited {
                    Text("(edited)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(style: .regular, radius: DailyOKGlass.radiusMedium, elevation: DailyOKElevation.level2)
        .contextMenu {
            noteActions(note)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: note))
        .accessibilityActions {
            if model.canEdit(note) {
                Button("Edit") { beginEdit(note) }
            }
            if model.canDelete(note) {
                Button("Delete") { noteToDelete = note }
            }
        }
    }

    @ViewBuilder
    private func noteActions(_ note: CareNote) -> some View {
        if model.canEdit(note) {
            Button {
                beginEdit(note)
            } label: { Label("Edit", systemImage: "pencil") }
        }
        if model.canDelete(note) {
            Button(role: .destructive) {
                noteToDelete = note
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func accessibilityLabel(for note: CareNote) -> String {
        let when = note.createdAt.formatted(date: .abbreviated, time: .shortened)
        let edited = note.wasEdited ? String(localized: ", edited") : ""
        return String(localized: "\(note.authorName), \(when)\(edited): \(note.body)")
    }

    private func beginEdit(_ note: CareNote) {
        editingNote = note
        draft = note.body
        composerFocused = true
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if editingNote != nil {
                HStack {
                    Text("Editing note")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { cancelEdit() }
                        .font(.subheadline)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            HStack(spacing: 8) {
                TextField("Add a note…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($composerFocused)
                Button {
                    Task { await submit() }
                } label: {
                    Image(systemName: editingNote == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving)
                .tint(DailyOKColor.green)
                .accessibilityLabel(editingNote == nil ? "Send note" : "Save note")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private func submit() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isSaving else { return }
        let saved: Bool
        let wasNew = editingNote == nil
        if let editing = editingNote {
            saved = await model.edit(editing, newBody: text)
        } else {
            saved = await model.add(body: text)
        }
        // Keep the text when the save failed, so a note typed on a weak
        // connection isn't lost behind the error.
        guard saved else { return }
        draft = ""
        editingNote = nil
        composerFocused = false
        if wasNew { scrollToTopToken += 1 }
    }

    private func cancelEdit() {
        editingNote = nil
        draft = ""
        composerFocused = false
    }
}

@MainActor
final class CareNotesViewModel: ObservableObject {
    @Published var notes: [CareNote] = []
    @Published var isLoading = true
    @Published var isSaving = false
    @Published var errorMessage: String?
    /// Matches the action that failed ("Couldn't delete note" for a delete).
    @Published var errorTitle: String = String(localized: "Couldn't save note")
    /// True when the last load failed — lets the view show an error + retry
    /// instead of the "No notes yet" empty state (US-IOS102).
    @Published var loadFailed = false

    private let familyId: UUID
    private let receiverId: UUID
    private var currentUserId: UUID?
    private var currentUserName: String = "A caregiver"
    private var isOwner = false
    private var channel: RealtimeChannelV2?
    private var listenerTask: Task<Void, Never>?
    /// Bumped by start() and stop(); a start() still in flight after the
    /// screen closed (or reopened) must not subscribe.
    private var generation = 0

    init(familyId: UUID, receiverId: UUID) {
        self.familyId = familyId
        self.receiverId = receiverId
    }

    private struct CareNoteInsert: Encodable {
        let family_id: String
        let receiver_id: String
        let author_id: String
        let author_name: String
        let body: String
    }

    private struct IdRow: Decodable { let id: UUID }

    func canEdit(_ note: CareNote) -> Bool { note.authorId == currentUserId }
    func canDelete(_ note: CareNote) -> Bool { note.authorId == currentUserId || isOwner }

    func start() async {
        generation += 1
        let myGeneration = generation
        await resolveIdentity()
        guard !Task.isCancelled, generation == myGeneration else { return }
        await reload()
        guard !Task.isCancelled, generation == myGeneration else { return }
        await subscribe(generation: myGeneration)
    }

    /// Retry after a failed load: also re-resolves who the user is, which may
    /// have failed for the same reason (offline cold open).
    func retry() async {
        if currentUserId == nil { await resolveIdentity() }
        await reload()
    }

    func stop() {
        generation += 1
        listenerTask?.cancel()
        listenerTask = nil
        if let channel {
            Task { await channel.unsubscribe() }
        }
        channel = nil
    }

    private func resolveIdentity() async {
        guard let session = try? await SupabaseService.shared.client.auth.session else { return }
        currentUserId = session.user.id
        do {
            struct UserName: Decodable { let displayName: String; enum CodingKeys: String, CodingKey { case displayName = "display_name" } }
            let u: UserName = try await SupabaseService.shared.client
                .from("users").select("display_name")
                .eq("id", value: session.user.id.uuidString)
                .single().execute().value
            currentUserName = u.displayName
        } catch { /* keep default */ }
        // Owner check for moderation rights — of THIS family, not whichever
        // family getFamily() happens to return first.
        struct OwnerRow: Decodable { let ownerId: UUID; enum CodingKeys: String, CodingKey { case ownerId = "owner_id" } }
        if let row: OwnerRow = try? await SupabaseService.shared.client
            .from("families").select("owner_id")
            .eq("id", value: familyId.uuidString)
            .single().execute().value {
            isOwner = (row.ownerId == session.user.id)
        }
    }

    func reload() async {
        do {
            notes = try await SupabaseService.shared.client
                .from("care_notes")
                .select()
                .eq("family_id", value: familyId.uuidString)
                .eq("receiver_id", value: receiverId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            loadFailed = false
        } catch {
            // Distinguish a load failure from a genuinely empty list so the view
            // can offer Retry instead of "No notes yet" (US-IOS102).
            loadFailed = true
        }
        isLoading = false
    }

    /// Returns true when the note was saved; the view keeps the draft otherwise.
    func add(body: String) async -> Bool {
        errorTitle = String(localized: "Couldn't save note")
        isSaving = true
        defer { isSaving = false }
        if currentUserId == nil { await resolveIdentity() }
        guard let uid = currentUserId else {
            errorMessage = String(localized: "Couldn't confirm you're signed in. Check your connection and try again — your note is still here.")
            return false
        }
        do {
            try await SupabaseService.shared.client
                .from("care_notes")
                .insert(CareNoteInsert(
                    family_id: familyId.uuidString,
                    receiver_id: receiverId.uuidString,
                    author_id: uid.uuidString,
                    author_name: currentUserName,
                    body: body
                ))
                .execute()
            await reload()
            return true
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
            return false
        }
    }

    func edit(_ note: CareNote, newBody: String) async -> Bool {
        errorTitle = String(localized: "Couldn't save note")
        isSaving = true
        defer { isSaving = false }
        do {
            // Returning rows so a write RLS silently refused (0 rows) is not
            // reported as saved.
            let rows: [IdRow] = try await SupabaseService.shared.client
                .from("care_notes")
                .update(["body": newBody])
                .eq("id", value: note.id.uuidString)
                .select("id")
                .execute()
                .value
            guard !rows.isEmpty else {
                errorMessage = String(localized: "This note can no longer be edited. It may have been deleted.")
                await reload()
                return false
            }
            await reload()
            return true
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
            return false
        }
    }

    func delete(_ note: CareNote) async {
        do {
            let rows: [IdRow] = try await SupabaseService.shared.client
                .from("care_notes")
                .delete()
                .eq("id", value: note.id.uuidString)
                .select("id")
                .execute()
                .value
            if rows.isEmpty {
                // Already gone, or not ours to delete: show the server's truth.
                await reload()
                if notes.contains(where: { $0.id == note.id }) {
                    errorTitle = String(localized: "Couldn't delete note")
                    errorMessage = String(localized: "You can't delete this note.")
                }
                return
            }
            notes.removeAll { $0.id == note.id }
        } catch {
            errorTitle = String(localized: "Couldn't delete note")
            errorMessage = DailyOKError.network(error).localizedDescription
        }
    }

    private func subscribe(generation myGeneration: Int) async {
        let client = SupabaseService.shared.client
        let ch = client.realtimeV2.channel("care-notes:\(receiverId.uuidString)")
        let changes = ch.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "care_notes",
            filter: "receiver_id=eq.\(receiverId.uuidString)"
        )
        await ch.subscribe()
        // The screen closed while subscribing: don't leave an orphaned
        // channel and listener running for the rest of the session.
        guard generation == myGeneration, !Task.isCancelled, channel == nil else {
            await ch.unsubscribe()
            return
        }
        channel = ch
        listenerTask = Task { [weak self] in
            for await _ in changes {
                await self?.reload()
            }
        }
    }
}
