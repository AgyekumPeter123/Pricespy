import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import this

import 'splash_screen.dart';
import 'onboarding_page.dart'; // Import your new Onboarding Page

void main() async {
  // 1. Initialize bindings
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Firebase
  try {
    await Firebase.initializeApp();
    print("✅ Firebase initialized successfully");
  } catch (e) {
    print("❌ Firebase failed to load: $e");
  }

  // 3. Initialize Supabase
  await Supabase.initialize(
    url: 'https://vgrmjascnnmaajbdtxhr.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZncm1qYXNjbm5tYWFqYmR0eGhyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU5MzI3MDQsImV4cCI6MjA4MTUwODcwNH0.Hj7QOEs_bhrxEPRrV_P_MEglsuaMMeQrEMmCsEcp0ak',
  );

  // 4. Check Onboarding Status
  final prefs = await SharedPreferences.getInstance();
  final bool seenOnboarding = prefs.getBool('seenOnboarding') ?? false;

  // 5. RUN APP (Device Preview Removed)
  runApp(App(showOnboarding: !seenOnboarding));
}

class App extends StatelessWidget {
  final bool showOnboarding;

  const App({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // DevicePreview.locale and builder REMOVED here
      debugShowCheckedModeBanner: false,
      title: 'PriceSpy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: showOnboarding ? const OnboardingPage() : const SplashScreen(),
    );
  }
}
