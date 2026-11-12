#!/usr/bin/env python3
"""Writes a deterministic, made-up Android Studio logcat JSON for tip clips.

Recording tips against a fabricated log means no real device data can end up in
a published clip, and every retake shows the same lines.

    python3 scripts/tips_media/make_sample_log.py out.json [--recent MINUTES]

--recent spreads the lines evenly over the last MINUTES minutes, ending now,
for clips of the time filter ("5m"), which is measured from the current time.
Generate it right before importing: the window slides as the clock runs.
"""
import argparse
import json
import random
import time

APP = "com.example.notes"
LINES = [
    ("I", "ActivityManager", "system_server", "Start proc 4182:com.example.notes/u0a214 for top-activity"),
    ("D", "NotesApp", APP, "onCreate: restoring 42 notes from cache"),
    ("I", "NotesRepository", APP, "Sync started (trigger=app_open)"),
    ("D", "OkHttp", APP, "--> GET https://api.example.com/v2/notes?since=1731300000"),
    ("D", "OkHttp", APP, "<-- 200 OK (184ms, 12.4kB)"),
    ("I", "NotesRepository", APP, "Sync finished: 3 added, 1 updated, 0 removed"),
    ("V", "Choreographer", APP, "Frame time: 7.9ms"),
    ("D", "EditorFragment", APP, "Opened note id=note_0193 (1,284 chars)"),
    ("W", "ImageLoader", APP, "Thumbnail cache miss for attachment att_771, decoding"),
    ("D", "Autosave", APP, "Draft saved (debounce 800ms)"),
    ("I", "WorkManager", APP, "Enqueued BackupWorker (constraints: unmetered, charging)"),
    ("E", "SyncWorker", APP, "Upload failed for note_0187: HTTP 409 Conflict, retrying in 30s"),
    ("D", "ConflictResolver", APP, "Merging remote revision 14 into local revision 13"),
    ("I", "SyncWorker", APP, "Retry succeeded for note_0187"),
    ("V", "Choreographer", APP, "Frame time: 8.4ms"),
    ("D", "SearchViewModel", APP, "Query \"grocery\" -> 6 results in 11ms"),
    ("W", "StrictMode", APP, "DiskReadViolation in NotesDatabase.open()"),
    ("I", "ReminderScheduler", APP, "Scheduled reminder for note_0201 at 18:30"),
    ("D", "Autosave", APP, "Draft saved (debounce 800ms)"),
    ("E", "AttachmentUploader", APP, "java.io.IOException: unexpected end of stream on api.example.com"),
    ("I", "NotesApp", APP, "onTrimMemory(level=20) releasing image cache"),
    ("D", "EditorFragment", APP, "Closed note id=note_0193, 3 edits"),
]


def main(out: str, recent_minutes: float | None) -> None:
    rng = random.Random(7)
    seconds, nanos = 1731300000, 120_000_000
    rows = [line for _ in range(4) for line in LINES]  # fill the visible area
    if recent_minutes:
        end_ns = time.time_ns()
        step_ns = int(recent_minutes * 60e9 / len(rows))
    msgs = []
    for i, (level, tag, proc, message) in enumerate(rows):
        if recent_minutes:
            t = end_ns - (len(rows) - 1 - i) * step_ns
            seconds, nanos = divmod(t, 1_000_000_000)
        else:
            nanos += rng.randint(15, 240) * 1_000_000
            seconds += nanos // 1_000_000_000
            nanos %= 1_000_000_000
        pid = 1023 if proc == "system_server" else 4182
        msgs.append({
            "header": {
                "logLevel": level,
                "pid": pid,
                "tid": pid + rng.choice([0, 0, 11, 23, 37]),
                "tag": tag,
                "applicationId": proc,
                "processName": proc,
                "timestamp": {"seconds": seconds, "nanos": nanos},
            },
            "message": message,
        })
    data = {
        "metadata": {"device": {"physicalDevice": None}, "totalLogs": len(msgs)},
        "logcatMessages": msgs,
    }
    with open(out, "w") as f:
        json.dump(data, f, indent=2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("out", nargs="?", default="notes_sample.json")
    parser.add_argument("--recent", type=float, metavar="MINUTES")
    args = parser.parse_args()
    main(args.out, args.recent)
