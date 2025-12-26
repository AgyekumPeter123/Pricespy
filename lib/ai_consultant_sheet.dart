import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';

class AiConsultantPage extends StatefulWidget {
  final Map<String, dynamic> predictionResult;
  final Map<String, dynamic> originalInputs;
  // 🔴 NEW: Accept the persistent history from the parent
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
  static const String _apiKey = 'AIzaSyBIT2-85NooggkUlFqYomUVz4ygtwuHQVM';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent';

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 🔴 LOGIC CHANGE: Only add greeting if it's a NEW chat session
    if (widget.sessionHistory.isEmpty) {
      _initChat();
    }
  }

  void _initChat() {
    setState(() {
      widget.sessionHistory.add({
        'role': 'model',
        'text':
            "Good day. I am your personal AI Business Consultant, at your service.\n\nI have reviewed the customer profile you submitted. Based on the analysis, I can see some critical indicators regarding their retention status.\n\nHow may I assist you in strategizing for this customer today?",
      });
    });
  }

  Future<void> _sendMessage() async {
    final message = _textController.text;
    if (message.isEmpty) return;

    setState(() {
      widget.sessionHistory.add({'role': 'user', 'text': message});
      _isLoading = true;
      _textController.clear();
    });
    _scrollToBottom();

    // 🔴 SYSTEM CONTEXT GENERATION (Executed on every call to keep AI focused)
    final double rate = widget.predictionResult['rateUsed'] ?? 15.0;
    final bool isChurn = widget.predictionResult['willChurn'] ?? false;
    final double prob = widget.predictionResult['probability'] ?? 0.0;
    final inputs = widget.originalInputs;

    final String systemContext =
        '''
    You are a distinguished and highly experienced Business Retention Consultant specialized in the Ghanaian market. 
    Your tone should be formal, professional, yet warm and encouraging.
    
    CRITICAL INSTRUCTION:
    You must ALWAYS frame your answers in the context of the specific customer profile provided below, unless the user explicitly asks a general business question. Even then, try to relate it back to this customer if relevant.
    
    SPECIFIC CUSTOMER PROFILE (Focus on this):
    - Status: ${isChurn ? "High Risk" : "Loyal"}
    - Churn Probability: ${(prob * 100).toStringAsFixed(1)}%
    - Tenure: ${inputs['Tenure']} months
    - Monthly Spend: ${inputs['MonthlyCharges']} GHS
    - Contract: ${inputs['Contract']}
    - Payment Method: ${inputs['PaymentMethod']}
    - Exchange Rate: 1 USD = $rate GHS.

    Formatting Rules:
    - Use Markdown Tables for data/numbers.
    - Be concise but insightful.
    ''';

    try {
      // 🔴 UPDATED: We use the 'system_instruction' field for strong context
      final Map<String, dynamic> requestBody = {
        "system_instruction": {
          "parts": [
            {"text": systemContext},
          ],
        },
        "contents": widget.sessionHistory.map((msg) {
          return {
            "role": msg['role'],
            "parts": [
              {"text": msg['text']},
            ],
          };
        }).toList(),
      };

      final url = Uri.parse('$_baseUrl?key=$_apiKey');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final aiText = data['candidates'][0]['content']['parts'][0]['text'];

        setState(() {
          widget.sessionHistory.add({'role': 'model', 'text': aiText});
        });
      } else {
        setState(() {
          widget.sessionHistory.add({
            'role': 'model',
            'text':
                "I apologize, but I encountered a momentary system error. (Code: ${response.statusCode})",
          });
        });
      }
    } catch (e) {
      setState(() {
        widget.sessionHistory.add({
          'role': 'model',
          'text':
              "I am unable to connect to the server at this moment. Please check your internet connection.",
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
        title: const Text("AI Consultant"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: widget.sessionHistory.length, // 🔴 Use shared history
              itemBuilder: (context, index) {
                final msg = widget.sessionHistory[index];
                final isUser = msg['role'] == 'user';

                return Row(
                  mainAxisAlignment: isUser
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUser)
                      CircleAvatar(
                        backgroundColor: Colors.green[800],
                        radius: 16,
                        child: const Icon(
                          Icons.smart_toy,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),

                    const SizedBox(width: 8),

                    Flexible(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isUser ? Colors.green[800] : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: isUser
                                ? const Radius.circular(20)
                                : Radius.zero,
                            bottomRight: isUser
                                ? Radius.zero
                                : const Radius.circular(20),
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
                          data: msg['text']!,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              color: isUser ? Colors.white : Colors.black87,
                              fontSize: 15,
                              height: 1.4,
                            ),
                            strong: TextStyle(
                              color: isUser ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                            tableBorder: TableBorder.all(
                              color: Colors.grey.shade300,
                            ),
                            tableHead: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                            tableBody: TextStyle(
                              color: isUser ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: Colors.green[800],
                backgroundColor: Colors.green[100],
              ),
            ),

          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: "Type your query here...",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _isLoading ? null : _sendMessage,
                  backgroundColor: Colors.green[800],
                  elevation: 2,
                  child: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
