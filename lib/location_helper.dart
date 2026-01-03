import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';

class LocationHelper {
  // 1. Get the current raw position (Lat/Long)
  Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if GPS hardware is turned on
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // 🟢 FIX: Return null instead of error so app continues without location
      return null;
    }

    // Check Permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // 🟢 FIX: Permission denied, return null to allow app to proceed
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // 🟢 FIX: Handle permanent denial gracefully
      // Ideally, the UI should check this null and show a "Open Settings" button,
      // but returning null here prevents the app from crashing/stuck loading.
      return null;
    }

    // Get the actual position
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(
          seconds: 10,
        ), // Prevent infinite loading if GPS is weak
      );
    } catch (e) {
      // 🟢 FIX: Fallback to last known position if current fetch fails/times out
      debugPrint("Error fetching precise location: $e. Trying last known.");
      return await Geolocator.getLastKnownPosition();
    }
  }

  // 2. Convert Lat/Long to a Readable Shop/Street/Town Name
  Future<String> getAddressFromCoordinates(double lat, double long) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, long);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];

        // Priority 1: Specific Name (e.g. "Melcom" or "Sunyani Polytechnic")
        if (place.name != null &&
            place.name!.isNotEmpty &&
            !place.name!.contains('+')) {
          return place.name!;
        }

        // Priority 2: Street Name
        if (place.street != null &&
            place.street!.isNotEmpty &&
            place.street!.toLowerCase() != "unnamed road") {
          return place.street!;
        }

        // Priority 3: SubLocality or Locality (Neighborhood/Town)
        return place.subLocality ?? place.locality ?? "Nearby Area";
      }
      return "Unknown Location";
    } catch (e) {
      debugPrint("Geocoding Error: $e");
      return "Location details unavailable";
    }
  }
}
