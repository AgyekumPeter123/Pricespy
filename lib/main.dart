import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'splash_screen.dart';
import 'onboarding_page.dart';
import 'lifecycle_manager.dart'; // 🟢 NEW IMPORT

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(
    LifeCycleManager(
      // 🟢 WRAP THE ENTIRE APP HERE
      child: App(showOnboarding: !seenOnboarding),
    ),
  );
}

class App extends StatelessWidget {
  final bool showOnboarding;
  const App({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
