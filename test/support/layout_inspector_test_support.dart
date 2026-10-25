import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A stand-in for the on-device helper's `adb shell` process, speaking its
/// protocol (inspector_helper/, `Main.java`): JSON lines in on stdin, out on
/// stdout. Requests are answered by [respond]; closing stdin exits it, as
/// the real helper does.
class FakeHelperProcess implements Process {
  FakeHelperProcess({this.respond, bool sayHello = true}) {
    stdin = IOSink(_StdinConsumer(this));
    if (sayHello) send({'event': 'hello', 'protocol': 1, 'sdk': 34});
  }

  final StreamController<List<int>> _stdout = StreamController();
  final StreamController<List<int>> _stderr = StreamController();
  final Completer<int> _exit = Completer();

  /// The result for a request; null answers `{}`. Throw to answer an error.
  Map<String, Object?>? Function(String method, Map<String, Object?> params)?
  respond;

  /// Every request received, in order.
  final List<Map<String, Object?>> requests = [];

  List<String> get methods => [
    for (final request in requests) request['method'] as String,
  ];

  bool get hasExited => _exit.isCompleted;

  void send(Map<String, Object?> message) {
    if (!_stdout.isClosed) _stdout.add(utf8.encode('${jsonEncode(message)}\n'));
  }

  void sendChanged() => send({'event': 'changed'});

  void writeStderr(String text) {
    if (!_stderr.isClosed) _stderr.add(utf8.encode(text));
  }

  void exit(int code) {
    if (_exit.isCompleted) return;
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    _exit.complete(code);
  }

  void _handle(String line) {
    final request = (jsonDecode(line) as Map).cast<String, Object?>();
    requests.add(request);
    final params =
        (request['params'] as Map?)?.cast<String, Object?>() ?? const {};
    try {
      final result =
          respond?.call(request['method'] as String, params) ?? const {};
      send({'id': request['id'], 'result': result});
    } catch (error) {
      send({'id': request['id'], 'error': '$error'});
    }
  }

  @override
  late final IOSink stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    exit(-9);
    return true;
  }
}

class _StdinConsumer implements StreamConsumer<List<int>> {
  _StdinConsumer(this._process);

  final FakeHelperProcess _process;
  final StringBuffer _pending = StringBuffer();

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _pending.write(utf8.decode(chunk));
      var text = _pending.toString();
      var newline = text.indexOf('\n');
      while (newline >= 0) {
        final line = text.substring(0, newline);
        text = text.substring(newline + 1);
        if (line.trim().isNotEmpty) _process._handle(line);
        newline = text.indexOf('\n');
      }
      _pending
        ..clear()
        ..write(text);
    }
  }

  @override
  Future<void> close() async => _process.exit(0);
}

/// A helper `snapshot` result: an app window with a toolbar, a list and a
/// button, under a status bar.
Map<String, Object?> helperSnapshotResult({String buttonText = 'Sign in'}) => {
  'display': {'width': 1080, 'height': 2400, 'rotation': 0, 'density': 420},
  'windows': [
    {
      'id': 3,
      'type': 'system',
      'layer': 2,
      'bounds': [0, 0, 1080, 128],
      'root': {
        'class': 'android.widget.FrameLayout',
        'package': 'com.android.systemui',
        'bounds': [0, 0, 1080, 128],
        'flags': ['enabled', 'visible'],
      },
    },
    {
      'id': 7,
      'type': 'application',
      'title': 'Example',
      'layer': 1,
      'active': true,
      'bounds': [0, 0, 1080, 2400],
      'root': {
        'class': 'android.widget.FrameLayout',
        'package': 'com.example.app',
        'bounds': [0, 0, 1080, 2400],
        'flags': ['enabled', 'visible'],
        'children': [
          {
            'class': 'android.widget.TextView',
            'package': 'com.example.app',
            'resourceId': 'com.example.app:id/title',
            'text': 'Welcome',
            'bounds': [48, 160, 1032, 260],
            'flags': ['enabled', 'visible'],
          },
          {
            'class': 'android.widget.Button',
            'package': 'com.example.app',
            'resourceId': 'com.example.app:id/sign_in',
            'text': buttonText,
            'bounds': [48, 2100, 1032, 2244],
            'flags': ['clickable', 'enabled', 'focusable', 'visible'],
          },
        ],
      },
    },
  ],
  'treeMs': 3,
  'elapsedMs': 5,
};

/// `dumpsys activity top` for [helperSnapshotResult]'s app, behind the
/// launcher's task.
const dumpsysActivityTop = '''
TASK null id=11 userId=0 displayId=0(type=INTERNAL)
  ACTIVITY com.android.launcher/.Launcher 6da6527 pid=28052 userId=0 uid=10162 displayId=0(type=INTERNAL)
    Local Activity 319fa29 State:
      mResumed=false mStopped=true mFinished=false
    View Hierarchy:
      DecorView@4273ad2[Launcher]
        android.widget.FrameLayout{a01b141 V.E...... ........ 0,0-1080,2400}
    Looper (main, tid 2) {4766249}
TASK 10195:com.example.app id=22 userId=0 displayId=0(type=INTERNAL)
  ACTIVITY com.example.app/.MainActivity bb81167 pid=13470 userId=0 uid=10195 displayId=0(type=INTERNAL)
    Local Activity 25bc626 State:
      mResumed=true mStopped=false mFinished=false
    View Hierarchy:
      DecorView@e441fd3[MainActivity]
        android.widget.LinearLayout{86bdbb4 V.E...... ........ 0,0-1080,2400}
          android.view.ViewStub{41593dd G.E...... ......I. 0,0-0,0 #10201ca android:id/action_mode_bar_stub}
          com.example.app.ui.HeaderView{a2b7b52 V.E...... ........ 48,160-1032,260 #7f0a0136 app:id/title aid=1073741826}
          i{holder=b{controllerAttached=true}}
          com.google.android.material.button.MaterialButton{782ae23 VFED..C.. ...P.... 48,2100-1032,2244 #7f0a0140 app:id/sign_in}
    Looper (main, tid 2) {4766249}
''';

/// `adb exec-out uiautomator dump /dev/tty`, trailer included.
const uiautomatorDumpOutput =
    "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>"
    '<hierarchy rotation="1">'
    '<node index="0" text="" resource-id="" class="android.widget.FrameLayout" package="com.example.app" content-desc="" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" scrollable="false" long-clickable="false" password="false" selected="false" bounds="[0,0][2400,1080]">'
    '<node index="0" text="Say &quot;hi&quot;" resource-id="com.example.app:id/greeting" class="android.widget.TextView" package="com.example.app" content-desc="" checkable="false" checked="false" clickable="true" enabled="true" focusable="true" focused="false" scrollable="false" long-clickable="false" password="false" selected="false" bounds="[100,100][700,200]" />'
    '<node index="1" text="" resource-id="" class="android.widget.ImageView" package="com.example.app" content-desc="Profile" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" scrollable="false" long-clickable="false" password="false" selected="false" bounds="[0,0][2400,1080]" />'
    '</node></hierarchy>UI hierchary dumped to: /dev/tty\n';
