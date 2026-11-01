import AVFoundation
import PhotosUI
import SwiftUI
import VisionKit

/// Soft pastel look for the hiragana hunter. Placeholder art until custom illustrations exist.
enum HunterStyle {
    static let cream = Color(red: 1, green: 0.97, blue: 0.92)
    static let pink = Color(red: 1, green: 0.47, blue: 0.62)
    static let ink = Color(red: 0.33, green: 0.25, blue: 0.36)
    /// One gentle hue per gojūon row (あ行, か行, …).
    static let rowHues: [Double] = [0.97, 0.06, 0.12, 0.30, 0.42, 0.52, 0.60, 0.70, 0.80, 0.88]

    static func color(for character: String) -> Color {
        let row = Hiragana.rows.firstIndex { $0.contains(character) } ?? 0
        return Color(hue: rowHues[row], saturation: 0.45, brightness: 1)
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct HiraganaHunterView: View {
    @State private var collection = HiraganaCollection()
    @State private var voice = HiraganaVoice()
    @State private var showCamera = false
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var finds: FindBatch?
    @State private var detail: HiraganaLetter?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                progress
                grid
                Text("しゃしんは この たんまつの なかだけに ほぞんします。")
                    .font(HunterStyle.rounded(12, .medium)).foregroundStyle(HunterStyle.ink.opacity(0.6))
            }
            .padding(16)
        }
        .background(HunterStyle.cream.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle("ひらがなハンター")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCamera) {
            HiraganaCameraView(collection: collection, voice: voice)
        }
        .sheet(item: $finds) { batch in
            HiraganaResultView(finds: batch.finds, collection: collection, voice: voice)
        }
        .sheet(item: $detail) { letter in
            HiraganaDetailView(character: letter.id, collection: collection, voice: voice)
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            reading = true
            Task {
                defer { reading = false }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    collection.error = "しゃしんを よみこめませんでした。"
                    return
                }
                finds = FindBatch(finds: await HiraganaReader.finds(in: image))
            }
        }
        .alert("ひらがなハンター", isPresented: Binding(get: { collection.error != nil }, set: { if !$0 { collection.error = nil } })) {
            Button("とじる") { collection.error = nil }
        } message: { Text(collection.error ?? "") }
        .onDisappear { voice.stop() }
    }

    private var progress: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("ずかん").font(HunterStyle.rounded(20))
                Spacer()
                Text("\(collection.caughtKinds)").font(HunterStyle.rounded(34, .heavy)).foregroundStyle(HunterStyle.pink)
                Text("/ \(Hiragana.all.count)もじ").font(HunterStyle.rounded(16))
            }
            GeometryReader { proxy in
                Capsule().fill(HunterStyle.pink.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule().fill(HunterStyle.pink)
                            .frame(width: max(14, proxy.size.width * CGFloat(collection.caughtKinds) / CGFloat(Hiragana.all.count)))
                    }
            }
            .frame(height: 14)
            if collection.caughtKinds == Hiragana.all.count {
                Text("🎉 ぜんぶ あつめたね！ すごい！").font(HunterStyle.rounded(16))
            }
        }
        .foregroundStyle(HunterStyle.ink)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private var grid: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Hiragana.rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(0..<5, id: \.self) { column in
                        if let character = Hiragana.rows[row][column] {
                            Button { detail = HiraganaLetter(id: character); voice.letter(character) } label: {
                                HiraganaCell(character: character, collection: collection)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button { showCamera = true } label: {
                Label("ハントする", systemImage: "camera.fill")
                    .font(HunterStyle.rounded(20)).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .foregroundStyle(.white).background(HunterStyle.pink, in: Capsule())
                    .shadow(color: HunterStyle.pink.opacity(0.35), radius: 8, y: 4)
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Image(systemName: reading ? "hourglass" : "photo.on.rectangle")
                    .font(.system(size: 22, weight: .bold)).frame(width: 58, height: 58)
                    .foregroundStyle(HunterStyle.pink).background(.white, in: Circle())
            }
            .disabled(reading)
            .accessibilityLabel("しゃしんから さがす")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(HunterStyle.cream.opacity(0.95))
    }
}

private struct FindBatch: Identifiable {
    let id = UUID()
    let finds: [HiraganaFind]
}

private struct HiraganaLetter: Identifiable { let id: String }

private struct HiraganaCell: View {
    let character: String
    let collection: HiraganaCollection

    var body: some View {
        let latest = collection.catches(of: character).first
        let count = collection.count(of: character)
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(latest == nil ? Color.white.opacity(0.6) : HunterStyle.color(for: character))
            if let latest, let image = UIImage(contentsOfFile: collection.imageURL(latest).path()) {
                Image(uiImage: image).resizable().scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12)).padding(4)
            } else {
                Text(character).font(HunterStyle.rounded(30, .heavy))
                    .foregroundStyle(latest == nil ? HunterStyle.ink.opacity(0.18) : .white)
            }
            if latest == nil {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(HunterStyle.ink.opacity(0.15), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
            if count > 1 {
                Text("×\(count)").font(HunterStyle.rounded(11, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(HunterStyle.pink, in: Capsule()).offset(x: 4, y: -4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(count == 0 ? "\(character)、まだ" : "\(character)、\(count)こ")
    }
}

/// Live camera with Apple's on-device text highlighting. The shutter keeps one photo frame
/// in memory only long enough to crop each found character.
private struct HiraganaCameraView: View {
    @Environment(\.dismiss) private var dismiss
    let collection: HiraganaCollection
    let voice: HiraganaVoice
    @State private var scanner: DataScannerViewController?
    @State private var live: [String] = []
    /// When each letter was last seen by the live scanner; a shot keeps only recent ones.
    @State private var lastSeen: [String: Date] = [:]
    @State private var reading = false
    @State private var finds: FindBatch?
    @State private var unavailable: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let scanner {
                ScannerRepresentable(scanner: scanner).ignoresSafeArea()
                    .task { await follow(scanner) }
            } else if let unavailable {
                Text(unavailable).font(HunterStyle.rounded(17)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).padding(32)
            } else {
                ProgressView().tint(.white)
            }
            VStack {
                HStack(alignment: .top) {
                    liveChips
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundStyle(HunterStyle.ink)
                            .frame(width: 44, height: 44).background(.white, in: Circle())
                    }.accessibilityLabel("とじる")
                }
                Spacer()
                shutter
            }
            .padding(16)
        }
        .task { await prepare() }
        .sheet(item: $finds) { batch in
            HiraganaResultView(finds: batch.finds, collection: collection, voice: voice)
        }
        .alert("ひらがなハンター", isPresented: Binding(get: { collection.error != nil }, set: { if !$0 { collection.error = nil } })) {
            Button("とじる") { collection.error = nil }
        } message: { Text(collection.error ?? "") }
        .onDisappear { scanner?.stopScanning() }
    }

    private var liveChips: some View {
        Group {
            if !live.isEmpty {
                Text("みえてる：" + live.prefix(12).joined(separator: " "))
                    .font(HunterStyle.rounded(16)).foregroundStyle(HunterStyle.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.white.opacity(0.92), in: Capsule())
                    .accessibilityLabel("みえている ひらがな \(live.joined(separator: "、"))")
            }
        }
    }

    private var shutter: some View {
        Button { Task { await capture() } } label: {
            ZStack {
                Circle().fill(.white).frame(width: 84, height: 84)
                Circle().strokeBorder(HunterStyle.pink, lineWidth: 6).frame(width: 74, height: 74)
                if reading { ProgressView().tint(HunterStyle.pink) }
                else { Image(systemName: "sparkle.magnifyingglass").font(.system(size: 28, weight: .bold)).foregroundStyle(HunterStyle.pink) }
            }
        }
        .disabled(scanner == nil || reading)
        .accessibilityLabel("つかまえる")
    }

    private func prepare() async {
        guard DataScannerViewController.isSupported else {
            unavailable = "この きしゅでは カメラハントが つかえません。\nしゃしんから さがしてね。"
            return
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard DataScannerViewController.isAvailable else {
            unavailable = "カメラが つかえません。\n「設定」で カメラを オンにしてね。"
            return
        }
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["ja-JP"])], qualityLevel: .accurate,
            recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: false, isHighlightingEnabled: true)
        scanner = controller
    }

    private func follow(_ scanner: DataScannerViewController) async {
        // Start once the controller is on screen; VisionKit ignores an off-screen start.
        try? await Task.sleep(for: .milliseconds(300))
        try? scanner.startScanning()
        for await items in scanner.recognizedItems {
            let text = items.compactMap { item -> String? in
                if case .text(let value) = item { return value.transcript }
                return nil
            }.joined()
            live = Hiragana.unique(in: text)
            let now = Date()
            for character in live { lastSeen[character] = now }
        }
    }

    private func capture() async {
        guard let scanner, !reading else { return }
        reading = true
        defer { reading = false }
        guard let image = try? await scanner.capturePhoto() else {
            collection.error = "しゃしんを とれませんでした。"
            return
        }
        let recent = Set(lastSeen.filter { $0.value > Date().addingTimeInterval(-3) }.keys)
        finds = FindBatch(finds: await HiraganaReader.finds(in: image, seenLive: recent))
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let scanner: DataScannerViewController
    func makeUIViewController(context: Context) -> DataScannerViewController { scanner }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
}

/// Shows what one photo caught. Every find starts selected; tap to leave out misreads.
private struct HiraganaResultView: View {
    @Environment(\.dismiss) private var dismiss
    let finds: [HiraganaFind]
    let collection: HiraganaCollection
    let voice: HiraganaVoice
    @State private var excluded = Set<UUID>()

    private var kept: [HiraganaFind] { finds.filter { !excluded.contains($0.id) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if finds.isEmpty {
                    VStack(spacing: 12) {
                        Text("🔍").font(.system(size: 60))
                        Text("ひらがなが みつからなかったよ").font(HunterStyle.rounded(20))
                        Text("もじに ちかづいて、あかるい ところで とってみてね。")
                            .font(HunterStyle.rounded(15, .medium)).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(HunterStyle.ink).padding(.top, 60).padding(.horizontal, 24)
                } else {
                    Text("ちがう もじは タップして はずしてね").font(HunterStyle.rounded(14, .medium))
                        .foregroundStyle(HunterStyle.ink.opacity(0.7)).padding(.top, 8)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(finds) { find in
                            Button { toggle(find) } label: { card(find) }.buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .background(HunterStyle.cream.ignoresSafeArea())
            .navigationTitle(finds.isEmpty ? "ざんねん" : "つかまえた！")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(finds.isEmpty ? "もどる" : "やめる") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if !finds.isEmpty {
                    Button { keep() } label: {
                        Text("ずかんに いれる（\(kept.count)）").font(HunterStyle.rounded(20))
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .foregroundStyle(.white).background(HunterStyle.pink, in: Capsule())
                    }
                    .disabled(kept.isEmpty).opacity(kept.isEmpty ? 0.5 : 1)
                    .padding(16)
                }
            }
            .onAppear { voice.caught(finds.map(\.character)) }
        }
    }

    private func card(_ find: HiraganaFind) -> some View {
        let on = !excluded.contains(find.id)
        return VStack(spacing: 6) {
            if let image = UIImage(data: find.image) {
                Image(uiImage: image).resizable().scaledToFill()
                    .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            Text(find.character).font(HunterStyle.rounded(26, .heavy)).foregroundStyle(HunterStyle.ink)
        }
        .padding(8)
        .background(on ? HunterStyle.color(for: find.character) : Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))
        .opacity(on ? 1 : 0.45)
        .overlay(alignment: .topLeading) {
            if on && !collection.has(find.character) {
                Text("NEW").font(HunterStyle.rounded(11, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(HunterStyle.pink, in: Capsule()).offset(x: -4, y: -6)
            }
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22)).foregroundStyle(on ? HunterStyle.pink : .gray)
                .background(.white, in: Circle()).offset(x: 6, y: -6)
        }
        .accessibilityElement()
        .accessibilityLabel("\(find.character)、\(on ? "いれる" : "はずす")")
    }

    private func toggle(_ find: HiraganaFind) {
        if excluded.remove(find.id) == nil { excluded.insert(find.id) } else { voice.letter(find.character) }
    }

    private func keep() {
        do {
            try collection.add(kept)
            dismiss()
        } catch { collection.error = "ずかんに ほぞんできませんでした。" }
    }
}

private struct HiraganaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let character: String
    let collection: HiraganaCollection
    let voice: HiraganaVoice
    @State private var pendingDelete: HiraganaCatch?

    var body: some View {
        let items = collection.catches(of: character)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Button { voice.letter(character) } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Text(character).font(HunterStyle.rounded(110, .heavy)).foregroundStyle(.white)
                                .frame(width: 180, height: 180)
                                .background(items.isEmpty ? Color.gray.opacity(0.3) : HunterStyle.color(for: character), in: Circle())
                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 20, weight: .bold))
                                .foregroundStyle(HunterStyle.pink).frame(width: 46, height: 46).background(.white, in: Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(character)を きく")
                    Text(items.isEmpty ? "まだ つかまえていないよ" : "\(items.count)こ つかまえた！")
                        .font(HunterStyle.rounded(20)).foregroundStyle(HunterStyle.ink)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(items) { item in
                            VStack(spacing: 4) {
                                if let image = UIImage(contentsOfFile: collection.imageURL(item).path()) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                Text(item.date.formatted(date: .numeric, time: .omitted))
                                    .font(HunterStyle.rounded(11, .medium)).foregroundStyle(HunterStyle.ink.opacity(0.6))
                            }
                            .contextMenu {
                                Button("ずかんから けす", systemImage: "trash", role: .destructive) { pendingDelete = item }
                            }
                        }
                    }
                    if !items.isEmpty {
                        Text("しゃしんを ながおしで けせます").font(HunterStyle.rounded(12, .medium))
                            .foregroundStyle(HunterStyle.ink.opacity(0.5))
                    }
                }
                .padding(16)
            }
            .background(HunterStyle.cream.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("とじる") { dismiss() } } }
            .confirmationDialog("この しゃしんを けしますか？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("けす", role: .destructive) {
                    if let item = pendingDelete {
                        do { try collection.remove(item) } catch { collection.error = "けせませんでした。" }
                    }
                    pendingDelete = nil
                }
            }
        }
    }
}
