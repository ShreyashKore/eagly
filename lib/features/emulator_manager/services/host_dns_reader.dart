import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Reads the DNS servers this machine is currently using, so an emulator can
/// be booted with the same ones (`emulator -dns-server`).
///
/// The emulator's default resolver setup breaks on hosts behind a VPN, split
/// DNS or a local resolver — the guest comes up "online" but resolves nothing.
/// Handing it the host's own servers fixes that, and reading them at launch
/// time (rather than storing them) keeps it right after a Wi-Fi or VPN switch.
///
/// Returns an empty list when nothing could be read; never throws.
class HostDnsReader {
  const HostDnsReader();

  static const Duration _timeout = Duration(seconds: 5);

  Future<List<String>> read() async {
    try {
      if (Platform.isMacOS) {
        return parseScutil(await _run('scutil', ['--dns']));
      }
      if (Platform.isLinux) {
        return parseResolvConf(await File('/etc/resolv.conf').readAsString());
      }
      if (Platform.isWindows) {
        return parseLines(
          await _run('powershell', [
            '-NoProfile',
            '-Command',
            '(Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses',
          ]),
        );
      }
    } catch (_) {
      // Fall through: no servers is a state the caller reports.
    }
    return const [];
  }

  Future<String> _run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments).timeout(_timeout);
    return result.exitCode == 0 ? '${result.stdout}' : '';
  }

  /// `scutil --dns` lists every resolver, each with `nameserver[n] : <ip>`
  /// lines; the same server shows up under several resolvers.
  @visibleForTesting
  static List<String> parseScutil(String output) => _unique(
    RegExp(
      r'^\s*nameserver\[\d+\]\s*:\s*(\S+)',
      multiLine: true,
    ).allMatches(output).map((match) => match.group(1)!),
  );

  @visibleForTesting
  static List<String> parseResolvConf(String contents) => _unique(
    RegExp(
      r'^\s*nameserver\s+(\S+)',
      multiLine: true,
    ).allMatches(contents).map((match) => match.group(1)!),
  );

  @visibleForTesting
  static List<String> parseLines(String output) =>
      _unique(const LineSplitter().convert(output).map((line) => line.trim()));

  /// De-duplicated, in first-seen order, keeping only IPv4 addresses — the
  /// emulator's `-dns-server` rejects anything it cannot parse, and one bad
  /// entry fails the whole list.
  static List<String> _unique(Iterable<String> candidates) {
    final seen = <String>{};
    return [
      for (final candidate in candidates)
        if (_ipv4.hasMatch(candidate) && seen.add(candidate)) candidate,
    ];
  }

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
}
