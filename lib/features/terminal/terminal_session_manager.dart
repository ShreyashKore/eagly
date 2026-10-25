import '../../session/device_session_controller.dart';
import '../../session/tab_list_manager.dart';
import 'terminal_controller.dart';

/// Manages the ordered list of terminal tabs for one device session, the same
/// way `LogSessionManager` does for log tabs: the first tab is permanent, any
/// number of extra tabs can be opened and closed.
///
/// Each tab is an independent [TerminalController] with its own scrollback,
/// history and target device — so one tab can sit on `adb logcat` while another
/// pokes at a second device.
class TerminalSessionManager({required final DeviceSessionController _session})
    extends TabListManager<TerminalController> {
  this {
    appendTab(TerminalController(_session), notify: false);
  }

  TerminalController get selectedTab => tabAt(selectedIndex);

  /// Human-readable label for the tab at [index]. A tab pointed at another
  /// device says so, since that is the thing worth noticing at a glance.
  String labelFor(int index) {
    final tab = tabAt(index);
    if (tab.isPinnedElsewhere) return tab.targetDevice.displayName;
    return index == 0 ? 'Terminal' : 'Terminal ${index + 1}';
  }

  /// The first tab is permanent; the rest can be closed.
  @override
  bool canClose(int index) => index > 0 && index < tabCount;

  void addTab() {
    if (isDisposed) return;
    appendTab(TerminalController(_session));
  }
}
