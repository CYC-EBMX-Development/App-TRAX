import 'package:flutter/material.dart';

class TraxOrWidget extends StatelessWidget {
  const TraxOrWidget({super.key, this.color = Colors.white});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: color, indent: 20)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('OR', style: TextStyle(color: color, fontSize: 14)),
        ),
        Expanded(child: Divider(color: color, endIndent: 20)),
      ],
    );
  }
}
