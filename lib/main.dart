import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'splash_screen.dart';
import 'onboarding_page.dart';
import 'lifecycle_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🟢 2. LOAD SECRETS FIRST
  try {
    await dotenv.load(fileName: ".env");
    print("✅ Secrets loaded");
  } catch (e) {
    print("❌ Failed to load .env: $e");
  }

  try {
    await Firebase.initializeApp();
    print("✅ Firebase initialized successfully");
  } catch (e) {
    print("❌ Firebase failed to load: $e");
  }

  await Supabase.initialize(
    url: 'https://vgrmjascnnmaajbdtxhr.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZncm1qYXNjbm5tYWFqYmR0eGhyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU5MzI3MDQsImV4cCI6MjA4MTUwODcwNH0.Hj7QOEs_bhrxEPRrV_P_MEglsuaMMeQrEMmCsEcp0ak',
  );

  final prefs = await SharedPreferences.getInstance();
  final bool seenOnboarding = prefs.getBool('seenOnboarding') ?? false;

  runApp(LifeCycleManager(child: App(showOnboarding: !seenOnboarding)));
}

class App extends StatelessWidget {
  final bool showOnboarding;
  const App({super.key, required this.showOnboarding});

  // 🎨 PALETTE CONSTANTS
  static const Color _primaryColor = Color(0xFF1A6EA0); // Deep Cerulean
  static const Color _primaryAccent = Color(0xFF5AA9E6); // Sky Glow
  static const Color _secondaryColor = Color(0xFF7C9E6F); // Earthy Sage
  static const Color _tertiaryColor = Color(0xFFFF8A6C); // Warm Coral
  static const Color _errorColor = Color(0xFFFC8181); // Soft Red
  static const Color _neutralDark = Color(0xFF2D3748); // Cool Slate
  static const Color _neutralLight = Color(0xFFF7FAFC); // Light Pearl

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PriceSpy',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _neutralLight, // Clean background
        // 1. GLOBAL COLOR SCHEME
        colorScheme: const ColorScheme.light(
          primary: _primaryColor,
          secondary: _secondaryColor,
          tertiary: _tertiaryColor,
          error: _errorColor,
          surface: Colors.white,
          onPrimary: Colors.white, // Text on Blue buttons
          onSecondary: Colors.white, // Text on Green buttons
          onSurface: _neutralDark, // Standard Text Color
        ),

        // 2. APP BAR THEME
        appBarTheme: const AppBarTheme(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),

        // 3. BUTTON THEME (Global Styling)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),

        // 4. CARD THEME
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        ),

        // 5. INPUT DECORATION (Text Fields)
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primaryColor, width: 2),
          ),
        ),
      ),
      home: showOnboarding ? const OnboardingPage() : const SplashScreen(),
    );
  }
}
