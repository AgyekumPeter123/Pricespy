import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'login_page.dart'; // Import your Login Page

class RestrictedPage extends StatelessWidget {
  final DateTime? until;

  const RestrictedPage({super.key, this.until});

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
    String formattedDate = until != null
        ? DateFormat('MMMM dd, yyyy - hh:mm a').format(until!)
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
