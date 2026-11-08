#!/usr/bin/env python3
"""Writes the baseline pair the probe set reads: one run where every difference is covered."""

import json
import os
import sys

HERE = "/home/mak/Work/rivulet/Tools/parity"
HEAD = "56498c1"
sys.path.insert(0, HERE)
import parity_check as p

FLAGS = {"FETCHER_ALLOW_PRIVATE_NETWORKS": "true", "BATCH_SIZE": "100", "POLLING_LIMIT_PER_HOST": "0",
         "POLLING_PARSING_ERROR_LIMIT": "0", "RUN_MIGRATIONS": "false"}
BASE = {"reference": "http://127.0.0.1:8080", "port": "http://127.0.0.1:9001"}
KEYS = ["corpus/tag_order.xml", "corpus/table_content.xml", "corpus/name_class.xml",
        "corpus/zone_pst.xml", "corpus/sub_second_date.xml", "request/method_mismatch",
        "request/no_trailing_slash", "request/repeated_header"]
HEADERS = {"X-Content-Type-Options": ["nosniff"], "X-Frame-Options": ["DENY"],
           "Referrer-Policy": ["no-referrer"]}
TRACED = dict(HEADERS, **{"X-Trace": ["one", "two"]})
PATHS = {"/reader/api/0/user-info": "request/repeated_header", "/reader/api/0/tag/list": "corpus/tag_order.xml",
         "/reader/api/0/stream/items/ids": "request/stream_items_ids",
         "/reader/api/0/stream/items/contents": "request/stream_items_contents",
         "/reader/api/0/edit-tag": "request/method_mismatch", "/reader/api/0": "request/no_trailing_slash"}


def clock(msec):
    return {"updated": msec, "crawlTimeMsec": str(msec), "timestampUsec": str(msec) + "000"}


def item(row):
    """The item the content endpoint writes, with the row number of the side that wrote it."""
    return {"id": p.ITEM_PREFIX + "%016x" % row["row"], "enclosure": []}


def row(file, hash, row, title, content, published, clock_value):
    return {"file": file, "hash": hash, "row": row, "title": title, "content": content,
            "published": published, "status": "unread", "starred": False, "clock": clock(clock_value)}


def redirect_headers():
    """What the mux writes on its own redirect: the pair the builder never sees, because the
    redirect is written before the handler, so the three names the builder writes are not there."""
    return {"Location": ["/reader/api/0/"], "Content-Type": ["text/html; charset=utf-8"]}


def build():
    ref, port = {}, {}
    for side, name in ((ref, "reference"), (port, "port")):
        side["side"] = name
        pinned = p.PINNED_REFERENCE if name == "reference" else "rivulet at " + HEAD
        side["run"] = {"reference": pinned, "flags": dict(FLAGS), "base_url": BASE[name],
                       "media_proxy_mode": "none", "user": "parity", "network": "loopback"}
        side["inputs"] = {key: "sha256-" + key for key in KEYS}

    ref["entries"] = [
        row("corpus/tag_order.xml", "h1", 11, "Zebra", "the byte order puts this first", 1719792000, 101000),
        row("corpus/tag_order.xml", "h2", 12, "apple", "the collation puts this first", 1719792000, 102000),
        row("corpus/table_content.xml", "h3", 13, "Foster parenting",
            "<p>y</p><table><tbody><tr><td>z</td></tr></tbody></table>", 1719792000, 103000),
        row("corpus/zone_pst.xml", "h4", 14, "Zone abbreviation", "the instant the two zones part on",
            1719817200, 104000),
        row("corpus/sub_second_date.xml", "h5", 15, "Sub second", "the value one side keeps",
            "1719792000.000001", 105000),
    ]
    port["entries"] = [
        row("corpus/tag_order.xml", "h1", 61, "Zebra", "the byte order puts this first", 1719792000, 161000),
        row("corpus/tag_order.xml", "h2", 62, "apple", "the collation puts this first", 1719792000, 162000),
        row("corpus/table_content.xml", "h3", 63, "Foster parenting",
            "<table>y<tbody><tr><td>z</td></tr></tbody></table>", 1719792000, 163000),
        row("corpus/zone_pst.xml", "h4", 64, "Zone abbreviation", "the instant the two zones part on",
            1719820800, 164000),
        row("corpus/sub_second_date.xml", "h5", 65, "Sub second", "the value one side keeps",
            "1719792000", 165000),
        row("corpus/name_class.xml", "h6", 66, "Name class", "the item this port reads alone",
            1719792000, 166000),
    ]

    ref["feeds"] = [{"file": key, "row": 31 + index, "title": key.split("/")[-1]}
                    for index, key in enumerate(KEYS[:5])]
    port["feeds"] = [{"file": key, "row": 41 + index, "title": key.split("/")[-1]}
                     for index, key in enumerate(KEYS[:5])]

    sequence = [
        {"key": "request/repeated_header", "method": "POST", "path": "/accounts/ClientLogin", "status": 200,
         "document": {"SID": "sid", "LSID": "sid", "Auth": "sid"}, "headers": TRACED,
         "acted_on": {"X-Trace": "one"}, "asked": ["Email", "Passwd", "output"]},
        {"key": "corpus/tag_order.xml", "method": "GET", "path": "/reader/api/0/tag/list", "status": 200,
         "document": {"tags": [{"id": "user/1/state/com.google/label/apple", "label": "apple"},
                               {"id": "user/1/state/com.google/label/Zebra", "label": "Zebra"}]},
         "headers": HEADERS, "acted_on": {}, "asked": ["output=json"]},
        {"key": "request/stream_items_ids", "method": "GET", "path": "/reader/api/0/stream/items/ids",
         "status": 200, "document": {"itemRefs": []}, "headers": HEADERS, "acted_on": {},
         "asked": ["output=json", "stream=user/-/state/com.google/reading-list"]},
        {"key": "request/stream_items_contents", "method": "POST",
         "path": "/reader/api/0/stream/items/contents", "status": 200,
         "document": {"self": [], "updated": 1719792300, "items": []}, "headers": HEADERS,
         "acted_on": {}, "asked": ["output=json", "stream=user/-/state/com.google/reading-list"]},
        {"key": "request/method_mismatch", "method": "GET", "path": "/reader/api/0/edit-tag",
         "status": 405, "document": {"error": "Method Not Allowed"}, "headers": HEADERS,
         "acted_on": {}, "asked": []},
        {"key": "request/no_trailing_slash", "method": "GET", "path": "/reader/api/0", "status": 307,
         "document": {"body": "html"}, "headers": HEADERS, "acted_on": {}, "asked": []},
    ]
    ref["requests"] = [dict(one) for one in sequence]
    port["requests"] = [dict(one) for one in sequence]

    for side, name in ((ref, "reference"), (port, "port")):
        for one in side["requests"]:
            document = dict(one["document"])
            if one["key"] == "request/stream_items_contents":
                document["items"] = [dict(item(entry), origin={
                    "streamId": "tag:google.com,2005:reader/feed/%d" % p.feed_row(side, entry),
                    "title": entry["title"]}) for entry in side["entries"]]
                document["self"] = [{"href": BASE[name] + one["path"]}]
            if name == "port":
                if one["key"] == "request/method_mismatch":
                    one["status"] = 404
                elif one["key"] == "request/no_trailing_slash":
                    one["status"] = 200
                elif one["key"] == "corpus/tag_order.xml":
                    document["tags"] = list(reversed(document["tags"]))
            one["document"] = document

    pair = {"rules": list(p.RULES), "recorded": p.parse_table(open(p.DEFAULTS["table"]).read()),
           "manifest": p.parse_manifest(open(p.DEFAULTS["manifest"]).read()),
           "reference": ref, "port": port}
    for side in (ref, port):
        side["counts"] = p.counted(side, pair)
    return pair


pair = build()
document = {"reference": pair["reference"], "port": pair["port"]}
with open(os.path.join(HERE, "baseline.json"), "w") as out:
    json.dump(document, out, indent=1, sort_keys=True, ensure_ascii=False)
    out.write("\n")
print("wrote baseline.json")
