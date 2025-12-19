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
      return Future.error(
        'Location services are disabled. Please turn on your GPS.',
      );
    }

    // Check Permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Logic: Tell user they must enable it in phone settings
      return Future.error(
        'Location permissions are permanently denied. Please enable them in your phone settings.',
      );
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
      // Fallback to last known position if current fetch fails
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
