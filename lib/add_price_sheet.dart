import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_cropper/image_cropper.dart';
import 'image_helper.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'profile_page.dart';

class AddPriceSheet extends StatefulWidget {
  final Map<String, dynamic>? existingData;
  final String? existingId;

  const AddPriceSheet({super.key, this.existingData, this.existingId});

  @override
  State<AddPriceSheet> createState() => _AddPriceSheetState();
}

class _AddPriceSheetState extends State<AddPriceSheet> {
  // Page Control
  int _currentStep = 0;

  // Controllers
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _locationController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _shopNameController = TextEditingController();

  // Focus Nodes
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _descFocus = FocusNode();
  final FocusNode _priceFocus = FocusNode();
  final FocusNode _shopNameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _locationFocus = FocusNode();
  final FocusNode _landmarkFocus = FocusNode();

  String _itemCondition = 'New';
  File? _productImage;
  File? _shopFrontImage;
  String? _existingImageUrl;
  bool _isLoading = false;
  final ImageHelper _imageHelper = ImageHelper();
  String _posterType = 'Individual';
  Position? _currentPosition;

  // Voice & Suggestions
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _selectedUnit = 'Item';
  List<String> _aiSuggestions = [];

  // 🟢 SEPARATE LOADING STATES
  bool _isAnalyzingProduct = false;
  bool _isAnalyzingShop = false; // New state for Shop OCR

  final List<String> _marketUnits = [
    'Item',
    'Kg',
    'Bowl',
    'Olonka',
    'Heap',
    'Bag',
    'Crate',
    'Tuber',
    '1L Bottle',
    '500ml',
    '750ml',
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();

    if (widget.existingData != null) {
      _loadExistingData();
    } else {
      _detectLocation();
      // 🟢 REMOVED: The initial _checkUserProfile() call.
      // Now it only checks when you tap "Individual".
    }

    // Listeners for Chart updates
    _nameController.addListener(() => setState(() {}));
    _priceController.addListener(() => setState(() {}));
    _locationController.addListener(() => setState(() {}));
    _landmarkController.addListener(() => setState(() {}));
    _descriptionController.addListener(
      () => setState(() {}),
    ); // Listener for description length
  }

  void _loadExistingData() {
    _currentStep = 1;
    final data = widget.existingData!;
    _nameController.text = data['product_name'] ?? '';
    _descriptionController.text = data['description'] ?? '';
    _priceController.text = (data['price'] ?? 0).toString();
    _phoneController.text = data['phone'] ?? '';
    _whatsappController.text = data['whatsapp_phone'] ?? data['phone'] ?? '';
    _locationController.text = data['location_name'] ?? '';
    _landmarkController.text = data['landmark'] ?? '';
    _posterType = data['poster_type'] ?? 'Individual';
    _selectedUnit = data['unit'] ?? 'Item';
    _existingImageUrl = data['image_url'];
    _shopNameController.text = data['shop_name'] ?? '';
    _itemCondition = data['item_condition'] ?? 'New';
  }

  Future<void> _checkUserProfile() async {
    if (_posterType != 'Individual') return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final String callNum = data['call_number'] ?? "";
        final String waNum = data['whatsapp_number'] ?? "";

        if (callNum.isNotEmpty) _phoneController.text = callNum;
        if (waNum.isNotEmpty) _whatsappController.text = waNum;

        if (callNum.isEmpty || waNum.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) _showIncompleteProfileDialog();
        }
      }
    } catch (e) {
      debugPrint("Profile Fetch Error: $e");
    }
  }

  void _showIncompleteProfileDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.contact_phone, color: Colors.blue),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Help Buyers Reach You",
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          "Your profile is private, but adding your contact numbers there allows buyers to call or WhatsApp you directly from this post.\n\nIt also saves you from typing them every time!",
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "I'll type it manually",
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[800],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
            child: const Text("Update Profile"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    _locationController.dispose();
    _landmarkController.dispose();
    _shopNameController.dispose();
    super.dispose();
  }

  Future<void> _detectLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;

    if (mounted) setState(() => _locationController.text = "Detecting...");

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) setState(() => _currentPosition = position);

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = "${place.street}, ${place.locality}";
        if (place.street == null || place.street!.isEmpty)
          address = "${place.subLocality}, ${place.locality}";
        String landmark = place.name ?? "";
        if (landmark == place.street) landmark = "";

        if (mounted) {
          setState(() {
            _locationController.text = address;
            _landmarkController.text = landmark;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _locationController.text = "");
    }
  }

  void _listenToDescription() async {
    if (!_isListening) {
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) return;
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening')
            setState(() => _isListening = false);
        },
        onError: (val) => setState(() => _isListening = false),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _descriptionController.text = val.recognizedWords;
            });
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  // --- PRODUCT IMAGE LOGIC ---
  Future<void> _pickProductImage() async {
    final file = await _imageHelper.pickImage();
    if (file == null) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Edit Photo',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Edit Photo'),
      ],
    );
    if (cropped != null) {
      setState(() {
        _productImage = File(cropped.path);
        _isAnalyzingProduct = true;
      });
      await _analyzeProductImage(File(cropped.path));
    }
  }

  Future<void> _analyzeProductImage(File image) async {
    setState(() {
      _isAnalyzingProduct = true;
      _aiSuggestions = [];
    });
    final InputImage inputImage = InputImage.fromFile(image);
    try {
      final imageLabeler = ImageLabeler(
        options: ImageLabelerOptions(confidenceThreshold: 0.5),
      );
      final labels = await imageLabeler.processImage(inputImage);
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);

      List<String> newSuggestions = [];
      String? foundPrice;

      final List<String> ignoredLabels = [
        'Room',
        'Furniture',
        'Metal',
        'Plastic',
        'Glass',
        'Hand',
        'Person',
        'Selfie',
      ];
      for (var l in labels) {
        if (!ignoredLabels.contains(l.label)) newSuggestions.add(l.label);
      }

      for (TextBlock block in recognizedText.blocks) {
        String text = block.text.trim().toLowerCase();
        final priceWithCurrencyRegex = RegExp(r'([₵$]|ghs)\s*(\d+(\.\d{2})?)');
        if (priceWithCurrencyRegex.hasMatch(text)) {
          var match = priceWithCurrencyRegex.firstMatch(text);
          if (match != null)
            foundPrice = match.group(0)!.replaceAll(RegExp(r'[^0-9.]'), '');
        }
        if (text.length > 3 && text.length < 20) {
          String cleanText = block.text.replaceAll(RegExp(r'[^\w\s]'), '');
          if (cleanText.isNotEmpty) newSuggestions.insert(0, cleanText);
        }
      }

      if (mounted) {
        setState(() {
          _aiSuggestions = newSuggestions.take(8).toList();
          if (foundPrice != null) _priceController.text = foundPrice!;
        });
      }
      imageLabeler.close();
      textRecognizer.close();
    } catch (e) {
      debugPrint("AI Error: $e");
    } finally {
      if (mounted) setState(() => _isAnalyzingProduct = false);
    }
  }

  // --- 🟢 NEW: SHOP IMAGE LOGIC (OCR) ---
  Future<void> _pickShopImage() async {
    final file = await _imageHelper.pickImage();
    if (file == null) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Shop Front',
          toolbarColor: Colors.blue[800],
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Shop Front'),
      ],
    );
    if (cropped != null) {
      setState(() => _shopFrontImage = File(cropped.path));
      // Trigger Shop Name analysis
      await _analyzeShopImage(File(cropped.path));
    }
  }

  // 🟢 Detects Shop Name from image
  Future<void> _analyzeShopImage(File image) async {
    setState(() => _isAnalyzingShop = true);
    final InputImage inputImage = InputImage.fromFile(image);

    try {
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);

      // HEURISTIC: Shop names are usually the largest text on the sign
      TextBlock? largestBlock;
      double maxArea = 0;

      for (var block in recognizedText.blocks) {
        double area = block.boundingBox.width * block.boundingBox.height;
        if (area > maxArea) {
          maxArea = area;
          largestBlock = block;
        }
      }

      if (largestBlock != null) {
        // Remove newlines to keep it single line if possible
        String shopName = largestBlock.text.replaceAll('\n', ' ').trim();

        if (mounted) {
          setState(() {
            _shopNameController.text = shopName;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Detected Shop: $shopName"),
              backgroundColor: Colors.blue[800],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      textRecognizer.close();
    } catch (e) {
      debugPrint("Shop OCR Error: $e");
    } finally {
      if (mounted) setState(() => _isAnalyzingShop = false);
    }
  }

  Future<void> _saveProduct() async {
    // 🟢 1. STRICT QUALITY CHECK
    if (_calculateQualityScore() < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Listing Quality must be 100% to post!"),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      String imageUrl = _existingImageUrl ?? "";
      if (_productImage != null)
        imageUrl = await _imageHelper.uploadImage(_productImage!) ?? "";

      String shopImageUrl = "";
      if (_shopFrontImage != null)
        shopImageUrl = await _imageHelper.uploadImage(_shopFrontImage!) ?? "";

      String whatsappNum = _whatsappController.text.trim();
      if (whatsappNum.isEmpty) whatsappNum = _phoneController.text.trim();

      final dataMap = {
        'search_key': _nameController.text.trim().toLowerCase(),
        'product_name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': double.tryParse(_priceController.text) ?? 0.0,
        'unit': _selectedUnit,
        'phone': _phoneController.text.trim(),
        'whatsapp_phone': whatsappNum,
        'location_name': _locationController.text.trim(),
        'landmark': _landmarkController.text.trim(),
        'latitude':
            _currentPosition?.latitude ??
            widget.existingData?['latitude'] ??
            0.0,
        'longitude':
            _currentPosition?.longitude ??
            widget.existingData?['longitude'] ??
            0.0,
        'image_url': imageUrl,
        'shop_front_image_url': shopImageUrl,
        'poster_type': _posterType,
        'shop_name': _posterType == 'Shop Owner'
            ? _shopNameController.text.trim()
            : "",
        'item_condition': _posterType == 'Individual' ? _itemCondition : "",
        'ai_tags': _aiSuggestions,
        'uploader_id': FirebaseAuth.instance.currentUser?.uid,
        'uploader_name':
            FirebaseAuth.instance.currentUser?.displayName ?? "Anonymous",
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (widget.existingId != null) {
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.existingId)
            .update(dataMap);
      } else {
        await FirebaseFirestore.instance.collection('posts').add(dataMap);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Spy Report Saved!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _calculateQualityScore() {
    double score = 0;
    if (_productImage != null ||
        (_existingImageUrl != null && _existingImageUrl!.isNotEmpty))
      score += 30;
    if (_nameController.text.isNotEmpty) score += 20;
    if (_priceController.text.isNotEmpty) score += 20;
    if (_locationController.text.isNotEmpty) score += 10;
    if (_landmarkController.text.isNotEmpty) score += 10;
    if (_descriptionController.text.length > 10) score += 10;
    return score;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: _currentStep == 0
                  ? _buildTypeSelection()
                  : _buildModernForm(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelection() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          const Text(
            "Who are you reporting for?",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              _buildModernTypeCard(
                "Individual",
                Icons.person_outline,
                Colors.green,
                'Individual',
              ),
              const SizedBox(width: 15),
              _buildModernTypeCard(
                "Shop / Market",
                Icons.storefront,
                Colors.blue,
                'Shop Owner',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernTypeCard(
    String title,
    IconData icon,
    Color color,
    String type,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          setState(() {
            _posterType = type;
            _currentStep = 1;
          });
          // 🟢 Only check profile if INDIVIDUAL is selected
          if (type == 'Individual') {
            await _checkUserProfile();
          }
        },
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.8), color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 45, color: Colors.white),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernForm() {
    double qualityScore = _calculateQualityScore();
    // 🟢 1. Disable button visual logic if score < 100
    bool isReady = qualityScore >= 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 📊 LISTING QUALITY CHART
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              SizedBox(
                height: 50,
                width: 50,
                child: PieChart(
                  PieChartData(
                    startDegreeOffset: 270,
                    sectionsSpace: 0,
                    centerSpaceRadius: 15,
                    sections: [
                      PieChartSectionData(
                        color: Colors.green[800],
                        value: qualityScore,
                        radius: 6,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        color: Colors.green[200],
                        value: 100 - qualityScore,
                        radius: 6,
                        showTitle: false,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Listing Quality: ${qualityScore.toInt()}%",
                    style: TextStyle(
                      color: Colors.green[900],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    isReady
                        ? "Perfect! Ready to post."
                        : "Reach 100% to enable posting.",
                    style: TextStyle(
                      color: isReady ? Colors.green[700] : Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 📸 IMAGE UPLOAD
        GestureDetector(
          onTap: _pickProductImage,
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade300), // Added border
              image: _productImage != null
                  ? DecorationImage(
                      image: FileImage(_productImage!),
                      fit: BoxFit.cover,
                    )
                  : (_existingImageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_existingImageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null),
            ),
            child: _productImage == null && _existingImageUrl == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        size: 40,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Upload Photo",
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : (_isAnalyzingProduct
                      ? const Center(child: CircularProgressIndicator())
                      : null),
          ),
        ),

        if (_aiSuggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _aiSuggestions.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(_aiSuggestions[index]),
                    backgroundColor: Colors.blue[50],
                    labelStyle: TextStyle(color: Colors.blue[800]),
                    onPressed: () => setState(
                      () => _nameController.text = _aiSuggestions[index],
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 20),

        _buildGlassInput(
          "Product Name",
          _nameController,
          icon: Icons.shopping_bag_outlined,
        ),
        const SizedBox(height: 12),
        _buildGlassInput(
          "Description",
          _descriptionController,
          maxLines: 3,
          suffix: IconButton(
            onPressed: _listenToDescription,
            icon: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: _isListening ? Colors.red : Colors.grey,
            ),
          ),
        ),

        const SizedBox(height: 12),
        Row(
          children: [
            // 🟢 3. RESIZED RATIOS: Price smaller, Combo larger
            Expanded(
              flex: 4, // 40% Width
              child: _buildGlassInput(
                "Price",
                _priceController,
                isNumber: true,
                prefix: "₵ ",
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 5, // 50% Width
              child: _buildGlassDropdown(),
            ),
          ],
        ),

        // 🟢 SHOP ONLY SECTION
        if (_posterType == 'Shop Owner') ...[
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _pickShopImage,
            child: Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue[200]!),
                image: _shopFrontImage != null
                    ? DecorationImage(
                        image: FileImage(_shopFrontImage!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _shopFrontImage == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isAnalyzingShop)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else ...[
                          Icon(Icons.storefront, color: Colors.blue[800]),
                          Text(
                            "Add Shop Front Photo",
                            style: TextStyle(
                              color: Colors.blue[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          _buildGlassInput("Shop Name", _shopNameController, icon: Icons.store),
        ],

        const SizedBox(height: 20),
        const Text(
          "Location & Contact",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 10),

        _buildGlassInput(
          "Location / Street",
          _locationController,
          suffix: IconButton(
            onPressed: _detectLocation,
            icon: const Icon(Icons.my_location, color: Colors.blue),
          ),
        ),
        const SizedBox(height: 12),
        _buildGlassInput(
          "Closest Landmark",
          _landmarkController,
          icon: Icons.flag_outlined,
        ),
        const SizedBox(height: 12),
        _buildGlassInput(
          "Contact Number",
          _phoneController,
          isNumber: true,
          icon: Icons.phone_outlined,
        ),
        const SizedBox(height: 12),
        _buildGlassInput(
          "WhatsApp Number",
          _whatsappController,
          isNumber: true,
          icon: Icons.message_outlined,
        ),

        const SizedBox(height: 30),

        SizedBox(
          height: 55,
          child: ElevatedButton(
            // 🟢 1. Disable button if not ready or loading
            onPressed: (_isLoading || !isReady) ? null : _saveProduct,
            style: ElevatedButton.styleFrom(
              backgroundColor: isReady ? Colors.green[800] : Colors.grey,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 5,
              shadowColor: Colors.green.withOpacity(0.4),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    "POST REPORT",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassInput(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
    int maxLines = 1,
    IconData? icon,
    String? prefix,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50, // 🟢 MODERNIZED
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300), // 🟢 MODERNIZED
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          prefixIcon: icon != null ? Icon(icon, color: Colors.grey[400]) : null,
          suffixIcon: suffix,
          border: InputBorder.none,
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildGlassDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50, // 🟢 MODERNIZED
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300), // 🟢 MODERNIZED
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _marketUnits.contains(_selectedUnit)
              ? _selectedUnit
              : _marketUnits[0],
          isExpanded: true,
          // 🟢 2. FIX OVERLAP: Ensure items have height and no weird padding
          itemHeight: 50,
          menuMaxHeight: 300,
          items: _marketUnits
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e, overflow: TextOverflow.ellipsis, maxLines: 1),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedUnit = v!),
        ),
      ),
    );
  }
}
