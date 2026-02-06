import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors (Legacy Red & Black)
  static const Color primary = Color(0xFFD32F2F); // Red 700
  static const Color primaryLight = Color(0xFFFF5252); 
  static const Color primaryDark = Color(0xFFB71C1C);
  
  static const Color secondary = Color(0xFFFF5252); // Red Accent
  static const Color accent = Color(0xFFD32F2F); 
  
  // Backgrounds
  static const Color background = Color(0xFFF5F5F5); 
  static const Color surface = Colors.white;
  static const Color surfaceGrey = Color(0xFFEEEEEE);

  // Dark Mode Palette
  static const Color backgroundDark = Color(0xFF181818); // OLED-like Black
  static const Color surfaceDark = Color(0xFF232323); // Dark Grey Card
  
  // Typography
  static const Color textPrimary = Color(0xFF000000); // Absolute Black
  static const Color textSecondary = Color(0xFF616161);
  static const Color textLight = Colors.white;
  
  // Status
  static const Color error = Color(0xFFD32F2F);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  
  // Legacy support
  static const MaterialColor primarySwatch = Colors.red;
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color blue = Colors.blue;
  static const Color green = Colors.green;
  static const Color orange = Colors.orange;
  static const Color red = Colors.red;
}
