import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'dart:io';

class GalleryViewer extends StatelessWidget {
  final List<String> galleryItems; // List of URLs or Paths
  final int initialIndex;

  const GalleryViewer({
    super.key,
    required this.galleryItems,
    this.initialIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PhotoViewGallery.builder(
        scrollPhysics: const BouncingScrollPhysics(),
        builder: (BuildContext context, int index) {
          final item = galleryItems[index];
          ImageProvider? provider;

          if (item.startsWith('http')) {
            provider = NetworkImage(item);
          } else {
            provider = FileImage(File(item));
          }

          return PhotoViewGalleryPageOptions(
            imageProvider: provider,
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
          );
        },
        itemCount: galleryItems.length,
        loadingBuilder: (context, event) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        pageController: PageController(initialPage: initialIndex),
      ),
    );
  }
}
