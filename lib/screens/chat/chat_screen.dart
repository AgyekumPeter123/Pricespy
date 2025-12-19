import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // REQUIRED FOR CLIPBOARD
import 'package:cloud_firestore/cloud_firestore.dart' hide Source;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- YOUR IMPORTS ---
import '../../services/chat_service.dart';
import '../../services/chat_status_service.dart'; // REINSTATED
import '../../encryption_service.dart';
import '../../MediaPreviewScreen.dart';
import '../../video_trimmer.dart';
import '../../gallery_viewer.dart';
import 'chat_bubble.dart';
import 'chat_input.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String receiverId;
  final String receiverName;
  final String? receiverPhoto;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.receiverId,
    required this.receiverName,
    this.receiverPhoto,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// Re-added WidgetsBindingObserver to detect when user leaves/returns to app
class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late ChatService _chatService;
  late ChatStatusService _statusService; // REINSTATED

  final TextEditingController _textController = TextEditingController();
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _itemListener = ItemPositionsListener.create();
  final String myUid = FirebaseAuth.instance.currentUser!.uid;

  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isRecorderLocked = false;
  Timer? _recordTimer;
  String _recordDuration = "00:00";
  DateTime? _recordStartTime;
  String? _currentlyPlayingUrl;

  Map<String, dynamic>? _replyMessage;
  bool _isSelectionMode = false;
  Set<String> _selectedIds = {};
  List<QueryDocumentSnapshot> _currentDocs = [];

  // WALLPAPER STATE
  Color _backgroundColor = const Color(0xFFE5E5E5);
  String? _highlightedMessageId;

  @override
  void initState() {
    super.initState();
    _chatService = ChatService(
      chatId: widget.chatId,
      myUid: myUid,
      receiverId: widget.receiverId,
    );

    // Initialize Status Service and start observing app state
    _statusService = ChatStatusService(currentUserId: myUid);
    WidgetsBinding.instance.addObserver(this);

    // FIX: Mark as read immediately on entry to clear Chat List badge
    _statusService.markMessagesAsRead(widget.chatId);
    _statusService.setUserOnline(true);

    _initRecorder();
    _loadWallpaper();
  }

  // Detect app background/foreground to update online status
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _statusService.setUserOnline(true);
      _statusService.markMessagesAsRead(widget.chatId);
    } else {
      _statusService.setUserOnline(false);
    }
  }

  // --- WALLPAPER LOGIC ---
  Future<void> _loadWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    final int? colorValue = prefs.getInt('wallpaper_${widget.chatId}');
    if (colorValue != null) {
      setState(() {
        _backgroundColor = Color(colorValue);
      });
    }
  }

  Future<void> _saveWallpaper(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wallpaper_${widget.chatId}', color.value);
    setState(() {
      _backgroundColor = color;
    });
  }

  void _showColorPicker() {
    final List<Color> colors = [
      const Color(0xFFE5E5E5), // Default
      const Color(0xFFFFF7D6), // Cream
      const Color(0xFFD4F1F4), // Light Blue
      const Color(0xFFE8DFF5), // Light Purple
      const Color(0xFFFFE4E1), // Rose
      const Color(0xFFE0F2F1), // Teal
      const Color(0xFF121212), // Dark
    ];

    showModalBottomSheet(
      context: context,
      builder: (c) => Container(
        height: 150,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Choose Wallpaper",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 15),
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: colors.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () {
                      _saveWallpaper(colors[index]);
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 15),
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: colors[index],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey[300]!),
                        boxShadow: [
                          const BoxShadow(color: Colors.black12, blurRadius: 4),
                        ],
                      ),
                      child: _backgroundColor.value == colors[index].value
                          ? const Icon(Icons.check, color: Colors.grey)
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- STANDARD INIT LOGIC ---
  Future<void> _initRecorder() async {
    await Permission.microphone.request();
    await _audioRecorder.openRecorder();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Stop observing app state
    _statusService.setUserOnline(false);
    _statusService.dispose();
    _textController.dispose();
    _audioRecorder.closeRecorder();
    _audioPlayer.dispose();
    _recordTimer?.cancel();
    super.dispose();
  }

  // --- SCROLL TO MESSAGE LOGIC ---
  void _scrollToMessage(String msgId) {
    int index = _currentDocs.indexWhere((doc) => doc.id == msgId);
    if (index != -1) {
      _scrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _highlightedMessageId = msgId);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightedMessageId = null);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Message not found (might be loaded above)"),
        ),
      );
    }
  }

  // --- MENU ACTIONS ---
  void _showMessageOptions(String docId, Map<String, dynamic> data, bool isMe) {
    bool isAlreadyDeleted = data['isDeleted'] == true;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAlreadyDeleted) ...[
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.orange,
                  ),
                  title: const Text("Remove this placeholder"),
                  onTap: () {
                    Navigator.pop(context);
                    _chatService.deleteMessage(docId, data, forEveryone: false);
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.reply, color: Colors.blue),
                  title: const Text("Reply"),
                  onTap: () {
                    Navigator.pop(context);
                    _handleReply(docId, data);
                  },
                ),
                if (data['type'] == 'text')
                  ListTile(
                    leading: const Icon(Icons.copy, color: Colors.grey),
                    title: const Text("Copy Text"),
                    onTap: () async {
                      Navigator.pop(context);
                      String text = "";
                      try {
                        text = EncryptionService.decryptMessage(
                          data['text'],
                          widget.chatId,
                        );
                      } catch (_) {}

                      await Clipboard.setData(ClipboardData(text: text));

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Copied!")),
                        );
                      }
                    },
                  ),
                const Divider(),
                if (isMe)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_forever,
                      color: Colors.red,
                    ),
                    title: const Text("Delete for everyone"),
                    onTap: () {
                      Navigator.pop(context);
                      _chatService.deleteMessage(
                        docId,
                        data,
                        forEveryone: true,
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.orange,
                  ),
                  title: const Text("Delete for me"),
                  onTap: () {
                    Navigator.pop(context);
                    _chatService.deleteMessage(docId, data, forEveryone: false);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Clear Chat?"),
        content: const Text(
          "This will clear all messages for you. They will remain for the other person.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              _chatService.clearChat();
            },
            child: const Text("Clear", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // --- ACTIONS ---
  void _toggleSelection(String docId) {
    setState(() {
      if (_selectedIds.contains(docId)) {
        _selectedIds.remove(docId);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(docId);
      }
    });
  }

  void _deleteSelected() async {
    List<String> ids = List.from(_selectedIds);
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });

    for (var id in ids) {
      final doc = _currentDocs.firstWhere((d) => d.id == id);
      final data = doc.data() as Map<String, dynamic>;
      bool isMe = data['senderId'] == myUid;
      bool isAlreadyDeleted = data['isDeleted'] == true;
      await _chatService.deleteMessage(
        id,
        data,
        forEveryone: isMe && !isAlreadyDeleted,
      );
    }
  }

  void _handleReply(String docId, Map<String, dynamic> data) {
    String replyText = "Media";
    String? thumbUrl = data['attachmentUrl'];

    if (data['type'] == 'text') {
      try {
        replyText = EncryptionService.decryptMessage(
          data['text'],
          widget.chatId,
        );
      } catch (_) {}
    } else {
      replyText = data['type'] == 'image'
          ? "Photo"
          : data['type'] == 'video'
          ? "Video"
          : "File";
    }

    setState(() {
      _replyMessage = {
        'id': docId,
        'senderName': data['senderId'] == myUid ? "You" : widget.receiverName,
        'text': replyText,
        'type': data['type'],
        'attachmentUrl': thumbUrl,
      };
    });
  }

  void _playAudio(String url) async {
    if (_currentlyPlayingUrl == url) {
      await _audioPlayer.stop();
      setState(() => _currentlyPlayingUrl = null);
    } else {
      Source source = url.startsWith('http')
          ? UrlSource(url)
          : DeviceFileSource(url);
      await _audioPlayer.play(source);
      setState(() => _currentlyPlayingUrl = url);
      _audioPlayer.onPlayerComplete.listen(
        (_) => setState(() => _currentlyPlayingUrl = null),
      );
    }
  }

  // --- MEDIA PICKING ---
  Future<void> _pickMedia(String type) async {
    final ImagePicker picker = ImagePicker();
    XFile? file;
    if (type == 'image') {
      file = await picker.pickImage(source: ImageSource.gallery);
      if (file != null && mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                MediaPreviewScreen(file: File(file!.path), type: 'image'),
          ),
        );
        if (result != null) {
          _chatService.sendMediaMessage(
            result['file'],
            'image',
            caption: result['caption'],
            replyMessage: _replyMessage,
          );
        }
      }
    } else if (type == 'video') {
      file = await picker.pickVideo(source: ImageSource.gallery);
      if (file != null && mounted) {
        final trimmed = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoTrimmerScreen(file: File(file!.path)),
          ),
        );
        if (trimmed != null) {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MediaPreviewScreen(file: trimmed, type: 'video'),
            ),
          );
          if (result != null) {
            _chatService.sendMediaMessage(
              result['file'],
              'video',
              caption: result['caption'],
              replyMessage: _replyMessage,
            );
          }
        }
      }
    }
    setState(() => _replyMessage = null);
  }

  // --- RECORDING ---
  void _startRecording() async {
    Directory temp = await getTemporaryDirectory();
    String path =
        '${temp.path}/audio_${DateTime.now().millisecondsSinceEpoch}.aac';
    await _audioRecorder.startRecorder(toFile: path);
    setState(() {
      _isRecording = true;
      _recordStartTime = DateTime.now();
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final d = DateTime.now().difference(_recordStartTime!);
      setState(
        () => _recordDuration =
            "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}",
      );
    });
  }

  void _stopRecording(bool send) async {
    _recordTimer?.cancel();
    String? path = await _audioRecorder.stopRecorder();
    setState(() {
      _isRecording = false;
      _isRecorderLocked = false;
      _recordDuration = "00:00";
    });
    if (send && path != null) {
      _chatService.sendMediaMessage(
        File(path),
        'audio',
        replyMessage: _replyMessage,
      );
    }
  }

  // --- BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelectionMode
          ? AppBar(
              backgroundColor: Colors.white,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: () => setState(() {
                  _isSelectionMode = false;
                  _selectedIds.clear();
                }),
              ),
              title: Text(
                "${_selectedIds.length} Selected",
                style: const TextStyle(color: Colors.black),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: _deleteSelected,
                ),
              ],
            )
          : AppBar(
              backgroundColor: Colors.green[800],
              titleSpacing: 0,
              title: StreamBuilder<DocumentSnapshot>(
                stream: _statusService.getUserPresenceStream(widget.receiverId),
                builder: (context, snapshot) {
                  String name = widget.receiverName;
                  String? photo = widget.receiverPhoto;
                  bool isOnline = false;

                  if (snapshot.hasData && snapshot.data!.exists) {
                    final userData =
                        snapshot.data!.data() as Map<String, dynamic>;
                    name =
                        userData['displayName'] ?? userData['username'] ?? name;
                    photo =
                        userData['photoUrl'] ?? userData['photoURL'] ?? photo;
                    isOnline = userData['isOnline'] ?? false;
                  }

                  return Row(
                    children: [
                      CircleAvatar(
                        backgroundImage: photo != null
                            ? CachedNetworkImageProvider(photo)
                            : null,
                        child: photo == null ? const Icon(Icons.person) : null,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontSize: 16)),
                          Text(
                            isOnline ? "Online" : "Offline",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'clear') _showClearChatDialog();
                    if (value == 'wallpaper') _showColorPicker();
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem(
                      value: 'wallpaper',
                      child: Row(
                        children: [
                          Icon(Icons.wallpaper, color: Colors.grey),
                          SizedBox(width: 10),
                          Text("Wallpaper"),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'clear',
                      child: Row(
                        children: [
                          Icon(Icons.cleaning_services, color: Colors.grey),
                          SizedBox(width: 10),
                          Text("Clear Chat"),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      backgroundColor: _backgroundColor,
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());

                // FIX: Continuous mark as read for new messages arriving while screen is open
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _statusService.markMessagesAsRead(widget.chatId);
                });

                _currentDocs = snapshot.data!.docs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final del = List.from(d['deletedFor'] ?? []);
                  return !del.contains(myUid);
                }).toList();

                if (_currentDocs.isEmpty) {
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        "No messages yet",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                return ScrollablePositionedList.builder(
                  itemScrollController: _scrollController,
                  itemPositionsListener: _itemListener,
                  reverse: true,
                  itemCount: _currentDocs.length,
                  itemBuilder: (context, index) {
                    final doc = _currentDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    String decrypted = "";
                    try {
                      decrypted = EncryptionService.decryptMessage(
                        data['text'] ?? '',
                        widget.chatId,
                      );
                    } catch (_) {}

                    return ChatBubble(
                      docId: doc.id,
                      data: data,
                      isMe: data['senderId'] == myUid,
                      decryptedText: decrypted,
                      isSelected: _selectedIds.contains(doc.id),
                      isSelectionMode: _isSelectionMode,
                      currentlyPlayingUrl: _currentlyPlayingUrl,
                      isHighlighted: _highlightedMessageId == doc.id,
                      onPlayAudio: _playAudio,
                      onLongPress: (id) {
                        if (!_isSelectionMode) {
                          _showMessageOptions(
                            id,
                            data,
                            data['senderId'] == myUid,
                          );
                        }
                      },
                      onTap: (id) => _toggleSelection(id),
                      onOpenGallery: (url, isVideo) {
                        if (!isVideo) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  GalleryViewer(galleryItems: [url]),
                            ),
                          );
                        }
                      },
                      onReplyTap: (replyId) => _scrollToMessage(replyId),
                      onRetry: (id) => {},
                    );
                  },
                );
              },
            ),
          ),
          ChatInput(
            controller: _textController,
            isRecording: _isRecording,
            recordDuration: _recordDuration,
            isLocked: _isRecorderLocked,
            replyMessage: _replyMessage,
            onCancelReply: () => setState(() => _replyMessage = null),
            onAttachmentPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (_) => Wrap(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.image),
                      title: const Text("Image"),
                      onTap: () {
                        Navigator.pop(context);
                        _pickMedia('image');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.videocam),
                      title: const Text("Video"),
                      onTap: () {
                        Navigator.pop(context);
                        _pickMedia('video');
                      },
                    ),
                  ],
                ),
              );
            },
            onStartRecording: _startRecording,
            onStopRecording: _stopRecording,
            onLockRecording: () => setState(() => _isRecorderLocked = true),
            onCancelRecording: () => _stopRecording(false),
            onSendMessage: (txt) {
              _chatService.sendTextMessage(txt, _replyMessage);
              _textController.clear();
              setState(() => _replyMessage = null);
            },
            onTyping: (val) {
              _statusService.setTypingStatus(widget.chatId, val.isNotEmpty);
            },
          ),
        ],
      ),
    );
  }
}
