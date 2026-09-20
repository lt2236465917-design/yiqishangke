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
                            writeEnabled: drafts.contains(where: { !$0.timePending }) && !isWorking && !didWrite,
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
                Text("上午 09:00–12:00　下午 13:30–16:30　晚上 19:00–21:30")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(didWrite ? "已写入本机。如需改表请重新识别核对。" : "尚未写入。时间待定的课只展示，不写入今日课表。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(courseGroups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Divider().overlay(KegeTheme.line)
                    }
                    CourseChecklistRow(group: group)
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
                Text(replaceOnImport ? "写入时清空本机旧课表再放入这些已排课时段。" : "默认关闭：写入时合并进本机课表，不整表替换。")
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

    private var scheduledDrafts: [EditableClassDraft] { drafts.filter { !$0.timePending } }
    private var pendingDrafts: [EditableClassDraft] { drafts.filter(\.timePending) }

    private var summaryLine: String {
        let courseCount = Set(drafts.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }).count
        let scheduledCourses = Set(scheduledDrafts.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }).count
        let pendingCourses = Set(pendingDrafts.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }).count
        var parts = ["\(courseCount) 门课", "\(scheduledCourses) 门已排课"]
        if pendingCourses > 0 {
            parts.append("\(pendingCourses) 门时间待定")
        }
        if scheduledDrafts.count > 0 {
            parts.append("\(scheduledDrafts.count) 节有效时段")
        }
        return parts.joined(separator: " · ")
    }

    private var courseGroups: [CourseChecklistGroup] {
        var order: [String] = []
        var map: [String: [EditableClassDraft]] = [:]
        for draft in drafts {
            let key = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(draft)
        }
        return order.map { title in
            let items = map[title] ?? []
            let scheduled = items.filter { !$0.timePending }
            let chosen = scheduled.isEmpty ? items : scheduled
            return CourseChecklistGroup(title: title, drafts: chosen)
        }
        .sorted { lhs, rhs in
            if lhs.isPending != rhs.isPending { return !lhs.isPending }
            guard let a = lhs.drafts.first, let b = rhs.drafts.first else { return lhs.title < rhs.title }
            return EditableClassDraft.checklistOrder(a, b)
        }
    }
}

private struct CourseChecklistGroup: Identifiable {
    var title: String
    var drafts: [EditableClassDraft]
    var id: String { title }
    var isPending: Bool { drafts.allSatisfy(\.timePending) }
}

private struct CourseChecklistRow: View {
    let group: CourseChecklistGroup
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KegeTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(group.isPending ? KegeTheme.ochre : .secondary)
                }
                Spacer(minLength: 0)
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "收起" : "展开")
            }
            if expanded {
                if group.isPending {
                    if let teacher = group.drafts.first?.teacher, !teacher.isEmpty {
                        Text("教师 \(teacher)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(group.drafts) { draft in
                        Text(draft.slotLine)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.title) \(subtitle)")
    }

    private var subtitle: String {
        if group.isPending { return "时间、地点待定" }
        if let credit = group.drafts.compactMap(\.creditText).first {
            return credit
        }
        if group.drafts.count == 1, let draft = group.drafts.first {
            return draft.slotLine
        }
        return "\(group.drafts.count) 个时段"
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
    var notes: String
    var timePending: Bool

    init(_ draft: ParsedClassDraft) {
        title = draft.title
        teacher = draft.teacher
        location = draft.location
        weekday = draft.weekday
        startMinutes = draft.startMinutes
        endMinutes = draft.endMinutes
        notes = draft.notes
        timePending = draft.timePending
        if let weeks = draft.weeks, !weeks.isEmpty {
            weeksText = Self.compactWeeks(weeks)
        } else {
            weeksText = ""
        }
    }

    var startText: String { ClassSession.clockLabel(startMinutes) }
    var endText: String { ClassSession.clockLabel(endMinutes) }

    var creditText: String? {
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*学分"#),
           let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
           let range = Range(match.range(at: 1), in: notes) {
            return "\(notes[range]) 学分"
        }
        let parts = notes.split(whereSeparator: { $0 == "·" || $0 == "|" }).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if let token = parts.first(where: { $0.contains(".") && Double($0) != nil }) {
            return "\(token) 学分"
        }
        return nil
    }

    var slotLine: String {
        if timePending { return "时间、地点待定" }
        var parts = ["\(weekday.shortLabel) \(startText)-\(endText)"]
        let room = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !room.isEmpty { parts.append(room) }
        if !weeksText.isEmpty { parts.append("\(weeksText)周") }
        return parts.joined(separator: " · ")
    }

    var checklistLine: String {
        if timePending {
            return "时间、地点待定 · \(title.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        var parts = [slotLine]
        parts.append(title.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts.joined(separator: " · ")
    }

    var hasExpandableDetails: Bool {
        !teacher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !weeksText.isEmpty
    }

    static func checklistOrder(_ lhs: EditableClassDraft, _ rhs: EditableClassDraft) -> Bool {
        if lhs.timePending != rhs.timePending { return !lhs.timePending }
        if lhs.weekday.rawValue != rhs.weekday.rawValue {
            return lhs.weekday.rawValue < rhs.weekday.rawValue
        }
        if lhs.startMinutes != rhs.startMinutes {
            return lhs.startMinutes < rhs.startMinutes
        }
        return lhs.title < rhs.title
    }

    func asSession(source: ClassSource) -> ClassSession? {
        if timePending { return nil }
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
