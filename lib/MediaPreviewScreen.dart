import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:image_cropper/image_cropper.dart';

class MediaPreviewScreen extends StatefulWidget {
  final File file;
  final String type; // 'image' or 'video'

  const MediaPreviewScreen({super.key, required this.file, required this.type});

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  late File _currentFile;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  final TextEditingController _captionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentFile = widget.file;
    if (widget.type == 'video') {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    _videoController = VideoPlayerController.file(_currentFile);
    await _videoController!.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: true,
      looping: true,
    );
    setState(() {});
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _cropImage() async {
    if (widget.type != 'image') return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: _currentFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
      ],
    );
    if (cropped != null) {
      setState(() {
        _currentFile = File(cropped.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (widget.type == 'image')
            IconButton(icon: const Icon(Icons.crop), onPressed: _cropImage),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: widget.type == 'image'
                  ? Image.file(_currentFile)
                  : (_chewieController != null
                        ? Chewie(controller: _chewieController!)
                        : const CircularProgressIndicator()),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.black54,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _captionController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: "Add a caption...",
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                FloatingActionButton(
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.send, color: Colors.white),
                  onPressed: () {
                    // Return file and caption to ChatScreen
                    Navigator.pop(context, {
                      'file': _currentFile,
                      'caption': _captionController.text.trim(),
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
