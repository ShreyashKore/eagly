import '../../../data/device.dart';
import '../mcp_tool.dart';
import 'mcp_tool_context.dart';

/// `list_devices` and `list_apps`.
List<McpTool> deviceTools(McpToolContext context) => [
  McpTool(
    name: 'list_devices',
    title: 'List devices',
    description:
        'Lists the Android devices, emulators and iPhones Eagly knows, with '
        'their ids, whether each is connected, which one is selected in Eagly '
        '(the default target of every other tool) and what Eagly can read '
        'from it.',
    inputSchema: objectSchema({}),
    handler: (_) async {
      final selectedId = context.manager.selectedId;
      return McpToolResult.json({
        'devices': [
          for (final session in context.sessions)
            {
              'id': session.id,
              'name': session.device.displayName,
              'platform': platformName(session.device),
              'model': ?session.device.model,
              'connected': session.isConnected,
              'wireless': session.device.isWireless,
              'selectedInEagly': session.id == selectedId,
              'capabilities': {
                'logs': true,
                'crashReports': session.canReadCrashReports,
                'network': session.canInspectNetwork,
                'screenshot': session.isConnected,
                'apps': session.canManageApps,
              },
            },
        ],
      });
    },
  ),
  McpTool(
    name: 'list_apps',
    title: 'List apps',
    description:
        'Lists the apps installed on a device: package name (bundle id on '
        'iOS), name, version, and whether it is a system app or a debug '
        'build.',
    inputSchema: objectSchema({
      'device': deviceProperty,
      'query': stringProperty(
        'Only apps whose package name or app name contains this text.',
      ),
      'includeSystem': booleanProperty(
        'Include preinstalled system apps.',
        defaultValue: false,
      ),
    }),
    handler: (args) async {
      final session = context.resolveConnected(args.string('device'));
      final includeSystem = args.boolean('includeSystem') ?? false;
      final query = args.string('query')?.toLowerCase();

      final apps = session.appsController;
      // The pane's list follows the user's System-apps toggle; read the
      // device directly rather than flip it.
      final list = includeSystem && !apps.showSystemApps
          ? await session.service.listApps(includeSystemApps: true)
          : await apps.ensureLoaded().then((_) => apps.apps);
      if (list.isEmpty && apps.error != null) throw McpToolError(apps.error!);

      return McpToolResult.json({
        'device': session.id,
        'apps': [
          for (final app in list)
            if ((includeSystem || !app.isSystemApp) &&
                (query == null ||
                    app.packageName.toLowerCase().contains(query) ||
                    (app.appName?.toLowerCase().contains(query) ?? false)))
              {
                'package': app.packageName,
                'name': ?app.appName,
                'versionName': ?app.versionName,
                'versionCode': ?app.versionCode,
                'systemApp': app.isSystemApp,
                'debuggable': app.isDebuggable,
                'enabled': app.isEnabled,
                if (session.device is IosDevice)
                  'logProcessName': app.logProcessName,
              },
        ],
      });
    },
  ),
];
