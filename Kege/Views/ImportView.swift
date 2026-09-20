import SwiftUI
import PhotosUI
import UIKit

struct ImportView: View {
    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var sync: SyncCoordinator

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isWorking = false
    @State private var progressText = ""
    @State private var outcome: ImportOutcome?
    @State private var drafts: [EditableClassDraft] = []
    @State private var errorText: String?
    @State private var engineNote = "有 DeepSeek Key 时一次把多张切片交给模型出 JSON；没 Key 才用本机表格 OCR。写入前可改、可删。"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    KegeCard {
                        Text("截图导入")
                            .font(KegeTheme.titleFont)
                        Text("一周课表请一次选中上午/下午/晚上多张。门户能打开「我的课表」时仍优先网页解析；截图是备用路径。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }

                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 16,
                        selectionBehavior: .ordered,
                        matching: .images
                    ) {
                        Label("选择课表截图（可多选）", systemImage: "photo.badge.plus")
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
                        ProgressView(progressText.isEmpty ? "正在识别…" : progressText)
                    }

                    if let outcome {
                        KegeCard {
                            Text("识别引擎：\(outcome.engine)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(KegeTheme.sage)
                            Text("请确认 \(drafts.count) 节课后再写入")
                                .font(.headline)
                                .padding(.top, 4)
                            if !drafts.isEmpty {
                                Button("写入本机课表") {
                                    Task { await apply() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(KegeTheme.sage)
                                .padding(.top, 8)
                            }
                        }

                        ForEach($drafts) { $draft in
                            KegeCard {
                                TextField("课程名称", text: $draft.title)
                                    .font(.subheadline.weight(.semibold))
                                Picker("星期", selection: $draft.weekday) {
                                    ForEach(ChinaWeekday.allCases) { day in
                                        Text(day.shortLabel).tag(day)
                                    }
                                }
                                HStack {
                                    TextField("开始 HH:MM", text: $draft.startText)
                                        .keyboardType(.numbersAndPunctuation)
                                    TextField("结束 HH:MM", text: $draft.endText)
                                        .keyboardType(.numbersAndPunctuation)
                                }
                                TextField("教师", text: $draft.teacher)
                                TextField("教室", text: $draft.location)
                                TextField("周次（如 6-13 或 3,4）", text: $draft.weeksText)
                                Button("删除这节", role: .destructive) {
                                    drafts.removeAll { $0.id == draft.id }
                                }
                                .font(.caption)
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
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await recognize(items) }
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

    private func recognize(_ items: [PhotosPickerItem]) async {
        isWorking = true
        progressText = "正在读取 \(items.count) 张截图…"
        defer {
            isWorking = false
            progressText = ""
        }
        do {
            var images: [UIImage] = []
            for (index, item) in items.enumerated() {
                progressText = "正在读取第 \(index + 1)/\(items.count) 张…"
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    continue
                }
                images.append(image)
            }
            guard !images.isEmpty else {
                errorText = ScreenshotImporterError.invalidImage.localizedDescription
                return
            }
            progressText = "正在识别 \(images.count) 张周课表…"
            let importer = ScreenshotImporter()
            let next = try await importer.importImages(images)
            outcome = next
            drafts = next.result.classes.map(EditableClassDraft.init)
            pickerItems = []
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func apply() async {
        let sessions = drafts.compactMap { $0.asSession() }
        guard !sessions.isEmpty else {
            errorText = "没有可写入的课程，请先改完必填项。"
            return
        }
        if settings.replaceOnImport {
            schedule.replaceAll(sessions, source: .screenshot, note: outcome?.result.sourceDescription)
        } else {
            schedule.merge(sessions, source: .screenshot, note: outcome?.result.sourceDescription)
        }
        settings.lastSyncAt = Date()
        settings.lastSyncNote = "截图导入 \(sessions.count) 节"
        await sync.rebuildReminders()
        sync.lastMessage = "截图课表已写入今日/本周。"
    }
}

private struct EditableClassDraft: Identifiable {
    var id = UUID()
    var title: String
    var teacher: String
    var location: String
    var weekday: ChinaWeekday
    var startText: String
    var endText: String
    var weeksText: String

    init(_ draft: ParsedClassDraft) {
        title = draft.title
        teacher = draft.teacher
        location = draft.location
        weekday = draft.weekday
        startText = ClassSession.clockLabel(draft.startMinutes)
        endText = ClassSession.clockLabel(draft.endMinutes)
        if let weeks = draft.weeks, !weeks.isEmpty {
            weeksText = Self.compactWeeks(weeks)
        } else {
            weeksText = ""
        }
    }

    func asSession() -> ClassSession? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        guard let start = TimetableHeuristics.parseClock(startText),
              let end = TimetableHeuristics.parseClock(endText),
              end > start else { return nil }
        let weeks = weeksText.isEmpty
            ? nil
            : (TimetableHeuristics.parseWeeks(weeksText.contains("周") ? weeksText : "\(weeksText)周")
                ?? ZgysyjyMeeting.parseWeeksPrefix(weeksText))
        return ClassSession(
            title: trimmed,
            teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            weekday: weekday,
            startMinutes: start,
            endMinutes: end,
            weeks: weeks,
            source: .screenshot
        )
    }

    private static func compactWeeks(_ weeks: [Int]) -> String {
        guard let first = weeks.first, let last = weeks.last else { return "" }
        if weeks == Array(first...last) { return "\(first)-\(last)" }
        return weeks.map(String.init).joined(separator: ",")
    }
}
