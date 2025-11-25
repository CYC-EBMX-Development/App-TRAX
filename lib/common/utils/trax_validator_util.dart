class TraxValidatorUtil {
  TraxValidatorUtil._();

  /// 验证邮件格式
  static bool isEmail(String email) {
    if (email.isEmpty) return false;
    final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return regex.hasMatch(email);
  }

  /// 验证邮箱格式, 用于 TextField 的 validator
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter email';
    }
    if (!TraxValidatorUtil.isEmail(value)) {
      return 'Please enter valid email';
    }
    return null;
  }

  /// 验证密码格式, 用于 TextField 的 validator
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter password';
    }
    if (value.length < 8) {
      return 'Password enter valid password';
    }
    return null;
  }
}
