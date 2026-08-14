import 'dart:convert';
import 'dart:io';

/// CI coverage gate.
///
/// Usage: dart run tool/check_coverage.dart [lcov-path] [min-coverage-fraction]
///
/// Parses an lcov.info tracefile, sums LF/LH, and exits non-zero when the
/// line coverage is below the given minimum (a fraction such as 0.20).
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: dart run tool/check_coverage.dart [lcov] [min]');
    exit(2);
  }
  final lcovPath = args[0];
  final minCoverage = double.parse(args[1]);

  final file = File(lcovPath);
  if (!file.existsSync()) {
    stderr.writeln('lcov file not found: $lcovPath');
    exit(2);
  }

  var found = 0;
  var hit = 0;
  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    if (line.startsWith('LF:')) {
      found += int.tryParse(line.substring(3)) ?? 0;
    } else if (line.startsWith('LH:')) {
      hit += int.tryParse(line.substring(3)) ?? 0;
    }
  }

  if (found == 0) {
    stderr.writeln('no instrumented lines found in $lcovPath');
    exit(2);
  }

  final coverage = hit / found;
  stdout.writeln(
    'coverage: ${(coverage * 100).toStringAsFixed(1)}% '
    '($hit/$found lines), minimum ${(minCoverage * 100).toStringAsFixed(1)}%',
  );
  if (coverage < minCoverage) {
    stderr.writeln('coverage below the required minimum');
    exit(1);
  }
}
