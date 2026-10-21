import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/components/feature_view.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../../utils/url_launcher.dart';
import '../data/network_transaction.dart';
import '../network_controller.dart';
import '../services/network_source.dart';

/// Where the empty pane sends people for what it has no room for.
abstract final class NetworkGuideLinks {
  static const inspektorRepo = 'https://github.com/ShreyashKore/inspektor';
  static const inspektorReadme = '$inspektorRepo#readme';
  static const inspektorRemote = '$inspektorRepo#remote-inspection-with-eagly';
  static const inspektorSwift = '$inspektorRepo#from-swift-or-react-native';
  static const mavenCentral =
      'https://central.sonatype.com/artifact/com.gyanoba.inspektor/inspektor';
  static const paneGuide =
      'https://github.com/ShreyashKore/eagly/blob/main/docs/NETWORK_PANE.md';
}

/// Who is reading the empty pane: someone with a build in hand, or someone
/// adding Inspektor to one.
enum _Audience { tester, developer }

/// The HTTP stacks Inspektor can record, as far as setting it up differs.
enum _Client {
  okhttp('OkHttp'),
  ktor('Ktor'),
  urlSessionKotlin('URLSession (Kotlin)'),
  swift('Swift / React Native');

  const _Client(this.label);
  final String label;
}

/// What the Network pane shows while it has nothing to list: what fills it,
/// how to get an app to (for testers and for developers), and a HAR file for
/// when there is no app at hand. Written for people who have never heard of
/// Inspektor; the details live in the linked READMEs.
class const NetworkEmptyGuide({
  super.key,
  required final NetworkController controller,
  required final VoidCallback onOpenHar,
}) extends StatefulWidget {
  @override
  State<NetworkEmptyGuide> createState() => _NetworkEmptyGuideState();
}

class _NetworkEmptyGuideState extends State<NetworkEmptyGuide> {
  _Audience _audience = _Audience.tester;
  late _Client _client = widget.controller.device.platform == DevicePlatform.ios
      ? _Client.swift
      : _Client.okhttp;

  NetworkController get _controller => widget.controller;
  bool get _isIos => _controller.device.platform == DevicePlatform.ios;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.http, size: 36, color: theme.colorScheme.primary),
              const Gap(12),
              Text('No network traffic yet', style: theme.textTheme.titleLarge),
              const Gap(6),
              _Paragraph(
                'Requests an app makes on ${_controller.device.displayName} '
                'show up here, live, when a test build of the app includes '
                'Inspektor. You can also open a saved HAR file.',
              ),
              const Gap(14),
              ListenableBuilder(
                listenable: _controller.session,
                builder: (context, _) => _WatchStatus(controller: _controller),
              ),
              const Gap(16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: widget.onOpenHar,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Open HAR file'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        openExternalUrl(NetworkGuideLinks.inspektorReadme),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Inspektor on GitHub'),
                  ),
                ],
              ),
              const _SectionDivider(),
              const _Heading('What is Inspektor?'),
              const _Paragraph(
                'An open-source library developers add to Android and iOS '
                'apps. It records each request and response, and Eagly reads '
                'them over USB: no proxy or certificates needed.',
              ),
              const Gap(10),
              const Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Tag('Android'),
                  _Tag('iOS'),
                  _Tag('OkHttp & Retrofit'),
                  _Tag('Ktor'),
                  _Tag('URLSession & Alamofire'),
                  _Tag('React Native on iOS'),
                ],
              ),
              const _SectionDivider(),
              SegmentedButton<_Audience>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _Audience.tester,
                    icon: Icon(Icons.fact_check_outlined, size: 18),
                    label: Text('I’m testing an app'),
                  ),
                  ButtonSegment(
                    value: _Audience.developer,
                    icon: Icon(Icons.code, size: 18),
                    label: Text('I’m building the app'),
                  ),
                ],
                selected: {_audience},
                onSelectionChanged: (selection) =>
                    setState(() => _audience = selection.single),
              ),
              const Gap(18),
              if (_audience == _Audience.tester)
                ..._testerSteps(context)
              else
                ..._developerSteps(context),
              const _SectionDivider(),
              const _Heading('What is a HAR file?'),
              const _Paragraph(
                'A saved recording of network traffic. Inspektor, browser '
                'developer tools and proxies like Charles can export one. To '
                'share what you captured here, use Export as HAR above.',
              ),
              const _SectionDivider(),
              const _Heading('More help'),
              const Gap(4),
              const _Link(
                label: 'Network pane guide, with troubleshooting',
                url: NetworkGuideLinks.paneGuide,
              ),
              const _Link(
                label: 'Inspektor README: every option and integration',
                url: NetworkGuideLinks.inspektorReadme,
              ),
              const _Link(
                label: 'Inspektor’s remote inspection, and its safety notes',
                url: NetworkGuideLinks.inspektorRemote,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _testerSteps(BuildContext context) {
    final device = _controller.device.displayName;
    return [
      const _Step(
        number: 1,
        title: 'Get a test build that includes Inspektor',
        body:
            'Ask the app’s developers for a debug, dev or QA build with '
            'Inspektor’s remote inspection turned on. Builds from the App '
            'Store or Google Play never include it, on purpose. Developers '
            'can follow “I’m building the app” above.',
      ),
      ListenableBuilder(
        listenable: _controller.session,
        builder: (context, _) => _Step(
          number: 2,
          done: _controller.isConnected,
          title: _controller.isConnected
              ? '$device is connected'
              : 'Connect $device',
          body: _isIos
              ? 'Connect the iPhone with a cable, unlock it and tap Trust if '
                    'it asks. Install the test build on it.'
              : 'Connect the phone with a USB cable and allow USB debugging '
                    'when it asks, or pair it over Wi-Fi from the device '
                    'list. Install the test build on it.',
        ),
      ),
      const _Step(
        number: 3,
        title: 'Open the app and use it',
        body:
            'Its requests appear here within a couple of seconds, along with '
            'the ones it recorded before you looked. Keep this pane open: '
            'Eagly looks for apps only while it is.',
      ),
      _Step(
        number: 4,
        title: 'Still empty?',
        isLast: true,
        body: null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isIos)
              const _Bullet(
                'Keep the app in the foreground and the iPhone unlocked. iOS '
                'pauses apps in the background, and Eagly reconnects when the '
                'app comes back.',
              )
            else ...const [
              _Bullet(
                'Open the Logs pane and search for “Inspektor: remote '
                'inspection listening”. If that line never appears, this '
                'build doesn’t start Inspektor. Ask the developers for one '
                'that does.',
              ),
              _Bullet(
                'If the app restarted or crashed, give it a moment. Eagly '
                'reconnects and carries on with the same list.',
              ),
            ],
            const _Bullet(
              'Only requests made through OkHttp, Ktor or URLSession are '
              'recorded. A web page shown inside the app (a web view) is not.',
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _developerSteps(BuildContext context) {
    final client = _client;
    return [
      Text('Your HTTP client', style: Theme.of(context).textTheme.labelLarge),
      const Gap(8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final option in _Client.values)
            ChoiceChip(
              showCheckmark: false,
              label: Text(option.label),
              selected: option == client,
              onSelected: (_) => setState(() => _client = option),
            ),
        ],
      ),
      const Gap(18),
      ..._clientSteps(client),
      _Step(
        number: client == _Client.swift ? 3 : 4,
        title: 'Run it on ${_controller.device.displayName}',
        isLast: true,
        body:
            'Install the debug build, open the app and keep this pane open. '
            'Within a couple of seconds Eagly finds the app and lists its '
            'requests here. On start Inspektor writes “Inspektor: remote '
            'inspection listening on …” to the device log, which the Logs '
            'pane shows.',
      ),
    ];
  }

  List<Widget> _clientSteps(_Client client) {
    const startSnippet =
        '@OptIn(UnstableInspektorAPI::class)\n'
        'InspektorRemote.start()';
    const startBody =
        'Call it once, early: in Application.onCreate on Android, or when '
        'the app launches on iOS. It returns at once and is safe to call '
        'again. There is no password, so while it runs other apps on the '
        'device could read the traffic. Keep it to debug and test builds.';
    final versionNote = _Link(
      label: 'Replace <version> with the latest release',
      url: NetworkGuideLinks.mavenCentral,
      dense: true,
    );
    return switch (client) {
      _Client.okhttp => [
        _Step(
          number: 1,
          title: 'Add Inspektor to the debug build',
          body:
              'Release builds get the no-op twins: the same API, doing '
              'nothing, so your code compiles in both and users never get '
              'Inspektor.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Snippet(
                caption: 'app/build.gradle.kts',
                code:
                    'dependencies {\n'
                    '    debugImplementation("com.gyanoba.inspektor:inspektor-okhttp:<version>")\n'
                    '    debugImplementation("com.gyanoba.inspektor:inspektor-ui:<version>")\n'
                    '    releaseImplementation("com.gyanoba.inspektor:inspektor-okhttp-no-op:<version>")\n'
                    '    releaseImplementation("com.gyanoba.inspektor:inspektor-ui-no-op:<version>")\n'
                    '}',
              ),
              versionNote,
            ],
          ),
        ),
        const _Step(
          number: 2,
          title: 'Record your client’s traffic',
          body: 'Add the interceptor where you build the OkHttpClient.',
          child: _Snippet(
            code:
                'val client = OkHttpClient.Builder()\n'
                '    .installInspektor { level = LogLevel.BODY }\n'
                '    .build()',
          ),
        ),
        const _Step(
          number: 3,
          title: 'Turn on remote inspection',
          body: startBody,
          child: _Snippet(code: startSnippet),
        ),
      ],
      _Client.ktor => [
        _Step(
          number: 1,
          title: 'Add Inspektor to the debug build',
          body:
              'Release builds get the no-op twin: the same API, doing '
              'nothing. For Kotlin Multiplatform shared code, the README '
              'shows how to swap it in.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Snippet(
                caption: 'app/build.gradle.kts',
                code:
                    'dependencies {\n'
                    '    debugImplementation("com.gyanoba.inspektor:inspektor:<version>")\n'
                    '    releaseImplementation("com.gyanoba.inspektor:inspektor-no-op:<version>")\n'
                    '}',
              ),
              versionNote,
            ],
          ),
        ),
        const _Step(
          number: 2,
          title: 'Record your client’s traffic',
          body: 'Install the plugin in your HttpClient.',
          child: _Snippet(
            code:
                'val client = HttpClient {\n'
                '    install(Inspektor)\n'
                '}',
          ),
        ),
        const _Step(
          number: 3,
          title: 'Turn on remote inspection',
          body: startBody,
          child: _Snippet(code: startSnippet),
        ),
      ],
      _Client.urlSessionKotlin => [
        _Step(
          number: 1,
          title: 'Add Inspektor to the iOS source set',
          body:
              'Also add -lsqlite3 to Other Linker Flags in Xcode. For '
              'release builds, swap in inspektor-urlsession-no-op as the '
              'README shows.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Snippet(
                caption: 'shared/build.gradle.kts',
                code:
                    'kotlin {\n'
                    '    sourceSets.iosMain.dependencies {\n'
                    '        implementation("com.gyanoba.inspektor:inspektor-urlsession:<version>")\n'
                    '    }\n'
                    '}',
              ),
              versionNote,
            ],
          ),
        ),
        const _Step(
          number: 2,
          title: 'Record your session’s traffic',
          body:
              'Build the NSURLSession with Inspektor’s delegate. Tasks made '
              'with a completion handler skip delegates; the README covers '
              'InspektorUrlProtocol for those.',
          child: _Snippet(
            code:
                'val session = inspektorUrlSession {\n'
                '    level = LogLevel.BODY\n'
                '}',
          ),
        ),
        const _Step(
          number: 3,
          title: 'Turn on remote inspection',
          body: startBody,
          child: _Snippet(code: startSnippet),
        ),
      ],
      _Client.swift => [
        const _Step(
          number: 1,
          title: 'Build the framework and add the pod',
          body:
              'Inspektor isn’t on CocoaPods yet, so build it from a checkout '
              'of the Inspektor repository and point your Podfile at it. List '
              'only development configurations.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Snippet(
                caption: 'In the Inspektor checkout',
                code:
                    './gradlew :inspektor-urlsession:'
                    'assembleInspektorUrlSessionReleaseXCFramework',
              ),
              _Snippet(
                caption: 'ios/Podfile',
                code:
                    "pod 'InspektorUrlSession', :path => '../inspektor',\n"
                    "    :configurations => ['Debug']",
              ),
            ],
          ),
        ),
        const _Step(
          number: 2,
          title: 'Record traffic and turn on remote inspection',
          body:
              'At launch, in application(_:didFinishLaunchingWithOptions:). '
              'This records URLSession.shared; a session built from its own '
              'configuration also needs addTo(configuration:). There is no '
              'password, so keep it out of builds that reach users.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Snippet(
                caption: 'AppDelegate.swift',
                code:
                    '#if canImport(InspektorUrlSession)\n'
                    'import InspektorUrlSession\n'
                    '#endif\n'
                    '\n'
                    '#if canImport(InspektorUrlSession)\n'
                    'InspektorUrlProtocolBridge.shared.register(\n'
                    '    loaderConfiguration: .default\n'
                    ') { \$0.level = .body }\n'
                    'InspektorRemote.shared.start()\n'
                    '#endif',
              ),
              _Link(
                label: 'React Native: the README shows the session hook',
                url: NetworkGuideLinks.inspektorSwift,
                dense: true,
              ),
            ],
          ),
        ),
      ],
    };
  }
}

/// One line saying whether Eagly is looking for apps, and what it found.
class const _WatchStatus({required final NetworkController controller})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.eaglyTheme;
    final device = controller.device.displayName;
    final apps = [
      for (final source in controller.sources)
        if (source.kind == NetworkSourceKind.inspektor &&
            source.status == NetworkSourceStatus.live)
          source.label,
    ];
    final (color, text) = switch ((controller.isConnected, apps)) {
      (_, [_, ...]) => (
        tokens.statusLiveColor,
        'Connected to ${apps.join(', ')}. Use the app and its requests '
            'show up here.',
      ),
      (true, _) => (
        tokens.statusPausedColor,
        'Looking for apps with Inspektor on $device…',
      ),
      (false, _) => (
        tokens.statusStoppedColor,
        '$device is disconnected. Reconnect it to see its apps’ traffic.',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const Gap(10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// A numbered step, with a rail joining it to the next one.
class const _Step({
  required final int number,
  required final String title,
  required final String? body,
  final Widget? child,
  final bool done = false,
  final bool isLast = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final badgeColor = done ? context.eaglyTheme.statusLiveColor : cs.primary;
    // The rail is laid over the row rather than sized with it: measuring the
    // row's intrinsic height overestimates the code blocks' scroll views.
    return Stack(
      children: [
        if (!isLast)
          Positioned(
            left: 11.5,
            top: 28,
            bottom: 4,
            child: Container(width: 1, color: cs.outlineVariant),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: done
                  ? Icon(Icons.check, size: 15, color: badgeColor)
                  : Text(
                      '$number',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const Gap(12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    if (body != null) ...[const Gap(4), _Paragraph(body!)],
                    if (child != null) ...[const Gap(8), child!],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Code to paste, in the app's monospace face, with a copy button.
class const _Snippet({required final String code, final String? caption})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      caption ?? '',
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ),
                  AppIconButton(
                    tooltip: 'Copy',
                    icon: Icons.copy_rounded,
                    iconSize: 15,
                    padding: 4,
                    color: muted,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      FeatureView.showSnackBar(context, 'Copied to clipboard.');
                    },
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                code,
                style: context.eaglyTheme.monoStyle.copyWith(
                  fontSize: 12,
                  height: 1.45,
                  color: cs.onSurface,
                  // Show `=>` and `::` as typed, not as JetBrains Mono's
                  // ligatures, for anyone copying by hand.
                  fontFeatures: const [FontFeature.disable('calt')],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _Heading(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class const _Paragraph(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.45,
      ),
    );
  }
}

class const _Bullet(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 10),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(color: muted, shape: BoxShape.circle),
            ),
          ),
          Expanded(child: _Paragraph(text)),
        ],
      ),
    );
  }
}

class const _Tag(final String label) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

/// A line that opens [url] in the browser.
class const _Link({
  required final String label,
  required final String url,
  final bool dense = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Tooltip(
      message: url,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => openExternalUrl(url),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: dense ? 2 : 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style:
                      (dense
                              ? theme.textTheme.bodySmall
                              : theme.textTheme.bodyMedium)
                          ?.copyWith(color: color),
                ),
              ),
              const Gap(4),
              Icon(Icons.open_in_new, size: dense ? 13 : 15, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class const _SectionDivider() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 22),
    child: Divider(height: 1),
  );
}
