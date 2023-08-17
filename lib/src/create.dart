// ignore_for_file: avoid_print, implementation_imports

import 'dart:async';
import 'dart:io';
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

class FlutterpiCachedCreateAppArtifacts implements Artifacts {
  /// Creates a new [OverrideArtifacts].
  ///
  /// [parent] must be provided.
  FlutterpiCachedCreateAppArtifacts({
    required this.parent,
    required FlutterpiTargetPlatform flutterPackTargetPlatform,
    required FileSystem fileSystem,
    required Platform platform,
    required Cache cache,
    required OperatingSystemUtils operatingSystemUtils,
  })  : _flutterPackTargetPlatform = flutterPackTargetPlatform,
        _fileSystem = fileSystem,
        _cache = cache,
        _operatingSystemUtils = operatingSystemUtils;

  final FileSystem _fileSystem;
  final Cache _cache;
  final OperatingSystemUtils _operatingSystemUtils;
  final FlutterpiTargetPlatform _flutterPackTargetPlatform;
  final Artifacts parent;

  @override
  LocalEngineInfo? get localEngineInfo => parent.localEngineInfo;

  @override
  String getArtifactPath(
    Artifact artifact, {
    TargetPlatform? platform,
    BuildMode? mode,
    EnvironmentType? environmentType,
  }) {
    return parent.getArtifactPath(
      artifact,
      platform: platform,
      mode: mode,
      environmentType: environmentType,
    );
  }

  @override
  String getEngineType(TargetPlatform platform, [BuildMode? mode]) => parent.getEngineType(platform, mode);

  @override
  bool get isLocalEngine => parent.isLocalEngine;

  @override
  FileSystemEntity getHostArtifact(HostArtifact artifact) {
    return parent.getHostArtifact(artifact);
  }
}

class CreatePackageCommand extends Command<int> {
  @override
  String get name => 'create';

  @override
  String get description => 'create for flutter apps.';

  CreatePackageCommand() {
    argParser.addOption('offline', help: 'is  offline');
    //argParser.addFlag('flag', help: 'A custom flag');
  }

  ArtifactsGenerator getArtifacts() {
    return () => FlutterpiCachedCreateAppArtifacts(
          parent: CachedArtifacts(
            fileSystem: globals.fs,
            cache: globals.cache,
            platform: globals.platform,
            operatingSystemUtils: globals.os,
          ),
          flutterPackTargetPlatform: FlutterpiTargetPlatform.sample_app,
          fileSystem: globals.fs,
          platform: globals.platform,
          cache: globals.cache,
          operatingSystemUtils: globals.os,
        );
  }

  void writeToFile(String filename, String content) async {
    try {
      final file = io.File(filename);
      await file.writeAsString(content);
      print('Wrote content to file $filename');
    } catch (e) {
      print('Failed to write $filename: $e');
    }
  }

  void copyMakefileToProjectDir(Directory cachedir, Directory projectDir, String filename) {
    final cachedMakefile = io.File(path.join(cachedir.path, filename));
    final projectMakefile = io.File(path.join(projectDir.path, filename));

    if (!cachedMakefile.existsSync()) {
      print('Cached Makefile does not exist.');
      return;
    }
    try {
      if (!projectDir.existsSync()) {
        projectDir.createSync(recursive: true);
      }
      cachedMakefile.copySync(projectMakefile.path);
    } catch (error) {
      print('Error copying Makefile: $error');
    }
  }

  String replaceUnderscoreWithDash(String input) {
    return input.replaceAll(RegExp(r'_'), '-');
  }

  Future<void> setFileExecutable(String filePath) async {
    final isLinuxOrMac = io.Platform.isLinux || io.Platform.isMacOS;
    if (!isLinuxOrMac) {
      print('Currently only supports setting file permissions on Linux and Mac.');
      return;
    }
    var file = io.File(filePath);
    if (!file.existsSync()) {
      return;
    }
    try {
      final result = await io.Process.run('chmod', ['+x', filePath]);
      if (result.exitCode == 0) {
      } else {
        print('File permission setting failed: ${result.stderr}');
      }
    } catch (error) {
      print('File permission setting error: $error');
    }
  }

  @override
  Future<int> run() async {
    Cache.flutterRoot = await getFlutterRoot();

    //realCommand.argResults = argResults!; // 将 aaa 命令的参数传递给 bbb 命令
    ArgResults aaaArgs = argResults!;

    await runInContext(
      verbose: globalResults!['verbose'],
      artifactsGenerator: getArtifacts(),
      runner: () async {
        try {
          // update the cached flutter-gix artifacts
          await flutterPackCache.updateAll(
            const {DevelopmentArtifact.universal},
            offline: false,
            flutterpackPlatforms: const {
              FlutterpiTargetPlatform.sample_app,
            },
          );

          FlutterProject project = FlutterProject.current();
          String projectName = project.manifest.appName;
          final Directory projectDir = project.directory;
          print('Project name: $projectName');
          print('Project path: ${projectDir.path}');
          final cachedir =
              globals.cache.getRoot().childDirectory('artifacts').childDirectory('engine').childDirectory('sample_app');
          //print("------CACHE DIR: -${cachedir.path}------");

          if (!cachedir.existsSync()) {
            throwToolExit('Could not locate sample_app dir.');
          }

          final Directory gixTemplates = cachedir.childDirectory("gix");
          if (!projectDir.childDirectory("gix").existsSync()) {
            copyDirectory(gixTemplates, projectDir.childDirectory("gix"));
          } else {
            //print("------GIX DIR: -${gixTemplates.path} EXIST------");
          }

          final filesToMakeExecutable = [
            '${projectDir.path}/gix/ipkg-build.sh',
            '${projectDir.path}/gix/appstore/CONTROL/preinst',
            '${projectDir.path}/gix/appstore/CONTROL/postinst',
            '${projectDir.path}/gix/appstore/CONTROL/postrm',
          ];

          for (final filePath in filesToMakeExecutable) {
            if (io.File(filePath).existsSync()) {
              await setFileExecutable(filePath);
            } else {
            }
          }

          copyMakefileToProjectDir(cachedir, projectDir, 'Makefile');
          final projname = replaceUnderscoreWithDash(projectName);
          String content = 'APPNAME=${projname}\r\nAPPVERSION=1.0\r\n';
          writeToFile('${projectDir.path}/gix/build_config.mak', content);
          //final Directory eLinuxTemplates = globals.fs.directory(Cache.flutterRoot);
          //print("------eLinuxTemplates DIR: -${eLinuxTemplates.path}------");
        } on ToolExit catch (e) {
          if (e.message != null) {
            globals.printError(e.message!);
          }
          return exitWithHooks(e.exitCode ?? 1, shutdownHooks: globals.shutdownHooks);
        }
      },
    );
    return 0;
  }
}
