#!/usr/bin/env python3
"""The run reads the version the app's own metadata writes with this half.

It asserts nothing. It prints the version the first release record in the file names, which is the
value the run declares, so the version guard can be seen to fail on a version the file does not
write.

The read walks from the release record to the first run of digits and dots after it, which is the
value the record names, and reads nothing before the record: the XML header carries a version of its
own. The codes are written from numbers, because a bracket expression or a quote passed through a
command is not the same bytes as the one the run reads.
"""

import sys

DIGITS = set(chr(code) for code in range(48, 58)) | {chr(46)}
START = chr(60) + "release " + "version"

text = open(sys.argv[1], encoding="utf-8").read()
head = text.find(START)
if head < 0:
    print("")
    raise SystemExit(0)

value = ""
for char in text[head + len(START):]:
    if char in DIGITS:
        value += char
    elif value:
        break
print(value)
