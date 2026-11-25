import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Reads the DNS servers this machine is currently using, so an emulator can
/// be booted with the same ones (`emulator -dns-server`).
///
/// The emulator's default resolver setup breaks on hosts behind a VPN or a
/// local resolver — the guest comes up "online" but resolves nothing. Handing
/// it the host's own servers fixes that, and reading them at launch time
/// (rather than storing them) keeps it right after a Wi-Fi or VPN switch.
///
/// Split DNS is not carried over: names only a domain-scoped resolver knows
/// stay unresolved in the guest.
///
/// Returns an empty list when nothing could be read; never throws.
class HostDnsReader {
  const HostDnsReader();

  // Above a cold PowerShell start plus the two modules the script loads.
  static const Duration _timeout = Duration(seconds: 10);

  /// Every interface has configured servers, disconnected ones included, and
  /// the emulator takes at most four: only connected interfaces count, the one
  /// Windows prefers (lowest metric) first.
  static const String _windowsDnsScript =
      r'$dns = Get-DnsClientServerAddress -AddressFamily IPv4; '
      r'Get-NetIPInterface -AddressFamily IPv4 -ConnectionState Connected | '
      r'Sort-Object InterfaceMetric | ForEach-Object { '
      r'$index = $_.InterfaceIndex; '
      r'($dns | Where-Object { $_.InterfaceIndex -eq $index }).ServerAddresses '
      r'}';

  Future<List<String>> read() async {
    try {
      if (Platform.isMacOS) {
        return parseScutil(await run('scutil', ['--dns']));
      }
      if (Platform.isLinux) {
        return parseResolvConf(await File('/etc/resolv.conf').readAsString());
      }
      if (Platform.isWindows) {
        return parseLines(
          await run('powershell', [
            '-NoProfile',
            '-Command',
            _windowsDnsScript,
          ]),
        );
      }
    } catch (_) {
      // Fall through: no servers is a state the caller reports.
    }
    return const [];
  }

  /// The command's output, or empty when it fails. One that outlives [timeout]
  /// is killed rather than left running behind the next attempt.
  @visibleForTesting
  static Future<String> run(
    String executable,
    List<String> arguments, {
    Duration timeout = _timeout,
  }) async {
    final process = await Process.start(executable, arguments);
    final output = StringBuffer();
    final streams = [
      process.stdout.transform(systemEncoding.decoder).listen(output.write),
      process.stderr.listen((_) {}),
    ];
    try {
      final closed = streams[0].asFuture<void>();
      final (exitCode, _) = await (
        process.exitCode,
        closed,
      ).wait.timeout(timeout);
      return exitCode == 0 ? '$output' : '';
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    } finally {
      for (final stream in streams) {
        unawaited(stream.cancel());
      }
    }
  }

  /// `scutil --dns` lists every resolver, each with `nameserver[n] : <ip>`
  /// lines; the same server shows up under several resolvers.
  ///
  /// A resolver with a `domain` answers only for that domain. The guest gets a
  /// flat list it treats as interchangeable, so those are left out: offering
  /// one for ordinary names breaks them, and it would seldom be asked for its
  /// own (the guest accepts another server's "no such name").
  @visibleForTesting
  static List<String> parseScutil(String output) => _unique(
    output
        .split(RegExp(r'^resolver #\d+', multiLine: true))
        .where((resolver) => !_scutilDomain.hasMatch(resolver))
        .expand(
          (resolver) => RegExp(
            r'^\s*nameserver\[\d+\]\s*:\s*(\S+)',
            multiLine: true,
          ).allMatches(resolver),
        )
        .map((match) => match.group(1)!),
  );

  // Not `search domain[n]`, which every ordinary resolver has.
  static final RegExp _scutilDomain = RegExp(
    r'^\s*domain\s*:',
    multiLine: true,
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
