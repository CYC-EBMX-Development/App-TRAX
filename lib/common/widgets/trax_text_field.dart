import 'package:flutter/material.dart';
import 'package:tra_x/common/utils/trax_log_util.dart';

class TraXTextField extends StatefulWidget {
  const TraXTextField({
    super.key,
    required this.labelText,
    required this.hintText,
    this.inPutPassword = false,
    required this.controller,
    this.validator,
  });

  final String labelText;
  final String hintText;
  final bool inPutPassword;
  final TextEditingController controller;
  final String? Function(String?)? validator;

  @override
  State<TraXTextField> createState() => _TraXTextFieldPage();
}

class _TraXTextFieldPage extends State<TraXTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      validator: widget.validator,
      controller: widget.controller,
      style: const TextStyle(color: Colors.white),
      obscureText: widget.inPutPassword ? _obscureText : false,
      decoration: InputDecoration(
        labelText: widget.labelText,
        labelStyle: const TextStyle(color: Colors.white),
        hintText: widget.labelText,
        hintStyle: const TextStyle(color: Colors.white),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(
            color: Colors.white, // 未聚焦时的边框颜色
            width: 1,
          ),
          borderRadius: BorderRadius.all(Radius.circular(5)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(
            color: Colors.white, // 聚焦时的边框颜色
            width: 1,
          ),
          borderRadius: BorderRadius.all(Radius.circular(5)),
        ),
        errorBorder: const OutlineInputBorder(
          borderSide: BorderSide(
            color: Colors.red, // 错误时的边框颜色
            width: 1,
          ),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderSide: BorderSide(
            color: Colors.redAccent, // 聚焦且错误时的边框颜色
            width: 1,
          ),
        ),
        suffixIcon: widget.inPutPassword
            ? IconButton(
                icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  setState(() {
                    _obscureText = !_obscureText;
                  });
                },
              )
            : null,
      ),
      onChanged: (value) {
        TraxLogUtil.debug('输入的内容: $value');
      },
    );
  }
}
