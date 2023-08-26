// ignore_for_file: avoid_print, implementation_imports

import 'dart:async';
import 'dart:io' as io;
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:package_config/package_config.dart';
import 'package:file/file.dart';
import 'create.dart';
import 'precache.dart';
import 'build.dart';
import 'clean.dart';

Never exitWithUsage(ArgParser parser,
    {String? errorMessage, int exitCode = 1}) {
  if (errorMessage != null) {
    print(errorMessage);
  }

  print('');
  print('Usage:');
  print('  flutter_pack [options...]');
  print('');
  print(parser.usage);
  io.exit(exitCode);
}

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>(
    'flutter_pack',
    'A tool to make development & distribution of flutter-gix apps easier.',
    usageLineLength: 120,
  );

  runner.addCommand(BuildCommand());
  runner.addCommand(PrecacheCommand());
  runner.addCommand(CreatePackageCommand());
  runner.addCommand(cleanCacheCommand());

  runner.argParser
    ..addSeparator('Other options')
    ..addFlag('verbose', negatable: false, help: 'Enable verbose logging.');

  late int exitCode;
  try {
    exitCode = await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    print(e);
    exitCode = 1;
  }
  io.exitCode = exitCode;
}
