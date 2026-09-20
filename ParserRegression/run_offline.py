#!/usr/bin/env python3
"""Offline equivalent of ZgysyjyParser list + OCR JSON post-process. No network."""

from __future__ import annotations

import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "Fixtures"

LINE_RE = re.compile(
    r"^(\d{1,2}(?:[-–—]\d{1,2})?(?:[,，、]\d{1,2}(?:[-–—]\d{1,2})?)*)"
    r"(周[1-7一二三四五六日天])-(上午课|下午课|晚上课)-(.+)$"
)

DAY_MAP = {
    "周一": 1, "周1": 1, "周二": 2, "周2": 2, "周三": 3, "周3": 3,
    "周四": 4, "周4": 4, "周五": 5, "周5": 5, "周六": 6, "周6": 6,
    "周日": 7, "周7": 7, "周天": 7,
}

BAND = {
    "上午课": (9 * 60, 12 * 60),
    "下午课": (13 * 60 + 30, 16 * 60 + 30),
    "晚上课": (19 * 60, 21 * 60 + 30),
}


def parse_weeks(prefix: str) -> list[int] | None:
    weeks: list[int] = []
    for part in re.split(r"[,，、]", prefix):
        piece = part.strip()
        m = re.match(r"^(\d{1,2})[-–—](\d{1,2})$", piece)
        if m:
            a, b = int(m.group(1)), int(m.group(2))
            if 1 <= a <= b <= 30:
                weeks.extend(range(a, b + 1))
            continue
        if piece.isdigit() and 1 <= int(piece) <= 30:
            weeks.append(int(piece))
    return sorted(set(weeks)) or None


def is_broken_placeholder(text: str) -> bool:
    compact = text.replace(" ", "").replace("\n", "").lower()
    if not compact:
        return False
    if "label.teachtask" in compact:
        return True
    if "courseclass.week.null" in compact:
        return True
    return "teachtask" in compact and "week.null" in compact


def parse_line(raw: str) -> dict | None:
    line = raw.strip()
    if not line or is_broken_placeholder(line):
        return None
    m = LINE_RE.match(line)
    if not m:
        return None
    day = DAY_MAP.get(m.group(2))
    minutes = BAND.get(m.group(3))
    if day is None or minutes is None:
        return None
    return {
        "weekday": day,
        "start": minutes[0],
        "end": minutes[1],
        "weeks": parse_weeks(m.group(1)),
        "room": m.group(4).strip(),
        "period": m.group(3),
    }


def is_pending_meeting(text: str, title: str = "") -> bool:
    if is_broken_placeholder(text):
        return True
    compact = text.replace(" ", "").replace("\n", "")
    title_c = title.replace(" ", "")
    keys = ["待定", "联系老师", "自行安排", "自排课", "时间地点待定", "时间、地点待定"]
    if any(k in compact or k in title_c for k in keys):
        return True
    if "导师课" in title_c and (not compact or not [ln for ln in compact.splitlines() if parse_line(ln)]):
        return True
    return compact == ""


def unique_meetings(drafts: list[dict]) -> list[dict]:
    seen: set[str] = set()
    out: list[dict] = []
    for d in drafts:
        title = d["title"].strip()
        if d.get("timePending"):
            key = f"pending|{title}"
        else:
            weeks = ",".join(str(w) for w in (d.get("weeks") or []))
            room = (d.get("location") or "").strip()
            key = f"{title}|{d['weekday']}|{d['start']}|{d['end']}|{room}|{weeks}"
        if key in seen:
            continue
        seen.add(key)
        out.append(d)
    return out


def merge_consecutive(drafts: list[dict]) -> list[dict]:
    def sort_key(d: dict):
        weeks = "".join(str(w) for w in (d.get("weeks") or []))
        return (d.get("weekday") or 0, d.get("title") or "", weeks, d.get("start") or 0)

    sorted_d = sorted(drafts, key=sort_key)
    result: list[dict] = []
    for draft in sorted_d:
        if draft.get("timePending"):
            result.append(draft)
            continue
        if result:
            last = result[-1]
            if (
                not last.get("timePending")
                and last.get("title") == draft.get("title")
                and last.get("weekday") == draft.get("weekday")
                and last.get("weeks") == draft.get("weeks")
                and (not last.get("teacher") or not draft.get("teacher") or last.get("teacher") == draft.get("teacher"))
                and (not last.get("location") or not draft.get("location") or last.get("location") == draft.get("location"))
                and draft["start"] <= last["end"] + 20
            ):
                last["end"] = max(last["end"], draft["end"])
                if not last.get("teacher"):
                    last["teacher"] = draft.get("teacher") or ""
                if not last.get("location"):
                    last["location"] = draft.get("location") or ""
                continue
        result.append(dict(draft))
    return result


def merge_and_dedupe(drafts: list[dict]) -> list[dict]:
    return unique_meetings(merge_consecutive(unique_meetings(drafts)))


class TableCollector(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.tables: list[list[list[str]]] = []
        self._rows: list[list[str]] | None = None
        self._row: list[str] | None = None
        self._cell: list[str] | None = None
        self._in_cell = False

    def handle_starttag(self, tag: str, attrs) -> None:
        tag = tag.lower()
        if tag == "table":
            self._rows = []
        elif tag == "tr" and self._rows is not None:
            self._row = []
        elif tag in {"td", "th"} and self._row is not None:
            self._cell = []
            self._in_cell = True
        elif tag == "br" and self._in_cell and self._cell is not None:
            self._cell.append("\n")

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in {"td", "th"} and self._row is not None and self._cell is not None:
            self._row.append("".join(self._cell).strip())
            self._cell = None
            self._in_cell = False
        elif tag == "tr" and self._rows is not None and self._row is not None:
            if self._row:
                self._rows.append(self._row)
            self._row = None
        elif tag == "table" and self._rows is not None:
            if self._rows:
                self.tables.append(self._rows)
            self._rows = None

    def handle_data(self, data: str) -> None:
        if self._in_cell and self._cell is not None:
            self._cell.append(data)


def is_list_header(row: list[str]) -> bool:
    joined = "".join(row)
    has_code = "课程编号" in joined or "课程编码" in joined
    has_title = "课程名称" in joined
    has_meeting = "上课时间" in joined or "上课周次" in joined
    return has_code and has_title and has_meeting


def column_index(header: list[str]) -> dict[str, int]:
    mapping: dict[str, int] = {}
    for i, raw in enumerate(header):
        h = raw.replace(" ", "")
        if "课程编号" in h or "课程编码" in h:
            mapping["code"] = i
        elif "课程名称" in h:
            mapping["title"] = i
        elif "班次" in h:
            mapping["class"] = i
        elif "学分" in h:
            mapping["credit"] = i
        elif "上课时间" in h or "上课周次" in h:
            mapping["meeting"] = i
        elif "选课性质" in h:
            mapping["nature"] = i
        elif "是否选中" in h:
            mapping["selected"] = i
    return mapping


def parse_list_table(rows: list[list[str]]) -> list[dict]:
    header = next((r for r in rows if is_list_header(r)), None)
    if not header:
        return []
    index = column_index(header)
    title_i = index.get("title")
    meeting_i = index.get("meeting")
    if title_i is None or meeting_i is None:
        return []
    drafts: list[dict] = []
    for row in rows:
        if is_list_header(row) or len(row) < 3:
            continue
        title = row[title_i].strip()
        if len(title) < 2:
            continue
        meeting_text = row[meeting_i] if meeting_i < len(row) else ""
        lines = [ln.strip() for ln in meeting_text.replace("\r", "\n").split("\n") if ln.strip()]
        parsed = [p for p in (parse_line(ln) for ln in lines) if p]
        if not parsed:
            if is_pending_meeting(meeting_text, title):
                drafts.append(
                    {
                        "title": title,
                        "teacher": "",
                        "location": "",
                        "weekday": 1,
                        "start": 0,
                        "end": 0,
                        "weeks": None,
                        "timePending": True,
                    }
                )
            continue
        for meeting in parsed:
            drafts.append(
                {
                    "title": title,
                    "teacher": "",
                    "location": meeting["room"],
                    "weekday": meeting["weekday"],
                    "start": meeting["start"],
                    "end": meeting["end"],
                    "weeks": meeting["weeks"],
                    "timePending": False,
                }
            )
    return drafts


def looks_like_weekly_grid(rows: list[list[str]]) -> bool:
    blob = "\n".join("\n".join(r) for r in rows)
    return "周一" in blob and "周日" in blob and ("上午课" in blob or "下午课" in blob)


def parse_clock_range(text: str) -> tuple[int, int] | None:
    m = re.search(r"(\d{1,2})[:：](\d{2})\s*[-–—~至到]{1,2}\s*(\d{1,2})[:：](\d{2})", text)
    if not m:
        return None
    return int(m.group(1)) * 60 + int(m.group(2)), int(m.group(3)) * 60 + int(m.group(4))


def period_kind(text: str) -> str | None:
    compact = text.replace(" ", "")
    if re.search(r"第\s*[0-9一二三四五六七八九十]+\s*节", compact):
        return "numbered"
    if "上午" in compact:
        return "bandMorning"
    if "下午" in compact:
        return "bandAfternoon"
    if "晚上" in compact or "晚课" in compact:
        return "bandEvening"
    return None


def parse_weekly_grid(rows: list[list[str]]) -> list[dict]:
    day_columns: dict[int, int] = {}
    numbered: list[dict] = []
    bands: list[dict] = []
    for row in rows:
        header_days = {}
        for i, raw in enumerate(row):
            compact = raw.replace(" ", "")
            if compact in DAY_MAP and len(compact) <= 8:
                header_days[i] = DAY_MAP[compact]
        if len(header_days) >= 3:
            day_columns = header_days
            continue
        if not day_columns:
            continue
        prefix = "\n".join(row[:3])
        clock = parse_clock_range(prefix)
        kind = period_kind(prefix)
        if clock is None:
            if kind == "bandMorning":
                clock = BAND["上午课"]
            elif kind == "bandAfternoon":
                clock = BAND["下午课"]
            elif kind == "bandEvening":
                clock = BAND["晚上课"]
            else:
                continue
        for col, weekday in day_columns.items():
            if col >= len(row):
                continue
            text = row[col].strip()
            if not text or (text.replace(" ", "") in DAY_MAP and len(text) <= 8):
                continue
            if period_kind(text) or parse_clock_range(text):
                continue
            chunks = [ln.strip() for ln in text.split("\n") if ln.strip()]
            title = next((ln for ln in chunks if ln not in DAY_MAP and "教室" not in ln and "校区" not in ln), "")
            if len(title) < 2:
                continue
            room = next((ln for ln in chunks if "教室" in ln or "校区" in ln or re.match(r"^\d{3,5}", ln)), "")
            draft = {
                "title": title,
                "teacher": "",
                "location": room,
                "weekday": weekday,
                "start": clock[0],
                "end": clock[1],
                "weeks": None,
                "timePending": False,
            }
            if kind == "numbered":
                numbered.append(draft)
            else:
                bands.append(draft)
    chosen = numbered if numbered else bands
    return merge_and_dedupe(chosen)


def merge_grid_preferred(grid: list[dict], listing: list[dict]) -> list[dict]:
    result = list(grid)
    for extra in listing:
        if extra.get("timePending"):
            if not any(r["title"] == extra["title"] and not r.get("timePending") for r in result) and not any(
                r["title"] == extra["title"] and r.get("timePending") for r in result
            ):
                result.append(extra)
            continue
        matched = None
        for i, draft in enumerate(result):
            if (
                draft["title"] == extra["title"]
                and draft.get("weekday") == extra.get("weekday")
                and not draft.get("timePending")
                and draft.get("start") == extra.get("start")
                and (
                    draft.get("weeks") == extra.get("weeks")
                    or draft.get("weeks") is None
                    or extra.get("weeks") is None
                )
            ):
                matched = i
                break
        if matched is None:
            result.append(extra)
        else:
            if not result[matched].get("location"):
                result[matched]["location"] = extra.get("location") or ""
            if result[matched].get("weeks") is None:
                result[matched]["weeks"] = extra.get("weeks")
    return unique_meetings(result)


def parse_html(html: str) -> list[dict]:
    collector = TableCollector()
    collector.feed(html)
    grid: list[dict] = []
    listing: list[dict] = []
    for table in collector.tables:
        if looks_like_weekly_grid(table):
            weekly = parse_weekly_grid(table)
            if weekly:
                grid.extend(weekly)
                continue
        listing.extend(parse_list_table(table))
    return merge_grid_preferred(grid, listing)


def parse_js_tables(payload: dict) -> list[dict]:
    grid: list[dict] = []
    listing: list[dict] = []
    for table in payload.get("tables") or []:
        rows = []
        for row in table.get("rows") or []:
            rows.append([cell.get("t", "") if isinstance(cell, dict) else str(cell) for cell in row])
        if looks_like_weekly_grid(rows):
            weekly = parse_weekly_grid(rows)
            if weekly:
                grid.extend(weekly)
                continue
        listing.extend(parse_list_table(rows))
    return merge_grid_preferred(grid, listing)


def parse_ocr_json(payload: dict) -> list[dict]:
    drafts: list[dict] = []
    for node in payload.get("pending") or []:
        title = node.get("title") or ""
        if len(title) < 2:
            continue
        drafts.append(
            {
                "title": title,
                "teacher": node.get("teacher") or "",
                "location": "",
                "weekday": 1,
                "start": 0,
                "end": 0,
                "weeks": None,
                "timePending": True,
            }
        )
    for node in payload.get("scheduled") or []:
        title = node.get("title") or ""
        if len(title) < 2:
            continue
        line = node.get("sourceLine") or node.get("line") or node.get("meeting")
        parsed = parse_line(line) if line else None
        if parsed:
            drafts.append(
                {
                    "title": title,
                    "teacher": node.get("teacher") or "",
                    "location": parsed["room"],
                    "weekday": parsed["weekday"],
                    "start": parsed["start"],
                    "end": parsed["end"],
                    "weeks": parsed["weeks"],
                    "timePending": False,
                }
            )
            continue
        weekday_raw = node.get("weekday") or ""
        weekday = DAY_MAP.get(str(weekday_raw).replace(" ", ""))
        start_s = node.get("startTime") or node.get("start")
        end_s = node.get("endTime") or node.get("end")
        if weekday is None or not start_s or not end_s:
            continue
        sh, sm = [int(x) for x in str(start_s).replace("：", ":").split(":")]
        eh, em = [int(x) for x in str(end_s).replace("：", ":").split(":")]
        weeks = parse_weeks(str(node.get("weeks") or "").replace("周", ""))
        drafts.append(
            {
                "title": title,
                "teacher": node.get("teacher") or "",
                "location": node.get("room") or node.get("location") or "",
                "weekday": weekday,
                "start": sh * 60 + sm,
                "end": eh * 60 + em,
                "weeks": weeks,
                "timePending": False,
            }
        )
    return merge_and_dedupe(drafts)


def assert_golden(drafts: list[dict], label: str) -> None:
    scheduled = [d for d in drafts if not d.get("timePending")]
    pending = [d for d in drafts if d.get("timePending")]
    if len(scheduled) != 23:
        raise AssertionError(f"{label}: expected 23 scheduled, got {len(scheduled)}")
    if len(pending) != 2:
        raise AssertionError(f"{label}: expected 2 pending, got {len(pending)} {[p['title'] for p in pending]}")
    titles = {p["title"] for p in pending}
    if "导师课" not in titles:
        raise AssertionError(f"{label}: missing pending 导师课")
    if not any("思政" in t for t in titles):
        raise AssertionError(f"{label}: missing pending 思政")
    starts = {d["start"] for d in scheduled}
    ends = {d["end"] for d in scheduled}
    if starts <= {9 * 60} and ends <= {12 * 60}:
        raise AssertionError(f"{label}: all sessions collapsed to 09:00–12:00")
    if 13 * 60 + 30 not in starts:
        raise AssertionError(f"{label}: missing afternoon 13:30")
    if 19 * 60 not in starts:
        raise AssertionError(f"{label}: missing evening 19:00")
    if 9 * 60 not in starts:
        raise AssertionError(f"{label}: missing morning 09:00")
    identities = {
        (d["title"], d["weekday"], d["start"], tuple(d.get("weeks") or []), d.get("location"))
        for d in scheduled
    }
    if len(identities) != len(scheduled):
        raise AssertionError(f"{label}: duplicate scheduled identities")


def main() -> int:
    html = (FIXTURES / "golden-my-schedule.html").read_text(encoding="utf-8")
    html_drafts = parse_html(html)
    assert_golden(html_drafts, "html")

    tables = json.loads((FIXTURES / "extract-schedule-tables.json").read_text(encoding="utf-8"))
    js_drafts = parse_js_tables(tables)
    assert_golden(js_drafts, "extract-schedule-tables")

    ocr = json.loads((FIXTURES / "ocr-model-sample.json").read_text(encoding="utf-8"))
    ocr_drafts = parse_ocr_json(ocr)
    assert_golden(ocr_drafts, "ocr-model-sample")

    merge_payload = json.loads((FIXTURES / "ocr-merge-input.json").read_text(encoding="utf-8"))
    merged = parse_ocr_json(merge_payload)
    scheduled = [d for d in merged if not d.get("timePending")]
    pending = [d for d in merged if d.get("timePending")]
    if len(scheduled) != 3:
        raise AssertionError(f"ocr-merge-input: expected 3 scheduled after merge, got {len(scheduled)}")
    heritage = next(d for d in scheduled if d["title"] == "遗产概论")
    if heritage["start"] != 9 * 60 or heritage["end"] != 10 * 60 + 30:
        raise AssertionError(f"ocr-merge-input: consecutive periods not merged: {heritage}")
    art = [d for d in scheduled if d["title"] == "东亚艺术通史"]
    if len(art) != 2:
        raise AssertionError("ocr-merge-input: distinct week ranges must stay")
    if {p["title"] for p in pending} != {"导师课", "思政大讲堂：形势与政策"}:
        raise AssertionError(f"ocr-merge-input pending { [p['title'] for p in pending] }")

    if "周一" not in html or "上午课" not in html or "第一节" not in html:
        raise AssertionError("html missing week-grid structure")

    print("ParserRegression offline checks passed:")
    print("  html scheduled=23 pending=2 (distinct morning/afternoon/evening)")
    print("  extract-schedule-tables.json same")
    print("  ocr-model-sample.json same (no live API)")
    print("  ocr-merge-input.json mergeAndDedupe consecutive+TBD")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
