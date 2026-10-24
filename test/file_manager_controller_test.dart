import 'package:eagly/data/device.dart';
import 'package:eagly/features/file_manager/data/device_file_entry.dart';
import 'package:eagly/features/file_manager/data/file_view_options.dart';
import 'package:eagly/features/file_manager/file_manager_controller.dart';
import 'package:eagly/features/file_manager/services/device_file_system.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 25, 15);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    FileManagerController.clock = () => now;
  });

  tearDown(() {
    FileManagerController.fileSystemFactory = null;
    FileManagerController.clock = DateTime.now;
  });

  DeviceFileEntry dir(String path, {DateTime? modified}) => DeviceFileEntry(
    name: path.split('/').last,
    path: path,
    type: DeviceFileType.directory,
    modified: modified,
  );

  DeviceFileEntry file(String path, {int size = 0, DateTime? modified}) =>
      DeviceFileEntry(
        name: path.split('/').last,
        path: path,
        type: DeviceFileType.file,
        sizeBytes: size,
        modified: modified,
      );

  final listings = <String, List<DeviceFileEntry>>{
    '/sdcard': [
      file('/sdcard/IMG_10.jpg', size: 300, modified: now),
      file('/sdcard/IMG_2.jpg', size: 100, modified: DateTime(2026, 10, 24)),
      file('/sdcard/notes.txt', size: 200, modified: DateTime(2025, 3, 1)),
      file('/sdcard/.nomedia'),
      dir('/sdcard/DCIM', modified: DateTime(2026, 10, 20)),
      dir('/sdcard/Android'),
    ],
    '/sdcard/DCIM': [file('/sdcard/DCIM/a.jpg')],
    '/': [dir('/sdcard')],
  };

  Future<FileManagerController> controller() async {
    FileManagerController.fileSystemFactory = (_) => _FakeFileSystem(listings);
    final device = Device(
      'emulator-5554',
      'device',
      platform: DevicePlatform.android,
    );
    final session = DeviceSessionController(
      device: device,
      service: FakeSessionService(device),
    );
    addTearDown(session.dispose);
    final controller = session.fileManagerController;
    await controller.refresh();
    return controller;
  }

  List<String> names(FileManagerController c) => [
    for (final entry in c.entries) entry.name,
  ];

  test('sorts folders first, then by name in natural order', () async {
    final c = await controller();
    expect(names(c), [
      'Android',
      'DCIM',
      '.nomedia',
      'IMG_2.jpg',
      'IMG_10.jpg',
      'notes.txt',
    ]);

    c.setSort(FileSortField.name);
    expect(names(c).first, 'DCIM', reason: 'a second click reverses');
  });

  test('a new sort field starts in its natural direction', () async {
    final c = await controller();
    c.setSort(FileSortField.size);
    expect(c.sortAscending, isFalse);
    expect(names(c).skip(2), [
      'IMG_10.jpg',
      'notes.txt',
      'IMG_2.jpg',
      '.nomedia',
    ]);
    expect(PreferencesService.filesSortField, FileSortField.size);
    expect(PreferencesService.filesSortAscending, isFalse);
  });

  test('folders mix in when folders-first is off', () async {
    final c = await controller();
    c.setFoldersFirst(false);
    expect(names(c), [
      '.nomedia',
      'Android',
      'DCIM',
      'IMG_2.jpg',
      'IMG_10.jpg',
      'notes.txt',
    ]);
  });

  test('filters by substring, or a whole-name glob', () async {
    final c = await controller();
    c.setFilterText('img');
    expect(names(c), ['IMG_2.jpg', 'IMG_10.jpg']);
    c.setFilterText('*.TXT');
    expect(names(c), ['notes.txt']);
    c.setFilterText('IMG_?.jpg');
    expect(names(c), ['IMG_2.jpg']);
    expect(c.isFiltered, isTrue);
  });

  test('hides dotfiles on request and counts them', () async {
    final c = await controller();
    c.setShowHidden(false);
    expect(names(c), isNot(contains('.nomedia')));
    expect(c.hiddenCount, 1);
    expect(c.entryCount, 6);
  });

  test('groups by kind in kind order', () async {
    final c = await controller();
    c.setGrouping(FileGrouping.kind);
    expect(
      [for (final g in c.groups) g.label],
      ['Folders', 'Images', 'Documents', 'Other'],
    );
    expect(names(c).take(2), ['Android', 'DCIM']);
  });

  test('groups by date modified, newest bucket first', () async {
    final c = await controller();
    c.setGrouping(FileGrouping.modified);
    expect(
      {
        for (final g in c.groups) g.label: [for (final e in g.entries) e.name],
      },
      {
        'Today': ['IMG_10.jpg'],
        'Yesterday': ['IMG_2.jpg'],
        'Previous 7 days': ['DCIM'],
        'Older': ['notes.txt'],
        'Unknown date': ['Android', '.nomedia'],
      },
    );
  });

  test('keyboard moves skip a collapsed group', () async {
    final c = await controller();
    c.setGrouping(FileGrouping.kind);
    c.toggleGroupCollapsed(c.groups.first);
    c.moveSelection(1);
    expect(c.selectedEntry?.name, 'IMG_2.jpg');
    c.moveSelection(-5);
    expect(c.selectedEntry?.name, 'IMG_2.jpg', reason: 'stops at the start');
  });

  test('leaving a folder clears the filter and going up selects it', () async {
    final c = await controller();
    c.setFilterText('DC');
    await c.open(c.entries.single);
    expect(c.currentPath, '/sdcard/DCIM');
    expect(c.filterText, isEmpty);

    await c.navigateUp();
    expect(c.selectedEntry?.path, '/sdcard/DCIM');

    await c.refresh();
    expect(c.selectedEntry?.path, '/sdcard/DCIM', reason: 'refresh keeps it');
  });

  test('compareFileNames orders digit runs by value', () {
    final sorted = ['a10', 'a2', 'A1', 'a02b', 'b', 'a']
      ..sort(compareFileNames);
    expect(sorted, ['a', 'A1', 'a2', 'a02b', 'a10', 'b']);
  });
}

class _FakeFileSystem(final Map<String, List<DeviceFileEntry>> listings)
    implements DeviceFileSystem {
  @override
  String get initialPath => '/sdcard';

  @override
  String get rootPath => '/';

  @override
  Future<List<DeviceFileEntry>> list(String path) async => listings[path]!;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
