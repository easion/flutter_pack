// ignore_for_file: avoid_print, implementation_imports

import 'dart:async';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/bundle.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/logger.dart';

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/base/utils.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/create.dart';
import 'package:flutter_tools/src/flutter_project_metadata.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tools/src/template.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/base/platform.dart';

import 'package:flutter_tools/src/build_system/targets/common.dart';
import 'package:flutter_tools/src/build_info.dart';

import 'package:flutter_tools/src/artifacts.dart';

import 'package:package_config/package_config.dart';
import 'package:file/file.dart';
import 'common.dart';
import 'dart:convert';
import 'dart:io' as io;
import 'package:path/path.dart' as path;

import 'common.dart';

class cleanCacheCommand extends Command<int> {
  @override
  String get name => 'clean';

  @override
  String get description => 'delete flutter_pack\'s cache files.';

  ArtifactsGenerator getArtifacts() {
    return () => CachedArtifacts(
          fileSystem: globals.fs,
          cache: globals.cache,
          platform: globals.platform,
          operatingSystemUtils: globals.os,
        );
  }

  void deleteEngineSubfolders(String engineDir, String subdir) {
    final folder1 = io.Directory('$engineDir/$subdir');

    if (folder1.existsSync()) {
      folder1.deleteSync(recursive: true);
    }
  }

  @override
  Future<int> run() async {
    Cache.flutterRoot = await getFlutterRoot();

    await runInContext(
      verbose: globalResults!['verbose'],
      artifactsGenerator: getArtifacts(),
      runner: () async {
        try {
          final engineDir = globals.cache.getArtifactDirectory('engine').path;
          print("------engineDir = ${engineDir}--------");
          deleteEngineSubfolders(engineDir, "flutterpack-rk3399");
          deleteEngineSubfolders(engineDir, "sample_app");
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
