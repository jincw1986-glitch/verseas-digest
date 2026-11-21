#!/usr/bin/env python3
"""Validate data/index.json and data/issues/*.json.

The script uses only the Python standard library. It checks the contract in
data/schema.json: required fields, enums, section order, https URLs, newest-first
index, filenames, sentence counts, and local image files.

Usage (from the repository root or anywhere):
    python3 scripts/validate.py
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SCHEMA_PATH = DATA / "schema.json"
INDEX_PATH = DATA / "index.json"
ISSUES_DIR = DATA / "issues"

SECTION_ORDER = [
    "每日一图",
    "国际政治与时事",
    "经济与市场",
    "科技与人工智能",
    "社会资讯",
    "科学与体育",
    "影视与明星",
    "书籍与作家",
    "天涯海角",
    "美女与野兽",
    "笑话",
]
NEWS_SECTIONS = {
    "国际政治与时事",
    "经济与市场",
    "科技与人工智能",
    "社会资讯",
    "科学与体育",
    "影视与明星",
    "书籍与作家",
}
JOKE_SECTION = "笑话"
WIKI_SECTION = "维基漫游"
JOKE_URL_RE = re.compile(r"^https://x\.com/([A-Za-z0-9_]{1,15})/status/[0-9]+$")
HANDLE_RE = re.compile(r"^@[A-Za-z0-9_]{1,15}$")
CJK_RE = re.compile(r"[\u4e00-\u9fff]")
GLOSSARY_TYPES = {"person", "term", "concept", "award", "org"}
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
INDEX_PATH_RE = re.compile(r"^issues/\d{4}-\d{2}-\d{2}\.json$")

ERRORS: list[str] = []


def error(message: str) -> None:
    ERRORS.append(message)


def load_json(path: Path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        error(f"{path.relative_to(ROOT)}: 无法读取 ({exc})")
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        error(f"{path.relative_to(ROOT)}: JSON 无法解析 ({exc})")
        return None


def is_https_url(value: object) -> bool:
    if not isinstance(value, str) or not value.startswith("https://"):
        return False
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.netloc) and " " not in value


def count_sentences(text: str) -> int:
    """Count sentences, ignoring decimals and single-letter initials."""
    cleaned = re.sub(r"\d+\.\d+", lambda match: match.group(0).replace(".", ""), text)
    cleaned = re.sub(r"\b([A-Za-z])\.", r"\1", cleaned)
    parts = re.split(r"[。！？!?]+", cleaned)
    return len([part for part in parts if part.strip()])


def require_string(obj: dict, key: str, where: str) -> str | None:
    value = obj.get(key)
    if not isinstance(value, str) or not value.strip():
        error(f"{where}: 缺少非空字符串 {key}")
        return None
    return value


def check_date(value: str, where: str) -> bool:
    if not DATE_RE.match(value):
        error(f"{where}: 日期须为 YYYY-MM-DD，实际为 {value!r}")
        return False
    try:
        datetime.strptime(value, "%Y-%m-%d")
    except ValueError:
        error(f"{where}: {value} 不是有效公历日期")
        return False
    return True


def check_no_extra(obj: dict, allowed: set[str], where: str) -> None:
    extra = set(obj) - allowed
    if extra:
        error(f"{where}: 含有未定义字段 {sorted(extra)}")


def check_image(image: dict, where: str) -> None:
    check_no_extra(image, {"path", "url", "credit"}, where)
    credit = require_string(image, "credit", where)
    if credit is None:
        return
    path = image.get("path")
    url = image.get("url")
    if path is None and url is None:
        error(f"{where}: image 需要 path 或 url")
        return
    if path is not None:
        if not isinstance(path, str) or not path.strip():
            error(f"{where}: image.path 无效")
        else:
            if path.startswith("/") or "\\" in path or ".." in Path(path).parts:
                error(f"{where}: image.path 必须是 data/ 下的相对路径，不能包含 ..")
            else:
                suffix = Path(path).suffix.lower()
                if suffix not in IMAGE_SUFFIXES:
                    error(f"{where}: image.path 只接受 {sorted(IMAGE_SUFFIXES)}")
                file_path = DATA / path
                if not file_path.is_file():
                    error(f"{where}: 找不到图片文件 data/{path}")
    if url is not None and not is_https_url(url):
        error(f"{where}: image.url 必须是 https 地址")


def check_item(item: object, where: str) -> None:
    if not isinstance(item, dict):
        error(f"{where}: 条目必须是对象")
        return
    check_no_extra(item, {"headline", "summary", "sources", "image", "glossary"}, where)
    headline = require_string(item, "headline", where)
    summary = require_string(item, "summary", where)
    if summary is not None:
        count = count_sentences(summary)
        if count < 1 or count > 2:
            error(f"{where}: summary 须为 1 到 2 句，实际 {count} 句：{summary}")
    sources = item.get("sources")
    if not isinstance(sources, list) or not sources:
        error(f"{where}: sources 至少要有一条")
    else:
        for index, source in enumerate(sources, start=1):
            source_where = f"{where} 来源{index}"
            if not isinstance(source, dict):
                error(f"{source_where}: 必须是对象")
                continue
            check_no_extra(source, {"name", "url"}, source_where)
            require_string(source, "name", source_where)
            url = source.get("url")
            if not is_https_url(url):
                error(f"{source_where}: url 必须是 https 地址")
    image = item.get("image")
    if not isinstance(image, dict):
        error(f"{where}: 新闻条目必须有 image")
    else:
        check_image(image, f"{where} 图片")
    glossary = item.get("glossary")
    if not isinstance(glossary, list) or not (1 <= len(glossary) <= 3):
        error(f"{where}: glossary 须为 1 到 3 条")
        return
    seen_terms: set[str] = set()
    for index, entry in enumerate(glossary, start=1):
        entry_where = f"{where} 名词{index}"
        if not isinstance(entry, dict):
            error(f"{entry_where}: 必须是对象")
            continue
        check_no_extra(entry, {"term", "type", "explanation"}, entry_where)
        term = require_string(entry, "term", entry_where)
        if term is not None:
            if term in seen_terms:
                error(f"{entry_where}: 同一条目里名词重复：{term}")
            seen_terms.add(term)
        entry_type = entry.get("type")
        if entry_type not in GLOSSARY_TYPES:
            error(f"{entry_where}: type 必须是 {sorted(GLOSSARY_TYPES)} 之一")
        explanation = require_string(entry, "explanation", entry_where)
        if explanation is not None:
            count = count_sentences(explanation)
            if count < 2 or count > 4:
                error(f"{entry_where}: explanation 须为 2 到 4 句，实际 {count} 句：{explanation}")
    if headline is None:
        return


def check_joke(joke: object, where: str) -> None:
    if not isinstance(joke, dict):
        error(f"{where}: 笑话必须是对象")
        return
    check_no_extra(joke, {"text", "translation", "authorName", "handle", "url", "note"}, where)
    text = require_string(joke, "text", where)
    require_string(joke, "authorName", where)
    handle = require_string(joke, "handle", where)
    url = require_string(joke, "url", where)
    if handle is not None and not HANDLE_RE.match(handle):
        error(f"{where}: handle 须形如 @name")
    if url is not None:
        match = JOKE_URL_RE.match(url)
        if not match:
            error(f"{where}: url 须形如 https://x.com/<handle>/status/<id>")
        elif handle is not None and match.group(1) != handle[1:]:
            error(f"{where}: url 里的用户名与 handle 不一致")
    translation = joke.get("translation")
    if text is not None and not CJK_RE.search(text):
        if not isinstance(translation, str) or not translation.strip():
            error(f"{where}: 原文不是中文，必须提供 translation")
    elif translation is not None and (not isinstance(translation, str) or not translation.strip()):
        error(f"{where}: translation 不能是空字符串")
    note = joke.get("note")
    if note is not None and (not isinstance(note, str) or not note.strip()):
        error(f"{where}: note 不能是空字符串")


def check_photo(photo: object, where: str) -> None:
    if not isinstance(photo, dict):
        error(f"{where}: photo 必须是对象")
        return
    check_no_extra(photo, {"title", "interpretation", "image", "sources"}, where)
    require_string(photo, "title", where)
    text = require_string(photo, "interpretation", where)
    if text is not None:
        paragraphs = [part.strip() for part in text.split("\n\n") if part.strip()]
        if len(paragraphs) < 3 or count_sentences(text) < 6:
            error(f"{where}: 每日一图的解读至少三段、六句")
    image = photo.get("image")
    if not isinstance(image, dict):
        error(f"{where}: 每日一图必须有 image")
    else:
        check_image(image, f"{where} 图片")
    sources = photo.get("sources")
    if not isinstance(sources, list) or not sources:
        error(f"{where}: 每日一图至少要有一条来源")
    else:
        for index, source in enumerate(sources, start=1):
            if not isinstance(source, dict) or not is_https_url(source.get("url")):
                error(f"{where} 来源{index}: url 必须是 https 地址")
            else:
                require_string(source, "name", f"{where} 来源{index}")


def check_place(place: object, where: str) -> None:
    if not isinstance(place, dict):
        error(f"{where}: place 必须是对象")
        return
    check_no_extra(place, {"name", "paragraphs", "photos"}, where)
    require_string(place, "name", where)
    paragraphs = place.get("paragraphs")
    if not isinstance(paragraphs, list) or len(paragraphs) < 3:
        error(f"{where}: 天涯海角至少三段")
    elif any(not isinstance(part, str) or len(part.strip()) < 40 for part in paragraphs):
        error(f"{where}: 每一段都要写成完整的散文，不能是宣传短句")
    photos = place.get("photos")
    if not isinstance(photos, list) or not (1 <= len(photos) <= 3):
        error(f"{where}: 配图要 1 到 3 张")
        return
    for index, photo in enumerate(photos, start=1):
        if not isinstance(photo, dict):
            error(f"{where} 配图{index}: 必须是对象")
            continue
        check_no_extra(photo, {"path", "url", "credit", "caption"}, f"{where} 配图{index}")
        check_image(
            {key: photo[key] for key in ("path", "url", "credit") if key in photo},
            f"{where} 配图{index}",
        )


def check_gallery(gallery: object, where: str) -> None:
    if not isinstance(gallery, list) or len(gallery) < 4:
        error(f"{where}: 美女与野兽至少 4 张图")
        return
    kinds = set()
    for index, item in enumerate(gallery, start=1):
        item_where = f"{where} 图{index}"
        if not isinstance(item, dict):
            error(f"{item_where}: 必须是对象")
            continue
        check_no_extra(item, {"kind", "caption", "image", "source"}, item_where)
        kind = item.get("kind")
        if kind not in {"person", "animal"}:
            error(f"{item_where}: kind 只能是 person 或 animal")
        else:
            kinds.add(kind)
        require_string(item, "caption", item_where)
        image = item.get("image")
        if not isinstance(image, dict):
            error(f"{item_where}: 必须有 image")
        else:
            check_image(image, item_where)
        source = item.get("source")
        if source is not None:
            if not isinstance(source, dict) or not is_https_url(source.get("url")):
                error(f"{item_where}: source.url 必须是 https 地址")
    if kinds != {"person", "animal"}:
        error(f"{where}: 图集要同时有人物和动物")


def order_with_wiki() -> list[str]:
    order = list(SECTION_ORDER)
    order.insert(order.index(JOKE_SECTION), WIKI_SECTION)
    return order


def matching_order(names: list) -> list[str] | None:
    if names == SECTION_ORDER:
        return list(SECTION_ORDER)
    with_wiki = order_with_wiki()
    if names == with_wiki:
        return with_wiki
    return None


def cjk_count(text: str) -> int:
    return len(CJK_RE.findall(text))


def check_wiki(wiki: object, where: str) -> None:
    if not isinstance(wiki, dict):
        error(f"{where}: 维基漫游必须是对象")
        return
    check_no_extra(
        wiki,
        {"title", "originalTitle", "tagline", "body", "images", "sourceUrl"},
        where,
    )
    require_string(wiki, "title", where)
    require_string(wiki, "originalTitle", where)
    tagline = require_string(wiki, "tagline", where)
    if tagline is not None and count_sentences(tagline) != 1:
        error(f"{where}: tagline 须为 1 句，实际 {count_sentences(tagline)} 句：{tagline}")
    body = require_string(wiki, "body", where)
    if body is not None:
        count = cjk_count(body)
        if count < 300 or count > 500:
            error(f"{where}: body 须为 300 到 500 个汉字，实际 {count} 个")
    images = wiki.get("images")
    if not isinstance(images, list) or not (1 <= len(images) <= 2):
        error(f"{where}: images 须为 1 到 2 张")
    else:
        for index, image in enumerate(images, start=1):
            image_where = f"{where} 图片{index}"
            if not isinstance(image, dict):
                error(f"{image_where}: 必须是对象")
                continue
            check_no_extra(image, {"url", "credit"}, image_where)
            if not is_https_url(image.get("url")):
                error(f"{image_where}: url 必须是 https 地址")
            require_string(image, "credit", image_where)
    source = wiki.get("sourceUrl")
    if not is_https_url(source):
        error(f"{where}: sourceUrl 必须是 https 地址")
        return
    host = (urlparse(source).hostname or "").lower()
    if host != "wikipedia.org" and not host.endswith(".wikipedia.org"):
        error(f"{where}: sourceUrl 必须指向维基百科")


def check_issue(issue: dict, path: Path, index_date: str | None) -> None:
    where = str(path.relative_to(ROOT))
    check_no_extra(issue, {"date", "title", "sections"}, where)
    date = require_string(issue, "date", where)
    require_string(issue, "title", where)
    if date is not None:
        check_date(date, where)
        if path.stem != date:
            error(f"{where}: 文件名日期 {path.stem} 与 date 字段 {date} 不一致")
        if index_date is not None and index_date != date:
            error(f"{where}: 索引日期 {index_date} 与期刊 date {date} 不一致")
    sections = issue.get("sections")
    if not isinstance(sections, list):
        error(f"{where}: sections 必须是数组")
        return
    names = []
    for section in sections:
        if isinstance(section, dict) and isinstance(section.get("name"), str):
            names.append(section["name"])
        else:
            names.append(None)
    order = matching_order(names)
    if order is None:
        error(
            f"{where}: 栏目必须按此顺序各出现一次：{'、'.join(SECTION_ORDER)}。"
            f"「{WIKI_SECTION}」可以省略；若有，必须紧挨在笑话之前。实际为 {names}"
        )
        order = []
    for section, expected in zip(sections, order):
        if not isinstance(section, dict):
            error(f"{where}: 栏目必须是对象")
            continue
        section_where = f"{where} [{expected}]"
        if expected == "每日一图":
            check_no_extra(section, {"name", "photo"}, section_where)
            check_photo(section.get("photo"), section_where)
            continue
        if expected == "天涯海角":
            check_no_extra(section, {"name", "place"}, section_where)
            check_place(section.get("place"), section_where)
            continue
        if expected == "美女与野兽":
            check_no_extra(section, {"name", "gallery"}, section_where)
            check_gallery(section.get("gallery"), section_where)
            continue
        if expected == WIKI_SECTION:
            check_no_extra(section, {"name", "wiki"}, section_where)
            check_wiki(section.get("wiki"), section_where)
            continue
        check_no_extra(section, {"name", "items"}, section_where)
        items = section.get("items")
        if not isinstance(items, list) or not items:
            error(f"{section_where}: items 至少要有一条")
            continue
        if expected == JOKE_SECTION:
            if not isinstance(items, list) or len(items) < 10:
                error(f"{section_where}: 笑话至少 10 条")
            else:
                for index, item in enumerate(items, start=1):
                    label = item.get("handle") if isinstance(item, dict) else None
                    check_joke(item, f"{section_where} / {label or f'第{index}条'}")
            continue
        if not isinstance(items, list) or not (4 <= len(items) <= 7):
            error(f"{section_where}: 新闻栏目大约 5 则，允许 4 到 7 则")
            continue
        for index, item in enumerate(items, start=1):
            headline = item.get("headline") if isinstance(item, dict) else None
            label = headline if isinstance(headline, str) and headline else f"第{index}条"
            check_item(item, f"{section_where} / {label}")


def check_index(index: dict) -> list[tuple[str, str, Path]]:
    where = "data/index.json"
    check_no_extra(index, {"issues"}, where)
    entries = index.get("issues")
    if not isinstance(entries, list):
        error(f"{where}: issues 必须是数组")
        return []
    parsed: list[tuple[str, str, Path]] = []
    dates: list[str] = []
    for index_number, entry in enumerate(entries, start=1):
        entry_where = f"{where} 第{index_number}条"
        if not isinstance(entry, dict):
            error(f"{entry_where}: 必须是对象")
            continue
        check_no_extra(entry, {"date", "title", "path"}, entry_where)
        date = require_string(entry, "date", entry_where)
        require_string(entry, "title", entry_where)
        path_value = require_string(entry, "path", entry_where)
        if date is None or path_value is None:
            continue
        if not check_date(date, entry_where):
            continue
        if not INDEX_PATH_RE.match(path_value):
            error(f"{entry_where}: path 须形如 issues/YYYY-MM-DD.json")
            continue
        if path_value != f"issues/{date}.json":
            error(f"{entry_where}: path 应为 issues/{date}.json，实际为 {path_value}")
        dates.append(date)
        parsed.append((date, entry.get("title", ""), DATA / path_value))
    if dates != sorted(dates, reverse=True):
        error(f"{where}: issues 必须按日期从新到旧排列，实际为 {dates}")
    if len(dates) != len(set(dates)):
        error(f"{where}: issues 里有重复日期")
    return parsed


def check_orphans(indexed: set[str]) -> None:
    if not ISSUES_DIR.is_dir():
        error("data/issues/ 目录不存在")
        return
    on_disk = {path.stem for path in ISSUES_DIR.glob("*.json")}
    missing = indexed - on_disk
    extra = on_disk - indexed
    for date in sorted(missing):
        error(f"索引列出了 {date}，但 data/issues/{date}.json 不存在")
    for date in sorted(extra):
        error(f"data/issues/{date}.json 没有写进 data/index.json")


def check_schema_file() -> None:
    schema = load_json(SCHEMA_PATH)
    if not isinstance(schema, dict):
        error("data/schema.json 必须是 JSON 对象")
        return
    defs = schema.get("$defs")
    if not isinstance(defs, dict) or "issue" not in defs or "index" not in defs:
        error("data/schema.json 需要同时定义 issue 和 index")
    sections_schema = (
        defs.get("issue", {}).get("properties", {}).get("sections", {})
        if isinstance(defs, dict)
        else {}
    )
    variants = sections_schema.get("oneOf")
    if not isinstance(variants, list):
        variants = [sections_schema]
    declared = []
    for variant in variants:
        prefix = variant.get("prefixItems", []) if isinstance(variant, dict) else []
        names = []
        if isinstance(prefix, list):
            for item in prefix:
                try:
                    names.append(item["allOf"][1]["properties"]["name"]["const"])
                except (KeyError, IndexError, TypeError):
                    names.append(None)
        declared.append(names)
    expected = [list(SECTION_ORDER), order_with_wiki()]
    if declared != expected:
        error("data/schema.json 的栏目顺序与校验脚本不一致")


def self_test() -> None:
    assert count_sentences("甲。乙。") == 2
    assert count_sentences("标普跌3.70%，纳指跌5.28%。第二句。") == 2
    assert count_sentences("M. 约翰生于1945年。他获奖。") == 2
    assert count_sentences("只有一句没有句号") == 1
    assert matching_order(list(SECTION_ORDER)) == list(SECTION_ORDER)
    assert matching_order(order_with_wiki()) == order_with_wiki()
    assert matching_order(list(SECTION_ORDER) + [WIKI_SECTION]) is None
    assert count_sentences("甲。乙。丙。丁。戊。") == 5


def main() -> int:
    self_test()
    check_schema_file()
    index = load_json(INDEX_PATH)
    indexed_dates: set[str] = set()
    if isinstance(index, dict):
        entries = check_index(index)
        indexed_dates = {date for date, _, _ in entries}
        check_orphans(indexed_dates)
        for date, _, path in entries:
            issue = load_json(path)
            if isinstance(issue, dict):
                check_issue(issue, path, date)
    elif index is not None:
        error("data/index.json 必须是 JSON 对象")

    if ERRORS:
        print(f"校验失败，共 {len(ERRORS)} 个问题：", file=sys.stderr)
        for message in ERRORS:
            print(f"- {message}", file=sys.stderr)
        return 1
    issue_count = len(indexed_dates)
    print(f"校验通过：{issue_count} 期简报，栏目顺序、来源、名词解释和图片均符合 data/schema.json。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
