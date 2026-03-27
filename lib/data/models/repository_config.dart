import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'history_config.dart';

class AutoSyncConfig {
  final bool enabled;
  final int intervalMinutes;
  final String remote;
  final String action;

  const AutoSyncConfig({
    this.enabled = false,
    this.intervalMinutes = 30,
    this.remote = '',
    this.action = 'sync',
  });

  factory AutoSyncConfig.fromMap(Map<String, dynamic> map) {
    return AutoSyncConfig(
      enabled: map['enabled'] as bool? ?? false,
      intervalMinutes: map['interval_minutes'] as int? ?? 30,
      remote: map['remote'] as String? ?? '',
      action: map['action'] as String? ?? 'sync',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'interval_minutes': intervalMinutes,
      'remote': remote,
      'action': action,
    };
  }

  AutoSyncConfig copyWith({
    bool? enabled,
    int? intervalMinutes,
    String? remote,
    String? action,
  }) {
    return AutoSyncConfig(
      enabled: enabled ?? this.enabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      remote: remote ?? this.remote,
      action: action ?? this.action,
    );
  }
}

class IgnoreConfig {
  final List<String> patterns;
  final List<String> extensions;
  final List<String> folders;

  const IgnoreConfig({
    this.patterns = const [],
    this.extensions = const [],
    this.folders = const [],
  });

  factory IgnoreConfig.fromMap(Map<String, dynamic> map) {
    return IgnoreConfig(
      patterns:
          (map['patterns'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      extensions:
          (map['extensions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      folders:
          (map['folders'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {'patterns': patterns, 'extensions': extensions, 'folders': folders};
  }

  IgnoreConfig copyWith({
    List<String>? patterns,
    List<String>? extensions,
    List<String>? folders,
  }) {
    return IgnoreConfig(
      patterns: patterns ?? this.patterns,
      extensions: extensions ?? this.extensions,
      folders: folders ?? this.folders,
    );
  }

  List<String> toIgnoreRules() {
    final rules = <String>[];
    for (final pattern in patterns) {
      rules.add(pattern);
    }
    for (final ext in extensions) {
      if (!ext.startsWith('*')) {
        rules.add('*$ext');
      } else {
        rules.add(ext);
      }
    }
    for (final folder in folders) {
      if (!folder.endsWith('/')) {
        rules.add('$folder/');
      } else {
        rules.add(folder);
      }
    }
    return rules;
  }
}

class RepositoryConfig {
  final String id;
  final int version;
  final String name;
  final String description;
  final DateTime createdAt;
  final String defaultBranch;
  final List<String> remotes;
  final HistoryConfig history;
  final AutoSyncConfig autoSync;
  final IgnoreConfig ignore;

  RepositoryConfig({
    String? id,
    this.version = 1,
    required this.name,
    this.description = '',
    DateTime? createdAt,
    this.defaultBranch = 'main',
    List<String>? remotes,
    HistoryConfig? history,
    AutoSyncConfig? autoSync,
    IgnoreConfig? ignore,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       remotes = remotes ?? const [],
       history = history ?? const HistoryConfig(),
       autoSync = autoSync ?? const AutoSyncConfig(),
       ignore = ignore ?? const IgnoreConfig();

  factory RepositoryConfig.fromMap(Map<String, dynamic> map) {
    return RepositoryConfig(
      id: map['id'] as String? ?? const Uuid().v4(),
      version: map['version'] as int? ?? 1,
      name: map['name'] as String? ?? 'Unnamed',
      description: map['description'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      defaultBranch: map['default_branch'] as String? ?? 'main',
      remotes:
          (map['remotes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      history: map['history'] != null
          ? HistoryConfig.fromMap(map['history'] as Map<String, dynamic>)
          : const HistoryConfig(),
      autoSync: map['auto_sync'] != null
          ? AutoSyncConfig.fromMap(map['auto_sync'] as Map<String, dynamic>)
          : const AutoSyncConfig(),
      ignore: map['ignore'] != null
          ? IgnoreConfig.fromMap(map['ignore'] as Map<String, dynamic>)
          : const IgnoreConfig(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'version': version,
      'name': name,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'default_branch': defaultBranch,
      'remotes': remotes,
      'history': history.toMap(),
      'auto_sync': autoSync.toMap(),
      'ignore': ignore.toMap(),
    };
  }

  RepositoryConfig copyWith({
    String? id,
    int? version,
    String? name,
    String? description,
    DateTime? createdAt,
    String? defaultBranch,
    List<String>? remotes,
    HistoryConfig? history,
    AutoSyncConfig? autoSync,
    IgnoreConfig? ignore,
  }) {
    return RepositoryConfig(
      id: id ?? this.id,
      version: version ?? this.version,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      defaultBranch: defaultBranch ?? this.defaultBranch,
      remotes: remotes ?? List.from(this.remotes),
      history: history ?? this.history,
      autoSync: autoSync ?? this.autoSync,
      ignore: ignore ?? this.ignore,
    );
  }

  static Future<RepositoryConfig?> loadFromFile(String configPath) async {
    final file = File(configPath);
    if (!await file.exists()) {
      return null;
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return RepositoryConfig.fromMap(json);
    } catch (_) {
      return null;
    }
  }

  static Future<String> getConfigPath(String localPath) {
    return Future.value(
      '$localPath${Platform.pathSeparator}.nanosync${Platform.pathSeparator}config.json',
    );
  }

  Future<void> saveToFile(String localPath) async {
    final configPath = await getConfigPath(localPath);
    final file = File(configPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toMap()),
    );
  }
}
