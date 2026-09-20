import 'package:flutter/material.dart';

import 'package:kitten/app/theme/app_theme.dart';
import 'package:kitten/core/constants/app_constants.dart';
import 'package:kitten/features/home/presentation/pages/home_page.dart';

/// Root widget for the Kitten AI application.
class KittenApp extends StatelessWidget {
  const KittenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
