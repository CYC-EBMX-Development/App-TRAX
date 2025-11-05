import 'package:flutter/material.dart';

class TraXTextField extends StatefulWidget {
  const TraXTextField({
    super.key,
    required this.labelText,
    required this.hintText,
    this.inPutPassword = false,
    required this.onPressed,
  });
  final String labelText;
  final String hintText;
  final bool inPutPassword;
  final VoidCallback onPressed;

  @override
  State<TraXTextField> createState() => _TraXTextFieldPage();
}

class  _TraXTextFieldPage extends State<TraXTextField> {
  bool _obscureText = true;
  @override
  Widget build(BuildContext context) {
    return TextField(
      style: const TextStyle(
        color: Colors.white,
      ),
      obscureText: widget.inPutPassword ? _obscureText:false,
      decoration: InputDecoration(
        labelText: widget.labelText,
        labelStyle: const TextStyle(
          color: Colors.white,
        ),
        hintText: widget.labelText,
        hintStyle: const TextStyle(
          color: Colors.white,
        ),
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
            width: 1
          ),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderSide: BorderSide(
            color: Colors.redAccent, // 聚焦且错误时的边框颜色
            width: 1,
          ),
        ),
        suffixIcon: widget.inPutPassword ? IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() {
              _obscureText = !_obscureText;
            });
          },
        ):null,
      ),
      onChanged: (value) {
        print('输入的内容: $value');
        widget.onPressed;
      },
    );
  }
}

class SingleDigitInput extends StatefulWidget {
  const SingleDigitInput({
    super.key,
    required this.focusNode,
  required this.nextFocus,
  });
  final FocusNode focusNode;
  final VoidCallback nextFocus;

  @override
  _SingleDigitInputState createState() => _SingleDigitInputState();
}

class _SingleDigitInputState extends State<SingleDigitInput> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      width: 50,
      child: TextField(
        maxLength: 1,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 24,color: Colors.white),
        focusNode: widget.focusNode,
        decoration: InputDecoration(
          counterText: "",
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(
              color: Color(0xFF454545), // 未聚焦时的边框颜色
              width: 1,
            ),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(
              color: Colors.white, // 聚焦时的边框颜色
              width: 1,
            ),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          //contentPadding: EdgeInsets.all(16),
        ),
        onChanged: (value) {
          if (value.length == 1) {
            widget.focusNode.unfocus();
            widget.nextFocus();
          }
        },
      ),
    );
  }
}