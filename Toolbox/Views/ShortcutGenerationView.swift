import SwiftUI

/// This screen has no access to a library, history store, QR settings, or signer.
struct ShortcutGenerationView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var account: ChatGPTAccount
    let currentDraft: ShortcutDraft?
    let save: (ShortcutDraft) throws -> Void
    @State private var instruction = ""
    @State private var includeDraft = false
    @State private var task: Task<Void, Never>?
    @State private var operation = UUID()
    @State private var showSettings = false
    @State private var busy = false
    @State private var progress = 0
    @State private var error: String?
    @State private var preview: ShortcutDraft?
    @State private var confirm = false
    @State private var pendingInstruction = ""
    @State private var pendingDraft: ShortcutDraft?

    var body: some View {
        NavigationStack {
            Form {
                Section("ChatGPT") {
                    LabeledContent("状態", value: account.connected ? "接続済み" : "未接続")
                    if let name = account.models.first(where: { $0.id == account.model })?.name {
                        LabeledContent("モデル", value: name)
                    }
                    Button { showSettings = true } label: { Label("AI設定（ログイン・モデル）", systemImage: "gearshape") }
                        .disabled(busy)
                }
                Section("作りたいショートカット") {
                    TextEditor(text: $instruction).frame(minHeight: 100)
                        .accessibilityLabel("AIへの作成・変更指示").disabled(busy)
                    if let draft = currentDraft {
                        Toggle("現在の下書きも送って編集する", isOn: $includeDraft).disabled(busy)
                        if includeDraft {
                            DisclosureGroup("送る下書きの全内容を確認") {
                                Text(draft.name)
                                Text(draft.source).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                    Text("生成すると、入力した指示と、選択した場合だけ現在の下書きの名前・全JSON（URL・入力値・添付データを含む）をOpenAI（api.openai.com）へ送ります。保存ライブラリ・変更履歴・QR設定は送りません。秘密や個人情報を入力・選択しないでください。ChatGPTの利用枠を使います。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("送信内容を確認して生成") {
                        pendingInstruction = instruction
                        pendingDraft = includeDraft ? currentDraft : nil
                        confirm = true
                    }.disabled(busy || !account.connected || account.model.isEmpty || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if busy {
                        HStack { ProgressView(); Text(progress > 0 ? "生成中 · \(progress)文字" : "処理中…") }
                        Button("中断", role: .cancel) { cancel() }
                    }
                    Text("生成結果は編集できる下書き案です。確認して保存するまで元の内容は変えません。実行やShortcutyへの送信は行いません。中断しても送信済みの内容は取り消せません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AIでショートカット作成")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { cancel(); dismiss() } } }
            .confirmationDialog("OpenAIへ送信して生成しますか？", isPresented: $confirm, titleVisibility: .visible) {
                Button("OpenAIへ送信して生成") {
                    let prompt = pendingInstruction
                    let draft = pendingDraft
                    run {
                        let value = try await ShortcutAI.generate(instruction: prompt, selectedDraft: draft, account: account) { progress = $0 }
                        try Task.checkCancellation()
                        preview = value
                    }
                }
                Button("キャンセル", role: .cancel) { clearPending() }
            } message: {
                Text("宛先: api.openai.com\n指示: \(pendingInstruction)\n\(pendingDraft.map { "下書き「\($0.name)」の全JSONも送ります。" } ?? "現在の下書きは送りません。")\nChatGPTの利用枠を使います。")
            }
            .sheet(isPresented: $showSettings) { ChatGPTSettingsView(account: account) }
            .sheet(item: $preview) { draft in
                ShortcutAIReview(draft: draft) { value in
                    try save(value)
                    preview = nil
                    dismiss()
                }
            }
            .alert("ChatGPT", isPresented: Binding(get: { error != nil || account.notice != nil }, set: { if !$0 { error = nil; account.notice = nil } })) {
                Button("閉じる") { error = nil; account.notice = nil }
            } message: { Text(error ?? account.notice ?? "") }
            .onChange(of: account.epoch) { _, _ in
                // Account changes invalidate any in-flight generation and its preview.
                cancel(); preview = nil
            }
            .onDisappear { cancel() }
        }
    }

    private func clearPending() { pendingInstruction = ""; pendingDraft = nil }
    private func cancel() {
        operation = UUID(); task?.cancel(); task = nil; busy = false; clearPending()
    }
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        let id = UUID(); operation = id; busy = true; progress = 0
        task = Task { @MainActor in
            defer { if operation == id { busy = false; task = nil; clearPending() } }
            do { try await work() }
            catch { if operation == id && !Task.isCancelled { self.error = "処理を完了できませんでした。\(error.localizedDescription)" } }
        }
    }
}

private struct ShortcutAIReview: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: ShortcutDraft
    let save: (ShortcutDraft) throws -> Void
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("編集できる下書き案") {
                    TextField("名前", text: $draft.name)
                    Text(draft.summary)
                    Text("AIは存在しないアクションや危険な動作を提案する場合があります。内容を確認してください。実行・署名はしていません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("アクション") { ShortcutActionList(source: draft.source) }
                Section("JSONを編集") {
                    TextEditor(text: $draft.source).font(.caption.monospaced()).frame(minHeight: 260)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .navigationTitle("生成結果を確認")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("破棄") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("下書きに保存") {
                        do { try ShortcutFormat.validate(draft); try save(draft) }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            .alert("保存できません", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
