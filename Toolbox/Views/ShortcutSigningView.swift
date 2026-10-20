import SwiftUI
import UniformTypeIdentifiers

struct ShortcutSigningView: View {
    @State private var library = ShortcutLibrary()
    @State private var account = ChatGPTAccount()
    @State private var showAI = false
    @State private var showImport = false
    @State private var importing = false
    @State private var importTask: Task<Void, Never>?
    @State private var selectedID: UUID?
    @State private var pendingDeletion: ShortcutDraft?
    @State private var confirmDeletion = false

    var body: some View {
        List {
            Section {
                Label("読み込む・編集する・署名する", systemImage: "signature")
                    .font(.headline).foregroundStyle(Color.accentColor)
                Text("前に作ったショートカットを、この端末で編集。署名したファイルを共有・保存できます。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { showAI = true } label: { Label("AIで新しく作る", systemImage: "sparkles") }
                    .disabled(importing)
                Button { createSample() } label: { Label("サンプルから作る", systemImage: "plus.circle") }
                    .disabled(importing)
                Button { showImport = true } label: { Label("ファイルから読み込む", systemImage: "square.and.arrow.down") }
                    .disabled(importing)
                if importing {
                    HStack { ProgressView(); Text("読み込み中…") }
                    Button("中断", role: .cancel) { importTask?.cancel() }
                }
            }
            Section("編集ライブラリ") {
                ForEach(library.drafts.sorted { $0.modified > $1.modified }) { draft in
                    NavigationLink {
                        ShortcutEditor(draft: draft, library: library, account: account)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(draft.name).font(.headline)
                            Text("\(draft.actionCount)アクション · \(draft.modified.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }
                    .swipeActions {
                        Button("削除", role: .destructive) { pendingDeletion = draft; confirmDeletion = true }
                    }
                }
                if library.drafts.isEmpty { Text("読み込んだファイルをここに保存します").foregroundStyle(.secondary) }
            }
            Section {
                Text("JSON、plist、.shortcut、前のツールの編集用JSONに対応しています。署名済みファイルは『誰でも』で共有したものを選んでください。")
                Text("編集内容・履歴は端末内に保存します。AI生成時は確認した指示・選択内容をOpenAIへ、署名時は別の確認後にShortcutyへ全内容を送信します。ショートカットは自動実行しません。")
                Link("Shortcutyの署名サービス", destination: URL(string: "https://sign.shortcuty.app")!)
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("ショートカット署名")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedID) { id in
            if let draft = library.drafts.first(where: { $0.id == id }) { ShortcutEditor(draft: draft, library: library, account: account) }
        }
        .sheet(isPresented: $showAI) {
            ShortcutGenerationView(account: account, currentDraft: nil) { draft in
                try library.upsert(draft)
                selectedID = draft.id
            }
        }
        .fileImporter(isPresented: $showImport,
                      allowedContentTypes: [UTType(filenameExtension: "shortcut") ?? .data, .json, .propertyList, .data]) { result in
            switch result {
            case .success(let url): importFile(url)
            case .failure(let error): library.error = error.localizedDescription
            }
        }
        .confirmationDialog("この下書きを削除しますか？", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("下書きと履歴を削除", role: .destructive) {
                guard let draft = pendingDeletion else { return }
                do { try library.remove(draft.id) } catch { library.error = error.localizedDescription }
                pendingDeletion = nil
            }
            Button("キャンセル", role: .cancel) { pendingDeletion = nil }
        } message: { Text("\(pendingDeletion?.name ?? "")\nこの端末に保存した編集内容と履歴を削除します。元の読み込みファイルは残ります。") }
        .alert("読み込み・保存", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("閉じる") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .onAppear { ShortcutSigner.removeExpiredExports() }
        .onDisappear { importTask?.cancel() }
    }

    private func createSample() {
        do {
            var draft = ShortcutDraft.example
            draft.name = "新しいショートカット"
            try library.upsert(draft)
            selectedID = draft.id
        } catch { library.error = error.localizedDescription }
    }

    private func importFile(_ url: URL) {
        guard !importing else { return }
        importing = true
        importTask = Task {
            defer { importing = false; importTask = nil }
            let work = Task.detached(priority: .userInitiated) { try ShortcutImport.read(url) }
            do {
                let draft = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                try Task.checkCancellation()
                try library.upsert(draft)
                selectedID = draft.id
            } catch {
                if !Task.isCancelled { library.error = error.localizedDescription }
            }
        }
    }
}

private struct ShortcutExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .propertyList, .data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct ShortcutEditor: View {
    @State var draft: ShortcutDraft
    let library: ShortcutLibrary
    let account: ChatGPTAccount
    @State private var showAI = false
    @State private var busy = false
    @State private var signingTask: Task<Void, Never>?
    @State private var error: String?
    @State private var showSource = false
    @State private var showHistory = false
    @State private var confirmSign = false
    @State private var shared: SignedShortcutFile?
    @State private var shareForCleanup: SignedShortcutFile?
    @State private var exported: ShortcutExportDocument?
    @State private var exportType: UTType = .json
    @State private var exportName = "Shortcut"
    @State private var showExport = false

    var body: some View {
        List {
            Section {
                Text(draft.name).font(.title2.bold())
                Text(draft.summary).font(.subheadline).foregroundStyle(.secondary)
                Label("\(draft.actionCount)アクション", systemImage: "square.stack")
                    .font(.caption).foregroundStyle(Color.accentColor)
            }
            Section("アクション") { ShortcutActionList(source: draft.source) }
            if busy {
                Section {
                    HStack { ProgressView(); Text("署名・内容の検証中…") }
                    Button("中断", role: .cancel) { signingTask?.cancel() }
                    Text("送信済みの内容をサーバーから取り消すことはできません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("編集・保存") {
                Button { showAI = true } label: { Label("AIで作成・編集", systemImage: "sparkles") }
                Button { showSource = true } label: { Label("名前・JSONを編集", systemImage: "curlybraces") }
                Button { showHistory = true } label: { Label("変更履歴（\(draft.revisions.count)）", systemImage: "clock.arrow.circlepath") }
                    .disabled(draft.revisions.isEmpty)
                Button { exportDraft() } label: { Label("編集用ファイルを保存", systemImage: "square.and.arrow.up") }
                Button { exportPlist() } label: { Label("未署名のplistを保存", systemImage: "doc.badge.arrow.up") }
            }.disabled(busy)
            Section {
                Button { confirmSign = true } label: { Label("Shortcutyで署名", systemImage: "signature").fontWeight(.semibold) }
                    .disabled(busy || draft.actionCount == 0)
                Text("署名にはインターネット接続が必要です。受け取ったファイルの展開・内容一致を確認します。署名者の信頼性と追加可否はAppleのショートカットアプリが最終確認します。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("編集")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAI) {
            ShortcutGenerationView(account: account, currentDraft: draft) { value in
                try apply(name: value.name, source: value.source, summary: value.summary)
            }
        }
        .sheet(isPresented: $showSource) {
            ShortcutSourceEditor(name: draft.name, source: draft.source) { name, source in
                try apply(name: name, source: source, summary: "名前・JSONを手動で編集しました。")
            }
        }
        .sheet(isPresented: $showHistory) { history }
        .sheet(item: $shared, onDismiss: cleanupShare) { file in ShortcutShareSheet(url: file.url) }
        .fileExporter(isPresented: $showExport, document: exported, contentType: exportType, defaultFilename: exportName) { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
            exported = nil
        }
        .confirmationDialog("Shortcutyへ送信して署名しますか？", isPresented: $confirmSign, titleVisibility: .visible) {
            Button("全内容をShortcutyへ送信して署名") { sign() }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("「\(draft.name)」のアクション、入力値、URL、埋め込みデータを含む全内容をShortcuty（sign.shortcuty.app）へ送信します。個人情報や秘密が含まれていないか確認してください。編集履歴は送りません。署名者の信頼性と追加可否はAppleのショートカットアプリが最終確認します。")
        }
        .alert("確認", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("閉じる") { error = nil }
        } message: { Text(error ?? "") }
        .onDisappear {
            signingTask?.cancel()
            // Keep the file while the activity controller is using it.
            if shared == nil { cleanupShare() }
        }
    }

    private var history: some View {
        NavigationStack {
            List {
                Section {
                    Text("過去10件を保存します。復元前の内容も履歴に残ります。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(draft.revisions) { revision in
                    Button {
                        do {
                            try apply(name: revision.name, source: revision.source, summary: revision.summary)
                            showHistory = false
                        } catch { self.error = error.localizedDescription; showHistory = false }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(revision.name).font(.headline)
                            Text(revision.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            Text(revision.summary).font(.caption).foregroundStyle(.secondary)
                            Text("この版に戻す").font(.caption).foregroundStyle(Color.accentColor)
                        }
                    }.foregroundStyle(.primary)
                }
            }
            .navigationTitle("変更履歴")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showHistory = false } } }
        }
    }

    private func apply(name: String, source: String, summary: String) throws {
        var updated = draft
        updated.replace(name: name, source: source, summary: summary)
        try library.upsert(updated)
        draft = updated
    }

    private func sign() {
        guard !busy else { return }
        busy = true
        let snapshot = draft
        signingTask = Task {
            defer { busy = false; signingTask = nil }
            do {
                let file = try await ShortcutSigner.sign(snapshot)
                guard !Task.isCancelled else { file.remove(); return }
                cleanupShare()
                shareForCleanup = file
                shared = file
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    private func cleanupShare() { shareForCleanup?.remove(); shareForCleanup = nil }

    private func exportDraft() {
        do {
            exported = ShortcutExportDocument(data: try JSONEncoder().encode(draft))
            exportType = .json
            exportName = ShortcutFormat.safeName(draft.name) + ".studio.json"
            showExport = true
        } catch { self.error = error.localizedDescription }
    }

    private func exportPlist() {
        do {
            exported = ShortcutExportDocument(data: try ShortcutFormat.plist(draft.source))
            exportType = .propertyList
            exportName = ShortcutFormat.safeName(draft.name) + ".plist"
            showExport = true
        } catch { self.error = error.localizedDescription }
    }
}

struct ShortcutActionList: View {
    let source: String
    private var actions: [[String: Any]] { ((try? ShortcutFormat.workflow(source))?["WFWorkflowActions"] as? [[String: Any]]) ?? [] }
    private let names = ["gettext": "テキスト", "alert": "アラートを表示", "url": "URL", "openurl": "URLを開く", "getclipboard": "クリップボードを取得", "setclipboard": "クリップボードにコピー", "ask": "入力を要求", "showresult": "結果を表示"]

    var body: some View {
        if actions.isEmpty { Text("アクションがありません。JSONを編集して追加してください。").foregroundStyle(.secondary) }
        ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
            let identifier = action["WFWorkflowActionIdentifier"] as? String ?? ""
            let parameters = action["WFWorkflowActionParameters"] as? [String: Any] ?? [:]
            DisclosureGroup {
                Text((try? ShortcutFormat.json(parameters)) ?? "{}")
                    .font(.caption.monospaced()).textSelection(.enabled)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(names[identifier.replacingOccurrences(of: "is.workflow.actions.", with: "")] ?? identifier)
                            .font(.subheadline.weight(.semibold))
                        if let text = (parameters["WFTextActionText"] ?? parameters["WFAlertActionTitle"] ?? parameters["WFURLActionURL"] ?? parameters["WFAskActionPrompt"]) as? String {
                            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}

private struct ShortcutSourceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    @State var source: String
    let save: (String, String) throws -> Void
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("名前（100文字以内）", text: $name).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("ショートカットの名前")
                TextEditor(text: $source).font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("ショートカットのJSON")
            }.padding()
            .navigationTitle("名前・JSONを編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            _ = try ShortcutFormat.workflow(source)
                            try save(name.trimmingCharacters(in: .whitespacesAndNewlines), source)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .interactiveDismissDisabled()
            .alert("保存できません", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}

private struct ShortcutShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

#Preview {
    NavigationStack { ShortcutSigningView() }
}
