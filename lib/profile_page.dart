import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // We use 'User' from here
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    as sb; // FIX: Added prefix 'sb'
import 'package:cached_network_image/cached_network_image.dart';

import 'sidebar_drawer.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _callController = TextEditingController();
  final _whatsappController = TextEditingController();

  // This now correctly refers to Firebase Auth's User
  final User? user = FirebaseAuth.instance.currentUser;

  bool _isLoading = false;
  String? _currentPhotoUrl;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserData();
  }

  // --- 1. LOAD INITIAL DATA ---
  Future<void> _loadCurrentUserData() async {
    if (user == null) return;

    // Set initial values from Firebase Auth
    _nameController.text = user?.displayName ?? "";
    _currentPhotoUrl = user?.photoURL;

    // Fetch extra details (phone numbers) from Firestore
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _callController.text = data['call_number'] ?? "";
          _whatsappController.text = data['whatsapp_number'] ?? "";
          // If Firestore has a fresher photo, use it
          _currentPhotoUrl =
              data['photoUrl'] ?? data['photoURL'] ?? _currentPhotoUrl;
        });
      }
    } catch (e) {
      debugPrint("Error loading profile: $e");
    }
  }

  // --- 2. IMAGE PICKING & CROPPING ---
  Future<void> _pickAndCropImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 50,
    );

    if (pickedFile != null) {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Adjust Profile Picture',
            toolbarColor: Colors.green[800],
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
          IOSUiSettings(
            title: 'Adjust Profile Picture',
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
        ],
      );

      if (croppedFile != null) {
        // Start loading before calling the upload
        setState(() => _isLoading = true);
        await _uploadImageToSupabase(File(croppedFile.path));
      }
    }
  }

  // --- 3. UPLOAD TO SUPABASE ---
  Future<void> _uploadImageToSupabase(File imageFile) async {
    setState(() => _isLoading = true);
    try {
      final String fileName =
          '${user!.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // FIX: Used the 'sb' prefix here to access Supabase
      await sb.Supabase.instance.client.storage
          .from('product-images')
          .upload(fileName, imageFile);

      final String downloadUrl = sb.Supabase.instance.client.storage
          .from('product-images')
          .getPublicUrl(fileName);

      setState(() {
        _currentPhotoUrl = downloadUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Image uploaded! Press Save to apply changes."),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 4. SAVE PROFILE TO FIREBASE ---
  Future<void> _updateProfile() async {
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final String newName = _nameController.text.trim();
      final String callNum = _callController.text.trim();
      final String whatsappNum = _whatsappController.text.trim();

      // A. Update Firebase Auth Profile (Local display)
      await user!.updateDisplayName(newName);
      if (_currentPhotoUrl != null) {
        await user!.updatePhotoURL(_currentPhotoUrl);
      }

      // B. Update Firestore (Global display for chats/posts)
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        'uid': user!.uid,
        'displayName': newName,
        'username': newName, // Sync both for compatibility
        'photoUrl': _currentPhotoUrl,
        'photoURL': _currentPhotoUrl,
        'call_number': callNum,
        'whatsapp_number': whatsappNum,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile updated successfully!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to update: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndCropImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickAndCropImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- NEW: View Large Profile Picture (FIXED SIZE) ---
  void _viewProfilePicture() {
    if (_currentPhotoUrl == null || _currentPhotoUrl!.isEmpty) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black, // Dark background
        insetPadding: EdgeInsets.zero, // Remove padding to use full screen
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Interactive Viewer for Zooming
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                alignment: Alignment.center,
                child: CachedNetworkImage(
                  imageUrl: _currentPhotoUrl!,
                  placeholder: (context, url) =>
                      const CircularProgressIndicator(color: Colors.white),
                  errorWidget: (context, url, error) => const Icon(
                    Icons.broken_image,
                    size: 80,
                    color: Colors.white,
                  ),
                  fit: BoxFit.contain, // Ensures the whole image is visible
                ),
              ),
            ),
            // Close Button
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                style: IconButton.styleFrom(backgroundColor: Colors.black26),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // --- PROFILE IMAGE SECTION ---
            Stack(
              children: [
                // 1. Tap Avatar to VIEW
                GestureDetector(
                  onTap: _viewProfilePicture,
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _currentPhotoUrl != null
                        ? CachedNetworkImageProvider(_currentPhotoUrl!)
                        : null,
                    child: _currentPhotoUrl == null
                        ? Icon(Icons.person, size: 60, color: Colors.grey[400])
                        : null,
                  ),
                ),
                // 2. Tap Camera Icon to EDIT
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _showImageSourceActionSheet,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),

            // --- DETAILS SECTION ---
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Full Name",
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _callController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "Primary Call Number",
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _whatsappController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "WhatsApp Number",
                prefixIcon: Icon(Icons.message_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: _isLoading ? null : _updateProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[800],
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "SAVE CHANGES",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
