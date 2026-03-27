import 'package:uuid/uuid.dart';
import '../../core/constants/enums.dart';

class RemoteConnection {
  final String id;
  String name;
  RemoteProtocol protocol;
  String host;
  int port;
  String username;
  String password;
  DateTime createdAt;
  DateTime updatedAt;

  RemoteConnection({
    String? id,
    required this.name,
    this.protocol = RemoteProtocol.smb,
    required this.host,
    this.port = 445,
    this.username = '',
    this.password = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory RemoteConnection.fromMap(Map<String, dynamic> map) {
    return RemoteConnection(
      id: map['id'] as String,
      name: map['name'] as String,
      protocol: RemoteProtocol.fromValue(map['protocol'] as String? ?? 'smb'),
      host: map['host'] as String,
      port: map['port'] as int? ?? 445,
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'protocol': protocol.value,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'created_at': createdAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  RemoteConnection copyWith({
    String? name,
    RemoteProtocol? protocol,
    String? host,
    int? port,
    String? username,
    String? password,
  }) {
    return RemoteConnection(
      id: id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  String get displayAddress => '${protocol.label}://$host:$port';

  String get remoteKey => '${protocol.value}|$host|$port|$username';
}
