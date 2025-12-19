PriceSpy: Hyperlocal Price Discovery & Monitoring
PriceSpy is a community-driven market intelligence platform designed to help users stop overpaying for everyday goods and services. By crowdsourcing real-time price data, users can compare costs across their local area using an advanced 12-point GPS radar system and automated AI-powered listing tools.

🚀 The Problem
Local shoppers often face "price blindness" because costs for items like construction materials, groceries, and electronics are scattered across different physical shops. Without a central real-time database, consumers often overpay simply because they lack the data to compare nearby options.

✨ Core Features
📡 Hyperlocal Discovery Radar
12-Point Directional Scan: Unlike standard radius searches, PriceSpy performs a high-precision scan every 30 degrees around the user's anchored GPS position.

Step-Sampling Intelligence: The app "walks" outward in increments (5km, 10km, etc.) to find the last known populated place, providing summaries like "North (Kadu +6km beyond)" so you know exactly which towns are covered.

Discovery Constraints: Automatically filters results to the last 48 hours to ensure data "freshness."

🤖 AI-Powered Reporting
Smart-Form Filling: Uses Google ML Kit (Image Labeling & Text Recognition) to scan product photos.

Logic-Based Auto-Fill:

Price: Recognizes ₵, ghs, and $ symbols to automatically populate the price field.

Unit: Identifies measurement standards (grams, ml, kg, litres, mm, yards) to fill the product unit field.

Voice Integration: Converts voice descriptions to text for hands-free listing in busy markets.

🕵️ Spy Alert System
Watchlist Surveillance: Users set specific keywords (e.g., "Milo" or "Cement") and a maximum budget.

Real-time Radar Alerts: The app "spies" on incoming community reports and notifies users instantly if a matching deal is posted within their custom radius.

💬 Professional Community Chat
WhatsApp-Style Ticks: Tiered read receipts showing Sent (1 tick), Delivered (2 grey ticks), and Read (2 blue ticks).

Security & Privacy: End-to-end encryption using AES-256 and dynamic chat visibility that hides cleared conversations until a new message arrives.

Multimedia Support: High-performance handling of images, video playback, and voice notes with local caching for speed.

🛡️ Security & Governance
Administrative Security Guard: A robust SplashScreen gate checks for user restrictions at every login.

Admin Console: Real-time moderation tools allowing admins to investigate reported content, issue warnings via chat, or apply time-bound account bans.

Verified Content: Prioritizes live camera photos to reduce the risk of scams and outdated price reports.

🛠️ Technical Stack
Framework: Flutter

Database: Firebase Firestore

Storage: Supabase (Media & Assets)

AI Engine: Google ML Kit

Charts: FL Chart (Price Trend Visualization)

Email: SMTP (Mailer Package)

Track. Compare. Save. — PriceSpy
