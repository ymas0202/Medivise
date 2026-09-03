import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:medivise/auth_service.dart';

class ChatPage extends StatefulWidget {
  final String chatId;

  const ChatPage({super.key, required this.chatId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _textCtrl = TextEditingController();
  bool _sending = false;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _sendInitialGreeting();
  }

  Future<void> _loadMessages() async {
    try {
      final authToken = AuthService.getToken();
      if (authToken == null) return;

      final response = await http.get(
        Uri.parse('http://localhost:3000/api/chats/${widget.chatId}/messages'),
        headers: {'Authorization': 'Bearer $authToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading messages: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendInitialGreeting() async {
    try {
      final authToken = AuthService.getToken();
      if (authToken == null) return;

      // Only send greeting if no messages exist
      if (_messages.isEmpty) {
        await http.post(
          Uri.parse('http://localhost:3000/api/chats/${widget.chatId}/ai-response'),
          headers: {
            'Authorization': 'Bearer $authToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'isInitialGreeting': true,
          }),
        );
        await _loadMessages();
      }
    } catch (e) {
      print('Error in initial greeting: $e');
    }
  }

  Future<void> _sendUserMessageToBackend(String message) async {
    try {
      final authToken = AuthService.getToken();
      if (authToken == null) return;

      await http.post(
        Uri.parse('http://localhost:3000/api/chats/${widget.chatId}/messages'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': message,
          'role': 'user',
        }),
      );
    } catch (e) {
      print('Error saving user message: $e');
    }
  }

  Future<void> _sendMessage() async {
    final message = _textCtrl.text.trim();
    if (message.isEmpty || _sending) return;

    _textCtrl.clear();
    setState(() => _sending = true);

    try {
      // Save user message to backend FIRST
      await _sendUserMessageToBackend(message);
      
      // Then reload messages to include the user message
      await _loadMessages();

      // Get AI response
      final authToken = AuthService.getToken();
      if (authToken == null) return;

      final response = await http.post(
        Uri.parse('http://localhost:3000/api/chats/${widget.chatId}/ai-response'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userMessage': message,
          'isInitialGreeting': false,
        }),
      );

      if (response.statusCode == 200) {
        await _loadMessages(); // Reload to show bot response
      } else {
        throw Exception('Failed to get response');
      }
    } catch (e) {
      print('Error sending message: $e');
      // Show error message
      setState(() {
        _messages.add({
          'text': 'Sorry, there was an error. Please try again.',
          'role': 'bot',
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
    } finally {
      setState(() => _sending = false);
    }
  }

  Widget _buildMessage(String role, String text) {
    final isUser = role == 'user';
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                backgroundColor: const Color(0xFF003366),
                child: Text('AI', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF003366) : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          if (isUser)
            Container(
              margin: const EdgeInsets.only(left: 8),
              child: CircleAvatar(
                backgroundColor: Colors.grey[400],
                child: Icon(Icons.person, color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        title: const Text('Medivise Assistant', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) {
                          final message = _messages[i];
                          return _buildMessage(message['role'], message['text']);
                        },
                      ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Type your question...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _sending 
                      ? const CircularProgressIndicator()
                      : const Icon(Icons.send),
                  onPressed: _sending ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}