import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../data/device.dart';
import '../../../session/device_session_controller.dart';
import '../../../utils/utils.dart';
import '../../crash_reports/crash_report_controller.dart';
import '../mcp_tool.dart';
import 'mcp_tool_context.dart';

/// `list_crash_reports`, `get_crash_report` and `take_screenshot`.
List<McpTool> captureTools(McpToolContext context) => [
  McpTool(
    name: 'list_crash_reports',
    title: 'List crash reports',
    description:
        'Lists the crash reports on an iPhone (newest first): file name, the '
        'process that crashed, and when. Pulls them from the device, which '
        'takes a few seconds. Android crashes are in the log instead: use '
        'query_logs with filter "tag:AndroidRuntime level:e" (Java/Kotlin) '
        'or "tag:DEBUG level:f" (native).',
    inputSchema: objectSchema({
      'device': deviceProperty,
      'process': stringProperty(
        'Only reports whose process name contains this text.',
      ),
      'refresh': booleanProperty(
        'Pull from the device again. False reuses what Eagly last pulled.',
        defaultValue: true,
      ),
      'limit': integerProperty(
        'Most reports to return.',
        minimum: 1,
        maximum: 500,
        defaultValue: 50,
      ),
    }),
    handler: (args) async {
      final session = context.resolve(args.string('device'));
      final crashes = _crashReports(session);
      if (args.boolean('refresh') ?? true) {
        await crashes.refresh();
      } else {
        await crashes.ensureLoaded();
      }
      if (crashes.loadState == CrashReportLoadState.error) {
        throw McpToolError(crashes.error ?? 'Pulling crash reports failed.');
      }
      final process = args.string('process')?.toLowerCase();
      final limit = args.integer('limit', min: 1, max: 500) ?? 50;
      final matching = [
        for (final report in crashes.reports)
          if (process == null ||
              report.processName.toLowerCase().contains(process))
            report,
      ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return McpToolResult.json({
        'device': session.id,
        'reports': [
          for (final report in matching.take(limit))
            {
              'fileName': report.fileName,
              'process': report.processName,
              'time': report.timestamp.toIso8601String(),
              'sizeBytes': report.sizeBytes,
            },
        ],
        'totalMatching': matching.length,
      });
    },
  ),
  McpTool(
    name: 'get_crash_report',
    title: 'Get a crash report',
    description:
        'Returns the text of one iPhone crash report (.ips or .crash) by the '
        'file name list_crash_reports gave.',
    inputSchema: objectSchema(
      {
        'device': deviceProperty,
        'fileName': stringProperty('The report\'s file name.'),
        'maxBytes': integerProperty(
          'Longest text to return; longer reports are cut.',
          minimum: 1024,
          maximum: 2 * 1024 * 1024,
          defaultValue: 256 * 1024,
        ),
      },
      required: ['fileName'],
    ),
    handler: (args) async {
      final session = context.resolve(args.string('device'));
      final crashes = _crashReports(session);
      final fileName = args.requiredString('fileName');
      final maxBytes =
          args.integer('maxBytes', min: 1024, max: 2 * 1024 * 1024) ??
          256 * 1024;
      await crashes.ensureLoaded();
      var report = crashes.reports
          .where((r) => r.fileName == fileName)
          .firstOrNull;
      if (report == null) {
        await crashes.refresh();
        report = crashes.reports
            .where((r) => r.fileName == fileName)
            .firstOrNull;
      }
      if (report == null) {
        throw McpToolError(
          'No crash report "$fileName". Call list_crash_reports for the '
          'current file names.',
        );
      }
      final text = await readTextLenient(File(report.filePath));
      final cut = text.length > maxBytes;
      return McpToolResult.json({
        'device': session.id,
        'fileName': report.fileName,
        'process': report.processName,
        'time': report.timestamp.toIso8601String(),
        'text': cut ? text.substring(0, maxBytes) : text,
        if (cut) 'truncated': 'Cut to $maxBytes of ${text.length} characters.',
      });
    },
  ),
  McpTool(
    name: 'take_screenshot',
    title: 'Take a screenshot',
    description:
        'Captures the device screen as a PNG, scaled so its longer edge is '
        'at most maxEdge pixels. Nothing is saved. On an iPhone it takes about '
        'a second and needs the phone unlocked and trusted.',
    inputSchema: objectSchema({
      'device': deviceProperty,
      'maxEdge': integerProperty(
        'Longest edge of the returned image, in pixels.',
        minimum: 200,
        maximum: 4096,
        defaultValue: 1280,
      ),
    }),
    handler: (args) async {
      final session = context.resolveConnected(args.string('device'));
      final maxEdge = args.integer('maxEdge', min: 200, max: 4096) ?? 1280;
      final Uint8List png;
      try {
        png = await session.service.captureScreenshot();
      } catch (error) {
        throw McpToolError('The screenshot failed: ${describeError(error)}');
      }
      final scaled = await _downscale(png, maxEdge);
      return McpToolResult(
        image: McpImage(scaled.bytes),
        text:
            'Screenshot of ${session.device.displayName}: ${scaled.width}×'
            '${scaled.height} px'
            '${scaled.scaled ? ' (scaled from ${scaled.originalWidth}×${scaled.originalHeight})' : ''}.',
      );
    },
  ),
];

CrashReportController _crashReports(DeviceSessionController session) {
  if (session.device is! IosDevice) {
    throw const McpToolError(
      'Crash report files are an iPhone feature. On Android, crashes are in '
      'the log: query_logs with filter "tag:AndroidRuntime level:e".',
    );
  }
  return session.crashReportController;
}

Future<
  ({
    Uint8List bytes,
    int width,
    int height,
    int originalWidth,
    int originalHeight,
    bool scaled,
  })
>
_downscale(Uint8List png, int maxEdge) async {
  final descriptor = await ui.ImageDescriptor.encoded(
    await ui.ImmutableBuffer.fromUint8List(png),
  );
  final width = descriptor.width;
  final height = descriptor.height;
  final longest = width > height ? width : height;
  if (longest <= maxEdge) {
    descriptor.dispose();
    return (
      bytes: png,
      width: width,
      height: height,
      originalWidth: width,
      originalHeight: height,
      scaled: false,
    );
  }
  final scale = maxEdge / longest;
  final codec = await descriptor.instantiateCodec(
    targetWidth: (width * scale).round(),
    targetHeight: (height * scale).round(),
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final result = (
    bytes: data!.buffer.asUint8List(),
    width: image.width,
    height: image.height,
    originalWidth: width,
    originalHeight: height,
    scaled: true,
  );
  image.dispose();
  codec.dispose();
  descriptor.dispose();
  return result;
}
