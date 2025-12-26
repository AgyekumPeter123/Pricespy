import 'package:flutter/material.dart';
import 'sidebar_drawer.dart';

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                'assets/icon/app_icon.png',
                height: 100,
                width: 100,
                errorBuilder: (c, o, s) => Icon(
                  Icons.security_rounded,
                  size: 80,
                  color: Colors.green[800],
                ),
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              "Safety First",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "PriceSpy is a community tool. Your safety depends on your vigilance.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 40),

            // --- 2. SAFETY SECTIONS ---
            _buildSafetySection(
              title: "Smart Radar Privacy",
              content:
                  "Our 12-point GPS scan shows you items within your chosen radius. We do not share your exact coordinates with other users.",
              icon: Icons.radar,
              color: Colors.blue,
            ),

            _buildSafetySection(
              title: "AI Vision Data",
              content:
                  "AI is used to read labels and price tags to speed up listing. This data is processed securely and is never shared with third parties.",
              icon: Icons.center_focus_strong,
              color: Colors.purple,
            ),

            // --- UPDATED SECTION FOR AI CONSULTANT ---
            _buildSafetySection(
              title: "AI Advice & Predictions",
              content:
                  "The AI Consultant and Churn Predictions are based on probability models. They are estimates, not guarantees. PriceSpy is not liable for any business decisions or financial losses resulting from AI-generated advice.",
              icon: Icons.psychology_alt,
              color: Colors.indigo,
            ),

            // -----------------------------------------
            _buildSafetySection(
              title: "Verified by Camera",
              content:
                  "To prevent scams, users are encouraged to use live camera photos. Always look for listings with clear, recent images.",
              icon: Icons.camera_alt,
              color: Colors.orange,
            ),

            _buildSafetySection(
              title: "In-App Safety",
              content:
                  "Use our secure chat for all negotiations. Never share personal OTPs, passwords, or pay for items you haven't seen in person.",
              icon: Icons.lock,
              color: Colors.red,
            ),

            _buildSafetySection(
              title: "Community Watch",
              content:
                  "If you spot a scam or fake price, report it immediately. Our admin team investigates every report to keep the community safe.",
              icon: Icons.gavel_rounded,
              color: Colors.teal,
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
                        color: const Color(0xFFB71C1C),
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
              "TRACK . COMPARE . SAVE",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 4.0,
                color: Colors.green[900],
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
              // 🟢 FIX: Replaced withOpacity with withValues
              color: color.withValues(alpha: 0.1),
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
