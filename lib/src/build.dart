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
import 'package:path/path.dart' as path;

import 'common.dart';

class FlutterpiArtifactPaths {
  String getTargetDirName(FlutterpiTargetPlatform target) {
    return switch (target) {
      FlutterpiTargetPlatform.genericArmV7 => 'flutterpack-armv7-generic',
      FlutterpiTargetPlatform.genericAArch64 => 'flutterpack-aarch64-generic',
      FlutterpiTargetPlatform.genericX64 => 'flutterpack-x64-generic',
      FlutterpiTargetPlatform.pi4 => 'flutterpack-pi4',
      FlutterpiTargetPlatform.pi4_64 => 'flutterpack-pi4-64',
      FlutterpiTargetPlatform.rk3399 => 'flutterpack-rk3399',
      FlutterpiTargetPlatform.sample_app => 'sample_app',
    };
  }

  String getHostDirName(HostPlatform hostPlatform) {
    return switch (hostPlatform) {
      HostPlatform.linux_x64 => 'linux-x64',
      _ => throw UnsupportedError('Unsupported host platform: $hostPlatform'),
    };
  }

  String getGenSnapshotFilename(
      HostPlatform hostPlatform, BuildMode buildMode) {
    return switch ((hostPlatform, buildMode)) {
      (HostPlatform.linux_x64, BuildMode.profile) =>
        'gen_snapshot_linux_x64_profile',
      (HostPlatform.linux_x64, BuildMode.release) =>
        'gen_snapshot_linux_x64_release',
      _ => throw UnsupportedError(
          'Unsupported host platform & build mode combinations: $hostPlatform, $buildMode'),
    };
  }

  String getEngineFilename(BuildMode buildMode, {bool unoptimized = false}) {
    return switch ((buildMode, unoptimized)) {
      (BuildMode.debug, true) => 'libflutter_engine.so.debug_unopt',
      (BuildMode.debug, false) => 'libflutter_engine.so.debug',
      (BuildMode.profile, false) => 'libflutter_engine.so.profile',
      (BuildMode.release, false) => 'libflutter_engine.so.release',
      _ => throw UnsupportedError('Unsupported build mode: $buildMode'),
    };
  }

  File getEngine({
    required Directory engineCacheDir,
    required HostPlatform hostPlatform,
    required FlutterpiTargetPlatform flutterPackTargetPlatform,
    required BuildMode buildMode,
    bool unoptimized = false,
  }) {
    return engineCacheDir
        .childDirectory(getTargetDirName(flutterPackTargetPlatform))
        .childDirectory(getHostDirName(hostPlatform))
        .childFile(getEngineFilename(buildMode, unoptimized: unoptimized));
  }

  File getGenSnapshot({
    required Directory engineCacheDir,
    required HostPlatform hostPlatform,
    required FlutterpiTargetPlatform flutterPackTargetPlatform,
    required BuildMode buildMode,
    bool unoptimized = false,
  }) {
    return engineCacheDir
        .childDirectory(getTargetDirName(flutterPackTargetPlatform))
        .childDirectory(getHostDirName(hostPlatform))
        .childFile(getGenSnapshotFilename(hostPlatform, buildMode));
  }

  Source getEngineSource({
    String artifactSubDir = 'engine',
    required HostPlatform hostPlatform,
    required FlutterpiTargetPlatform flutterPackTargetPlatform,
    required BuildMode buildMode,
    bool unoptimized = false,
  }) {
    final targetDirName = getTargetDirName(flutterPackTargetPlatform);
    final hostDirName = getHostDirName(hostPlatform);
    final engineFileName =
        getEngineFilename(buildMode, unoptimized: unoptimized);
    final dest = Source.pattern(
        '{CACHE_DIR}/artifacts/$artifactSubDir/$targetDirName/$hostDirName/$engineFileName');
    return dest;
  }
}

/// Copies the kernel_blob.bin to the output directory.
class CopyFlutterAssets extends CopyFlutterBundle {
  const CopyFlutterAssets();

  @override
  String get name => 'bundle_flutter_pack_assets';
}

/// A wrapper for AOT compilation that copies app.so into the output directory.
class FlutterpiAppElf extends Target {
  /// Create a [FlutterpiAppElf] wrapper for [aotTarget].
  const FlutterpiAppElf(this.aotTarget);

  /// The [AotElfBase] subclass that produces the app.so.
  final AotElfBase aotTarget;

  @override
  String get name => 'flutter_pack_aot_bundle';

  @override
  List<Source> get inputs => const <Source>[
        Source.pattern('{BUILD_DIR}/app.so'),
      ];

  @override
  List<Source> get outputs => const <Source>[
        Source.pattern('{OUTPUT_DIR}/app.so'),
      ];

  @override
  List<Target> get dependencies => <Target>[
        aotTarget,
      ];

  @override
  Future<void> build(Environment environment) async {
    final File outputFile = environment.buildDir.childFile('app.so');
    outputFile.copySync(environment.outputDir.childFile('app.so').path);
  }
}

class CopyFlutterpiEngine extends Target {
  const CopyFlutterpiEngine(
    this.flutterPackTargetPlatform, {
    required BuildMode buildMode,
    required HostPlatform hostPlatform,
    bool unoptimized = false,
    required FlutterpiArtifactPaths artifactPaths,
  })  : _buildMode = buildMode,
        _hostPlatform = hostPlatform,
        _unoptimized = unoptimized,
        _artifactPaths = artifactPaths;

  final FlutterpiTargetPlatform flutterPackTargetPlatform;
  final BuildMode _buildMode;
  final HostPlatform _hostPlatform;
  final bool _unoptimized;
  final FlutterpiArtifactPaths _artifactPaths;

  @override
  List<Target> get dependencies => [];

  @override
  List<Source> get inputs => [
        _artifactPaths.getEngineSource(
          hostPlatform: _hostPlatform,
          flutterPackTargetPlatform: flutterPackTargetPlatform,
          buildMode: _buildMode,
          unoptimized: _unoptimized,
        )
      ];

  @override
  String get name =>
      'copy_flutter_pack_engine_${flutterPackTargetPlatform.shortName}_$_buildMode${_unoptimized ? '_unopt' : ''}';

  @override
  List<Source> get outputs => [
        const Source.pattern('{OUTPUT_DIR}/libflutter_engine.so'),
      ];

  @override
  Future<void> build(Environment environment) async {
    final outputFile = environment.outputDir.childFile('libflutter_engine.so');
    if (!outputFile.parent.existsSync()) {
      outputFile.parent.createSync(recursive: true);
    }

    _artifactPaths
        .getEngine(
          engineCacheDir: environment.cacheDir
              .childDirectory('artifacts')
              .childDirectory('engine'),
          hostPlatform: _hostPlatform,
          flutterPackTargetPlatform: flutterPackTargetPlatform,
          buildMode: _buildMode,
        )
        .copySync(outputFile.path);
  }
}

class CopyIcudtl extends Target {
  const CopyIcudtl();

  @override
  String get name => 'flutter_pack_copy_icudtl';

  @override
  List<Source> get inputs => const <Source>[
        Source.artifact(Artifact.icuData),
      ];

  @override
  List<Source> get outputs => const <Source>[
        Source.pattern('{OUTPUT_DIR}/icudtl.dat'),
      ];

  @override
  List<Target> get dependencies => [];

  @override
  Future<void> build(Environment environment) async {
    final icudtl = environment.fileSystem
        .file(environment.artifacts.getArtifactPath(Artifact.icuData));
    final outputFile = environment.outputDir.childFile('icudtl.dat');
    icudtl.copySync(outputFile.path);
  }
}

class DebugBundleFlutterpiAssets extends CompositeTarget {
  DebugBundleFlutterpiAssets({
    required this.flutterPackTargetPlatform,
    required HostPlatform hostPlatform,
    bool unoptimized = false,
    required FlutterpiArtifactPaths artifactPaths,
  }) : super([
          const CopyFlutterAssets(),
          const CopyIcudtl(),
          CopyFlutterpiEngine(
            flutterPackTargetPlatform,
            buildMode: BuildMode.debug,
            hostPlatform: hostPlatform,
            unoptimized: unoptimized,
            artifactPaths: artifactPaths,
          ),
        ]);

  final FlutterpiTargetPlatform flutterPackTargetPlatform;

  @override
  String get name => 'debug_bundle_flutter_pack_assets';
}

class ProfileBundleFlutterpiAssets extends CompositeTarget {
  ProfileBundleFlutterpiAssets({
    required this.flutterPackTargetPlatform,
    required HostPlatform hostPlatform,
    required FlutterpiArtifactPaths artifactPaths,
  }) : super([
          const CopyFlutterAssets(),
          const CopyIcudtl(),
          CopyFlutterpiEngine(
            flutterPackTargetPlatform,
            buildMode: BuildMode.profile,
            hostPlatform: hostPlatform,
            artifactPaths: artifactPaths,
          ),
          const FlutterpiAppElf(AotElfProfile(TargetPlatform.linux_arm64)),
        ]);

  final FlutterpiTargetPlatform flutterPackTargetPlatform;

  @override
  String get name =>
      'profile_bundle_flutter_pack_${flutterPackTargetPlatform.shortName}_assets';
}

class ReleaseBundleFlutterpiAssets extends CompositeTarget {
  ReleaseBundleFlutterpiAssets({
    required this.flutterPackTargetPlatform,
    required HostPlatform hostPlatform,
    required FlutterpiArtifactPaths artifactPaths,
  }) : super([
          const CopyFlutterAssets(),
          const CopyIcudtl(),
          CopyFlutterpiEngine(
            flutterPackTargetPlatform,
            buildMode: BuildMode.release,
            hostPlatform: hostPlatform,
            artifactPaths: artifactPaths,
          ),
          const FlutterpiAppElf(AotElfRelease(TargetPlatform.linux_arm64)),
        ]);

  final FlutterpiTargetPlatform flutterPackTargetPlatform;

  @override
  String get name =>
      'release_bundle_flutter_pack_${flutterPackTargetPlatform.shortName}_assets';
}

Future<void> buildFlutterpiBundle({
  required FlutterpiTargetPlatform flutterPackTargetPlatform,
  required BuildInfo buildInfo,
  FlutterpiArtifactPaths? artifactPaths,
  FlutterProject? project,
  String? mainPath,
  String manifestPath = defaultManifestPath,
  String? applicationKernelFilePath,
  String? depfilePath,
  String? assetDirPath,
  Artifacts? artifacts,
  BuildSystem? buildSystem,
  bool unoptimized = false,
}) async {
  project ??= FlutterProject.current();
  mainPath ??= defaultMainPath;
  depfilePath ??= defaultDepfilePath;
  assetDirPath ??= getAssetBuildDirectory();
  buildSystem ??= globals.buildSystem;
  artifacts ??= globals.artifacts!;
  artifactPaths ??= FlutterpiArtifactPaths();

  // If the precompiled flag was not passed, force us into debug mode.
  final environment = Environment(
    projectDir: project.directory,
    outputDir: globals.fs.directory(assetDirPath),
    buildDir: project.dartTool.childDirectory('flutter_build'),
    cacheDir: globals.cache.getRoot(),
    flutterRootDir: globals.fs.directory(Cache.flutterRoot),
    engineVersion: globals.artifacts!.isLocalEngine
        ? null
        : globals.flutterVersion.engineRevision,
    defines: <String, String>{
      // used by the KernelSnapshot target
      kTargetPlatform: getNameForTargetPlatform(TargetPlatform.linux_arm64),
      kTargetFile: mainPath,
      kDeferredComponents: 'false',
      ...buildInfo.toBuildSystemEnvironment(),

      // The flutter_tool computes the `.dart_tool/` subdir name from the
      // build environment hash.
      // Adding a flutter_pack-target entry here forces different subdirs for
      // different target platforms.
      //
      // If we don't have this, the flutter tool will happily reuse as much as
      // it can, and it determines it can reuse the `app.so` from (for example)
      // an arm build with an arm64 build, leading to errors.
      'flutterpack-target': flutterPackTargetPlatform.shortName,
    },
    artifacts: artifacts,
    fileSystem: globals.fs,
    logger: globals.logger,
    processManager: globals.processManager,
    usage: globals.flutterUsage,
    platform: globals.platform,
    generateDartPluginRegistry: true,
  );

  final hostPlatform = globals.os.hostPlatform;

  final target = switch (buildInfo.mode) {
    BuildMode.debug => DebugBundleFlutterpiAssets(
        flutterPackTargetPlatform: flutterPackTargetPlatform,
        hostPlatform: hostPlatform,
        unoptimized: unoptimized,
        artifactPaths: artifactPaths,
      ),
    BuildMode.profile => ProfileBundleFlutterpiAssets(
        flutterPackTargetPlatform: flutterPackTargetPlatform,
        hostPlatform: hostPlatform,
        artifactPaths: artifactPaths,
      ),
    BuildMode.release => ReleaseBundleFlutterpiAssets(
        flutterPackTargetPlatform: flutterPackTargetPlatform,
        hostPlatform: hostPlatform,
        artifactPaths: artifactPaths,
      ),
    _ => throwToolExit('Unsupported build mode: ${buildInfo.mode}'),
  };

  final result = await buildSystem.build(target, environment);
  if (!result.success) {
    for (final measurement in result.exceptions.values) {
      globals.printError(
        'Target ${measurement.target} failed: ${measurement.exception}',
        stackTrace: measurement.fatal ? measurement.stackTrace : null,
      );
    }

    throwToolExit('Failed to build bundle.');
  }

  final depfile = Depfile(result.inputFiles, result.outputFiles);
  final outputDepfile = globals.fs.file(depfilePath);
  if (!outputDepfile.parent.existsSync()) {
    outputDepfile.parent.createSync(recursive: true);
  }

  final depfileService = DepfileService(
    fileSystem: globals.fs,
    logger: globals.logger,
  );
  depfileService.writeToFile(depfile, outputDepfile);

  return;
}

/// An implementation of [Artifacts] that provides individual overrides.
///
/// If an artifact is not provided, the lookup delegates to the parent.
class FlutterpiCachedGenSnapshotArtifacts implements Artifacts {
  /// Creates a new [OverrideArtifacts].
  ///
  /// [parent] must be provided.
  FlutterpiCachedGenSnapshotArtifacts({
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

  String _getGenSnapshotPath(BuildMode buildMode) {
    final engineDir = _cache.getArtifactDirectory('engine').path;

    final hostPlatform = _operatingSystemUtils.hostPlatform;

    print("------engineDir = ${engineDir}--------");

    // Just some shorthands so the formatting doesn't look totally weird below.
    const genericArmv7 = FlutterpiTargetPlatform.genericArmV7;
    const genericAArch64 = FlutterpiTargetPlatform.genericAArch64;
    const genericX64 = FlutterpiTargetPlatform.genericX64;
    const pi4 = FlutterpiTargetPlatform.pi4;
    const pi4_64 = FlutterpiTargetPlatform.pi4_64;
    const rk3399 = FlutterpiTargetPlatform.rk3399;
    //const sample_app = FlutterpiTargetPlatform.sample_app;

    // ignore: constant_identifier_names
    const linux_x64 = HostPlatform.linux_x64;

    final subdir = switch ((_flutterPackTargetPlatform, hostPlatform)) {
      (genericArmv7, linux_x64) => const [
          'flutterpack-armv7-generic',
          'linux-x64'
        ],
      (genericAArch64, linux_x64) => const [
          'flutterpack-aarch64-generic',
          'linux-x64'
        ],
      (genericX64, linux_x64) => const ['flutterpack-x64-generic', 'linux-x64'],
      (pi4, linux_x64) => const ['flutterpack-pi4', 'linux-x64'],
      (pi4_64, linux_x64) => const ['flutterpack-pi4-64', 'linux-x64'],
      //(sample_app, linux_x64) => const ['sample_app', 'linux-x64'],
      (rk3399, linux_x64) => const ['flutterpack-rk3399', 'linux-x64'],
      _ => throw UnsupportedError(
          'Unsupported target platform & host platform combination: $_flutterPackTargetPlatform, $hostPlatform'),
    };

    final genSnapshotFilename =
        switch ((_operatingSystemUtils.hostPlatform, buildMode)) {
      (linux_x64, BuildMode.profile) => 'gen_snapshot_linux_x64_profile',
      (linux_x64, BuildMode.release) => 'gen_snapshot_linux_x64_release',
      _ => throw UnsupportedError(
          'Unsupported host platform & build mode combinations: $hostPlatform, $buildMode'),
    };

    return _fileSystem.path
        .joinAll([engineDir, ...subdir, genSnapshotFilename]);
  }

  @override
  String getArtifactPath(
    Artifact artifact, {
    TargetPlatform? platform,
    BuildMode? mode,
    EnvironmentType? environmentType,
  }) {
    if (artifact == Artifact.genSnapshot &&
        (mode == BuildMode.profile || mode == BuildMode.release)) {
      return _getGenSnapshotPath(mode!);
    }
    return parent.getArtifactPath(
      artifact,
      platform: platform,
      mode: mode,
      environmentType: environmentType,
    );
  }

  @override
  String getEngineType(TargetPlatform platform, [BuildMode? mode]) =>
      parent.getEngineType(platform, mode);

  @override
  bool get isLocalEngine => parent.isLocalEngine;

  @override
  FileSystemEntity getHostArtifact(HostArtifact artifact) {
    return parent.getHostArtifact(artifact);
  }
}

class BuildCommand extends Command<int> {
  static const archs = ['arm', 'arm64', 'x64'];
  static const cpus = ['generic', 'pi4', 'rk3399'];

  BuildCommand() {
    argParser
      ..addSeparator(
          'Runtime mode options (Defaults to debug. At most one can be specified)')
      ..addFlag('debug', negatable: false, help: 'Build for debug mode.')
      ..addFlag('profile', negatable: false, help: 'Build for profile mode.')
      ..addFlag('release', negatable: false, help: 'Build for release mode.')
      ..addFlag(
        'debug-unoptimized',
        negatable: false,
        help:
            'Build for debug mode and use unoptimized engine. (For stepping through engine code)',
      )
      ..addSeparator('Build options')
      ..addFlag(
        'tree-shake-icons',
        help:
            'Tree shake icon fonts so that only glyphs used by the application remain.',
      )
      ..addSeparator('Target options')
      ..addOption(
        'arch',
        allowed: archs,
        defaultsTo: 'arm',
        help: 'The target architecture to build for.',
        valueHelp: 'target arch',
        allowedHelp: {
          'arm': 'Build for 32-bit ARM. (armv7-linux-gnueabihf)',
          'arm64': 'Build for 64-bit ARM. (aarch64-linux-gnu)',
          'x64': 'Build for x86-64. (x86_64-linux-gnu)',
        },
      )
      ..addOption(
        'cpu',
        allowed: cpus,
        defaultsTo: 'generic',
        help:
            'If specified, uses an engine tuned for the given CPU. An engine tuned for one CPU will likely not work on other CPUs.',
        valueHelp: 'target cpu',
        allowedHelp: {
          'generic':
              'Don\'t use a tuned engine. The generic engine will work on all CPUs of the specified architecture.',
          'rk3399':
              'Use a rockpi4b tuned engine. Compatible with arm and arm64. (-mcpu=cortex-a53 -mtune=cortex-a53)',
          'pi4':
              'Use a Raspberry Pi 4 tuned engine. Compatible with arm and arm64. (-mcpu=cortex-a72+nocrypto -mtune=cortex-a72)',
        },
      );
  }

  @override
  String get name => 'build';

  @override
  String get description => 'Builds a flutter-gix asset bundle.';

  int exitWithUsage({int exitCode = 1, String? errorMessage, String? usage}) {
    if (errorMessage != null) {
      print(errorMessage);
    }

    if (usage != null) {
      print(usage);
    } else {
      printUsage();
    }
    return exitCode;
  }

  ({
    BuildMode buildMode,
    FlutterpiTargetPlatform targetPlatform,
    bool unoptimized,
    bool? treeShakeIcons,
    bool verbose,
  }) parse() {
    final results = argResults!;

    final target = switch ((results['arch'], results['cpu'])) {
      ('arm', 'generic') => FlutterpiTargetPlatform.genericArmV7,
      ('arm', 'pi4') => FlutterpiTargetPlatform.pi4,
      ('arm64', 'generic') => FlutterpiTargetPlatform.genericAArch64,
      ('arm64', 'pi4') => FlutterpiTargetPlatform.pi4_64,
      ('arm64', 'rk3399') => FlutterpiTargetPlatform.rk3399,
      ('x64', 'generic') => FlutterpiTargetPlatform.genericX64,
      (final arch, final cpu) => throw UsageException(
          'Unsupported target arch & cpu combination: architecture "$arch" is not supported for cpu "$cpu"',
          usage,
        ),
    };

    final (buildMode, unoptimized) = switch ((
      debug: results['debug'],
      profile: results['profile'],
      release: results['release'],
      debugUnopt: results['debug-unoptimized']
    )) {
      // single flag was specified.
      (debug: true, profile: false, release: false, debugUnopt: false) => (
          BuildMode.debug,
          false
        ),
      (debug: false, profile: true, release: false, debugUnopt: false) => (
          BuildMode.profile,
          false
        ),
      (debug: false, profile: false, release: true, debugUnopt: false) => (
          BuildMode.release,
          false
        ),
      (debug: false, profile: false, release: false, debugUnopt: true) => (
          BuildMode.debug,
          true
        ),

      // default case if no flags were specified.
      (debug: false, profile: false, release: false, debugUnopt: false) => (
          BuildMode.debug,
          false
        ),

      // more than a single flag has been specified.
      _ => throw UsageException(
          'At most one of `--debug`, `--profile`, `--release` or `--debug-unoptimized` can be specified.',
          usage,
        )
    };

    final treeShakeIcons = results['tree-shake-icons'] as bool?;

    final verbose = globalResults!['verbose'] as bool;

    return (
      buildMode: buildMode,
      targetPlatform: target,
      unoptimized: unoptimized,
      treeShakeIcons: treeShakeIcons,
      verbose: verbose,
    );
  }

  ArtifactsGenerator getArtifacts(FlutterpiTargetPlatform targetPlatform) {
    return () => FlutterpiCachedGenSnapshotArtifacts(
          parent: CachedArtifacts(
            fileSystem: globals.fs,
            cache: globals.cache,
            platform: globals.platform,
            operatingSystemUtils: globals.os,
          ),
          flutterPackTargetPlatform: targetPlatform,
          fileSystem: globals.fs,
          platform: globals.platform,
          cache: globals.cache,
          operatingSystemUtils: globals.os,
        );
  }

  @override
  Future<int> run() async {
    final parsed = parse();

    Cache.flutterRoot = await getFlutterRoot();

    await runInContext(
      targetPlatform: parsed.targetPlatform,
      artifactsGenerator: getArtifacts(parsed.targetPlatform!),
      verbose: parsed.verbose,
      runner: () async {
        try {
          // update the cached flutter-gix artifacts
          await flutterPackCache.updateAll(
            const {DevelopmentArtifact.universal},
            offline: false,
            flutterpackPlatforms: {parsed.targetPlatform},
          );

          // actually build the flutter bundle
          await buildFlutterpiBundle(
            flutterPackTargetPlatform: parsed.targetPlatform,
            buildInfo: switch (parsed.buildMode) {
              BuildMode.debug => BuildInfo(
                  BuildMode.debug,
                  null,
                  trackWidgetCreation: true,
                  treeShakeIcons:
                      parsed.treeShakeIcons ?? BuildInfo.debug.treeShakeIcons,
                ),
              BuildMode.profile => BuildInfo(
                  BuildMode.profile,
                  null,
                  treeShakeIcons:
                      parsed.treeShakeIcons ?? BuildInfo.profile.treeShakeIcons,
                ),
              BuildMode.release => BuildInfo(
                  BuildMode.release,
                  null,
                  treeShakeIcons:
                      parsed.treeShakeIcons ?? BuildInfo.release.treeShakeIcons,
                ),
              _ => throw UnsupportedError(
                  'Build mode ${parsed.buildMode} is not supported.'),
            },

            // for `--debug-unoptimized` build mode
            unoptimized: parsed.unoptimized,
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
