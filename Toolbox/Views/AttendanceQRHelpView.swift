import ActivityKit
import SwiftUI

struct AttendanceQRHelpView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

    var body: some View {
        List {
            Section {
                Label("ロック画面から、必要なときだけQRを表示", systemImage: "qrcode")
                    .font(.headline)
                Text("固定のQR文字列を設定して使います。QRの作成・表示に通信は使いません。")
            }
            Section("設定方法") {
                Text("1. ロック画面を長押しして『カスタマイズ』→ロック画面を選びます。")
                Text("2. ウィジェット欄から『工具箱』のQRウィジェットを追加します。")
                Text("3. 追加したウィジェットをタップし、表示名・登庁／退庁・QR内容・表示時間を設定します。")
                Text("4. 編集を完了して、QRボタンをタップします。登庁用と退庁用を別々に設定できます。")
            }
            Section("表示について") {
                Label(activitiesEnabled ? "ライブアクティビティを利用できます" : "ライブアクティビティが無効です",
                      systemImage: activitiesEnabled ? "checkmark.circle" : "exclamationmark.circle")
                if !activitiesEnabled {
                    Text("iPhoneの設定で工具箱のライブアクティビティを許可してください。")
                }
                Text("カードはiOSが管理するライブアクティビティです。表示位置・認証の要否・削除のタイミングは端末や設定で変わります。30秒または60秒後の削除を予約します。")
                Text("ロック画面での表示を目的にしています。Dynamic IslandにQRが同じ時間表示され続ける機能ではありません。")
            }
            Section("大切な注意") {
                Text("表示中のQRは周囲の人やカメラから読めます。カードを閉じても固定QRそのものは無効になりません。勤務先の利用ルールを確認し、公開してはいけない内容や他人のQRを設定しないでください。")
                Text("ボタンを押すだけでは登庁・退庁の記録は行いません。勤務先の読み取り機器でQRを読み取ってください。")
                Text("最初は機密情報を含まないテスト用の文字列で、表示と読み取りを確認してください。QR内容はUTF-8で64バイト以内です。長い内容はQRが細かくなり、読み取れない場合があります。")
            }
        }
        .navigationTitle("登庁・退庁QR")
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled }
        }
    }
}
