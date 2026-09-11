import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const MoneyHandlerApp());
}

class MoneyHandlerApp extends StatelessWidget {
  const MoneyHandlerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Money Handler',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
