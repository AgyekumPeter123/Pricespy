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

  // Focus Nodes (For Smooth Keyboard Navigation)
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _descFocus = FocusNode();
  final FocusNode _priceFocus = FocusNode();
  final FocusNode _unitFocus = FocusNode();
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
  bool _isAnalyzing = false;

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
    } else {
      _detectLocation();
    }
  }

  @override
  void dispose() {
    // Dispose FocusNodes to prevent memory leaks
    _nameFocus.dispose();
    _descFocus.dispose();
    _priceFocus.dispose();
    _unitFocus.dispose();
    _shopNameFocus.dispose();
    _phoneFocus.dispose();
    _locationFocus.dispose();
    _landmarkFocus.dispose();

    // Dispose Controllers
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

  // ... (Keep existing _detectLocation, _listenToDescription, _pickProductImage, _pickShopImage, _analyzeImage, _saveProduct logic exactly as is)

  Future<void> _detectLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    if (mounted) setState(() => _currentPosition = position);

    try {
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
      debugPrint("Address error: $e");
    }
  }

  void _listenToDescription() async {
    if (!_isListening) {
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Microphone permission required")),
          );
        return;
      }
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
              if (_descriptionController.text.isNotEmpty) {
                _descriptionController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _descriptionController.text.length),
                );
              }
            });
          },
        );
      } else {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Speech unavailable")));
        setState(() => _isListening = false);
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  Future<void> _pickProductImage() async {
    final file = await _imageHelper.pickImage();
    if (file != null) {
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop',
            toolbarColor: Colors.green,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: 'Crop'),
        ],
      );
      if (cropped != null) {
        setState(() => _productImage = File(cropped.path));
        await _analyzeImage(File(cropped.path));
      }
    }
  }

  Future<void> _pickShopImage() async {
    final file = await _imageHelper.pickImage();
    if (file != null) {
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Shop Front',
            toolbarColor: Colors.blue,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: 'Shop Front'),
        ],
      );
      if (cropped != null) {
        setState(() => _shopFrontImage = File(cropped.path));
      }
    }
  }

  Future<void> _analyzeImage(File image) async {
    setState(() {
      _isAnalyzing = true;
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
        'Table',
        'Design',
        'Technology',
        'Electronic device',
        'Rectangle',
        'Circle',
        'Square',
        'Shape',
        'Pattern',
        'Texture',
        'Close-up',
        'Hand',
        'Finger',
        'Thumb',
        'Nail',
        'Flesh',
        'Skin',
        'Human',
        'Person',
        'Selfie',
        'Metal',
        'Plastic',
        'Glass',
        'Wood',
        'Leather',
        'Denim',
        'Jeans',
        'Textile',
        'Fabric',
        'Material',
        'Mesh',
        'Automotive design',
        'Automotive tire',
        'Rim',
        'Tread',
        'Synthetic rubber',
        'Snapshot',
        'Photography',
        'Image',
        'Color',
      ];

      for (var l in labels) {
        if (!ignoredLabels.contains(l.label)) newSuggestions.add(l.label);
      }

      for (TextBlock block in recognizedText.blocks) {
        String text = block.text.trim();
        if (RegExp(r'^\d+(\.\d{2})?$').hasMatch(text) || text.contains('₵')) {
          foundPrice = text.replaceAll(RegExp(r'[^0-9.]'), '');
        } else if (text.length > 3 && text.length < 20) {
          String cleanText = text.replaceAll(RegExp(r'[^\w\s]'), '');
          if (cleanText.isNotEmpty) newSuggestions.insert(0, cleanText);
        }
      }
      if (mounted) {
        setState(() {
          _aiSuggestions = newSuggestions.take(8).toList();
          if (foundPrice != null) _priceController.text = foundPrice;
        });
      }
      imageLabeler.close();
      textRecognizer.close();
    } catch (e) {
      debugPrint("AI Error: $e");
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _saveProduct() async {
    if (_nameController.text.isEmpty || _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill Name and Price")),
      );
      return;
    }
    if (_posterType == 'Shop Owner' && _shopNameController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter Shop Name")));
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
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Updated Successfully!")),
          );
      } else {
        await FirebaseFirestore.instance.collection('posts').add(dataMap);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Spy Report Saved!"),
              backgroundColor: Colors.green,
            ),
          );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- SMOOTH UI WIDGETS ---

  InputDecoration _smoothDecoration(
    String label, {
    IconData? icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, color: Colors.grey[600]) : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      floatingLabelStyle: TextStyle(color: Colors.green[800]),
    );
  }

  Widget _buildTypeSelection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Who are you reporting for?",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              _typeCard("Individual", Icons.person, Colors.green, 'Individual'),
              const SizedBox(width: 15),
              _typeCard(
                "Shop / Market",
                Icons.store,
                Colors.blue,
                'Shop Owner',
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _typeCard(String title, IconData icon, Color color, String type) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _posterType = type;
          _currentStep = 1;
        }),
        child: Container(
          height: 130,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Photo Picker (Clean & Smooth)
        GestureDetector(
          onTap: _pickProductImage,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 160,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
              image: _productImage != null
                  ? DecorationImage(
                      image: FileImage(_productImage!),
                      fit: BoxFit.cover,
                    )
                  : (_existingImageUrl != null && _existingImageUrl!.isNotEmpty)
                  ? DecorationImage(
                      image: NetworkImage(_existingImageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: (_productImage == null && _existingImageUrl == null)
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_rounded,
                        color: Colors.green,
                        size: 48,
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Tap to add photo",
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : (_isAnalyzing
                      ? const Center(child: CircularProgressIndicator())
                      : null),
          ),
        ),

        // 2. AI Suggestions
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
                    backgroundColor: Colors.green[50],
                    labelStyle: TextStyle(color: Colors.green[900]),
                    onPressed: () =>
                        _nameController.text = _aiSuggestions[index],
                  ),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 20),

        // 3. Name Field
        TextField(
          controller: _nameController,
          focusNode: _nameFocus,
          textInputAction: TextInputAction.next, // KEY for smoothness
          decoration: _smoothDecoration("Product Name"),
        ),

        const SizedBox(height: 12),

        // 4. Description with Mic
        TextField(
          controller: _descriptionController,
          focusNode: _descFocus,
          textInputAction: TextInputAction.next,
          maxLines: 2,
          decoration: _smoothDecoration(
            "Description / Details",
            suffix: GestureDetector(
              onTap: _listenToDescription,
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: _isListening ? Colors.red : Colors.grey,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 5. Shop Name or Condition
        if (_posterType == 'Shop Owner')
          TextField(
            controller: _shopNameController,
            focusNode: _shopNameFocus,
            textInputAction: TextInputAction.next,
            decoration: _smoothDecoration("Shop Name", icon: Icons.store),
          )
        else
          DropdownButtonFormField<String>(
            value: _itemCondition,
            items: [
              'New',
              'Used',
              'Refurbished',
            ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _itemCondition = v!),
            decoration: _smoothDecoration("Item Condition"),
          ),

        const SizedBox(height: 12),

        // 6. Price and Unit Row
        Row(
          children: [
            Expanded(
              flex: 4,
              child: TextField(
                controller: _priceController,
                focusNode: _priceFocus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: _smoothDecoration(
                  "Price",
                  icon: Icons.attach_money,
                ), // Using attach_money as simple icon, prefix text handles currency
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Autocomplete<String>(
                    initialValue: TextEditingValue(text: _selectedUnit),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') return _marketUnits;
                      return _marketUnits.where((String option) {
                        return option.toLowerCase().contains(
                          textEditingValue.text.toLowerCase(),
                        );
                      });
                    },
                    onSelected: (String selection) => _selectedUnit = selection,
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                          controller.addListener(() {
                            _selectedUnit = controller.text;
                          });
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            textInputAction: TextInputAction.next,
                            decoration: _smoothDecoration(
                              "Unit",
                              suffix: const Icon(
                                Icons.arrow_drop_down,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        },
                  );
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),
        Text(
          "Contact & Location",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 12),

        // 7. Phone
        TextField(
          controller: _phoneController,
          focusNode: _phoneFocus,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          decoration: _smoothDecoration("Call Number", icon: Icons.phone),
        ),

        const SizedBox(height: 12),

        // 8. Location
        TextField(
          controller: _locationController,
          focusNode: _locationFocus,
          textInputAction: TextInputAction.next,
          decoration: _smoothDecoration(
            "Street / Area",
            suffix: IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _detectLocation,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 9. Landmark
        TextField(
          controller: _landmarkController,
          focusNode: _landmarkFocus,
          textInputAction: TextInputAction.done, // Closes keyboard
          decoration: _smoothDecoration("Closest Landmark", icon: Icons.flag),
        ),

        if (_posterType == 'Shop Owner') ...[
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _pickShopImage,
            child: Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.shade200,
                  width: 1,
                  style: BorderStyle.solid,
                ),
                image: _shopFrontImage != null
                    ? DecorationImage(
                        image: FileImage(_shopFrontImage!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _shopFrontImage == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.storefront, color: Colors.blue),
                        Text("Add Shop Front Photo"),
                      ],
                    )
                  : null,
            ),
          ),
        ],

        const SizedBox(height: 30),

        // 10. Submit Button
        ElevatedButton(
          onPressed: _isLoading ? null : _saveProduct,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[800],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
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
                  "POST REPORT",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
        const SizedBox(height: 20), // Padding for bottom safe area
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // FIX: Removed manual padding calculation.
    // We let the SingleChildScrollView inside the sheet handle the content flow naturally.
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
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
          // Scrollable Content
          Flexible(
            child: SingleChildScrollView(
              physics:
                  const BouncingScrollPhysics(), // Smooth iOS-style scrolling
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _currentStep == 0 ? _buildTypeSelection() : _buildForm(),
            ),
          ),
        ],
      ),
    );
  }
}
