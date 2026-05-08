import 'package:get/get.dart';

class GlobalUserInfo {
  GlobalUserInfo._();
  static final GlobalUserInfo instance = GlobalUserInfo._();

  final id = Rxn<int>();
  final name = ''.obs;
  final email = ''.obs;
  final avatar = ''.obs;

  void setUserInfo({int? id, String? name, String? email, String? avatar}) {
    this.id.value = id;
    this.name.value = name ?? '';
    this.email.value = email ?? '';
    this.avatar.value = avatar ?? '';
  }

  void clear() {
    id.value = null;
    name.value = '';
    email.value = '';
    avatar.value = '';
  }
}
