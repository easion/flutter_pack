// ignore_for_file: avoid_print, implementation_imports

import 'dart:async';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:flutter_tools/src/bundle.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/depfile.dart';
import 'package:flutter_tools/src/build_system/targets/common.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/flutter_cache.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/isolated/mustache_template.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

import 'package:package_config/package_config.dart';
import 'package:file/file.dart';

import 'common.dart';

class PrecacheCommand extends Command<int> {
  @override
  String get name => 'precache';

  @override
  String get description =>
      'Populate the flutter_pack\'s cache of binary artifacts.';

  ArtifactsGenerator getArtifacts() {
    return () => CachedArtifacts(
          fileSystem: globals.fs,
          cache: globals.cache,
          platform: globals.platform,
          operatingSystemUtils: globals.os,
        );
  }

  @override
  Future<int> run() async {
    Cache.flutterRoot = await getFlutterRoot();

    await runInContext(
      verbose: globalResults!['verbose'],
      artifactsGenerator: getArtifacts(),
      runner: () async {
        try {
          // update the cached flutter-gix artifacts
          await flutterPackCache.updateAll(
            const {DevelopmentArtifact.universal},
            offline: false,
            //flutterpackPlatforms: FlutterpiTargetPlatform.values.toSet(),
            flutterpackPlatforms: const {
              FlutterpiTargetPlatform.rk3399,
              FlutterpiTargetPlatform.sample_app,
            },
          );
        } on ToolExit catch (e) {
          if (e.message != null) {
            globals.printError(e.message!);
          }

          return exitWithHooks(e.exitCode ?? 1,
              shutdownHooks: globals.shutdownHooks);
        }
      },
    );

    return 0;
  }
}
