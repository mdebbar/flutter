// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert' show latin1;
import 'dart:io' as io;

/// Reads the resource usage of the browser, `flutter run`, and the current
/// process from `/proc`.
///
/// Shows in the logs of a stalled web benchmark whether the stall coincides
/// with a process or the machine running out of file descriptors, memory,
/// shared memory, or sockets. Reads are best-effort: anything that cannot be
/// read is reported as `?`, and no method throws. Only works on Linux.
class ProcessResourceSampler {
  ProcessResourceSampler({
    required this.browserDebugPort,
    required this.toolPid,
    required this.serverPorts,
  });

  /// The `--remote-debugging-port` of the browser, used to find its processes.
  final int browserDebugPort;

  /// The pid of the `flutter run` process that launched the browser.
  final int toolPid;

  /// Local TCP ports served to or by the browser whose sockets are counted.
  final List<int> serverPorts;

  /// CPU ticks (user + system) of each process at the previous call.
  final Map<int, int> _previousCpuTicks = <int, int>{};
  DateTime _previousSampleTime = DateTime.now();

  /// The role of each process found by the last [summarize] or [describe] call.
  Map<int, String> _rolesByPid = <int, String>{};

  /// The highest number of open file descriptors of a process of each role
  /// since the last [takePeaks] call.
  final Map<String, int> _peakFdsByRole = <String, int>{};

  /// Whether `/proc` is available.
  static bool get isSupported => io.Platform.isLinux;

  /// Returns a single line that is cheap enough to log on every page load.
  String summarize() {
    if (!isSupported) {
      return 'resource sampling is only supported on Linux';
    }
    try {
      final List<_ProcessReport> reports = _collect();
      final String processes = reports
          .map(
            (_ProcessReport r) =>
                '${r.role}/${r.pid}:${r.fdCount}/${r.fdLimit}fd/${r.rssKiB ~/ 1024}M/${r.threads}t/${r.vmas}vma',
          )
          .join(' ');
      return 'procs[$processes] sys[${_systemSummary()}] tcp[${_tcpSummary()}]';
    } on Object catch (error) {
      return 'resource sampling failed: $error';
    }
  }

  /// Records the number of open file descriptors of the processes found by the
  /// last [summarize] or [describe] call, to find the peak between two calls of
  /// [takePeaks].
  ///
  /// Meant to be called repeatedly while the browser loads the app, as the
  /// file descriptors of a process can peak while resources load and be back
  /// down when the load is done.
  void samplePeaks() {
    if (!isSupported) {
      return;
    }
    try {
      for (final MapEntry<int, String> entry in _rolesByPid.entries) {
        final int count = _countFds(entry.key);
        if (count > (_peakFdsByRole[entry.value] ?? 0)) {
          _peakFdsByRole[entry.value] = count;
        }
      }
    } on Object {
      // Best-effort: processes exit at any time.
    }
  }

  /// Describes the peaks recorded by [samplePeaks], then forgets them.
  String takePeaks() {
    final String peaks =
        (_peakFdsByRole.entries.toList()..sort(
              (MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value),
            ))
            .map((MapEntry<String, int> e) => '${e.key}=${e.value}')
            .join(' ');
    _peakFdsByRole.clear();
    return 'peakFds[${peaks.isEmpty ? '-' : peaks}]';
  }

  /// Returns a detailed description, one entry per line, for a stalled run.
  List<String> describe() {
    if (!isSupported) {
      return <String>['resource sampling is only supported on Linux'];
    }
    try {
      final now = DateTime.now();
      final double seconds = now.difference(_previousSampleTime).inMilliseconds / 1000;
      final List<_ProcessReport> reports = _collect();
      final lines = <String>[];
      for (final r in reports) {
        final int? previousTicks = _previousCpuTicks[r.pid];
        // 100 ticks per second (CLK_TCK) on Linux.
        final cpu = previousTicks == null || seconds <= 0
            ? '?'
            : '${((r.cpuTicks - previousTicks) / seconds).round()}%';
        final String kinds =
            (r.fdKinds.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                .map((MapEntry<String, int> e) => '${e.key}=${e.value}')
                .join(' ');
        lines.add(
          '${r.role}/${r.pid} state=${r.state} fds=${r.fdCount}/${r.fdLimit} [$kinds] '
          'threads=${r.threads} vmas=${r.vmas} rss=${r.rssKiB ~/ 1024}M vsz=${r.vsizeKiB ~/ 1024}M cpu=$cpu',
        );
      }
      lines
        ..add('sys: ${_systemSummary()}')
        ..add('shm: ${_describeDevShm()}')
        ..add('tcp: ${_tcpSummary()}')
        ..add(
          'ephemeral ports: ${_readText('/proc/sys/net/ipv4/ip_local_port_range')?.trim() ?? '?'}',
        );
      return lines;
    } on Object catch (error) {
      return <String>['resource sampling failed: $error'];
    }
  }

  List<_ProcessReport> _collect() {
    final Map<int, _ProcessStat> all = _readAllProcessStats();
    final Set<int> chromePids = _findChromePids(all);
    final reports = <_ProcessReport>[];
    final now = DateTime.now();
    for (final _ProcessStat stat in all.values) {
      // Zombies are only waiting to be reaped. Their file descriptors are gone.
      if (stat.state == 'Z') {
        continue;
      }
      final String role;
      if (chromePids.contains(stat.pid)) {
        role = _chromeRole(stat);
      } else if (stat.pid == io.pid) {
        role = 'self';
      } else if (stat.pid == toolPid || _hasAncestor(stat.pid, <int>{toolPid}, all)) {
        role = stat.name;
      } else {
        continue;
      }
      final _FdInfo fds = _readFds(stat.pid);
      reports.add(
        _ProcessReport(
          pid: stat.pid,
          role: role,
          state: stat.state,
          threads: stat.threads,
          rssKiB: stat.rssKiB,
          vsizeKiB: stat.vsizeKiB,
          cpuTicks: stat.cpuTicks,
          fdCount: fds.count,
          fdKinds: fds.kinds,
          fdLimit: _readFdLimit(stat.pid),
          vmas: _countVmas(stat.pid),
        ),
      );
    }
    reports.sort((_ProcessReport a, _ProcessReport b) => a.role.compareTo(b.role));
    _rolesByPid = <int, String>{for (final _ProcessReport r in reports) r.pid: r.role};
    _previousCpuTicks
      ..clear()
      ..addEntries(reports.map((_ProcessReport r) => MapEntry<int, int>(r.pid, r.cpuTicks)));
    _previousSampleTime = now;
    return reports;
  }

  /// Finds the browser process (by its debugging port) and all its descendants.
  ///
  /// Falls back to every process named `chrome` when the browser process
  /// cannot be identified.
  Set<int> _findChromePids(Map<int, _ProcessStat> all) {
    final chromePids = <int>{};
    final roots = <int>{};
    for (final _ProcessStat stat in all.values) {
      if (!stat.name.contains('chrome')) {
        continue;
      }
      chromePids.add(stat.pid);
      final String commandLine = _readCommandLine(stat.pid);
      if (!commandLine.contains('--type=') &&
          commandLine.contains('--remote-debugging-port=$browserDebugPort')) {
        roots.add(stat.pid);
      }
    }
    if (roots.isEmpty) {
      return chromePids;
    }
    return chromePids
        .where((int pid) => roots.contains(pid) || _hasAncestor(pid, roots, all))
        .toSet();
  }

  String _chromeRole(_ProcessStat stat) {
    if (stat.name.contains('crashpad')) {
      return 'crashpad';
    }
    final String commandLine = _readCommandLine(stat.pid);
    final String? type = RegExp(r'--type=([\w-]+)').firstMatch(commandLine)?.group(1);
    switch (type) {
      case null:
        return 'browser';
      case 'renderer':
        return 'renderer';
      case 'gpu-process':
        return 'gpu';
      case 'zygote':
        return 'zygote';
      case 'utility':
        final String subType =
            RegExp(r'--utility-sub-type=([\w.]+)').firstMatch(commandLine)?.group(1) ?? '';
        if (subType.contains('NetworkService')) {
          return 'network';
        }
        if (subType.contains('StorageService')) {
          return 'storage';
        }
        return 'utility';
      default:
        return type;
    }
  }

  static bool _hasAncestor(int pid, Set<int> ancestors, Map<int, _ProcessStat> all) {
    int? current = all[pid]?.parentPid;
    // Bounded to protect against cycles in a racy snapshot.
    for (var depth = 0; depth < 32 && current != null && current > 1; depth++) {
      if (ancestors.contains(current)) {
        return true;
      }
      current = all[current]?.parentPid;
    }
    return false;
  }

  static Map<int, _ProcessStat> _readAllProcessStats() {
    final stats = <int, _ProcessStat>{};
    for (final io.FileSystemEntity entry in io.Directory('/proc').listSync(followLinks: false)) {
      final int? pid = int.tryParse(entry.path.substring('/proc/'.length));
      if (pid == null) {
        continue;
      }
      final _ProcessStat? stat = _ProcessStat.parse(pid, _readText('/proc/$pid/stat'));
      if (stat != null) {
        stats[pid] = stat;
      }
    }
    return stats;
  }

  static String _readCommandLine(int pid) {
    return _readText('/proc/$pid/cmdline')?.replaceAll('\u0000', ' ') ?? '';
  }

  static String _readFdLimit(int pid) {
    final String? limits = _readText('/proc/$pid/limits');
    if (limits == null) {
      return '?';
    }
    for (final String line in limits.split('\n')) {
      if (line.startsWith('Max open files')) {
        final List<String> columns = line
            .substring('Max open files'.length)
            .trim()
            .split(RegExp(r'\s+'));
        // Columns: soft limit, hard limit, units.
        return columns.first;
      }
    }
    return '?';
  }

  static int _countFds(int pid) {
    try {
      return io.Directory('/proc/$pid/fd').listSync(followLinks: false).length;
    } on io.FileSystemException {
      return -1;
    }
  }

  /// Counts the memory mappings (VMAs) of a process, which the kernel limits to
  /// `vm.max_map_count` per process. Returns -1 if they cannot be read.
  static int _countVmas(int pid) {
    try {
      var count = 0;
      for (final int byte in io.File('/proc/$pid/maps').readAsBytesSync()) {
        // One mapping per line.
        if (byte == 0x0A) {
          count++;
        }
      }
      return count;
    } on io.FileSystemException {
      return -1;
    }
  }

  static _FdInfo _readFds(int pid) {
    final kinds = <String, int>{};
    var count = 0;
    try {
      for (final io.FileSystemEntity entry in io.Directory(
        '/proc/$pid/fd',
      ).listSync(followLinks: false)) {
        var kind = '?';
        if (entry is io.Link) {
          try {
            kind = _fdKind(entry.targetSync());
          } on io.FileSystemException {
            // The file descriptor was closed while listing.
            kind = 'closed';
          }
        }
        kinds[kind] = (kinds[kind] ?? 0) + 1;
        count++;
      }
    } on io.FileSystemException {
      return (count: -1, kinds: const <String, int>{});
    }
    return (count: count, kinds: kinds);
  }

  static String _fdKind(String target) {
    if (target.startsWith('socket:')) {
      return 'sock';
    }
    if (target.startsWith('pipe:')) {
      return 'pipe';
    }
    if (target.startsWith('anon_inode:')) {
      return 'anon';
    }
    if (target.startsWith('/memfd:') || target.startsWith('/dev/shm/')) {
      return 'shm';
    }
    if (target.startsWith('/dev/') || target.startsWith('/proc/')) {
      return 'dev';
    }
    if (target.startsWith('/')) {
      return 'file';
    }
    return 'other';
  }

  static String _systemSummary() {
    final parts = <String>[];
    final Map<String, int> memory = _readMeminfoKiB();
    parts.add(
      'memAvail=${_formatKiB(memory['MemAvailable'])}/${_formatKiB(memory['MemTotal'])} '
      'shmem=${_formatKiB(memory['Shmem'])} '
      'swapFree=${_formatKiB(memory['SwapFree'])}',
    );
    final List<String>? fileNr = _readText('/proc/sys/fs/file-nr')?.trim().split(RegExp(r'\s+'));
    if (fileNr != null && fileNr.length >= 3) {
      parts.add('system-fds=${fileNr[0]}/${fileNr[2]}');
    }
    parts.add('maxMaps=${_readText('/proc/sys/vm/max_map_count')?.trim() ?? '?'}');
    final List<String>? load = _readText('/proc/loadavg')?.trim().split(' ');
    if (load != null && load.length >= 3) {
      parts.add('load=${load.take(3).join(',')}');
    }
    // cgroup v2, then v1.
    final String? cgroupMemory =
        _readText('/sys/fs/cgroup/memory.current') ??
        _readText('/sys/fs/cgroup/memory/memory.usage_in_bytes');
    final String? cgroupMemoryLimit =
        _readText('/sys/fs/cgroup/memory.max') ??
        _readText('/sys/fs/cgroup/memory/memory.limit_in_bytes');
    if (cgroupMemory != null) {
      parts.add('cgroupMem=${_formatBytes(cgroupMemory)}/${_formatBytes(cgroupMemoryLimit)}');
    }
    final String? cgroupPids =
        _readText('/sys/fs/cgroup/pids.current') ?? _readText('/sys/fs/cgroup/pids/pids.current');
    final String? cgroupPidsMax =
        _readText('/sys/fs/cgroup/pids.max') ?? _readText('/sys/fs/cgroup/pids/pids.max');
    if (cgroupPids != null) {
      parts.add('cgroupPids=${cgroupPids.trim()}/${cgroupPidsMax?.trim() ?? '?'}');
    }
    return parts.join(' ');
  }

  static Map<String, int> _readMeminfoKiB() {
    final values = <String, int>{};
    final String? text = _readText('/proc/meminfo');
    if (text == null) {
      return values;
    }
    for (final String line in text.split('\n')) {
      final List<String> columns = line.split(RegExp(r'\s+'));
      if (columns.length >= 2 && columns[0].endsWith(':')) {
        final int? value = int.tryParse(columns[1]);
        if (value != null) {
          values[columns[0].substring(0, columns[0].length - 1)] = value;
        }
      }
    }
    return values;
  }

  static String _formatKiB(int? kiB) {
    if (kiB == null) {
      return '?';
    }
    if (kiB >= 1024 * 1024) {
      return '${(kiB / (1024 * 1024)).toStringAsFixed(1)}G';
    }
    return '${kiB ~/ 1024}M';
  }

  static String _formatBytes(String? bytesText) {
    final String? trimmed = bytesText?.trim();
    final int? bytes = trimmed == null ? null : int.tryParse(trimmed);
    if (bytes == null) {
      // Includes "max" (cgroup v2 without a limit).
      return trimmed ?? '?';
    }
    return _formatKiB(bytes ~/ 1024);
  }

  static String _describeDevShm() {
    try {
      final io.ProcessResult result = io.Process.runSync('df', <String>['-k', '/dev/shm']);
      final List<String> lines = (result.stdout as String).trim().split('\n');
      return lines.length >= 2 ? lines[1].trim().replaceAll(RegExp(r'\s+'), ' ') : '?';
    } on io.ProcessException catch (error) {
      return 'df failed: $error';
    }
  }

  /// Counts TCP sockets by state: overall, and for the browser's side
  /// ("client", remote port is a [serverPorts] entry) and the server's side
  /// (local port is a [serverPorts] entry) of each connection to those ports.
  ///
  /// For the ports, also sums the bytes that sit in the receive (`rq`) and send
  /// (`sq`) queues of the sockets. Bytes in the receive queue of a server socket
  /// mean that the server does not read its requests, and bytes in the receive
  /// queue of a client socket mean that the browser does not read the responses.
  String _tcpSummary() {
    const states = <String, String>{
      '01': 'ESTAB',
      '02': 'SYN_SENT',
      '03': 'SYN_RECV',
      '04': 'FIN_WAIT1',
      '05': 'FIN_WAIT2',
      '06': 'TIME_WAIT',
      '07': 'CLOSE',
      '08': 'CLOSE_WAIT',
      '09': 'LAST_ACK',
      '0A': 'LISTEN',
      '0B': 'CLOSING',
    };
    final totals = _SocketCounts();
    final client = <int, _SocketCounts>{for (final int port in serverPorts) port: _SocketCounts()};
    final server = <int, _SocketCounts>{for (final int port in serverPorts) port: _SocketCounts()};
    for (final file in const <String>['/proc/net/tcp', '/proc/net/tcp6']) {
      final String? text = _readText(file);
      if (text == null) {
        continue;
      }
      for (final String line in text.split('\n').skip(1)) {
        final List<String> columns = line.trim().split(RegExp(r'\s+'));
        if (columns.length < 5) {
          continue;
        }
        final String state = states[columns[3]] ?? columns[3];
        // The queues are "<tx_queue>:<rx_queue>" in hex.
        final List<String> queues = columns[4].split(':');
        final int sendQueue = queues.length == 2 ? int.tryParse(queues[0], radix: 16) ?? 0 : 0;
        final int receiveQueue = queues.length == 2 ? int.tryParse(queues[1], radix: 16) ?? 0 : 0;
        totals.add(state, receiveQueue: 0, sendQueue: 0);
        final int? localPort = _hexPort(columns[1]);
        final int? remotePort = _hexPort(columns[2]);
        if (remotePort != null) {
          client[remotePort]?.add(state, receiveQueue: receiveQueue, sendQueue: sendQueue);
        }
        if (localPort != null && state != 'LISTEN') {
          server[localPort]?.add(state, receiveQueue: receiveQueue, sendQueue: sendQueue);
        }
      }
    }
    final ports = <String>[
      for (final int port in serverPorts)
        ':$port client{${client[port]!.describe()}} server{${server[port]!.describe()}}',
    ];
    return 'all{${totals.describe()}} ${ports.join(' ')}';
  }

  static int? _hexPort(String address) {
    final int separator = address.lastIndexOf(':');
    return separator < 0 ? null : int.tryParse(address.substring(separator + 1), radix: 16);
  }

  static String? _readText(String path) {
    try {
      // /proc files are not UTF-8 safe (e.g. command lines), so decode as Latin-1.
      return latin1.decode(io.File(path).readAsBytesSync());
    } on io.FileSystemException {
      return null;
    }
  }
}

typedef _FdInfo = ({int count, Map<String, int> kinds});

/// Counts of TCP sockets by state, and the bytes queued in their buffers.
class _SocketCounts {
  final Map<String, int> _byState = <String, int>{};
  int _receiveQueueBytes = 0;
  int _sendQueueBytes = 0;

  void add(String state, {required int receiveQueue, required int sendQueue}) {
    _byState[state] = (_byState[state] ?? 0) + 1;
    _receiveQueueBytes += receiveQueue;
    _sendQueueBytes += sendQueue;
  }

  String describe() {
    if (_byState.isEmpty) {
      return '-';
    }
    return <String>[
      _byState.entries.map((MapEntry<String, int> e) => '${e.key}=${e.value}').join(','),
      if (_receiveQueueBytes > 0) 'rq=$_receiveQueueBytes',
      if (_sendQueueBytes > 0) 'sq=$_sendQueueBytes',
    ].join(' ');
  }
}

/// The fields of `/proc/<pid>/stat` that the sampler reports.
class _ProcessStat {
  _ProcessStat({
    required this.pid,
    required this.name,
    required this.state,
    required this.parentPid,
    required this.cpuTicks,
    required this.threads,
    required this.rssKiB,
    required this.vsizeKiB,
  });

  /// Parses the contents of `/proc/<pid>/stat`.
  ///
  /// Returns null if the process exited or the contents are malformed.
  static _ProcessStat? parse(int pid, String? text) {
    if (text == null) {
      return null;
    }
    final int nameStart = text.indexOf('(');
    // The name can contain spaces and parentheses, so find the last one.
    final int nameEnd = text.lastIndexOf(')');
    if (nameStart < 0 || nameEnd < nameStart || text.length < nameEnd + 2) {
      return null;
    }
    // Fields after the name, starting at field 3 (state) of proc(5).
    final List<String> fields = text.substring(nameEnd + 2).trim().split(' ');
    if (fields.length < 22) {
      return null;
    }
    final int? parentPid = int.tryParse(fields[1]);
    final int? userTicks = int.tryParse(fields[11]);
    final int? systemTicks = int.tryParse(fields[12]);
    final int? threads = int.tryParse(fields[17]);
    final int? vsizeBytes = int.tryParse(fields[20]);
    final int? rssPages = int.tryParse(fields[21]);
    if (parentPid == null ||
        userTicks == null ||
        systemTicks == null ||
        threads == null ||
        vsizeBytes == null ||
        rssPages == null) {
      return null;
    }
    return _ProcessStat(
      pid: pid,
      name: text.substring(nameStart + 1, nameEnd),
      state: fields[0],
      parentPid: parentPid,
      cpuTicks: userTicks + systemTicks,
      threads: threads,
      // Assumes 4 KiB pages.
      rssKiB: rssPages * 4,
      vsizeKiB: vsizeBytes ~/ 1024,
    );
  }

  final int pid;
  final String name;
  final String state;
  final int parentPid;
  final int cpuTicks;
  final int threads;
  final int rssKiB;
  final int vsizeKiB;
}

class _ProcessReport {
  _ProcessReport({
    required this.pid,
    required this.role,
    required this.state,
    required this.threads,
    required this.rssKiB,
    required this.vsizeKiB,
    required this.cpuTicks,
    required this.fdCount,
    required this.fdKinds,
    required this.fdLimit,
    required this.vmas,
  });

  final int pid;
  final String role;
  final String state;
  final int threads;
  final int rssKiB;
  final int vsizeKiB;
  final int cpuTicks;

  /// The number of open file descriptors, or -1 if they cannot be listed.
  final int fdCount;

  /// The number of open file descriptors by kind (sockets, pipes, ...).
  final Map<String, int> fdKinds;

  /// The soft limit of open file descriptors.
  final String fdLimit;

  /// The number of memory mappings, or -1 if they cannot be read.
  final int vmas;
}
