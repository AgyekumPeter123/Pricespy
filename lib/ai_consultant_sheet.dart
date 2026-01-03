import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AiConsultantPage extends StatefulWidget {
  final Map<String, dynamic> predictionResult;
  final Map<String, dynamic> originalInputs;
  final List<Map<String, String>> sessionHistory;

  const AiConsultantPage({
    super.key,
    required this.predictionResult,
    required this.originalInputs,
    required this.sessionHistory,
  });

  @override
  State<AiConsultantPage> createState() => _AiConsultantPageState();
}

class _AiConsultantPageState extends State<AiConsultantPage> {
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
  final String _modelId = 'gemini-2.5-flash'; // Updated to latest stable flash

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  // 💡 NEW: Quick Actions for better UX
  final List<String> _suggestedPrompts = [
    "Draft a retention email",
    "Suggest a discount offer",
    "Analyze risk factors",
    "Explain the churn probability",
  ];

  @override
  void initState() {
    super.initState();
    if (widget.sessionHistory.isEmpty) {
      _initChat();
    }
  }

  void _initChat() {
    setState(() {
      widget.sessionHistory.add({
        'role': 'model',
        'text':
            "Good day. I am your specialized AI Business Consultant.\n\nI have analyzed this customer's profile. Select a quick action below or ask me anything.",
      });
    });
  }

  Future<void> _sendMessage({String? quickPrompt}) async {
    final message = quickPrompt ?? _textController.text;
    if (message.isEmpty) return;

    setState(() {
      widget.sessionHistory.add({'role': 'user', 'text': message});
      _isLoading = true;
      _textController.clear();
    });
    _scrollToBottom();

    // Context Preparation
    final bool isChurn = widget.predictionResult['willChurn'] ?? false;
    final double prob = widget.predictionResult['probability'] ?? 0.0;
    final inputs = widget.originalInputs;

    final String systemContext =
        '''
    You are a distinguished Business Retention Consultant in Ghana.
    
    CUSTOMER PROFILE:
    - Status: ${isChurn ? "High Risk" : "Loyal"}
    - Risk Probability: ${(prob * 100).toStringAsFixed(1)}%
    - Tenure: ${inputs['Tenure']} months
    - Monthly Spend: ${inputs['MonthlyCharges']} GHS
    - Contract: ${inputs['Contract']}
    - Payment Method: ${inputs['PaymentMethod']}
    
    INSTRUCTIONS:
    - Provide concise, strategic advice.
    - If asked for an email, write a professional, empathetic email from the company manager.
    - If asked for a discount, suggest specific amounts in GHS.
    - Use Markdown for formatting (bold, bullet points).
    ''';

    try {
      final model = GenerativeModel(
        model: _modelId,
        apiKey: _apiKey,
        systemInstruction: Content.system(systemContext),
      );

      final historyContent = widget.sessionHistory
          .take(widget.sessionHistory.length - 1)
          .map((msg) {
            return msg['role'] == 'user'
                ? Content.text(msg['text']!)
                : Content.model([TextPart(msg['text']!)]);
          })
          .toList();

      final chat = model.startChat(history: historyContent);
      final response = await chat.sendMessage(Content.text(message));

      setState(() {
        widget.sessionHistory.add({
          'role': 'model',
          'text': response.text ?? "No response generated.",
        });
      });
    } catch (e) {
      setState(() {
        widget.sessionHistory.add({
          'role': 'model',
          'text': "Error: Unable to connect to AI Agent. (Details: $e)",
        });
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Strategy Agent"),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            // ✅ UPDATED: Matches ChurnPredictionPage (Green -> Teal)
            gradient: LinearGradient(
              colors: [Colors.green[900]!, Colors.teal[700]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: widget.sessionHistory.length,
              itemBuilder: (context, index) {
                final msg = widget.sessionHistory[index];
                final isUser = msg['role'] == 'user';
                return _buildMessageBubble(msg['text']!, isUser);
              },
            ),
          ),

          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Agent is typing...",
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          // Quick Action Chips Bar
          if (!_isLoading)
            SizedBox(
              height: 50,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _suggestedPrompts.length,
                separatorBuilder: (c, i) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return ActionChip(
                    label: Text(_suggestedPrompts[index]),
                    backgroundColor: Colors.green[50], // Updated to Green tint
                    labelStyle: TextStyle(
                      color: Colors.green[900],
                      fontSize: 12,
                    ),
                    onPressed: () =>
                        _sendMessage(quickPrompt: _suggestedPrompts[index]),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: Colors.green.withOpacity(0.2)),
                    ),
                  );
                },
              ),
            ),

          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String text, bool isUser) {
    // 1. Get current user for the avatar
    final user = FirebaseAuth.instance.currentUser;
    final String? photoUrl = user?.photoURL;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- AI AVATAR (Left Side) ---
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: Colors.indigo[100],
              child: Icon(
                Icons.smart_toy_outlined,
                color: Colors.indigo[800],
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
          ],

          // --- CHAT BUBBLE (Middle) ---
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue[800] : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: MarkdownBody(
                data: text,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: isUser ? Colors.white : Colors.black87,
                    fontSize: 15,
                  ),
                  strong: TextStyle(
                    color: isUser ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

          // --- USER AVATAR (Right Side) ---
          if (isUser) ...[
            const SizedBox(width: 8),
            // 2. Logic to display the fetched DP
            CircleAvatar(
              radius: 18, // Slightly larger for better visibility
              backgroundColor: Colors.blue[100],
              // A. If photoUrl exists, load it. If not, make background null.
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : null,
              // B. If no photoUrl, show the Icon as a child
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? Icon(Icons.person, color: Colors.blue[800], size: 20)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: "Ask a follow-up question...",
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              mini: true,
              backgroundColor: Colors.indigo[800],
              elevation: 0,
              onPressed: _isLoading ? null : () => _sendMessage(),
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
