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
    @State private var didWrite = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    KegeCard {
                        Text("截图导入")
                            .font(KegeTheme.titleFont)
                        Text("一周课表请一次选中上午/下午/晚上多张。识别结果只用于核对，不会自动写入本机课表。")
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

                    if isWorking {
                        ProgressView(progressText.isEmpty ? "正在识别…" : progressText)
                    }

                    if outcome != nil {
                        ScheduleImportChecklist(
                            engine: outcome?.engine ?? "",
                            drafts: drafts,
                            didWrite: didWrite,
                            replaceOnImport: $settings.replaceOnImport,
                            writeEnabled: !drafts.isEmpty && !isWorking && !didWrite,
                            onWrite: {
                                Task { await apply() }
                            }
                        )
                    }

                    Text("有 DeepSeek Key 时一次把多张切片交给模型出 JSON；没 Key 才用本机表格 OCR。请对照网页课表核对清单后再点写入。")
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
            drafts = next.result.classes
                .map(EditableClassDraft.init)
                .sorted(by: EditableClassDraft.checklistOrder)
            didWrite = false
            pickerItems = []
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func apply() async {
        let sessions = drafts.compactMap { $0.asSession(source: .screenshot) }
        guard !sessions.isEmpty else {
            errorText = "没有可写入的课程，请重新选图识别。"
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
        didWrite = true
    }
}

struct ScheduleImportChecklist: View {
    let engine: String
    let drafts: [EditableClassDraft]
    let didWrite: Bool
    @Binding var replaceOnImport: Bool
    var writeEnabled: Bool
    var onWrite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            KegeCard {
                Text("识别引擎：\(engine)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KegeTheme.sage)
                Text(summaryLine)
                    .font(.headline)
                    .padding(.top, 4)
                Text(didWrite ? "已写入本机。如需改表请重新识别核对。" : "尚未写入。请按星期和时间对照网页课表。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                    if index > 0 {
                        Divider().overlay(KegeTheme.line)
                    }
                    ImportChecklistRow(draft: draft)
                }
            }
            .padding(.horizontal, 12)
            .background(KegeTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(KegeTheme.line, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 12) {
                Toggle("导入后替换本机课表", isOn: $replaceOnImport)
                Text(replaceOnImport ? "写入时清空本机旧课表再放入这些节次。" : "默认关闭：写入时合并进本机课表，不整表替换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("写入本机课表") {
                    onWrite()
                }
                .buttonStyle(.borderedProminent)
                .tint(KegeTheme.sage)
                .disabled(!writeEnabled)
            }
            .padding(.top, 4)
        }
    }

    private var summaryLine: String {
        let courseCount = Set(drafts.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }).count
        let days = Set(drafts.map(\.weekday))
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.shortLabel)
        let dayText = days.isEmpty ? "无星期" : days.joined(separator: "、")
        return "共 \(drafts.count) 节 · \(courseCount) 门课 · 覆盖 \(dayText)"
    }
}

struct ImportChecklistRow: View {
    let draft: EditableClassDraft
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(draft.checklistLine)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(KegeTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if draft.hasExpandableDetails {
                    Button {
                        expanded.toggle()
                    } label: {
                        Text(expanded ? "收起" : "详情")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KegeTheme.sage)
                }
            }
            if expanded {
                if !draft.teacher.isEmpty {
                    Text("教师 \(draft.teacher)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !draft.weeksText.isEmpty {
                    Text("周次 \(draft.weeksText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(draft.checklistLine)
    }
}

struct EditableClassDraft: Identifiable {
    var id = UUID()
    var title: String
    var teacher: String
    var location: String
    var weekday: ChinaWeekday
    var startMinutes: Int
    var endMinutes: Int
    var weeksText: String

    init(_ draft: ParsedClassDraft) {
        title = draft.title
        teacher = draft.teacher
        location = draft.location
        weekday = draft.weekday
        startMinutes = draft.startMinutes
        endMinutes = draft.endMinutes
        if let weeks = draft.weeks, !weeks.isEmpty {
            weeksText = Self.compactWeeks(weeks)
        } else {
            weeksText = ""
        }
    }

    var startText: String { ClassSession.clockLabel(startMinutes) }
    var endText: String { ClassSession.clockLabel(endMinutes) }

    var checklistLine: String {
        var parts = ["\(weekday.shortLabel) \(startText)-\(endText)"]
        let room = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !room.isEmpty {
            parts.append(room)
        }
        parts.append(title.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts.joined(separator: " · ")
    }

    var hasExpandableDetails: Bool {
        !teacher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !weeksText.isEmpty
    }

    static func checklistOrder(_ lhs: EditableClassDraft, _ rhs: EditableClassDraft) -> Bool {
        if lhs.weekday.rawValue != rhs.weekday.rawValue {
            return lhs.weekday.rawValue < rhs.weekday.rawValue
        }
        if lhs.startMinutes != rhs.startMinutes {
            return lhs.startMinutes < rhs.startMinutes
        }
        return lhs.title < rhs.title
    }

    func asSession(source: ClassSource) -> ClassSession? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        guard endMinutes > startMinutes else { return nil }
        let weeks = weeksText.isEmpty
            ? nil
            : (TimetableHeuristics.parseWeeks(weeksText.contains("周") ? weeksText : "\(weeksText)周")
                ?? ZgysyjyMeeting.parseWeeksPrefix(weeksText))
        return ClassSession(
            title: trimmed,
            teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            weekday: weekday,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            weeks: weeks,
            source: source
        )
    }

    private static func compactWeeks(_ weeks: [Int]) -> String {
        guard let first = weeks.first, let last = weeks.last else { return "" }
        if weeks == Array(first...last) { return "\(first)-\(last)" }
        return weeks.map(String.init).joined(separator: ",")
    }
}
