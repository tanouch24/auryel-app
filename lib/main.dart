import 'package:flutter/material.dart';

import 'theme/auryel_theme.dart';
import 'widgets/main_nav_shell.dart';

void main() {
  runApp(const AuryelApp());
}

class AuryelApp extends StatelessWidget {
  const AuryelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auryel',
      debugShowCheckedModeBanner: false,
      theme: AuryelTheme.dark,
      home: const MainNavShell(),
    );
  }
}
