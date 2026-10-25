import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/components/snack_bars.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../settings/components/settings_section_card.dart';
import '../mcp_server_controller.dart';

/// Settings → MCP server: the switch, where the server listens, and what to
/// paste into an agent to connect it.
class const McpSettingsSection({
  super.key,
  required final McpServerController controller,
}) extends StatefulWidget {
  @override
  State<McpSettingsSection> createState() => _McpSettingsSectionState();
}

class _McpSettingsSectionState extends State<McpSettingsSection> {
  late final TextEditingController _portController = TextEditingController(
    text: '${widget.controller.port}',
  );

  McpServerController get _server => widget.controller;

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  Future<void> _applyPort() async {
    final parsed = int.tryParse(_portController.text.trim());
    if (parsed == null || parsed < 1024 || parsed > 65535) {
      showMessageSnackBar(context, 'The port must be between 1024 and 65535.');
      return;
    }
    await _server.setPort(parsed);
    if (mounted) {
      showMessageSnackBar(context, 'MCP server port set to $parsed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eagly = context.eaglyTheme;
    final mono = eagly.monoStyle.copyWith(
      fontSize: theme.textTheme.bodySmall?.fontSize,
      height: 1.4,
    );
    return ListenableBuilder(
      listenable: _server,
      builder: (context, _) => SettingsSectionCard(
        title: 'MCP server',
        children: [
          SwitchListTile(
            dense: true,
            value: _server.enabled,
            title: const Text('Let coding agents read device state'),
            subtitle: const Text(
              'Claude Code, Cursor and other MCP clients on this computer can '
              'read logs, crash reports, captured network traffic and '
              'screenshots. Read-only; listens on this computer only.',
            ),
            onChanged: (value) => _server.setEnabled(value),
          ),
          ListTile(
            dense: true,
            title: const Text('Status'),
            subtitle: Text(
              _statusText(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _server.status == McpServerStatus.failed
                    ? theme.colorScheme.error
                    : eagly.secondaryTextColor,
              ),
            ),
            trailing: _server.status == McpServerStatus.failed
                ? TextButton(
                    onPressed: _server.retry,
                    child: const Text('Retry'),
                  )
                : null,
          ),
          SettingsRow(
            child: Row(
              children: [
                const Expanded(child: Text('Port')),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '${McpServerController.defaultPort}',
                    ),
                    onSubmitted: (_) => _applyPort(),
                  ),
                ),
                const Gap(12),
                FilledButton(onPressed: _applyPort, child: const Text('Apply')),
              ],
            ),
          ),
          _SnippetRow(
            title: 'Add to Claude Code',
            text: _server.claudeCommand,
            style: mono,
            copiedMessage: 'Command copied.',
          ),
          _SnippetRow(
            title: 'JSON config (Cursor, VS Code, .mcp.json)',
            text: _server.jsonConfig,
            style: mono,
            copiedMessage: 'Config copied.',
          ),
          SwitchListTile(
            dense: true,
            value: _server.requireToken,
            title: const Text('Require an access token'),
            subtitle: const Text(
              'Only clients that send the token can connect. Turn it on if '
              'other people use accounts on this computer. Web pages are '
              'refused either way.',
            ),
            onChanged: (value) => _server.setRequireToken(value),
          ),
          if (_server.requireToken)
            ListTile(
              dense: true,
              title: const Text('Token'),
              subtitle: Text('${_server.token.substring(0, 8)}…', style: mono),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconButton(
                    tooltip: 'Copy token',
                    icon: Icons.copy_outlined,
                    onPressed: () =>
                        copyWithToast(context, _server.token, 'Token copied.'),
                  ),
                  TextButton(
                    onPressed: _server.regenerateToken,
                    child: const Text('Regenerate'),
                  ),
                ],
              ),
            ),
          SwitchListTile(
            dense: true,
            value: _server.redactHeaders,
            title: const Text('Hide credentials in network headers'),
            subtitle: const Text(
              'Authorization, cookies and token-like headers reach the agent '
              'as their length only',
            ),
            onChanged: _server.setRedactHeaders,
          ),
        ],
      ),
    );
  }

  String _statusText() {
    final client = _server.lastClient;
    return switch (_server.status) {
      McpServerStatus.off => 'Off',
      McpServerStatus.starting => 'Starting…',
      McpServerStatus.failed => _server.error ?? 'Not running',
      McpServerStatus.running =>
        'Listening on ${_server.url}'
            '${client == null ? '' : ' · last client: ${client.name}'}',
    };
  }
}

/// A snippet to paste somewhere else, with a copy button.
class const _SnippetRow({
  required final String title,
  required final String text,
  required final TextStyle style,
  required final String copiedMessage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(title),
    subtitle: SelectableText(text, style: style),
    trailing: AppIconButton(
      tooltip: 'Copy',
      icon: Icons.copy_outlined,
      onPressed: () => copyWithToast(context, text, copiedMessage),
    ),
  );
}
