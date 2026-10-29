import SwiftUI

struct ControlPanel: View {
    @Bindable var controller: SpikeController

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TestSection(controller: controller)
                    PermissionSection(controller: controller)
                    TrackpadSection(controller: controller)
                    SessionSection(controller: controller)
                }
                .padding(20)
            }
            .frame(width: 470)
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSection(controller: controller)
                        HapticTestSection(controller: controller)
                    }
                    .padding(20)
                }
                Divider()
                LogSection(controller: controller)
                    .frame(height: 260)
            }
        }
        .frame(minWidth: 1080, minHeight: 820)
    }
}

private struct TestSection: View {
    @Bindable var controller: SpikeController

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("テスト", selection: $controller.currentTest) {
                    ForEach(SpikeTest.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: controller.currentTest) { controller.testChanged() }
                Text(controller.currentTest.steps(key: controller.triggerName))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("気づいたことをメモ（Enter でログに記録）", text: $controller.memo)
                    .onSubmit { controller.submitMemo() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("いまのテスト").font(.headline)
        }
    }
}

private struct PermissionSection: View {
    let controller: SpikeController

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                row("アクセシビリティ", controller.permissions.accessibility, "入力の横取り・キー送出")
                row("入力監視", controller.permissions.listen, "キーの監視")
                row("イベント送出", controller.permissions.post, "キー送出（Phase 1 で使う）")
                Text("イベントタップ: \(controller.tapStatus)")
                    .font(.callout)
                HStack {
                    Button("アクセシビリティを要求") { controller.requestAccessibility() }
                    Button("入力監視を要求") { controller.requestListenAccess() }
                    Button("システム設定を開く") { controller.openPrivacySettings() }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("権限").font(.headline)
        }
    }

    private func row(_ title: String, _ granted: Bool, _ note: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .red)
            Text(title)
            Text(note).foregroundStyle(.secondary).font(.caption)
        }
    }
}

private struct TrackpadSection: View {
    let controller: SpikeController

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let error = controller.multitouchError {
                    Text("MultitouchSupport を読み込めない: \(error)").foregroundStyle(.red)
                }
                ForEach(controller.devices) { Text($0.summary).font(.caption.monospaced()) }
                TrackpadMiniView(controller: controller)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { Text("フレーム数").foregroundStyle(.secondary); Text("\(controller.frameCount)").monospacedDigit() }
                    GridRow { Text("指").foregroundStyle(.secondary); Text("\(controller.fingerCount)本") }
                    GridRow {
                        Text("位置").foregroundStyle(.secondary)
                        Text(controller.position.map { String(format: "x %.3f  y %.3f", $0.x, $0.y) } ?? "—").monospacedDigit()
                    }
                    GridRow { Text("マス").foregroundStyle(.secondary); Text(controller.currentCell.map { "\($0 + 1)" } ?? "—") }
                    GridRow {
                        Text("観測した範囲").foregroundStyle(.secondary)
                        HStack {
                            Text(controller.range.description).monospacedDigit()
                            Button("リセット") { controller.resetRange() }.controlSize(.small)
                        }
                    }
                }
                .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("トラックパッド").font(.headline)
        }
    }
}

/// トラックパッドを上から見た図。点が指、色付きのマスが選択中
private struct TrackpadMiniView: View {
    let controller: SpikeController

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                if let cell = controller.currentCell, controller.fingerCount > 0 {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: width / 3, height: height / 3)
                        .offset(x: CGFloat(cell % 3) * width / 3, y: CGFloat(cell / 3) * height / 3)
                }
                Path { path in
                    for i in 1...2 {
                        let x = width * CGFloat(i) / 3
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                        let y = height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                if let position = controller.position {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 16, height: 16)
                        .position(x: position.x * width, y: (1 - position.y) * height)
                }
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.6))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .aspectRatio(121.9 / 74.1, contentMode: .fit)
        .frame(maxWidth: 400)
    }
}

private struct SessionSection: View {
    let controller: SpikeController

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("状態").foregroundStyle(.secondary)
                    HStack {
                        Text(controller.phase.rawValue).fontWeight(.semibold)
                        Button("HUD を3秒プレビュー") { controller.previewHUD() }.controlSize(.small)
                    }
                }
                GridRow { Text("最後の実行").foregroundStyle(.secondary); Text(controller.lastExecuted) }
                GridRow { Text("最後のスワイプ").foregroundStyle(.secondary); Text(controller.lastSwipe) }
                GridRow(alignment: .top) {
                    Text("最後のセッション").foregroundStyle(.secondary)
                    Text(controller.lastSessionSummary).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("セッション").font(.headline)
        }
    }
}

private struct SettingsSection: View {
    @Bindable var controller: SpikeController

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("トリガーキー")
                    Picker("", selection: $controller.trigger) {
                        ForEach(TriggerKey.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("実行タイミング（HUD）")
                    Picker("", selection: $controller.fireMode) {
                        ForEach(FireMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("HUD の待ち時間")
                    HStack {
                        Slider(value: $controller.hudDelay, in: 0.2...0.6, step: 0.05)
                        Text(String(format: "%.2f 秒", controller.hudDelay)).monospacedDigit().frame(width: 60)
                    }
                }
                GridRow {
                    Text("HUD の位置")
                    Picker("", selection: $controller.hudPosition) {
                        ForEach(HUDPosition.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("入力の抑止")
                    Picker("", selection: $controller.suppression) {
                        ForEach(Suppression.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("タップの位置")
                    Picker("", selection: $controller.tapLocation) {
                        ForEach(EventTap.Location.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: controller.tapLocation) { controller.installTap() }
                }
                GridRow {
                    Text("トリガーキー")
                    Toggle("前面アプリに渡さない", isOn: $controller.swallowTrigger)
                }
                GridRow {
                    Text("境界の余裕")
                    HStack {
                        Slider(value: $controller.hysteresis, in: 0...0.08, step: 0.01)
                        Text(String(format: "%.2f", controller.hysteresis)).monospacedDigit().frame(width: 60)
                    }
                }
                GridRow {
                    Text("触覚")
                    Picker("", selection: $controller.hapticMode) {
                        ForEach(HapticMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("MTActuator")
                    HStack {
                        Stepper("ID \(controller.actuationID)", value: $controller.actuationID, in: 1...20)
                        Text("引数")
                        TextField("", value: $controller.actuationUnknown2, format: .number).frame(width: 50)
                        TextField("", value: $controller.actuationUnknown3, format: .number).frame(width: 50)
                    }
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("設定").font(.headline)
        }
    }
}

private struct HapticTestSection: View {
    let controller: SpikeController

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("ボタンを押したら、2秒以内にトラックパッドへ指を置いたまま待ってください。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("選んだ方式で1回") { controller.playHapticTest() }
                    Button("全方式を順番に") { controller.runHapticSequence() }
                }
                Text(controller.hapticTestLabel.isEmpty ? " " : controller.hapticTestLabel)
                    .font(.title3.monospaced())
                Text("アクチュエータ: \(controller.actuatorStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("触覚テスト").font(.headline)
        }
    }
}

private struct LogSection: View {
    let controller: SpikeController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ログ（新しい順）").font(.headline)
                Spacer()
                Text(controller.logPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Button("Finder で表示") { controller.revealLog() }.controlSize(.small)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(controller.logLines.enumerated().reversed()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }
}
