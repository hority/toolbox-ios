import SwiftUI

/// App-wide ChatGPT connection shared by every tool that offers optional AI features.
struct ChatGPTSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var account: ChatGPTAccount
    @State private var task: Task<Void, Never>?
    @State private var operation = UUID()
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !account.records.registrations.isEmpty {
                        Picker("アカウント", selection: Binding(get: { account.records.selectedID ?? "" }, set: { id in
                            cancel()
                            do { try account.select(id) } catch { self.error = error.localizedDescription }
                        })) {
                            ForEach(account.records.registrations, id: \.clientID) { record in
                                Text("\(record.email) · \(record.clientID.suffix(8))").tag(record.clientID)
                            }
                        }.disabled(busy)
                    }
                    LabeledContent("状態", value: account.connected ? "接続済み" : "未接続")
                    Button("Continue with ChatGPT") {
                        run { try await account.signIn(); try await account.refreshModels() }
                    }.buttonStyle(ChatGPTConnectionButtonStyle()).disabled(busy)
                    if !account.records.registrations.isEmpty {
                        Button("別のアカウントを追加") {
                            run { try await account.signIn(newAccount: true); try await account.refreshModels() }
                        }.disabled(busy)
                        Button("ログアウト", role: .destructive) {
                            cancel()
                            run { await account.signOut() }
                        }
                    }
                    if busy {
                        HStack { ProgressView(); Text("処理中…") }
                        Button("中断", role: .cancel) { cancel(); account.cancelSignIn() }
                    }
                } header: { Text("ChatGPT") } footer: {
                    Text("工具箱のAI機能（ショートカット作成など）で共通に使います。OpenAIの画面でChatGPTプランの利用を許可します。利用できるプラン・モデル・枠はアカウントや提供状況によって異なります。ログイン情報はこの端末のKeychainに保存します。")
                }
                Section("モデル") {
                    Button("利用可能なモデルを更新") { run { try await account.refreshModels() } }
                        .disabled(busy || !account.connected)
                    if !account.models.isEmpty {
                        Picker("モデル", selection: $account.model) {
                            ForEach(account.models) { Text($0.name).tag($0.id) }
                        }.disabled(busy)
                    }
                }
                Section {
                    Link("ChatGPTの利用状況・接続管理", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                }
            }
            .navigationTitle("AI設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .alert("ChatGPT", isPresented: Binding(get: { error != nil || account.notice != nil }, set: { if !$0 { error = nil; account.notice = nil } })) {
                Button("閉じる") { error = nil; account.notice = nil }
            } message: { Text(error ?? account.notice ?? "") }
            .onDisappear { cancel() }
        }
    }

    private func cancel() { operation = UUID(); task?.cancel(); task = nil; busy = false }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        let id = UUID(); operation = id; busy = true
        task = Task { @MainActor in
            defer { if operation == id { busy = false; task = nil } }
            do { try await work() }
            catch { if operation == id && !Task.isCancelled { self.error = "処理を完了できませんでした。\(error.localizedDescription)" } }
        }
    }
}
