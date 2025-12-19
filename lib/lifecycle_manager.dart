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
    _initStatusService();
  }

  void _initStatusService() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _statusService = ChatStatusService(currentUserId: user.uid);
      _statusService!.setUserOnline(true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_statusService == null) {
      // Re-init if user logged in after app started
      _initStatusService();
    }

    if (_statusService != null) {
      if (state == AppLifecycleState.resumed) {
        _statusService!.setUserOnline(true);
        _statusService!.markAllAsDelivered();
      } else {
        // Paused, Detached, or Inactive (User left the app entirely)
        _statusService!.setUserOnline(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
