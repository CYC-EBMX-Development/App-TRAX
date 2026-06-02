import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

const List<Permission> _anPerms = [
  Permission.location,
  Permission.bluetoothConnect,
  Permission.bluetoothScan,
];

const List<Permission> _iosPerms = [
  Permission.bluetooth,
];

class BlePermission {
  static Future<List<String>> checkPerm() async {
    if (kIsWeb || Platform.isMacOS) {
      return [];
    }

    final perms = Platform.isIOS ? _iosPerms : _anPerms;
    final errors = <String>[];
    await perms.request().then((status) {
      status.forEach((key, value) {
        if (value != PermissionStatus.granted) {
          errors.add(key.toString());
        }
      });
    });
    return errors;
  }
}
