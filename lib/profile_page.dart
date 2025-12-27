import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:cached_network_image/cached_network_image.dart';

import 'sidebar_drawer.dart';
import 'login_page.dart'; // 🟢 Ensure this is imported for redirection

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _callController = TextEditingController();
  final _whatsappController = TextEditingController();

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

    _nameController.text = user?.displayName ?? "";
    _currentPhotoUrl = user?.photoURL;

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
          SnackBar(
            content: const Text("Image updated! Don't forget to Save."),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green[800],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
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

      await user!.updateDisplayName(newName);
      if (_currentPhotoUrl != null) {
        await user!.updatePhotoURL(_currentPhotoUrl);
      }

      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        'uid': user!.uid,
        'displayName': newName,
        'username': newName,
        'photoUrl': _currentPhotoUrl,
        'photoURL': _currentPhotoUrl,
        'call_number': callNum,
        'whatsapp_number': whatsappNum,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("✅ Profile updated successfully!"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green[800],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 5. DELETE ACCOUNT LOGIC ---
  Future<void> _deleteAccount() async {
    if (user == null) return;

    // 1. Confirm Dialog
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          "Delete Account?",
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "This action is permanent. Your profile and user data will be deleted forever. You cannot undo this.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("DELETE FOREVER"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      // 2. Delete Firestore Record
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .delete();

      // 3. Delete Authentication Record
      await user!.delete();

      // 4. Redirect to Login
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        // If user hasn't logged in recently, Firebase requires re-auth
        String msg = "Error deleting account.";
        if (e.code == 'requires-recent-login') {
          msg =
              "Security: Please log out and log in again to delete your account.";
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndCropImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Colors.purple),
              title: const Text('Take a Photo'),
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

  void _viewProfilePicture() {
    if (_currentPhotoUrl == null || _currentPhotoUrl!.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: _currentPhotoUrl!,
                placeholder: (context, url) =>
                    const CircularProgressIndicator(),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
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
      backgroundColor: Colors.grey[50],
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text(
          "Edit Profile",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            // --- AVATAR ---
            Center(
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: _viewProfilePicture,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 65,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: _currentPhotoUrl != null
                            ? CachedNetworkImageProvider(_currentPhotoUrl!)
                            : null,
                        child: _currentPhotoUrl == null
                            ? Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.grey[400],
                              )
                            : null,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 4,
                    child: GestureDetector(
                      onTap: _showImageSourceActionSheet,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green[700],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // --- INPUT FIELDS ---
            _buildModernTextField(
              controller: _nameController,
              label: "Full Name",
              icon: Icons.person_rounded,
            ),
            const SizedBox(height: 20),
            _buildModernTextField(
              controller: _callController,
              label: "Phone Number",
              icon: Icons.phone_rounded,
              inputType: TextInputType.phone,
              iconColor: Colors.blue[700],
            ),
            const SizedBox(height: 20),
            _buildModernTextField(
              controller: _whatsappController,
              label: "WhatsApp Number",
              icon: FontAwesomeIcons.whatsapp,
              inputType: TextInputType.phone,
              iconColor: Colors.green[600],
            ),

            const SizedBox(height: 50),

            // --- SAVE BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  foregroundColor: Colors.white,
                  elevation: 5,
                  shadowColor: Colors.green.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        "SAVE CHANGES",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
              ),
            ),

            // --- DELETE BUTTON ---
            const SizedBox(height: 30),
            TextButton.icon(
              onPressed: _isLoading ? null : _deleteAccount,
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text(
                "Delete Account Forever",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
    Color? iconColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: inputType,
        style: const TextStyle(fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(icon, color: iconColor ?? Colors.grey[600]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
