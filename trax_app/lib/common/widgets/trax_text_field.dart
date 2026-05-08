import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TraxTextField extends StatefulWidget {
  const TraxTextField({
    super.key,
    this.labelText,
    required this.hintText,
    this.inPutPassword = false,
    required this.controller,
    this.validator,
    this.inputFormatters,
    this.fillColor = const Color(0xFF838586),
    this.textColor = Colors.white,
    this.autofocus = false,
    this.keyboardType,
    this.showShadow = true,
  });

  final TextInputType? keyboardType;
  final bool autofocus;
  final String? labelText;
  final String hintText;
  final bool inPutPassword;
  final List<TextInputFormatter>? inputFormatters;
  final Color fillColor;
  final Color textColor;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final bool showShadow;

  @override
  State<TraxTextField> createState() => _TraxTextFieldState();
}

class _TraxTextFieldState extends State<TraxTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: widget.showShadow
          ? const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(20)),
              boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 4))],
            )
          : null,
      child: TextFormField(
        autofocus: widget.autofocus,
        validator: widget.validator,
        controller: widget.controller,
        style: TextStyle(color: widget.textColor),
        obscureText: widget.inPutPassword ? _obscureText : false,
        cursorColor: Colors.black,
        decoration: InputDecoration(
          labelText: widget.labelText,
          labelStyle: const TextStyle(color: Colors.black54),
          hintText: widget.hintText,
          hintStyle: const TextStyle(color: Colors.black54),
          filled: true,
          fillColor: widget.fillColor,
          errorStyle: const TextStyle(color: Color(0xFFFF0000)),
          enabledBorder: _getInputBorder(),
          focusedBorder: _getInputBorder(),
          errorBorder: _getInputBorder(),
          focusedErrorBorder: _getInputBorder(),
          suffixIcon: widget.inPutPassword
              ? IconButton(
                  icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
                  color: const Color(0xFFAEAEAE),
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                )
              : null,
        ),
        inputFormatters: widget.inputFormatters,
        keyboardType: widget.keyboardType,
      ),
    );
  }

  OutlineInputBorder _getInputBorder() {
    return const OutlineInputBorder(
      borderSide: BorderSide(color: Colors.transparent, width: 0),
      borderRadius: BorderRadius.all(Radius.circular(20)),
    );
  }
}
