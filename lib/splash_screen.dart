import 'dart:io'; // Required for Internet Check
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_page.dart';
import 'home_page.dart';
import 'restricted_page.dart';
import 'services/chat_status_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Start the check sequence immediately
    _checkInternetAndStart();
  }

  /// 1. Check Internet -> 2. Wait Delay -> 3. Check Auth/Restriction
  Future<void> _checkInternetAndStart() async {
    bool hasInternet = await _hasNetwork();

    if (!hasInternet) {
      _showNoInternetDialog();
      return;
    }

    // Artificial delay for branding (optional, keep if you like the animation)
    await Future.delayed(const Duration(seconds: 3));

    _checkAuthAndRedirect();
  }

  /// Simple ping to Google to verify actual internet access
  Future<bool> _hasNetwork() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  void _showNoInternetDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("No Internet Connection"),
        content: const Text("Please check your connection and try again."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _checkInternetAndStart(); // Retry
            },
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAuthAndRedirect() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _navigateTo(const LoginPage());
      return;
    }

    // Sync basic info
    await _syncUserProfile(user);

    // Chat cleanup: Mark messages delivered & User online
    final statusService = ChatStatusService(currentUserId: user.uid);
    await statusService.markAllAsDelivered();
    await statusService.setUserOnline(true);

    try {
      // Check Restriction Status
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        bool isRestricted = data['isRestricted'] ?? false;
        Timestamp? restrictedUntil = data['restrictedUntil'];

        if (isRestricted && restrictedUntil != null) {
          DateTime expiry = restrictedUntil.toDate();

          // If restriction is still active
          if (DateTime.now().isBefore(expiry)) {
            // Mark offline so they don't look active while blocked
            await statusService.setUserOnline(false);
            _navigateTo(RestrictedPage(until: expiry));
            return;
          } else {
            // Optional: Auto-unrestrict if time has passed (cleanup)
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'isRestricted': false});
          }
        }
      }
      _navigateTo(const HomePage());
    } catch (e) {
      // On error (e.g., offline cache issues), default to Home or Login
      // Safety: Go to Home, or handle specific errors
      _navigateTo(const HomePage());
    }
  }

  Future<void> _syncUserProfile(User user) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignore sync errors if offline
    }
  }

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
            // Ensure you have this asset, otherwise it will crash
            Lottie.asset(
              'assets/files/splash_anim.json',
              height: 300,
              reverse: true,
              repeat: true,
              fit: BoxFit.fill,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.flash_on, size: 100, color: Colors.green),
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
