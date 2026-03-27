import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class DeviceIdentity {
  final String fingerprint;
  final String deviceName;
  final String username;

  const DeviceIdentity({
    required this.fingerprint,
    required this.deviceName,
    required this.username,
  });
}

class DeviceIdentityResolver {
  static DeviceIdentity resolve() {
    final env = Platform.environment;
    final deviceName = Platform.localHostname.trim();
    final username =
        (env['USERNAME'] ?? env['USER'] ?? env['LOGNAME'] ?? '').trim();

    final seed = <String>[
      deviceName,
      username,
      Platform.operatingSystem,
      Platform.operatingSystemVersion,
      env['USERDOMAIN'] ?? '',
      env['PROCESSOR_IDENTIFIER'] ?? '',
      env['COMPUTERNAME'] ?? '',
    ].join('|');

    final fingerprint = sha256.convert(utf8.encode(seed)).toString();

    return DeviceIdentity(
      fingerprint: fingerprint,
      deviceName: deviceName,
      username: username,
    );
  }
}
