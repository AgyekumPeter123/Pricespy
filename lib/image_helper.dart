import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // We use Supabase now

class ImageHelper {
  final ImagePicker _picker = ImagePicker();

  // 1. Pick Image (Stays the same - this works perfectly)
  Future<File?> pickImage({bool fromCamera = true}) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 50, // Compress to save data
      );

      if (photo != null) {
        return File(photo.path);
      }
      return null;
    } catch (e) {
      print("Error picking image: $e");
      return null;
    }
  }

  // 2. Upload Image to Supabase (THE NEW FREE WAY)
  Future<String?> uploadImage(File imageFile) async {
    try {
      // Create a unique filename: "170999123.jpg"
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      // A. Upload the file to the "product-images" bucket
      await Supabase.instance.client.storage
          .from(
            'product-images',
          ) // Make sure you named your bucket exactly this in Supabase!
          .upload(fileName, imageFile);

      // B. Get the Public Link
      final String publicUrl = Supabase.instance.client.storage
          .from('product-images')
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      print("Supabase Upload failed: $e");
      return null;
    }
  }
}
