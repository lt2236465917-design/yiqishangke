#!/usr/bin/env python3
"""Write desensitized golden HTML / JSON fixtures. Synthetic course names only."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "Fixtures"

# Shape mirrors zgysyjy 「我的课表」 list + week grid. Names are synthetic.
COURSES = [
    {
        "code": "SYN06104",
        "title": "暗房工艺基础实训",
        "klass": "1",
        "credit": "1.0",
        "meetings": [
            "5周日-上午课-虚拟教室1(主校区)",
            "5周六-上午课-虚拟教室1(主校区)",
            "5周日-下午课-虚拟教室1(主校区)",
            "5周六-下午课-虚拟教室1(主校区)",
        ],
        "nature": "正常考试",
        "selected": "选中",
    },
    {
        "code": "SYN01003",
        "title": "东亚艺术通史",
        "klass": "1",
        "credit": "2.0",
        "meetings": [
            "6-11周一-下午课-6406(主校区)",
            "3,4周一-下午课-6406(主校区)",
        ],
        "nature": "正常考试",
        "selected": "选中",
    },
    {
        "code": "SYN01005",
        "title": "艺术美学概论",
        "klass": "1",
        "credit": "2.0",
        "meetings": [
            "6-11周二-下午课-6406(主校区)",
            "3,4周二-下午课-6406(主校区)",
        ],
        "nature": "正常考试",
        "selected": "选中",
    },
    {
        "code": "SYN01020",
        "title": "思政大讲堂：形势与政策",
        "klass": "1",
        "credit": "1.0",
        "meetings": [
            "2label.teachtask.courseclass.week.null-自排教室，请与任课教师联系上课时间和地点",
        ],
        "nature": "正常考试",
        "selected": "选中",
        "pending": True,
    },
    {
        "code": "SYN21S102",
        "title": "视觉文化专题",
        "klass": "1",
        "credit": "1.0",
        "meetings": ["5-8周五-下午课-6408(主校区)"],
        "nature": "正常考试",
        "selected": "选中",
    },
    {
        "code": "SYN18B103",
        "title": "人类学理论专题",
        "klass": "1",
        "credit": "1.0",
        "meetings": [
            "6,7周三-下午课-6408(主校区)",
            "3,4周三-下午课-6408(主校区)",
        ],
        "nature": "正常考试",
        "selected": "选中",
    },
    {
        "code": "SYN21S104",
        "title": "遗产政策法规专题",
        "klass": "1",
        "credit": "2.0",
        "meetings": ["6-13周三-上午课-6607(主校区)"],
        "nature": "正常考试",
        "selected": "选中",
    },
    {
        "code": "SYN01011",
        "title": "导师课",
        "klass": "1",
        "credit": "2.0",
        "meetings": [],
        "nature": "正常考试",
        "selected": "选中",
        "pending": True,
    },
    {
        "code": "SYN001014",
        "title": "硕士英语（学术型）",
        "klass": "1",
        "credit": "2.0",
        "meetings": [
            "12周二-上午课-6310(主校区)",
            "6-10周二-上午课-6310(主校区)",
            "3,4周二-上午课-第五会议室(主校区)",
        ],
        "nature": "正常考试",
        "selected": "选中",
    },
    {
        "code": "SYN18S300",
        "title": "跨学科理论前沿",
        "klass": "1",
        "credit": "1.0",
        "meetings": ["14-17周五-下午课-虚拟教室3(主校区)"],
        "nature": "正常考试",
        "selected": "选中",
    },
    {
        "code": "SYN18S105",
        "title": "遗产概论",
        "klass": "1",
        "credit": "2.0",
        "meetings": ["6-13周一-上午课-6607(主校区)"],
        "nature": "正常考试",
        "selected": "选中",
    },
    {
        "code": "SYN18S106",
        "title": "遗产保护实践专题",
        "klass": "1",
        "credit": "1.0",
        "meetings": ["9-12周三-下午课-6408(主校区)"],
        "nature": "正常考试",
        "selected": "选中",
    },
    {
        "code": "SYN01001",
        "title": "中国特色社会主义理论与实践研究",
        "klass": "1",
        "credit": "2.0",
        "meetings": ["3-11周四-上午课-三楼学术报告厅(主校区)"],
        "nature": "正常考试",
        "selected": "选中",
    },
    {
        "code": "SYN101009",
        "title": "说唱艺术导论",
        "klass": "1",
        "credit": "1.0",
        "meetings": [
            "6周一-晚上课-自排教室-6401教室",
            "4周三-晚上课-自排教室-6401教室",
            "4周二-晚上课-自排教室-6401教室",
            "4周一-晚上课-自排教室-6401教室",
        ],
        "nature": "正常考试",
        "selected": "选中",
    },
]


def td(text: str, rowspan: int = 1, colspan: int = 1) -> str:
    attrs = ""
    if rowspan > 1:
        attrs += f' rowspan="{rowspan}"'
    if colspan > 1:
        attrs += f' colspan="{colspan}"'
    inner = text.replace("\n", "<br>")
    return f"<td{attrs}>{inner}</td>"


def list_table() -> str:
    header = [
        "课程编码",
        "课程名称",
        "班次",
        "学分",
        "上课周次、时间、地点",
        "选课性质",
        "是否选中",
    ]
    rows = ["<tr>" + "".join(f"<th>{h}</th>" for h in header) + "</tr>"]
    for course in COURSES:
        meeting = "<br>".join(course["meetings"])
        cells = [
            course["code"],
            course["title"],
            course["klass"],
            course["credit"],
            meeting,
            course["nature"],
            course["selected"],
        ]
        rows.append("<tr>" + "".join(td(c) for c in cells) + "</tr>")
    return "<table class=\"kb-list\">\n" + "\n".join(rows) + "\n</table>"


def grid_cell(lines: list[str]) -> str:
    return "\n".join(lines)


def week_grid() -> str:
    days = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    header = "<tr>" + td("节次") + td("时间") + "".join(td(d) for d in days) + "</tr>"

    # Band cells: title + room, no week numbers so list rows with distinct weeks stay distinct.
    morning = [
        grid_cell(["遗产概论", "6607(主校区)"]),
        grid_cell(["硕士英语（学术型）", "6310(主校区)"]),
        grid_cell(["遗产政策法规专题", "6607(主校区)"]),
        grid_cell(["中国特色社会主义理论与实践研究", "三楼学术报告厅(主校区)"]),
        "",
        grid_cell(["暗房工艺基础实训", "虚拟教室1(主校区)"]),
        grid_cell(["暗房工艺基础实训", "虚拟教室1(主校区)"]),
    ]
    afternoon = [
        grid_cell(["东亚艺术通史", "6406(主校区)"]),
        grid_cell(["艺术美学概论", "6406(主校区)"]),
        grid_cell(["人类学理论专题", "6408(主校区)", "", "遗产保护实践专题", "6408(主校区)"]),
        "",
        grid_cell(["视觉文化专题", "6408(主校区)", "", "跨学科理论前沿", "虚拟教室3(主校区)"]),
        grid_cell(["暗房工艺基础实训", "虚拟教室1(主校区)"]),
        grid_cell(["暗房工艺基础实训", "虚拟教室1(主校区)"]),
    ]
    evening = [
        grid_cell(["说唱艺术导论", "自排教室-6401教室"]),
        grid_cell(["说唱艺术导论", "自排教室-6401教室"]),
        grid_cell(["说唱艺术导论", "自排教室-6401教室"]),
        "",
        "",
        "",
        "",
    ]

    def band_row(label: str, clock: str, cells: list[str]) -> str:
        return "<tr>" + td(label) + td(clock) + "".join(td(c) for c in cells) + "</tr>"

    numbered = [
        ("第一节", "09:00--09:45"),
        ("第二节", "09:45--10:30"),
        ("第三节", "10:30--11:15"),
        ("第四节", "11:15--12:00"),
        ("第五节", "13:30--14:15"),
        ("第六节", "14:15--15:00"),
        ("第七节", "15:00--15:45"),
        ("第八节", "15:45--16:30"),
        ("第九节", "19:00--19:40"),
        ("第十节", "20:30--21:30"),
    ]
    empty = [""] * 7
    numbered_rows = [
        "<tr>" + td(label) + td(clock) + "".join(td(c) for c in empty) + "</tr>"
        for label, clock in numbered
    ]

    body = "\n".join(
        [
            header,
            band_row("上午课", "09:00--12:00", morning),
            band_row("下午课", "13:30--16:30", afternoon),
            band_row("晚上课", "19:00--21:30", evening),
            *numbered_rows,
        ]
    )
    return '<table class="kb-week">\n' + body + "\n</table>"


def page_html() -> str:
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>-新学期课表-</title>
</head>
<body>
<h1>新学期课表</h1>
<p>2026秋 第2周 · 合成夹具（非真实学生课表）</p>
{list_table()}
<h2>周课表</h2>
{week_grid()}
</body>
</html>
"""


def cell_obj(text: str, rowspan: int = 1, colspan: int = 1) -> dict:
    return {"t": text, "r": rowspan, "c": colspan}


def list_rows_json() -> list:
    header = [
        cell_obj(h)
        for h in [
            "课程编码",
            "课程名称",
            "班次",
            "学分",
            "上课周次、时间、地点",
            "选课性质",
            "是否选中",
        ]
    ]
    rows = [header]
    for course in COURSES:
        rows.append(
            [
                cell_obj(course["code"]),
                cell_obj(course["title"]),
                cell_obj(course["klass"]),
                cell_obj(course["credit"]),
                cell_obj("\n".join(course["meetings"])),
                cell_obj(course["nature"]),
                cell_obj(course["selected"]),
            ]
        )
    return rows


def week_rows_json() -> list:
    days = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    header = [cell_obj("节次"), cell_obj("时间")] + [cell_obj(d) for d in days]
    morning_texts = [
        "遗产概论\n6607(主校区)",
        "硕士英语（学术型）\n6310(主校区)",
        "遗产政策法规专题\n6607(主校区)",
        "中国特色社会主义理论与实践研究\n三楼学术报告厅(主校区)",
        "",
        "暗房工艺基础实训\n虚拟教室1(主校区)",
        "暗房工艺基础实训\n虚拟教室1(主校区)",
    ]
    afternoon_texts = [
        "东亚艺术通史\n6406(主校区)",
        "艺术美学概论\n6406(主校区)",
        "人类学理论专题\n6408(主校区)\n\n遗产保护实践专题\n6408(主校区)",
        "",
        "视觉文化专题\n6408(主校区)\n\n跨学科理论前沿\n虚拟教室3(主校区)",
        "暗房工艺基础实训\n虚拟教室1(主校区)",
        "暗房工艺基础实训\n虚拟教室1(主校区)",
    ]
    evening_texts = [
        "说唱艺术导论\n自排教室-6401教室",
        "说唱艺术导论\n自排教室-6401教室",
        "说唱艺术导论\n自排教室-6401教室",
        "",
        "",
        "",
        "",
    ]

    def band(label: str, clock: str, cells: list[str]) -> list:
        return [cell_obj(label), cell_obj(clock)] + [cell_obj(c) for c in cells]

    numbered = [
        ("第一节", "09:00--09:45"),
        ("第二节", "09:45--10:30"),
        ("第三节", "10:30--11:15"),
        ("第四节", "11:15--12:00"),
        ("第五节", "13:30--14:15"),
        ("第六节", "14:15--15:00"),
        ("第七节", "15:00--15:45"),
        ("第八节", "15:45--16:30"),
        ("第九节", "19:00--19:40"),
        ("第十节", "20:30--21:30"),
    ]
    rows = [
        header,
        band("上午课", "09:00--12:00", morning_texts),
        band("下午课", "13:30--16:30", afternoon_texts),
        band("晚上课", "19:00--21:30", evening_texts),
    ]
    empty = [""] * 7
    for label, clock in numbered:
        rows.append([cell_obj(label), cell_obj(clock)] + [cell_obj(c) for c in empty])
    return rows


def ocr_model_sample() -> dict:
    scheduled = []
    pending = []
    for course in COURSES:
        if course.get("pending"):
            reason = "时间、地点待定"
            if course["meetings"] and "label.teachtask" in course["meetings"][0]:
                reason = "思政占位行，联系教师自行安排"
            pending.append({"title": course["title"], "teacher": "", "reason": reason})
            continue
        for line in course["meetings"]:
            scheduled.append(
                {
                    "title": course["title"],
                    "teacher": "",
                    "sourceLine": line,
                    "credit": course["credit"],
                }
            )
    return {"scheduled": scheduled, "pending": pending}


def ocr_merge_input() -> dict:
    """Numbered-period duplicates + consecutive slots + TBD, post-process path."""
    return {
        "scheduled": [
            {
                "title": "遗产概论",
                "weekday": "周一",
                "periodLabel": "第一节",
                "startTime": "09:00",
                "endTime": "09:45",
                "weeks": "6-13",
                "room": "6607",
            },
            {
                "title": "遗产概论",
                "weekday": "周一",
                "periodLabel": "第二节",
                "startTime": "09:45",
                "endTime": "10:30",
                "weeks": "6-13",
                "room": "6607",
            },
            {
                "title": "遗产概论",
                "weekday": "周一",
                "periodLabel": "第一节",
                "startTime": "09:00",
                "endTime": "09:45",
                "weeks": "6-13",
                "room": "6607",
            },
            {
                "title": "东亚艺术通史",
                "weekday": "周一",
                "periodLabel": "下午课",
                "startTime": "13:30",
                "endTime": "16:30",
                "weeks": "6-11",
                "room": "6406",
            },
            {
                "title": "东亚艺术通史",
                "weekday": "周一",
                "periodLabel": "下午课",
                "startTime": "13:30",
                "endTime": "16:30",
                "weeks": "3,4",
                "room": "6406",
            },
        ],
        "pending": [
            {"title": "导师课", "reason": "时间、地点待定"},
            {"title": "思政大讲堂：形势与政策", "reason": "label.teachtask.courseclass.week.null"},
            {"title": "导师课", "reason": "时间、地点待定"},
        ],
    }


def expected() -> dict:
    return {
        "scheduledCount": 23,
        "pendingCount": 2,
        "pendingTitles": ["思政大讲堂：形势与政策", "导师课"],
        "requireDistinctBands": True,
        "morningMinutes": [540, 720],
        "afternoonMinutes": [810, 990],
        "eveningMinutes": [1140, 1290],
        "notes": "Synthetic names. List table is source of truth; week grid has empty 第N节 rows.",
    }


def main() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    (FIXTURES / "golden-my-schedule.html").write_text(page_html(), encoding="utf-8")
    payload = {
        "url": "https://wxt.zgysyjy.org.cn:7792/graduate/student/kb.jsp",
        "tableCount": 2,
        "frameCount": 2,
        "bestScore": 16,
        "tables": [
            {"url": "list", "score": 12, "rows": list_rows_json()},
            {"url": "week", "score": 18, "rows": week_rows_json()},
        ],
    }
    (FIXTURES / "extract-schedule-tables.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (FIXTURES / "ocr-model-sample.json").write_text(
        json.dumps(ocr_model_sample(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (FIXTURES / "ocr-merge-input.json").write_text(
        json.dumps(ocr_merge_input(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (FIXTURES / "expected.json").write_text(
        json.dumps(expected(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"wrote fixtures under {FIXTURES}")


if __name__ == "__main__":
    main()
