import 'package:flutter/material.dart';

import 'tip.dart';

/// The rotating pool of feature tips. Each launch surfaces the next one.
///
/// Keep every [Tip.title] short enough to read at a glance in the header and
/// every [Tip.detail] to a couple of sentences — the panel is meant to be
/// quiet and skimmable, not a manual.
const List<Tip> kTips = [
  Tip(
    id: 'hide-columns',
    icon: Icons.view_column_outlined,
    title: 'Hide columns you don\'t use',
    detail:
        'The log table has more columns than most people need. Right-click any '
        'column header to hide or show individual columns — trim it down to just '
        'the message, or add back PID, tag and time when you need them.',
    actionHint: 'Right-click a column header in the log view',
  ),
  Tip(
    id: 'advanced-filters',
    icon: Icons.filter_alt_outlined,
    title: 'Filter with exact, regex & negation',
    detail:
        'Switch the filter bar to the Inline style to type advanced filters. '
        'Use "tag:MyTag" to match, "-tag:Noise" to exclude, "tag=:Exact" for an '
        'exact match, and "tag~:Err.*" for a regular expression. Combine several '
        'terms to zero in on exactly the lines you want.',
    actionHint: 'Filter style → Inline (in the filter bar or Settings)',
  ),
  Tip(
    id: 'time-filter',
    icon: Icons.schedule_outlined,
    title: 'Show only the last few minutes',
    detail:
        'Chasing something that just happened? Add a time window like "5m", '
        '"30s" or "1h" to the filter to hide everything older than that, so a '
        'noisy log collapses to just the recent activity.',
    actionHint: 'Type a duration such as 5m into the filter',
  ),
  Tip(
    id: 'multiple-tabs',
    icon: Icons.tab_outlined,
    title: 'Open several log tabs per device',
    detail:
        'You are not limited to one stream. Open extra log tabs on the same '
        'device to keep a filtered view running alongside the raw feed, or to '
        'compare two captures side by side.',
    actionHint: 'Use the "New tab" action next to the device tabs',
  ),
  Tip(
    id: 'import-logs',
    icon: Icons.file_open_outlined,
    title: 'Open a saved log without a device',
    detail:
        'No device connected? You can still open a previously saved log file. '
        'It loads into an "Imported Logs" workspace where the same filtering, '
        'search and columns all work.',
    actionHint: 'Drop a log file onto the window, or use Open log',
  ),
  Tip(
    id: 'drag-drop-install',
    icon: Icons.install_mobile_outlined,
    title: 'Drag an app onto the window to install',
    detail:
        'Drop an .apk (Android) or .ipa (iOS) onto a connected device to install '
        'it in place. Drop any other file and it gets copied onto the device '
        'instead — no command line needed.',
    actionHint: 'Drag a file onto the device tab',
  ),
  Tip(
    id: 'screen-mirror',
    icon: Icons.screen_share_outlined,
    title: 'Mirror the device screen',
    detail:
        'Beyond logs, Eagly can mirror the device screen right inside the app, '
        'so you can watch the UI and the log stream together while you reproduce '
        'an issue.',
    actionHint: 'Pick the Mirror feature in the device sidebar',
  ),
  Tip(
    id: 'crash-reports',
    icon: Icons.bug_report_outlined,
    title: 'Browse crash reports',
    detail:
        'Eagly pulls crash reports off the device and lists them so you can read '
        'a stack trace without digging through raw log output.',
    actionHint: 'Open the Crash reports feature in the device sidebar',
  ),
  Tip(
    id: 'wireless-adb',
    icon: Icons.wifi_tethering,
    title: 'Debug Android over Wi‑Fi',
    detail:
        'Unplug the cable — connect an Android device wirelessly and stream '
        'logcat over the network. Pair once and reconnect from the header any '
        'time.',
    actionHint: 'Tap the Wireless ADB icon in the header',
  ),
  Tip(
    id: 'font-size',
    icon: Icons.format_size_outlined,
    title: 'Resize the log text quickly',
    detail:
        'Make dense logs easier to read: bump the log font size up or down with '
        'the keyboard shortcut, or set a default in Settings.',
    actionHint: 'Cmd/Ctrl and + or − while viewing logs',
  ),
];
