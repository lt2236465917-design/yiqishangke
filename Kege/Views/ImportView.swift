import SwiftUI
import PhotosUI
import UIKit

struct ImportView: View {
    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var sync: SyncCoordinator

    @State private var pickerItem: PhotosPickerItem?
    @State private var isWorking = false
    @State private var outcome: ImportOutcome?
    @State private var errorText: String?
    @State private var engineNote = "有开发者识图 Key 时优先走多模态；否则本机 Vision OCR。"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    KegeCard {
                        Text("截图导入")
                            .font(KegeTheme.titleFont)
                        Text("主路径（学校网页同步）若课表页未核实或校外打不开，用课表截图在本机识别。截图不会带上学校账号。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("选择课表截图", systemImage: "photo.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KegeTheme.accent)
                    .disabled(isWorking)

                    Toggle("导入后替换本机课表", isOn: $settings.replaceOnImport)
                        .padding(.horizontal, 4)

                    if isWorking {
                        ProgressView("正在识别…")
                    }

                    if let outcome {
                        KegeCard {
                            Text("识别引擎：\(outcome.engine)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(KegeTheme.sage)
                            Text("解析到 \(outcome.result.classes.count) 门课")
                                .font(.headline)
                                .padding(.top, 4)
                            if let blocker = outcome.result.blocker {
                                Text(blocker)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if !outcome.result.classes.isEmpty {
                                Button("写入本机课表") {
                                    Task { await apply(outcome.result) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(KegeTheme.sage)
                                .padding(.top, 8)

                                ForEach(Array(outcome.result.classes.enumerated()), id: \.offset) { _, draft in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(draft.title).font(.subheadline.weight(.semibold))
                                        Text("\(draft.weekday.shortLabel) \(ClassSession.clockLabel(draft.startMinutes))–\(ClassSession.clockLabel(draft.endMinutes)) \(draft.location)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.top, 6)
                                }
                            }
                            if let excerpt = outcome.result.rawExcerpt, !excerpt.isEmpty {
                                Text(excerpt)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                            }
                        }
                    }

                    Text(engineNote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
            }
            .background(KegeTheme.paper.ignoresSafeArea())
            .navigationTitle("导入")
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await recognize(item) }
            }
            .alert("导入失败", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private func recognize(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorText = ScreenshotImporterError.invalidImage.localizedDescription
                return
            }
            let importer = ScreenshotImporter()
            outcome = try await importer.importImage(image)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func apply(_ result: ParseResult) async {
        let sessions = result.classes.map { $0.asSession(source: .screenshot) }
        if settings.replaceOnImport {
            schedule.replaceAll(sessions, source: .screenshot, note: result.sourceDescription)
        } else {
            schedule.merge(sessions, source: .screenshot, note: result.sourceDescription)
        }
        settings.lastSyncAt = Date()
        settings.lastSyncNote = "截图导入 \(sessions.count) 门"
        await sync.rebuildReminders()
        sync.lastMessage = "截图课表已写入。"
    }
}
