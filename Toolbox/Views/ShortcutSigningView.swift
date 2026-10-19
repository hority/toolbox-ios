import SwiftUI

struct ShortcutSigningView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "signature")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 104, height: 104)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 28))
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("準備中")
                        .font(.title2.bold())
                    Text("ショートカット署名は\nまだ利用できません")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }

                Text("このバージョンには署名処理を実装していません。ファイルの読み込み・署名・書き出しはできません。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Label("実装予定のツール", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 28)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("ショートカット署名")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ShortcutSigningView()
    }
}
