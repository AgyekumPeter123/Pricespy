import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_page.dart';
import 'home_page.dart';
import 'restricted_page.dart';
import 'services/chat_status_service.dart'; // 🟢 NEW IMPORT

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
    await Future.delayed(const Duration(seconds: 3));

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _navigateTo(const LoginPage());
      return;
    }

    await _syncUserProfile(user);

    // 🟢 NEW: Trigger the global "Delivered" sweep
    // This turns all 1-tick messages into 2-tick messages for the senders
    final statusService = ChatStatusService(currentUserId: user.uid);
    await statusService.markAllAsDelivered();
    await statusService.setUserOnline(true);

    try {
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
          if (DateTime.now().isBefore(expiry)) {
            await statusService.setUserOnline(
              false,
            ); // 🟢 Add this to hide restricted users
            _navigateTo(RestrictedPage(until: expiry));
            return;
          }
        }
      }
      _navigateTo(const HomePage());
    } catch (e) {
      _navigateTo(const HomePage());
    }
  }

  Future<void> _syncUserProfile(User user) async {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'photoURL': user.photoURL,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
