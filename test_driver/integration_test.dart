import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

/// Persists what the walkthrough produces: a screenshot per screen, and — in
/// `--profile` — a frame timeline summary.
///
/// `integrationDriver` only hands the bytes over; storing them is the driver's
/// job, and the default driver discards both.
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? _]) async {
      final file = File('screenshots/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      stdout.writeln('screenshot: ${file.path} (${bytes.length} bytes)');
      return true;
    },
    responseDataCallback: (Map<String, dynamic>? data) async {
      // Null in debug — `traceAction` only records when timeline recording is
      // available, which is what makes profile mode the only honest place to
      // read these numbers.
      final timeline = data?['walkthrough_timeline'];
      if (timeline == null) {
        stdout.writeln('perf: no timeline (expected unless run with --profile)');
        return;
      }
      final summary = TimelineSummary.summarize(Timeline.fromJson(
          timeline as Map<String, dynamic>));
      await summary.writeTimelineToFile('walkthrough',
          destinationDirectory: 'build/perf', pretty: true);

      final json = summary.summaryJson;
      const keep = [
        'average_frame_build_time_millis',
        '90th_percentile_frame_build_time_millis',
        '99th_percentile_frame_build_time_millis',
        'worst_frame_build_time_millis',
        'average_frame_rasterizer_time_millis',
        '90th_percentile_frame_rasterizer_time_millis',
        '99th_percentile_frame_rasterizer_time_millis',
        'worst_frame_rasterizer_time_millis',
        'missed_frame_build_budget_count',
        'missed_frame_rasterizer_budget_count',
        'frame_count',
      ];
      stdout.writeln('=== FRAME SUMMARY ===');
      for (final k in keep) {
        if (json.containsKey(k)) stdout.writeln('$k: ${json[k]}');
      }
      stdout.writeln('=== raw: build/perf/walkthrough.timeline_summary.json');
      await File('build/perf/summary.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(json));
    },
  );
}
