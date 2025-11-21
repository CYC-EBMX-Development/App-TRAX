import 'package:flutter/material.dart';

// Use for login and signup
class TraxOrWidget extends StatelessWidget {
  const TraxOrWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Color(0xFF5E5E5E), indent: 20)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('OR', style: TextStyle(color: Color(0xFF949494), fontSize: 14)),
        ),
        Expanded(child: Divider(color: Color(0xFF5E5E5E), endIndent: 20)),
      ],
    );
  }
}
