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
import 'package:flutter_tools/src/context_runner.dart' as context_runner;
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/flutter_cache.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/isolated/mustache_template.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:github/github.dart' as gh;
import 'package:package_config/package_config.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as path;

FlutterpiCache get flutterPackCache => globals.cache as FlutterpiCache;

enum FlutterpiTargetPlatform {
  genericArmV7('generic-armv7'),
  genericAArch64('generic-aarch64'),
  genericX64('generic-x64'),
  rk3399('rk3399'),
  sample_app('sample_app'),
  pi4('pi4'),
  pi4_64('pi4-64');

  const FlutterpiTargetPlatform(this.shortName);

  final String shortName;
}

sealed class FlutterpiEngineCIArtifact extends EngineCachedArtifact {
  FlutterpiEngineCIArtifact(
    String stampName,
    FlutterpiCache cache,
    DevelopmentArtifact developmentArtifact,
  ) : super(stampName, cache, developmentArtifact);

  @override
  FlutterpiCache get cache => super.cache as FlutterpiCache;

  @override
  List<String> getPackageDirs() => const [];

  @override
  List<String> getLicenseDirs() => const [];

  List<(String, String)> getBinaryDirTuples();

  @override
  List<List<String>> getBinaryDirs() {
    return [
      for (final (path, name) in getBinaryDirTuples()) [path, name],
    ];
  }

  @override
  bool isUpToDateInner(FileSystem fileSystem) {
    final Directory pkgDir = cache.getCacheDir('pkg');
    for (final String pkgName in getPackageDirs()) {
      final String pkgPath = fileSystem.path.join(pkgDir.path, pkgName);
      if (!fileSystem.directory(pkgPath).existsSync()) {
        print("-------pkgPath ${pkgPath}---------------");
        return false;
      }
    }

    for (final List<String> toolsDir in getBinaryDirs()) {
      final Directory dir = fileSystem.directory(fileSystem.path.join(location.path, toolsDir[0]));
      if (!dir.existsSync()) {
        return false;
      }
      //print("${location.path}  --> ${toolsDir[0]}");
      //print("${dir.path} / ${dir.basename}");
    }

    for (final String licenseDir in getLicenseDirs()) {
      final File file = fileSystem.file(fileSystem.path.join(location.path, licenseDir, 'LICENSE'));
      if (!file.existsSync()) {
        return false;
      }
    }
    return true;
  }

  Future<gh.Release> findGithubReleaseByEngineHash(String hash) async {
    var tagName = 'engine/$hash';
    print("------EngineHash ${hash}-------");
    return await gh.GitHub().repositories.getReleaseByTagName(cache.flutterPiEngineCi, tagName);
  }

  @override
  Future<void> updateInner(
    ArtifactUpdater artifactUpdater,
    FileSystem fileSystem,
    OperatingSystemUtils operatingSystemUtils,
  ) async {
    late gh.Release ghRelease;
    try {
      ghRelease = await findGithubReleaseByEngineHash(version!);
    } on gh.ReleaseNotFound {
      throwToolExit('Flutter engine binaries for engine $version are not available .');
    }

    for (final List<String> dirs in getBinaryDirs()) {
      final cacheDir = dirs[0];
      final urlPath = dirs[1];

      final ghAsset =
          ghRelease.assets!.cast<gh.ReleaseAsset?>().singleWhere((asset) => asset!.name == urlPath, orElse: () => null);
      if (ghAsset == null) {
        throwToolExit('Flutter engine binaries with version $version and target $urlPath are not available.');
      }

      final downloadUrl = ghAsset.browserDownloadUrl!;
      final destDir = fileSystem.directory(fileSystem.path.join(location.path, cacheDir));

      print("======downloadUrl ${downloadUrl} to ${destDir}=========");

      await artifactUpdater.downloadZippedTarball(
        'Downloading $urlPath tools...',
        Uri.parse(downloadUrl),
        destDir,
      );
      _makeFilesExecutable(destDir, operatingSystemUtils);
    }
  }

  @override
  Future<bool> checkForArtifacts(String? engineVersion) async {
    try {
      await findGithubReleaseByEngineHash(version!);
      return true;
    } on gh.ReleaseNotFound {
      print("======file not found ${version}=========");
      return false;
    }
  }

  void _makeFilesExecutable(
    Directory dir,
    OperatingSystemUtils operatingSystemUtils,
  ) {
    operatingSystemUtils.chmod(dir, 'a+r,a+x');
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      final stat = file.statSync();

      final isUserExecutable = ((stat.mode >> 6) & 0x1) == 1;
      if (file.basename == 'flutter_tester' || isUserExecutable) {
        // Make the file readable and executable by all users.
        operatingSystemUtils.chmod(file, 'a+r,a+x');
      }
      if (file.basename.startsWith('gen_snapshot_')) {
        operatingSystemUtils.chmod(file, 'a+r,a+x');
      }
    }
  }
}

class FlutterpiEngineBinariesGeneric extends FlutterpiEngineCIArtifact {
  FlutterpiEngineBinariesGeneric(
    FlutterpiCache cache, {
    required Platform platform,
  })  : _platform = platform,
        super(
          'flutterpack-engine-binaries-generic',
          cache,
          DevelopmentArtifact.universal,
        );

  final Platform _platform;

  @override
  List<String> getPackageDirs() => const <String>[];

  @override
  List<(String, String)> getBinaryDirTuples() {
    if (!_platform.isLinux) {
      return [];
    }
    return [
      ('flutterpack-aarch64-generic/linux-x64', 'aarch64-generic.tar.xz'),
      ('flutterpack-armv7-generic/linux-x64', 'armv7-generic.tar.xz'),
      ('flutterpack-x64-generic/linux-x64', 'x64-generic.tar.xz'),
    ];
  }

  @override
  List<String> getLicenseDirs() {
    return <String>[];
  }
}

class FlutterpiEngineBinariesPi4 extends FlutterpiEngineCIArtifact {
  FlutterpiEngineBinariesPi4(
    FlutterpiCache cache, {
    required Platform platform,
  })  : _platform = platform,
        super(
          'flutterpack-engine-binaries-pi4',
          cache,
          DevelopmentArtifact.universal,
        );

  final Platform _platform;

  @override
  List<(String, String)> getBinaryDirTuples() {
    if (!_platform.isLinux) {
      return [];
    }

    return [
      ('flutterpack-pi4/linux-x64', 'pi4.tar.xz'),
      ('flutterpack-pi4-64/linux-x64', 'pi4-64.tar.xz'),
    ];
  }
}

class FlutterpiEngineBinariesRK3399 extends FlutterpiEngineCIArtifact {
  FlutterpiEngineBinariesRK3399(
    FlutterpiCache cache, {
    required Platform platform,
  })  : _platform = platform,
        super(
          'flutterpack-engine-binaries-rk3399',
          cache,
          DevelopmentArtifact.universal,
        );

  final Platform _platform;

  @override
  List<(String, String)> getBinaryDirTuples() {
    if (!_platform.isLinux) {
      return [];
    }

    //print("-------getBinaryDirTuples rk3399--------------");
    return [
      ('flutterpack-rk3399/linux-x64', 'rk3399.tar.xz'),
    ];
  }
}

class FlutterpiEngineBinariesSampleApp extends FlutterpiEngineCIArtifact {
  FlutterpiEngineBinariesSampleApp(
    FlutterpiCache cache, {
    required Platform platform,
  })  : _platform = platform,
        super(
          'flutterpack-sample_app',
          cache,
          DevelopmentArtifact.universal,
        );

  final Platform _platform;

  @override
  List<(String, String)> getBinaryDirTuples() {
    if (!_platform.isLinux) {
      return [];
    }

    print("-------getBinaryDirTuples sample_app--------------");
    return [
      ('sample_app', 'sample_app.tar.xz'),
    ];
  }
}

class FlutterpiCache extends FlutterCache {
  FlutterpiCache({
    required Logger logger,
    required FileSystem fileSystem,
    required Platform platform,
    required OperatingSystemUtils osUtils,
    required super.projectFactory,
  })  : _logger = logger,
        _fileSystem = fileSystem,
        _platform = platform,
        _osUtils = osUtils,
        super(
          logger: logger,
          platform: platform,
          fileSystem: fileSystem,
          osUtils: osUtils,
        ) {
    registerArtifact(FlutterpiEngineBinariesGeneric(
      this,
      platform: platform,
    ));

    registerArtifact(FlutterpiEngineBinariesPi4(
      this,
      platform: platform,
    ));
    registerArtifact(FlutterpiEngineBinariesRK3399(
      this,
      platform: platform,
    ));
    registerArtifact(FlutterpiEngineBinariesSampleApp(
      this,
      platform: platform,
    ));
  }

  final Logger _logger;
  final FileSystem _fileSystem;
  final Platform _platform;
  final OperatingSystemUtils _osUtils;
  final List<ArtifactSet> _artifacts = [];

  @override
  void registerArtifact(ArtifactSet artifactSet) {
    _artifacts.add(artifactSet);
    super.registerArtifact(artifactSet);
  }

  final flutterPiEngineCi = gh.RepositorySlug('easion', 'flutter_pack');
  final flutterPackageBaseUrl = 'https://github.com/easion/flutter_pack/';

  late final ArtifactUpdater _artifactUpdater = _createUpdater();

  /// This has to be lazy because it requires FLUTTER_ROOT to be initialized.
  ArtifactUpdater _createUpdater() {
    print("getDownloadDir --> ${getDownloadDir()}  -- ${flutterPackageBaseUrl} ");
    return ArtifactUpdater(
      operatingSystemUtils: _osUtils,
      logger: _logger,
      fileSystem: _fileSystem,
      tempStorage: getDownloadDir(),
      platform: _platform,
      httpClient: io.HttpClient(),
      allowedBaseUrls: <String>[storageBaseUrl, cipdBaseUrl, flutterPackageBaseUrl],
    );
  }

  /// Update the cache to contain all `requiredArtifacts`.
  @override
  Future<void> updateAll(
    Set<DevelopmentArtifact> requiredArtifacts, {
    bool offline = false,
    Set<FlutterpiTargetPlatform> flutterpackPlatforms = const {
      FlutterpiTargetPlatform.genericArmV7,
      FlutterpiTargetPlatform.genericAArch64,
      FlutterpiTargetPlatform.genericX64,
      FlutterpiTargetPlatform.rk3399,
      FlutterpiTargetPlatform.sample_app,
    },
  }) async {
    for (final ArtifactSet artifact in _artifacts) {
      final required = switch (artifact) {
        FlutterpiEngineCIArtifact _ => switch (artifact) {
            FlutterpiEngineBinariesGeneric _ => flutterpackPlatforms.contains(FlutterpiTargetPlatform.genericAArch64) ||
                flutterpackPlatforms.contains(FlutterpiTargetPlatform.genericArmV7) ||
                flutterpackPlatforms.contains(FlutterpiTargetPlatform.genericX64),
            FlutterpiEngineBinariesRK3399 _ => flutterpackPlatforms.contains(FlutterpiTargetPlatform.rk3399),
            FlutterpiEngineBinariesSampleApp _ => flutterpackPlatforms.contains(FlutterpiTargetPlatform.sample_app),
            FlutterpiEngineBinariesPi4 _ => flutterpackPlatforms.contains(FlutterpiTargetPlatform.pi4) ||
                flutterpackPlatforms.contains(FlutterpiTargetPlatform.pi4_64),
          },
        _ => requiredArtifacts.contains(artifact.developmentArtifact),
      };

      if (!required) {
        _logger.printTrace('Artifact $artifact is not required, skipping update.');
        continue;
      }

      if (await artifact.isUpToDate(_fileSystem)) {
        continue;
      }

      print("-------artifact.update ${flutterpackPlatforms}---------------");
      await artifact.update(
        _artifactUpdater,
        _logger,
        _fileSystem,
        _osUtils,
        offline: offline,
      );
    }
  }
}

Future<void> exitWithHooks(int code, {required ShutdownHooks shutdownHooks}) async {
  // Run shutdown hooks before flushing logs
  await shutdownHooks.runShutdownHooks(globals.logger);

  final completer = Completer<void>();

  // Give the task / timer queue one cycle through before we hard exit.
  Timer.run(() {
    try {
      globals.printTrace('exiting with code $code');
      io.exit(code);
    } catch (error, stackTrace) {
      // ignore: avoid_catches_without_on_clauses
      completer.completeError(error, stackTrace);
    }
  });

  return completer.future;
}

class TarXzCompatibleOsUtils implements OperatingSystemUtils {
  TarXzCompatibleOsUtils({
    required OperatingSystemUtils os,
    required ProcessUtils processUtils,
  })  : _os = os,
        _processUtils = processUtils;

  final OperatingSystemUtils _os;
  final ProcessUtils _processUtils;

  @override
  void chmod(FileSystemEntity entity, String mode) {
    return _os.chmod(entity, mode);
  }

  @override
  Future<int> findFreePort({bool ipv6 = false}) {
    return _os.findFreePort(ipv6: false);
  }

  @override
  Stream<List<int>> gzipLevel1Stream(Stream<List<int>> stream) {
    return _os.gzipLevel1Stream(stream);
  }

  @override
  HostPlatform get hostPlatform => _os.hostPlatform;

  @override
  void makeExecutable(File file) => _os.makeExecutable(file);

  @override
  File makePipe(String path) => _os.makePipe(path);

  @override
  String get name => _os.name;

  @override
  String get pathVarSeparator => _os.pathVarSeparator;

  @override
  void unpack(File gzippedTarFile, Directory targetDirectory) {
    _processUtils.runSync(
      <String>['tar', '-xf', gzippedTarFile.path, '-C', targetDirectory.path],
      throwOnError: true,
    );
  }

  @override
  void unzip(File file, Directory targetDirectory) {
    _os.unzip(file, targetDirectory);
  }

  @override
  File? which(String execName) {
    return _os.which(execName);
  }

  @override
  List<File> whichAll(String execName) {
    return _os.whichAll(execName);
  }
}

typedef ArtifactsGenerator = Artifacts Function();

Future<T> runInContext<T>({
  required FutureOr<T> Function() runner,
  required ArtifactsGenerator artifactsGenerator,
  FlutterpiTargetPlatform? targetPlatform,
  Set<FlutterpiTargetPlatform>? targetPlatforms,
  bool verbose = false,
}) async {
  Logger Function() loggerFactory = () => globals.platform.isWindows
      ? WindowsStdoutLogger(
          terminal: globals.terminal,
          stdio: globals.stdio,
          outputPreferences: globals.outputPreferences,
        )
      : StdoutLogger(
          terminal: globals.terminal,
          stdio: globals.stdio,
          outputPreferences: globals.outputPreferences,
        );

  if (verbose) {
    final oldLoggerFactory = loggerFactory;
    loggerFactory = () => VerboseLogger(oldLoggerFactory());
  }

  targetPlatforms ??= targetPlatform != null ? {targetPlatform} : null;
  targetPlatforms ??= FlutterpiTargetPlatform.values.toSet();

  return context_runner.runInContext(
    runner,
    overrides: {
      TemplateRenderer: () => const MustacheTemplateRenderer(),
      Cache: () => FlutterpiCache(
            logger: globals.logger,
            fileSystem: globals.fs,
            platform: globals.platform,
            osUtils: globals.os,
            projectFactory: globals.projectFactory,
          ),
      OperatingSystemUtils: () => TarXzCompatibleOsUtils(
            os: OperatingSystemUtils(
              fileSystem: globals.fs,
              logger: globals.logger,
              platform: globals.platform,
              processManager: globals.processManager,
            ),
            processUtils: ProcessUtils(
              processManager: globals.processManager,
              logger: globals.logger,
            ),
          ),
      Logger: loggerFactory,
      Artifacts: artifactsGenerator,
    },
  );
}

Future<String> getFlutterRoot() async {
  final pkgconfig = await findPackageConfigUri(io.Platform.script);
  pkgconfig!;

  final flutterToolsPath = pkgconfig.resolve(Uri.parse('package:flutter_tools/'))!.toFilePath();
  const dirname = path.dirname;
  return dirname(dirname(dirname(flutterToolsPath)));
}
