import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/local_storage_service.dart';
import '../../media_viewers.dart';

class ChatBubble extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final bool isMe;
  final String decryptedText;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isHighlighted;
  final Function(String) onLongPress;
  final Function(String) onTap;
  final Function(String, bool) onOpenGallery;
  final String? currentlyPlayingUrl;
  final Function(String) onPlayAudio;
  final Function(String)? onReplyTap;
  final Function(String)? onRetry;

  const ChatBubble({
    super.key,
    required this.docId,
    required this.data,
    required this.isMe,
    required this.decryptedText,
    required this.isSelected,
    required this.isSelectionMode,
    this.isHighlighted = false,
    required this.onLongPress,
    required this.onTap,
    required this.onOpenGallery,
    required this.currentlyPlayingUrl,
    required this.onPlayAudio,
    this.onReplyTap,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => onLongPress(docId),
      onTap: () {
        if (isSelectionMode) onTap(docId);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: isSelected
            ? Colors.blue.withOpacity(0.2)
            : isHighlighted
            ? Colors.yellow.withOpacity(0.3)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.of(context).size.width *
                  0.75, // prevent super wide bubbles
            ),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFFD9FDD3) : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: isMe
                    ? const Radius.circular(12)
                    : const Radius.circular(0),
                bottomRight: isMe
                    ? const Radius.circular(0)
                    : const Radius.circular(12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start, // Align content to start
              children: [
                if (data['replyToMsgId'] != null) _buildReplyHeader(),
                _buildContent(context),
                const SizedBox(height: 4), // Spacing before footer
                Align(
                  alignment:
                      Alignment.bottomRight, // Force footer to bottom right
                  child: _buildFooter(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyHeader() {
    String? thumb = data['replyToAttachmentUrl'];
    bool hasThumb = thumb != null && thumb.isNotEmpty;

    return GestureDetector(
      onTap: () {
        if (onReplyTap != null && data['replyToMsgId'] != null) {
          onReplyTap!(data['replyToMsgId']);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border(
            left: BorderSide(
              color: isMe ? Colors.green[800]! : Colors.purpleAccent,
              width: 4,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasThumb) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: thumb,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['replyToSender'] ?? 'User',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isMe ? Colors.green[800] : Colors.purple,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    data['replyToText'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    // 1. Time Logic
    Timestamp? ts = data['createdAt'] ?? data['timestamp'];
    String formattedTime = _formatTimestamp(ts);

    // 2. Read Time Logic (Optional: Show when it was read if detailed info is requested)
    // Timestamp? readAt = data['readAt'];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formattedTime,
          style: TextStyle(fontSize: 10, color: Colors.grey[600], height: 1.0),
        ),

        if (isMe) ...[
          const SizedBox(width: 4),
          // --- THE 4 STATES OF WHATSAPP ---
          if (data['status'] == 'sending')
            const Icon(Icons.access_time, size: 12, color: Colors.grey),

          if (data['status'] == 'sent')
            const Icon(
              Icons.check,
              size: 14,
              color: Colors.grey,
            ), // Single Grey Tick

          if (data['status'] == 'delivered')
            const Icon(
              Icons.done_all,
              size: 14,
              color: Colors.grey,
            ), // Double Grey Tick

          if (data['status'] == 'read')
            const Icon(
              Icons.done_all,
              size: 14,
              color: Colors.blueAccent,
            ), // Double Blue Tick (Read)

          if (data['status'] == 'error')
            GestureDetector(
              onTap: () => onRetry != null ? onRetry!(docId) : null,
              child: const Icon(
                Icons.error_outline,
                size: 14,
                color: Colors.red,
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (data['isDeleted'] == true) {
      return Text(
        decryptedText,
        style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
      );
    }

    String type = data['type'] ?? 'text';
    String? url = data['attachmentUrl'];
    String? localPath = data['localPath'];

    Timestamp? expiresAt = data['expiresAt'];
    bool isExpired = false;
    if (expiresAt != null) {
      isExpired = DateTime.now().isAfter(expiresAt.toDate());
    }

    return FutureBuilder<File?>(
      future: (url != null)
          ? LocalStorageService.getLocalFile(url)
          : Future.value(null),
      builder: (context, snapshot) {
        File? fileOnDisk = snapshot.data;
        if (localPath != null && File(localPath).existsSync()) {
          fileOnDisk = File(localPath);
        }

        if (fileOnDisk == null && isExpired) {
          return Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[200],
            child: const Row(
              children: [
                Icon(Icons.broken_image, size: 16),
                SizedBox(width: 4),
                Text("Expired"),
              ],
            ),
          );
        }

        if (url != null && fileOnDisk == null && !isExpired) {
          LocalStorageService.downloadAndSave(url);
        }

        Widget attachmentWidget;

        switch (type) {
          case 'image':
            attachmentWidget = _buildImage(context, fileOnDisk, url);
            break;
          case 'video':
            attachmentWidget = _buildVideo(context, fileOnDisk, url);
            break;
          case 'audio':
            attachmentWidget = _buildAudio(fileOnDisk, url);
            break;
          case 'file':
            attachmentWidget = _buildFile(url);
            break;
          default:
            attachmentWidget = const SizedBox.shrink();
        }

        if (type == 'text') {
          return Text(
            decryptedText,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          );
        } else {
          // Captions Logic
          bool hasCaption = decryptedText.isNotEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              attachmentWidget,
              if (hasCaption) ...[
                const SizedBox(height: 6),
                Text(
                  decryptedText,
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
              ],
            ],
          );
        }
      },
    );
  }

  Widget _buildImage(BuildContext context, File? file, String? url) {
    ImageProvider provider = (file != null)
        ? FileImage(file)
        : (url != null
                  ? CachedNetworkImageProvider(url)
                  : const AssetImage('assets/placeholder_image.png'))
              as ImageProvider;

    return GestureDetector(
      onTap: () {
        if (isSelectionMode)
          onTap(docId);
        else
          onOpenGallery(url ?? file?.path ?? "", false);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(
          image: provider,
          height: 200,
          width: 200,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildVideo(BuildContext context, File? file, String? url) {
    return GestureDetector(
      onTap: () {
        if (isSelectionMode)
          onTap(docId);
        else if (url != null || file != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenVideoViewer(
                videoUrl: file?.path ?? url!,
                isLocal: file != null,
              ),
            ),
          );
        }
      },
      child: Container(
        height: 150,
        width: 200,
        color: Colors.black,
        child: const Icon(
          Icons.play_circle_fill,
          color: Colors.white,
          size: 50,
        ),
      ),
    );
  }

  Widget _buildAudio(File? file, String? url) {
    bool isPlaying = currentlyPlayingUrl == (url ?? file?.path);
    return Container(
      width: 200,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isMe ? Colors.green[700] : Colors.blue,
            radius: 18,
            child: IconButton(
              icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow, size: 20),
              onPressed: () => onPlayAudio(url ?? file?.path ?? ""),
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "Voice Message",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFile(String? url) {
    String displayLabel = data['fileName'] ?? decryptedText;
    if (displayLabel.trim().isEmpty) displayLabel = "Document";

    return GestureDetector(
      onTap: () => (url != null)
          ? launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
          : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.insert_drive_file,
              size: 28,
              color: Colors.blueGrey,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return "";

    DateTime date = timestamp.toDate();
    DateTime now = DateTime.now();

    String period = date.hour >= 12 ? "PM" : "AM";
    int hour = date.hour > 12 ? date.hour - 12 : date.hour;
    if (hour == 0) hour = 12;
    String minute = date.minute.toString().padLeft(2, '0');
    String time = "$hour:$minute $period";

    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return time;
    }

    const List<String> months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    String month = months[date.month - 1];

    return "$month ${date.day}, $time";
  }
}
