import 'package:flutter/material.dart';
import 'screens/status_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const SushiskiStatusApp());
}

class SushiskiStatusApp extends StatelessWidget {
  const SushiskiStatusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sushiski Status',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const StatusScreen(),
    );
  }
}
