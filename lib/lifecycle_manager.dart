import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/chat_status_service.dart';

class LifeCycleManager extends StatefulWidget {
  final Widget child;
  const LifeCycleManager({super.key, required this.child});

  @override
  State<LifeCycleManager> createState() => _LifeCycleManagerState();
}

class _LifeCycleManagerState extends State<LifeCycleManager>
    with WidgetsBindingObserver {
  ChatStatusService? _statusService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 🟢 Listen to Auth Changes (Login/Logout)
    // This ensures we track the CORRECT user if they switch accounts.
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        // User Logged In: Initialize Service & Set Online
        setState(() {
          _statusService = ChatStatusService(currentUserId: user.uid);
        });
        _statusService?.setUserOnline(true);
        _statusService?.markAllAsDelivered();
      } else {
        // User Logged Out: Set Offline & Cleanup
        _statusService?.setUserOnline(false);
        setState(() {
          _statusService = null;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If no user is logged in, do nothing
    if (_statusService == null) return;

    if (state == AppLifecycleState.resumed) {
      // 🟢 App Opened / Came to Foreground -> ONLINE
      _statusService!.setUserOnline(true);
      _statusService!.markAllAsDelivered();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      // 🔴 App Minimized / Closed -> OFFLINE
      _statusService!.setUserOnline(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
