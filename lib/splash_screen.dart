import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_page.dart';
import 'home_page.dart';
import 'restricted_page.dart'; // Make sure you created this file

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _startGuard();
  }

  Future<void> _startGuard() async {
    // 1. Minimum show time for your animation (3 seconds)
    await Future.delayed(const Duration(seconds: 3));

    // 2. Check if user is logged in
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _navigateTo(const LoginPage());
      return;
    }

    // --- NEW: SYNC USER PROFILE ---
    // This ensures they appear in the Admin Dashboard even if they just signed up
    await _syncUserProfile(user);

    // 3. User is logged in, check Firestore for restriction status
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        _navigateTo(const HomePage());
        return;
      }

      final data = doc.data() as Map<String, dynamic>;
      final bool isRestricted = data['isRestricted'] ?? false;
      final Timestamp? restrictedUntil = data['restrictedUntil'];

      if (isRestricted) {
        if (restrictedUntil != null &&
            DateTime.now().isAfter(restrictedUntil.toDate())) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'isRestricted': false, 'restrictedUntil': null});
          _navigateTo(const HomePage());
        } else {
          _navigateTo(RestrictedPage(until: restrictedUntil?.toDate()));
        }
      } else {
        _navigateTo(const HomePage());
      }
    } catch (e) {
      debugPrint("Auth Guard Error: $e");
      _navigateTo(const HomePage());
    }
  }

  // --- NEW METHOD: SYNC AUTH TO FIRESTORE ---
  Future<void> _syncUserProfile(User user) async {
    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final doc = await userRef.get();

      // If the document doesn't exist, create it with Google/Auth details
      if (!doc.exists) {
        await userRef.set(
          {
            'uid': user.uid,
            'email': user.email,
            'displayName':
                user.displayName ?? 'New Spy', // Grabs Google name if available
            'photoUrl':
                user.photoURL ?? '', // Grabs Google profile pic if available
            'isRestricted': false,
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        ); // Merge ensures we don't wipe existing sub-collections
        debugPrint("✅ Database record synchronized for: ${user.email}");
      }
    } catch (e) {
      debugPrint("❌ Database Sync Error: $e");
    }
  }

  /*************  ✨ Windsurf Command ⭐  *************/
  /// Replaces the current route with the given [page].
  ///
  /// This is used to navigate away from the splash screen and auth guard.
  ///
  /// The [page] is the new route to be displayed.
  ///
  /// If the widget is not mounted, this does nothing.
  /*******  0f6e9eeb-ea52-4a2d-9af7-2e49bf5b9700  *******/
  void _navigateTo(Widget page) {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => page),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              'assets/files/splash_anim.json',
              height: 300,
              reverse: true,
              repeat: true,
              fit: BoxFit.fill,
            ),
            const SizedBox(height: 30),
            const Text(
              "PriceSpy",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.green,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Track. Compare. Save.",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 40),
            // Added a small loader to show the app is "checking"
            const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          ],
        ),
      ),
    );
  }
}
