// lib/constants/palette.dart
import 'package:flutter/material.dart';

class Palette {
  // Main Colors
  static const Color primary = Color(0xFF1A6EA0);
  static const Color primaryAccent = Color(0xFF5AA9E6);
  static const Color secondary = Color(0xFF7C9E6F);
  static const Color tertiary = Color(0xFFFF8A6C);
  static const Color error = Color(0xFFFC8181);

  // Neutrals
  static const Color textDark = Color(0xFF2D3748);
  static const Color textMedium = Color(0xFF718096);
  static const Color background = Color(0xFFF7FAFC);
  static const Color surface = Colors.white;

  // Semantic Gradients (for a more dynamic feel)
  static LinearGradient primaryGradient = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryAccent, primary],
  );
}
