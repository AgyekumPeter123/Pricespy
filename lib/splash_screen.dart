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
  // 🟢 NEW: State for humanized feedback
  String _statusMessage = "Initializing...";

  @override
  void initState() {
    super.initState();
    // Start the check sequence immediately
    _checkInternetAndStart();
  }

  /// 1. Check Internet -> 2. Wait Delay -> 3. Check Auth/Restriction
  Future<void> _checkInternetAndStart() async {
    setState(() => _statusMessage = "Establishing secure connection...");

    bool hasInternet = await _hasNetwork();

    if (!hasInternet) {
      _showNoInternetDialog();
      return;
    }

    // Artificial delay for branding (optional, keep if you like the animation)
    setState(() => _statusMessage = "Loading resources...");
    await Future.delayed(const Duration(seconds: 2));

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
    setState(() => _statusMessage = "Verifying identity...");

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // Small delay to let user read the status
      await Future.delayed(const Duration(milliseconds: 500));
      _navigateTo(const LoginPage());
      return;
    }

    // 🟢 NEW: If Admin is logging in, run maintenance to clear expired restrictions for EVERYONE
    if (user.email == "agyekumpeter123@gmail.com") {
      _performAdminMaintenance(user.uid);
    }

    // Sync basic info
    setState(() => _statusMessage = "Syncing profile...");
    await _syncUserProfile(user);

    // Chat cleanup: Mark messages delivered & User online
    final statusService = ChatStatusService(currentUserId: user.uid);
    await statusService.markAllAsDelivered();
    await statusService.setUserOnline(true);

    try {
      // Check Restriction Status for the CURRENT user
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
            // Optional: Auto-unrestrict self if time has passed (cleanup)
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'isRestricted': false, 'restrictedUntil': null});

            // Notify admin about the automatic lift
            await _notifyAdminRestrictionLifted(user.email ?? 'Unknown user');
          }
        }
      }

      setState(() => _statusMessage = "Welcome back!");
      await Future.delayed(const Duration(milliseconds: 500));
      _navigateTo(const HomePage());
    } catch (e) {
      // On error (e.g., offline cache issues), default to Home or Login
      // Safety: Go to Home, or handle specific errors
      _navigateTo(const HomePage());
    }
  }

  // 🟢 NEW: Checks all users for expired restrictions when Admin opens app
  Future<void> _performAdminMaintenance(String adminUid) async {
    try {
      final now = DateTime.now();
      // 1. Get all restricted users
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('isRestricted', isEqualTo: true)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final Timestamp? restrictedUntil = data['restrictedUntil'];

        if (restrictedUntil != null) {
          final expiry = restrictedUntil.toDate();

          // 2. If time is up
          if (now.isAfter(expiry)) {
            // 3. Remove restriction
            await FirebaseFirestore.instance
                .collection('users')
                .doc(doc.id)
                .update({'isRestricted': false, 'restrictedUntil': null});

            // 4. Send Inbox Notification to Admin
            await FirebaseFirestore.instance
                .collection('users')
                .doc(adminUid)
                .collection('notifications')
                .add({
                  'message':
                      'Time due: Restriction automatically removed for ${data['email'] ?? 'User'}',
                  'type': 'alert',
                  'timestamp': FieldValue.serverTimestamp(),
                  'read': false,
                  'post_id': '', // Prevent null errors
                });
          }
        }
      }
    } catch (e) {
      debugPrint("Admin Maintenance Error: $e");
    }
  }

  Future<void> _notifyAdminRestrictionLifted(String userEmail) async {
    try {
      // Get admin UID
      final adminQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: 'agyekumpeter123@gmail.com')
          .limit(1)
          .get();

      if (adminQuery.docs.isNotEmpty) {
        final adminUid = adminQuery.docs.first.id;

        // Add notification to admin's inbox
        await FirebaseFirestore.instance
            .collection('users')
            .doc(adminUid)
            .collection('notifications')
            .add({
              'message':
                  'Restriction automatically lifted for user: $userEmail',
              'type': 'alert',
              'timestamp': FieldValue.serverTimestamp(),
              'read': false,
            });
      }
    } catch (e) {
      // Ignore notification errors
      debugPrint('Error sending admin notification: $e');
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
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.flash_on,
                size: 100,
                color: Color(0xFF1A6EA0),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              "PriceSpy",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A6EA0),
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

            // 🟢 MODERNIZED SECTION
            const SizedBox(height: 50),

            // 1. Humanized Status Text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Text(
                _statusMessage,
                key: ValueKey(_statusMessage),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            const SizedBox(height: 15),

            // 2. Sleek Linear Progress Indicator
            Container(
              width: 180,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
              ),
              child: const LinearProgressIndicator(
                backgroundColor: Color(0xFFE0E0E0),
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1A6EA0)),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
