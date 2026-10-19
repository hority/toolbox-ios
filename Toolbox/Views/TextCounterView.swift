import SwiftUI

struct TextCounterView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var text = ""
    @State private var showingClearConfirmation = false
    @FocusState private var editorIsFocused: Bool

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), alignment: .leading),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    var body: some View {
        let statistics = TextStatistics(text: text)

        Form {
            Section {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("ここにテキストを入力、またはペースト")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    TextEditor(text: $text)
                        .frame(minHeight: 190)
                        .scrollContentBackground(.hidden)
                        .focused($editorIsFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("文字数を数えるテキスト")
                        .accessibilityHint("入力すると、下の集計が自動で更新されます")
                }
            } header: {
                Text("テキスト")
            } footer: {
                Text("入力内容はこの画面だけで使用し、アプリから保存・送信しません。")
            }

            Section("集計") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    StatisticTile(title: "文字数", value: statistics.characterCount, detail: "空白・改行を含む")
                    StatisticTile(title: "空白を除く", value: statistics.nonWhitespaceCharacterCount, detail: "空白・タブ・改行を除く")
                    StatisticTile(title: "行数", value: statistics.lineCount, detail: "末尾の空行も含む")
                    StatisticTile(title: "UTF-8 バイト数", value: statistics.utf8ByteCount, detail: "テキストのデータサイズ")
                }
                .padding(.vertical, 10)
            }

            Section {
                Label {
                    Text("絵文字や結合文字は、ひとまとまりを1文字として数えます。空のテキストは0行です。")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("文字数カウント")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("クリア", role: .destructive) {
                    showingClearConfirmation = true
                }
                .disabled(text.isEmpty)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") {
                    editorIsFocused = false
                }
            }
        }
        .confirmationDialog("入力したテキストを消去しますか？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("テキストを消去", role: .destructive) {
                text = ""
            }
            Button("キャンセル", role: .cancel) { }
        }
    }
}

private struct StatisticTile: View {
    let title: String
    let value: Int
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        TextCounterView()
    }
}
