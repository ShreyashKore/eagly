# Live log streaming: from device to `LogEntry`

How Eagly turns a device's live log output into `LogEntry` rows, what it guarantees about
them, and why it is built the way it is. **Read this before changing anything in the pipeline
below**: most of it exists because a simpler version lost, split or reordered log lines.

The priorities, in order: **data integrity and order** (every line the device logged
shows up exactly once, in the right entry, in order), then **performance** (a busy device
produces hundreds of thousands of lines a minute), then code sharing between platforms.
Where they conflict, the earlier one wins.

## The pipeline

```
                      raw output             parser + driver                    per-tab
Android   adb logcat -v long ─ lines ──► parseLogLines(LogcatParser)     ─┐
iOS CLI   idevicesyslog ────── lines ──► parseLogLines(IosSyslogParser)  ─┼─► Stream<LogEntry> ─► LogController
iOS Rust  os_trace_relay ──── records ──► parseLogRecords(IosSyslogParser)─┘    (ToolStreamSession)   queue → 300 ms flush → LogBuffer
```

| Piece | File |
|---|---|
| Parser contract, `parseLogLines`, `parseLogRecords` | `lib/features/logs/services/log_parsers/log_line_parser.dart` |
| Android parser | `lib/features/logs/services/log_parsers/logcat_parser.dart` |
| iOS parser (both iOS backends) | `lib/features/logs/services/log_parsers/ios_syslog_parser.dart` |
| Android source | `AdbTool.startLogcat` in `lib/services/tools/adb_tool.dart` |
| iOS CLI source | `IdeviceSyslogTool.start` in `lib/services/tools/idevice_syslog_tool.dart` |
| iOS Rust source | `RustIosLogService` in `lib/services/ios/rust_ios_log_service.dart`, `start_ios_syslog` in `rust/src/api/ios.rs` |
| Queueing and ordering in the UI | `LogController._attachLogStream` / `_appendImmediateLogEntry` / `_flushPendingLogs` in `lib/features/logs/log_controller.dart` |

> **Direction:** the libimobiledevice CLIs (`idevicesyslog` and friends) will be removed in a
> future version; the Rust `idevice` backend is the one that stays. New iOS log work goes on
> the Rust path first. See [Rust iOS: gaps to close](#rust-ios-gaps-to-close) and
> docs/IOS_RUST_MIGRATION.md.

## Guarantees

Each one is enforced by tests that fail CI; the right-hand column says where.

| # | Guarantee | Enforced by |
|---|---|---|
| 1 | A multi-line message is **one** entry, blank lines inside it kept. | `logcat_parser_test`, `ios_syslog_parser_test`, `log_line_parser_test` (records), `log_stream_pipeline_test` |
| 2 | **No text is lost**, even when an entry arrives in pieces slow enough to trip the idle flush: the late lines become a second row under the same header. | `log_line_parser_test` (fake time), `log_stream_pipeline_test` (real processes) |
| 3 | **Order is preserved** end to end — including separators (`beginning of crash`) and session markers (paused / stopped), which land after every entry that arrived before them. | `log_line_parser_test`, `log_controller_test` ("special entries keep their place…") |
| 4 | Two messages are never merged, even with identical headers (same thread, same millisecond). | `logcat_parser_test` ("keeps entries apart even when their headers are identical") |
| 5 | A parser exception becomes an error event → a tool-error row. It is never swallowed and never an uncaught zone error; the entry held before a source error is emitted first. | `log_line_parser_test` |
| 6 | Bounded latency: an entry is on screen within one idle interval (100–200 ms) of the device going quiet, or ~1.1 s if it looks cut off — never "until the next log line". | `log_line_parser_test` |
| 7 | Stopping capture keeps what was captured just before the stop. | `log_controller_test` |

There is also an opt-in **device check** that verifies 1–3 against real hardware; see
[Verifying a change](#verifying-a-change).

## The three sources

### Android: `adb logcat -v long`

`-v long` prints a header line once per entry, then the message **verbatim**, then a blank
footer line. Captured from a device (API 34):

```
--------- beginning of main
[ 09-26 20:46:04.996 32036:32036 D/EaglyML  ]
line one
line two

line four

[ 09-26 20:46:05.045 32040:32040 D/EaglyML  ]
single A

```

**Why not `-v threadtime`** (what Eagly used until `e155775`): it repeats the header on
*every* line of a multi-line message —

```
09-26 20:46:04.996 32036 32036 D EaglyML : line one
09-26 20:46:04.996 32036 32036 D EaglyML : line two
```

— and there is no way to tell that apart from two separate `Log.d` calls on the same thread in
the same millisecond (a loop over a list does exactly that). Merging lines with identical
headers would get the common case right and silently merge real, separate messages. `-v long`
has no such ambiguity: every entry has its own header.

Details the parser relies on:

- Header: `[ MM-DD HH:MM:SS.mmm  PID: TID L/TAG ]`, PID and TID space-padded to 5, the tag
  padded to 8. Tags may contain spaces and `]`; the regex anchors on the trailing ` ]`.
- A message may itself contain blank lines, so **only the next header (or separator) proves an
  entry ended**. The blank footer is a strong hint, which the flush policy uses.
- An empty message is a header followed by blank lines, and stays an entry with message `''`.
- `--------- beginning of <buffer>` / `switch to <buffer>` separators become `notice` entries.
- Adding a `-v` modifier (`uid`, `usec`, `epoch`, …) changes the header. Update the regex and
  the fixtures in the same change.

### iOS via the CLI: `idevicesyslog`

The bundled libimobiledevice CLI. By default it reads the `os_trace_relay` service (it has a
`--syslog-relay` flag to force the older one), which carries every level and microsecond
timestamps. It prints one header line per message and each further line of the message as a
bare continuation line:

```
[connected:00008140-001564CA3493801C]
Sep 26 23:11:50.009450 appleh16camerad(libEmbeddedSystemAUs.dylib)[136] <Debug>: AURemoteIO(0x…)::SetupConverter: input
  from:  1 ch,      0 Hz, Float32
    to:  2 ch,  48000 Hz, Float32, interleaved
Sep 26 23:11:50.009491 appleh16camerad(libEmbeddedSystemAUs.dylib)[136] <Debug>: AUIOHelper::Initialize
```

- Header: `Mon DD HH:MM:SS.ffffff process(category)[pid] <Level>: first line of message`.
  The year is not printed; the parser takes the current one.
- Anything that is not a header continues the entry before it. Unlike logcat there is no end
  marker at all, so the flush policy treats every held iOS entry as complete.
- Non-ASCII bytes can arrive as `cat -v` style escapes (`\M-b\M^U\M^T` → `╔`); the parser
  decodes them per line.
- The CLI prints its own status lines: `[connected:<udid>]` when it attaches and
  `[disconnected:<udid>]` if the device drops mid-stream. They are not device lines: each one
  ends the entry before it (so it can't be glued onto that message) and is dropped.

### iOS via Rust: the `os_trace_relay` service

`start_ios_syslog` uses the `idevice` crate's `OsTraceRelayClient` — the same service
`idevicesyslog` reads — and formats each structured record into the same header line the CLI
prints (`format_os_trace_log` in `rust/src/api/ios.rs`), so the Dart side is identical to the
CLI's: one header line per message plus bare continuation lines for the rest of it. Each string
sent to Dart is one **complete message**, embedded newlines included:

```
Sep 26 23:13:41.123456 softwareupdateservicesd(MobileSoftwareUpdate)[243] <Notice>: … state:{\n    ActionText = "…";\n}
```

Feeding that to a line parser was the bug fixed in `8b63d95`: the header regex doesn't match
a string containing `\n`, so a multi-line message was appended to the *previous* entry, under
its timestamp and PID. `parseLogRecords` splits each record on `\n`, feeds the pieces, and
flushes at the record boundary — the one place where the end of an entry is known for certain.
So the Rust path needs no idle timer, has no flush latency and cannot split an entry.

The record carries a clean process name and microsecond timestamp, so unlike the legacy
`syslog_relay` there is no hostname to strip and no missing level — see
[Rust iOS: gaps closed](#rust-ios-gaps-closed).

## The parser contract (`LogLineParser`)

```dart
abstract interface class LogLineParser {
  List<LogEntry> addLine(String line);           // entries this line completes, oldest first
  LogEntry? flush();                             // the entry still being built, if any
  PendingEntryStatus get pendingEntryStatus;     // how soon an idle stream may flush it
}
```

Rules every implementation follows:

1. **`addLine` is eager** and returns a `List` (the common no-entry case is a `const []`, so
   no allocation per continuation line). It used to be a lazy `sync*` generator, where a
   caller that ignored the result silently dropped the line.
2. **A new header or separator completes the entry before it** — that is the only certain
   end of an entry in a line-based format.
3. **Never drop lines after a flush.** A flush can come too early (an idle flush while the
   tool is mid-write), so the parser remembers the header of the entry it flushed. Body lines
   arriving before a new header start a new entry under that header. The worst case is one
   message split across two rows, never lost text. A new header or a separator forgets the
   remembered header. A resumed entry with only blank lines (a late footer) produces no row.
4. Lines before the first header ever seen are ignored — they can't be attributed to anyone.
5. `pendingEntryStatus` reports what the parser holds:

| Status | Meaning | `parseLogLines` flushes it on idle |
|---|---|---|
| `none` | nothing buffered | — |
| `awaitingBody` | a header whose body hasn't arrived | **never** — holding it delays nothing, since the next line either fills it or starts a new entry; end of stream flushes it |
| `incomplete` | no end marker yet (logcat: last line isn't the blank footer) | after `logLineIncompleteEntryFlushDelay` (1 s) of silence |
| `complete` | ends like a whole entry (iOS: always) | after `logLineIdleFlushInterval` (100 ms) of silence |

A new source means a new parser that follows these rules, plus fixtures captured from a real
device — not written from documentation.

## Flushing: `parseLogLines` and `parseLogRecords`

`parseLogLines(lines, parser)` drives a parser over a tool's stdout:

- **Silence is sampled on one `Timer.periodic`** (100 ms). A line sets a flag; a tick that sees
  no line since the last one counts as quiet. That is deliberate: a one-shot timer reset per
  line costs a timer allocation per line, and a busy device sends tens of thousands a second.
  So "quiet for 100 ms" really means between 100 and 200 ms.
- The status table above decides whether a quiet tick flushes. Both intervals are parameters
  (`idleFlushInterval`, `incompleteEntryFlushDelay`) so tests can pin them.
- **The timer stops while the output is paused** and restarts, with a fresh silence count, on
  resume: the rest of an entry may be sitting in the paused source, so silence proves nothing.
- **Parser calls are guarded**: an exception becomes an error event on the output stream. The
  CLI tools consume the stream with `await for` inside a `try`, which turns it into a
  tool-error row; `RustIosLogService` does the same in `onError`.
- **A source error flushes the held entry first**, then forwards the error — the entry came
  first, and an `await for` consumer stops at the error.
- End of stream flushes whatever is held, then closes.

`parseLogRecords(records, parser)` is for sources that frame whole entries (the Rust relay):
split each record on `\n` (dropping one trailing empty piece), feed the lines, flush. A parser
exception becomes an error event through `Stream.expand`. No timer.

## Ordering in `LogController`

The controller queues normal entries in `_pendingLogs` and appends them to the `LogBuffer`
on a 300 ms timer, so a busy stream costs one rebuild per flush instead of one per line.
Special entries — the stream's separators, and the controller's own session markers
(started / paused / resumed / stopped / notices) — are appended immediately. So
`_appendImmediateLogEntry` **flushes the queue first**; without that, a marker jumped ahead
of up to 300 ms of earlier entries, and a stop (which cancels the flush timer before appending
"stopped") stranded them for good. Anything that appends to the buffer outside the periodic
flush must go through `_appendImmediateLogEntry` or flush the queue itself.

## Do not

Each of these has been a real bug, or is the obvious "simplification" that brings one back.

- **Don't go back to `logcat -v threadtime`**, or merge lines that share a header.
  `log_stream_pipeline_test` fails if the arguments change.
- **Don't feed Rust relay records to `parseLogLines`** or split them on the Rust side into
  lines; the record boundary is the only certain end of an entry. Use `parseLogRecords`.
- **Don't let a parser forget the flushed header**, or drop lines when nothing is being built
  after the first header.
- **Don't idle-flush an `awaitingBody` entry**, or flush on a short timer regardless of status.
- **Don't reset a timer per line** in `parseLogLines`, and don't let the idle timer run while
  the output is paused.
- **Don't call a parser outside a guard** in a stream callback — an exception there escapes to
  the zone instead of reaching the user as a tool-error row.
- **Don't append special entries to the buffer without flushing `_pendingLogs`.**
- **Don't make `addLine` lazy again.**

## Verifying a change

Unit and pipeline tests run in CI with `fvm flutter test`:

| Test | Covers |
|---|---|
| `test/logcat_parser_test.dart` | `-v long` parsing, identical headers, resume after flush, statuses |
| `test/ios_syslog_parser_test.dart` | headers, continuations, meta escapes, resume after flush |
| `test/log_line_parser_test.dart` | `parseLogLines` flush timing (fake time), pauses, errors, cancel; `parseLogRecords` |
| `test/log_stream_pipeline_test.dart` | `AdbTool` / `IdeviceSyslogTool` against fake executables, with a mid-entry pause |
| `test/log_controller_test.dart` | separators and markers after queued entries; nothing lost on stop |

**Before changing the pipeline, also run the device check** with real devices attached. It
tees the raw tool output as it enters the pipeline, parses the same output again offline with
no idle timer, and requires the two to hold the same lines under the same headers in the same
order (splits allowed, and counted). It is skipped unless the variables are set:

```bash
cd rust && cargo build --release && cd ..        # only needed for the Rust iOS check
EAGLY_TEST_ANDROID_SERIAL=<adb serial> EAGLY_TEST_IOS_UDID=<udid> \
  fvm flutter test test/device/log_stream_integrity_test.dart
```

Results on 2026-09-26 (SM-E236B on API 34; iPhone17,3 on iOS 26.7, then 27.0):

| Source | Entries in 10 s | Multi-line | Result |
|---|---|---|---|
| Android (backlog replay, ~840k raw lines) | 263,810 – 290,515 | 2,322 – 2,790 | identical, 0 splits |
| iOS CLI | 4,082 – 197,183 | 261 – 8,004 | identical; 1 real idle-flush split seen in one run, every line kept |
| iOS Rust | 592 – 25,013 | 23 – 1,250 | identical, exactly one entry per record |

A device check only proves the pipeline agrees with the parser. It can't catch the device
*format* changing under the parser (both sides would parse it the same wrong way), so after an
OS update also eyeball the raw output:

```bash
# Android: make a multi-line log, then look at it
adb shell 'log -t EaglyML -p d "one
two

four"'
adb logcat -d -v long -s EaglyML

# iOS: header lines vs everything else
platform-tools/macos/idevicesyslog | head -50
```

## Known limitations

- **A split entry shows as two rows with the same header.** Only when a tool pauses for over
  100–200 ms mid-entry (iOS CLI), or over ~1 s before the logcat footer. Seen once in about
  6,000 iOS entries; never on Android. The text is complete and in order.
- **A logcat header with no body yet is held** until its body, the next header, or the end of
  the stream. Logcat writes an entry in one go, so in practice this is invisible.
- A continuation line that happens to look exactly like a header is parsed as one. Nothing
  distinguishes them in either format.
- A Rust relay record without a header would be filed under the previous entry's header as a
  separate row. None seen in the device runs (tens of thousands of records).

## Rust iOS: gaps closed

Found on hardware (iOS 26.7 and 27.0) against the legacy `syslog_relay`, and closed by moving
`start_ios_syslog` to `os_trace_relay`:

1. **Debug and Info messages were missing.** `syslog_relay` only carries Notice, Error and
   Fault. Measured over 10 s on iOS 27: `idevicesyslog` (os_trace_relay) 334,127 lines,
   `idevicesyslog --syslog-relay` 53,782 — about 80–85% of messages are Debug or Info.
   `os_trace_relay` carries every level.
2. **No sub-second timestamps.** `Sep 26 23:36:32` became `23:36:32.000`, so everything in
   a second sorted by arrival only. `os_trace_relay` records carry a microsecond timestamp,
   formatted as `%b %e %H:%M:%S.%06u`.
3. **Wrong process and package names.** Relay records kept the device's hostname after the
   timestamp (`… 23:36:32 Shreyashs-iPhone backboardd(QuartzCore)[75] …`); `IosSyslogParser`
   took it as part of the process label, giving `processName = "Shreyashs-iPhone
   backboardd(QuartzCore)"` and breaking package filtering. `os_trace_relay` returns a clean
   `filename`/`image_name` pair, formatted as `process(image)` with no hostname.

`format_os_trace_log` renders each record into the exact text `idevicesyslog` would print, so
the parser — and everything downstream — is unchanged. The switch is **not yet re-verified on
hardware**: re-run the device check below and compare level counts with `idevicesyslog` while it
still ships.
