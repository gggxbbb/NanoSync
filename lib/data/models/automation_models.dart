enum AutomationTriggerType { timeBased, changeBased }

enum AutomationActionType { commit, push, commitAndPush }

class AutomationRule {
  final String id;
  final String repositoryId;
  final String name;
  final bool enabled;
  final AutomationTriggerType triggerType;
  final AutomationActionType actionType;

  // For time-based triggers
  final int? intervalMinutes; // null = disabled
  final bool? autoCommitOnInterval;
  final bool? autoPushOnInterval;

  // For change-based triggers
  final bool? commitOnChange;
  final bool? pushAfterCommit;
  final int? debounceSeconds; // debounce time before auto-commit on change

  // Commit message template
  final String commitMessageTemplate;
  final DateTime createdAt;
  final DateTime? lastTriggeredAt;
  final DateTime updatedAt;

  AutomationRule({
    required this.id,
    required this.repositoryId,
    required this.name,
    required this.enabled,
    required this.triggerType,
    required this.actionType,
    this.intervalMinutes,
    this.autoCommitOnInterval,
    this.autoPushOnInterval,
    this.commitOnChange,
    this.pushAfterCommit,
    this.debounceSeconds,
    required this.commitMessageTemplate,
    required this.createdAt,
    this.lastTriggeredAt,
    required this.updatedAt,
  });

  factory AutomationRule.fromMap(Map<String, dynamic> map) {
    return AutomationRule(
      id: map['id'] as String,
      repositoryId: map['repository_id'] as String,
      name: map['name'] as String,
      enabled: (map['enabled'] as int?) == 1,
      triggerType:
          AutomationTriggerType.values[(map['trigger_type'] as int?) ??
              AutomationTriggerType.timeBased.index],
      actionType:
          AutomationActionType.values[(map['action_type'] as int?) ??
              AutomationActionType.commit.index],
      intervalMinutes: map['interval_minutes'] as int?,
      autoCommitOnInterval: (map['auto_commit_on_interval'] as int?) == 1,
      autoPushOnInterval: (map['auto_push_on_interval'] as int?) == 1,
      commitOnChange: (map['commit_on_change'] as int?) == 1,
      pushAfterCommit: (map['push_after_commit'] as int?) == 1,
      debounceSeconds: map['debounce_seconds'] as int?,
      commitMessageTemplate: map['commit_message_template'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      lastTriggeredAt: map['last_triggered_at'] != null
          ? DateTime.parse(map['last_triggered_at'] as String)
          : null,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repository_id': repositoryId,
      'name': name,
      'enabled': enabled ? 1 : 0,
      'trigger_type': triggerType.index,
      'action_type': actionType.index,
      'interval_minutes': intervalMinutes,
      'auto_commit_on_interval': autoCommitOnInterval == true ? 1 : 0,
      'auto_push_on_interval': autoPushOnInterval == true ? 1 : 0,
      'commit_on_change': commitOnChange == true ? 1 : 0,
      'push_after_commit': pushAfterCommit == true ? 1 : 0,
      'debounce_seconds': debounceSeconds,
      'commit_message_template': commitMessageTemplate,
      'created_at': createdAt.toIso8601String(),
      'last_triggered_at': lastTriggeredAt?.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  AutomationRule copyWith({
    String? id,
    String? repositoryId,
    String? name,
    bool? enabled,
    AutomationTriggerType? triggerType,
    AutomationActionType? actionType,
    int? intervalMinutes,
    bool? autoCommitOnInterval,
    bool? autoPushOnInterval,
    bool? commitOnChange,
    bool? pushAfterCommit,
    int? debounceSeconds,
    String? commitMessageTemplate,
    DateTime? createdAt,
    DateTime? lastTriggeredAt,
    DateTime? updatedAt,
  }) {
    return AutomationRule(
      id: id ?? this.id,
      repositoryId: repositoryId ?? this.repositoryId,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      triggerType: triggerType ?? this.triggerType,
      actionType: actionType ?? this.actionType,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      autoCommitOnInterval: autoCommitOnInterval ?? this.autoCommitOnInterval,
      autoPushOnInterval: autoPushOnInterval ?? this.autoPushOnInterval,
      commitOnChange: commitOnChange ?? this.commitOnChange,
      pushAfterCommit: pushAfterCommit ?? this.pushAfterCommit,
      debounceSeconds: debounceSeconds ?? this.debounceSeconds,
      commitMessageTemplate:
          commitMessageTemplate ?? this.commitMessageTemplate,
      createdAt: createdAt ?? this.createdAt,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
