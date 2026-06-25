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
            } else if model.notes.isEmpty && !model.isLoading {
                emptyState
            } else {
                notesList
            }
            composer
        }
        .background(AmbientBackground(tone: .neutral))
        .navigationTitle("Notes · \(receiverName)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .alert("Couldn't save note", isPresented: Binding(
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
            Button("Retry") { Task { await model.reload() } }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.notes) { note in
                    noteRow(note)
                }
            }
            .padding()
        }
        // Let the user swipe the list to dismiss the keyboard (US-IOS102).
        .scrollDismissesKeyboard(.interactively)
    }

    private func noteRow(_ note: CareNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.body)
                .font(.body)
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
            if model.canEdit(note) {
                Button {
                    editingNote = note
                    draft = note.body
                    composerFocused = true
                } label: { Label("Edit", systemImage: "pencil") }
            }
            if model.canDelete(note) {
                Button(role: .destructive) {
                    noteToDelete = note
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.authorName) wrote: \(note.body)")
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if editingNote != nil {
                HStack {
                    Text("Editing note")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { cancelEdit() }
                        .font(.caption2)
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
        guard !text.isEmpty else { return }
        if let editing = editingNote {
            await model.edit(editing, newBody: text)
        } else {
            await model.add(body: text)
        }
        draft = ""
        editingNote = nil
        composerFocused = false
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

    func canEdit(_ note: CareNote) -> Bool { note.authorId == currentUserId }
    func canDelete(_ note: CareNote) -> Bool { note.authorId == currentUserId || isOwner }

    func start() async {
        await resolveIdentity()
        await reload()
        await subscribe()
    }

    func stop() {
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
        // Owner check for moderation rights.
        if let family = try? await FamilyService.shared.getFamily() {
            isOwner = (family.ownerId == session.user.id)
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

    func add(body: String) async {
        guard let uid = currentUserId else { return }
        isSaving = true
        defer { isSaving = false }
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
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
        }
    }

    func edit(_ note: CareNote, newBody: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await SupabaseService.shared.client
                .from("care_notes")
                .update(["body": newBody])
                .eq("id", value: note.id.uuidString)
                .execute()
            await reload()
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
        }
    }

    func delete(_ note: CareNote) async {
        do {
            try await SupabaseService.shared.client
                .from("care_notes")
                .delete()
                .eq("id", value: note.id.uuidString)
                .execute()
            notes.removeAll { $0.id == note.id }
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
        }
    }

    private func subscribe() async {
        let client = SupabaseService.shared.client
        let ch = client.realtimeV2.channel("care-notes:\(receiverId.uuidString)")
        let changes = ch.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "care_notes",
            filter: "receiver_id=eq.\(receiverId.uuidString)"
        )
        await ch.subscribe()
        channel = ch
        listenerTask = Task { [weak self] in
            for await _ in changes {
                await self?.reload()
            }
        }
    }
}
