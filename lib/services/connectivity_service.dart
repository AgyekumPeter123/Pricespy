import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();

  /// Check if device has internet connectivity
  Future<bool> hasInternetConnection() async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Show a standardized no internet snackbar
  void showNoInternetSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "No internet connection. Please check your network and try again.",
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Check connectivity and show snackbar if no connection
  /// Returns true if connected, false if not connected (and shows snackbar)
  Future<bool> checkAndShowConnectivity(BuildContext context) async {
    final hasConnection = await hasInternetConnection();
    if (!hasConnection) {
      showNoInternetSnackBar(context);
    }
    return hasConnection;
  }
}
