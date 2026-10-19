import SwiftUI

struct ToolListView: View {
    @State private var query = ""
    @State private var filter = ToolFilter.all

    private var tools: [ToolDefinition] {
        ToolCatalog.tools(matching: query, filter: filter)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("日々の小さな作業を、軽やかに。", systemImage: "shippingbox.fill")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                        Text("必要な道具を、すぐ手元に。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    Picker("表示するツール", selection: $filter) {
                        ForEach(ToolFilter.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if tools.isEmpty {
                    ContentUnavailableView(
                        "ツールが見つかりません",
                        systemImage: "magnifyingglass",
                        description: Text("検索する言葉や表示条件を変えてみてください。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(tools) { tool in
                            NavigationLink {
                                destination(for: tool)
                            } label: {
                                ToolRow(tool: tool)
                            }
                        }
                    } header: {
                        Text("ツール")
                    } footer: {
                        Label("文字数カウントは端末内で処理します。", systemImage: "lock.shield")
                            .padding(.top, 8)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("工具箱")
            .searchable(text: $query, prompt: "ツールを探す")
        }
    }

    @ViewBuilder
    private func destination(for tool: ToolDefinition) -> some View {
        switch tool.id {
        case .textCounter:
            TextCounterView()
        case .shortcutSigning:
            ShortcutSigningView()
        case .attendanceQR:
            AttendanceQRHelpView()
        }
    }
}

private struct ToolRow: View {
    let tool: ToolDefinition

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: tool.symbol)
                .font(.title2)
                .foregroundStyle(tool.availability == .available ? Color.accentColor : .secondary)
                .frame(width: 46, height: 46)
                .background(
                    tool.availability == .available
                        ? Color.accentColor.opacity(0.10)
                        : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 13)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(tool.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(tool.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if tool.availability == .planned {
                    Text("準備中・まだ利用できません")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ToolListView()
}
