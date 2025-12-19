import 'package:flutter/material.dart';
import 'sidebar_drawer.dart';

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Clean background
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text("Safety & Terms"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: Column(
          children: [
            // --- 1. APP LOGO ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/icon/app_icon.png', // Ensure you saved the logo here
                height: 100,
                width: 100,
                errorBuilder: (c, o, s) => Icon(
                  Icons.security_rounded,
                  size: 80,
                  color: Colors.green[800],
                ), // Fallback if image fails
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              "Important Disclaimer",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Your safety is our priority. Please read carefully.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 40),

            // --- 2. SAFETY SECTIONS ---
            _buildSafetySection(
              title: "Location Tracking",
              content:
                  "Our app uses GPS to show you items nearby. While this is convenient, always meet strangers in safe, public places like police stations or busy malls.",
              icon: Icons.my_location,
              color: Colors.blue,
            ),

            _buildSafetySection(
              title: "AI & Voice Data",
              content:
                  "We use AI to scan product images and convert your voice to text. This data is processed securely to help list items faster. Do not record sensitive personal info.",
              icon: Icons.smart_toy,
              color: Colors.purple,
            ),

            _buildSafetySection(
              title: "Live Camera Only",
              content:
                  "To prevent scams, uploads are restricted to live camera photos. This ensures you see exactly what the item looks like right now.",
              icon: Icons.camera_alt,
              color: Colors.orange,
            ),

            _buildSafetySection(
              title: "Financial Safety",
              content:
                  "Never send money before seeing the item. Do not share bank OTPs or passwords. We provide chats for communication; use them wisely.",
              icon: Icons.lock,
              color: Colors.red,
            ),

            const SizedBox(height: 30),

            // --- 3. WARNING BOX ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red[800],
                    size: 30,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      "If a deal sounds too good to be true, it probably is. Stay vigilant!",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red[900],
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 60),

            // --- 4. FOOTER MESSAGE ---
            const Divider(),
            const SizedBox(height: 20),
            Text(
              "FIND . COMPARE . TRADE", // 3 words separated by dot (Visual style)
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 4.0,
                color: Colors.green[900],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Enjoy the App!",
              style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetySection({
    required String title,
    required String content,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
