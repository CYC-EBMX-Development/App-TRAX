class ValidatorUtil {
  /// 验证邮件格式
  static bool isEmailValid(String email) {
    if (email.isEmpty) return false;
    final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return regex.hasMatch(email);
  }
}
