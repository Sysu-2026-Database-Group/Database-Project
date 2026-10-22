"""只读核对 Week 6 原始证据、当前源码与 ER 内嵌图源；仅标准库。"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import struct
from urllib.parse import unquote
import xml.etree.ElementTree as ET


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def model(element: ET.Element) -> tuple:
    return (element.tag, sorted(element.attrib.items()),
            (element.text or "").strip(), tuple(model(c) for c in element))


def verify(root: Path) -> dict:
    evidence = root / "db/results/week-6/acceptance"
    runs = []
    for directory in (evidence, evidence / "final-check"):
        steps = json.loads((directory / "steps.json").read_text(encoding="utf-8-sig"))
        assert len(steps) == 45, directory
        for step in steps:
            raw = (directory / step["output"]).read_text(encoding="utf-8-sig")
            if step["expected_error"]:
                assert step["exit_code"] != 0 and re.search(
                    rf"消息 {step['expected_error']}，", raw), step["step"]
            else:
                assert step["exit_code"] == 0, step["step"]
        for before, after in (("01-source-before", "04-restored-snapshot"),
                              ("04-restored-snapshot", "10-migrated-snapshot"),
                              ("01-source-before", "38-source-after"),
                              ("01-source-before", "44-source-final"),
                              ("15-expanded-before-tests", "30-expanded-after-tests"),
                              ("32-failure-snapshot-before", "36-failure-snapshot-after")):
            def snapshot(name: str) -> list[str]:
                return re.findall(r"^[a-z_]+\|\d+\|[A-F0-9]{64}$",
                                  (directory / (name + ".txt")).read_text(encoding="utf-8-sig"), re.M)
            left, right = snapshot(before), snapshot(after)
            assert len(left) == len(right) == 19 and left == right, (before, after)
        assert (directory / "06-query-before.txt").read_bytes() == (directory / "11-query-after.txt").read_bytes()
        negative = (directory / "16-regression-negative.txt").read_text(encoding="utf-8-sig")
        role = (directory / "17-role.txt").read_text(encoding="utf-8-sig")
        assert len(re.findall(r"^\d+\|.*\|PASS\|", negative, re.M)) == 22
        assert len(re.findall(r"^PASS\|229\|", role, re.M)) == 3
        runs.append({"directory": str(directory.relative_to(root)), "steps": 45,
                     "equal_snapshot_pairs": 6, "tables_per_snapshot": 19,
                     "negative_cases": 22, "permission_denials": 3})
    final = evidence / "final-check"
    duplicates = (final / "08-migration.txt").read_text(encoding="utf-8-sig")
    assert len(re.findall(r"^(?:goods_book_isbn|goods_toy_code|sale_reservation_id|point_earn|point_use|point_return)\|0$", duplicates, re.M)) == 6
    unique = (final / "21-unique-index-week-6.txt").read_text(encoding="utf-8-sig")
    assert len(re.findall(r"^UX_goods_(?:book_isbn|toy_code)\|5\|PASS$", unique, re.M)) == 2
    dates = (final / "25-member-validity-week-6.txt").read_text(encoding="utf-8-sig")
    assert "6|5|5|6|6|PASS" in dates and dates.count("STATIC_DATA_ONLY") == 6
    assert "leap_first_purchase|2025-03-01|2025-03-01" in dates
    mutation = json.loads((final / "date-mutations.json").read_text(encoding="utf-8-sig"))
    assert len(mutation) == 2
    for case in mutation:
        raw = (final / case["output"]).read_text(encoding="utf-8-sig")
        assert case["exit_code"] != 0 and re.search(rf"消息 {case['expected_error']}，", raw)
    current_sources = json.loads((evidence / "source-current-manifest.json").read_text(encoding="utf-8-sig"))
    for item in current_sources:
        assert sha256(root / item["file"]) == item["sha256"].lower(), item["file"]
    manifest = json.loads((evidence / "manifest.json").read_text(encoding="utf-8-sig"))
    for item in manifest:
        assert sha256(evidence / item["file"]) == item["sha256"].lower(), item["file"]
    source = ET.parse(root / "ER/er-diagram-v1.4.drawio").getroot()
    diagram = source.find("diagram")
    assert diagram is not None and diagram.get("name") == "v1.4 原布局修订"
    png = (root / "ER/er-diagram-v1.4.drawio.png").read_bytes()
    pos, embedded = 8, None
    while pos < len(png):
        size = struct.unpack(">I", png[pos:pos + 4])[0]
        kind, data = png[pos + 4:pos + 8], png[pos + 8:pos + 8 + size]
        pos += size + 12
        if kind == b"tEXt" and data.startswith(b"mxfile\0"):
            embedded = ET.fromstring(unquote(data.split(b"\0", 1)[1].decode()))
    assert embedded is not None and model(source) == model(embedded), "PNG/source differ"
    cells = {cell.get("id"): cell for cell in source.iter("mxCell")}
    for cell in cells.values():
        if cell.get("edge") == "1":
            assert cell.get("source") in cells and cell.get("target") in cells, cell.get("id")
    schema = (root / "db/schema.sql").read_text(encoding="utf-8-sig")
    tables = list(re.finditer(r"CREATE TABLE dbo\.\[(\w+)\] \(", schema))
    field_results = []
    for i, match in enumerate(tables):
        body = schema[match.end():tables[i + 1].start() if i + 1 < len(tables) else schema.index("COMMIT", match.end())]
        columns = re.findall(r"^\s{8}\[(\w+)\]\s+\w+", body, re.M)
        if match[1] == "supplier":
            columns += ["updated_by", "updated_at"]
        value = html.unescape(re.sub(r"<[^>]+>", " ", cells[match[1]].get("value", "")))
        missing = [col for col in columns if not re.search(r"(?<!\w)" + re.escape(col) + r"(?!\w)", value)]
        assert not missing, (match[1], missing)
        field_results.append({"table": match[1], "columns": columns, "missing": missing})
    assert len(field_results) == 19 and sum(len(t["columns"]) for t in field_results) == 137
    er_record = json.loads((evidence / "er-consistency.json").read_text(encoding="utf-8-sig"))
    assert sha256(root / er_record["source_file"]) == er_record["drawio_sha256"]
    assert sha256(root / er_record["png_file"]) == er_record["png_sha256"]
    return {"status": "PASS", "runs": runs, "date_rule_examples": 11,
            "date_mutations_rejected": 2, "duplicate_groups": [0] * 6,
            "legal_null_rows": [5, 5], "evidence_hashes": len(manifest),
            "current_source_hashes": len(current_sources), "er_source_png_identical": True,
            "er_business_tables": field_results,
            "human_er_acceptance": er_record["human_visual_signoff"],
            "human_confirmation": er_record.get("human_acceptance"),
            "scope": "Technical evidence rechecked; human approval copied from user confirmation, not performed by this script. No app endpoint certification."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = verify(Path(__file__).resolve().parents[2])
    if args.output:
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Week6 artifact audit PASS: both 45-step runs, 11 date examples, 2 rejected mutants, 19 tables / 137 ER fields.")
