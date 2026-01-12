import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'sidebar_drawer.dart';
import 'constants/palette.dart'; // 🟢 Import Palette

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  // 🟢 Logic to open email
  Future<void> _contactSupport(BuildContext context) async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'agyekumpeter123@gmail.com',
      query:
          'subject=Report: Unusual Activity&body=Please describe the issue here:%0A%0A(Attaching evidence/screenshots solidifies reports and ensures quick action.)',
    );

    try {
      if (!await launchUrl(
        emailLaunchUri,
        mode: LaunchMode.externalApplication,
      )) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not open email app.")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error launching email: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text(
          "Safety & Terms",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Palette.primary, // 🟢 Updated to Blue
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.sort),
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
                // 🟢 Updated to Blue tint
                color: Palette.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/icon/app_icon.png',
                height: 100,
                width: 100,
                errorBuilder: (c, o, s) => const Icon(
                  Icons.security_rounded,
                  size: 80,
                  color: Palette.primary, // 🟢 Updated to Blue
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
              color: Palette.primary, // 🟢 Consistent Blue
            ),

            _buildSafetySection(
              title: "AI Vision Data",
              content:
                  "AI is used to read labels and price tags to speed up listing. This data is processed securely and is never shared with third parties.",
              icon: Icons.center_focus_strong,
              color: Colors.purple,
            ),

            _buildSafetySection(
              title: "AI Advice & Predictions",
              content:
                  "The AI Consultant and Churn Predictions are based on probability models. They are estimates, not guarantees. PriceSpy is not liable for any business decisions or financial losses resulting from AI-generated advice.",
              icon: Icons.psychology_alt,
              color: Colors.indigo,
            ),

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
              color: Palette.error, // 🟢 Consistent Red
            ),

            _buildSafetySection(
              title: "Community Watch",
              content:
                  "If you spot a scam or fake price, report it immediately. Our admin team investigates every report to keep the community safe.",
              icon: Icons.gavel_rounded,
              color: Palette.secondary, // 🟢 Sage Green for "Community/Success"
            ),

            // 🟢 NEW: Direct Reporting Section
            Padding(
              padding: const EdgeInsets.only(bottom: 25),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Palette.textMedium.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.support_agent,
                      color: Palette.textMedium,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Direct Reporting",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              "For other unusual reports, users can directly make reports via the ",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                height: 1.5,
                              ),
                            ),
                            InkWell(
                              onTap: () => _contactSupport(context),
                              child: Text(
                                "Support Team.",
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Palette.primary, // 🟢 Updated to Blue
                                  decoration: TextDecoration.underline,
                                  decorationColor: Palette.primary,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            Text(
                              "Adding evidence solidifies reports and ensures quick actions.",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // --- 3. WARNING BOX ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Palette.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Palette.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Palette.error,
                    size: 30,
                  ),
                  const SizedBox(width: 15),
                  const Expanded(
                    child: Text(
                      "If a deal sounds too good to be true, it probably is. Stay vigilant!",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Palette.error,
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
            const Text(
              "TRACK . COMPARE . SAVE",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 4.0,
                color: Palette.primary, // 🟢 Updated to Blue
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
