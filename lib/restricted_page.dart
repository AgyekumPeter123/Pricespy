import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'login_page.dart'; // Import your Login Page
import 'home_page.dart'; // Import Home Page

class RestrictedPage extends StatefulWidget {
  final DateTime? until;

  const RestrictedPage({super.key, this.until});

  @override
  State<RestrictedPage> createState() => _RestrictedPageState();
}

class _RestrictedPageState extends State<RestrictedPage> {
  late Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Check every minute if restriction has expired
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (widget.until != null && DateTime.now().isAfter(widget.until!)) {
        // Restriction expired, lift it
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'isRestricted': false, 'restrictedUntil': null});

          // Notify admin
          await _notifyAdminRestrictionLifted(user.email ?? 'Unknown user');

          // Navigate to home
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const HomePage()),
              (route) => false,
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

  Future<void> _handleLogout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      // Navigate to Login Page and remove all previous routes
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    String formattedDate = widget.until != null
        ? DateFormat('MMMM dd, yyyy - hh:mm a').format(widget.until!)
        : "Indefinitely";

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 100, color: Colors.red),
            const SizedBox(height: 30),
            const Text(
              "Account Restricted",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            Text(
              "Your access to PriceSpy has been restricted due to a violation of our community guidelines.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontSize: 16),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Restricted Until:\n$formattedDate",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => _handleLogout(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  "Log Out",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
