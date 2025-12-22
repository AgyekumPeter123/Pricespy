import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isRecording;
  final String recordDuration;
  final bool isLocked;
  final Map<String, dynamic>? replyMessage;

  final VoidCallback onCancelReply;
  final VoidCallback onAttachmentPressed;
  final VoidCallback onStartRecording;
  final Function(bool) onStopRecording;
  final VoidCallback onLockRecording;
  final VoidCallback onCancelRecording;
  final Function(String) onSendMessage;
  final Function(String) onTyping;

  const ChatInput({
    super.key,
    required this.controller,
    required this.isRecording,
    required this.recordDuration,
    required this.isLocked,
    this.replyMessage,
    required this.onCancelReply,
    required this.onAttachmentPressed,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onLockRecording,
    required this.onCancelRecording,
    required this.onSendMessage,
    required this.onTyping,
  });

  @override
  Widget build(BuildContext context) {
    if (isLocked) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: Row(
          children: [
            const Icon(Icons.mic, color: Colors.red),
            const SizedBox(width: 10),
            Text(recordDuration),
            const Spacer(),
            TextButton(
              onPressed: onCancelRecording,
              child: const Text("Cancel"),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.green),
              onPressed: () => onStopRecording(true),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (replyMessage != null)
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[200],
            child: Row(
              children: [
                if (replyMessage!['attachmentUrl'] != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: replyMessage!['attachmentUrl'],
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else
                  const Icon(Icons.reply, size: 20, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Replying to ${replyMessage!['senderName']}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        replyMessage!['text'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: onCancelReply,
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          // FIX: Changed from Colors.white to Colors.transparent
          color: Colors.transparent,
          child: Stack(
            alignment: Alignment.centerRight,
            clipBehavior: Clip.none,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isRecording)
                    IconButton(
                      icon: const Icon(Icons.attach_file, color: Colors.grey),
                      onPressed: onAttachmentPressed,
                    ),
                  Expanded(
                    child: isRecording
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              "Slide to cancel <   Recording: $recordDuration",
                              style: const TextStyle(color: Colors.grey),
                            ),
                          )
                        : TextField(
                            controller: controller,
                            minLines: 1,
                            maxLines: 6,
                            decoration: InputDecoration(
                              hintText: "Message",
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                            onChanged: onTyping,
                          ),
                  ),
                  // Spacer width 70 to keep gap between field and button
                  const SizedBox(width: 70, height: 60),
                ],
              ),
              Positioned(
                right: 0,
                bottom: -7, // Pushed down to align
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, child) {
                    bool hasText = value.text.trim().isNotEmpty;

                    return GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onLongPressMoveUpdate: hasText
                          ? null
                          : (details) {
                              if (details.offsetFromOrigin.dy < -50)
                                onLockRecording();
                              if (details.offsetFromOrigin.dx < -100)
                                onCancelRecording();
                            },
                      onLongPress: hasText ? null : onStartRecording,
                      onLongPressEnd: hasText
                          ? null
                          : (details) {
                              if (isRecording && !isLocked)
                                onStopRecording(true);
                            },

                      onTap: () {
                        if (hasText) onSendMessage(controller.text.trim());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8.0),
                        color: Colors.transparent,
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.green[800],
                          child: Icon(
                            !hasText
                                ? (isRecording ? Icons.mic : Icons.mic_none)
                                : Icons.send,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (isRecording && !isLocked)
                Positioned(
                  right: 14,
                  bottom: 76,
                  child: Column(
                    children: const [
                      Icon(Icons.lock_open, size: 16, color: Colors.grey),
                      Icon(
                        Icons.keyboard_arrow_up,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
