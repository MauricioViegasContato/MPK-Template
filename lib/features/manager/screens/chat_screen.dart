import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/service_locator.dart';

class ChatScreen extends StatefulWidget {
  final String filialId;
  final String title;
  final bool includeGlobal;
  final bool readOnly;

  const ChatScreen({
    super.key, 
    required this.filialId, 
    required this.title,
    this.includeGlobal = false,
    this.readOnly = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String _currentUserId = ServiceLocator.repository.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    // Mark messages as read when entering
    ServiceLocator.repository.markMessagesAsRead(widget.filialId, _currentUserId);
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;
    final msg = _controller.text;
    _controller.clear();

    try {
      await ServiceLocator.repository.enviarMensagem(msg, widget.filialId);
      // Auto-scroll handled by StreamBuilder
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Theme Awareness
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColorMyself = AppColors.primary;
    final cardColorOthers = isDark ? Colors.grey[800] : Colors.white;
    final textColorOthers = Theme.of(context).textTheme.bodyMedium?.color;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: ServiceLocator.repository.getMensagens(
                widget.filialId, 
                includeGlobal: widget.includeGlobal
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final messages = snapshot.data!;
                
                // Mark messages as read whenever the list updates (live view)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ServiceLocator.repository.markMessagesAsRead(widget.filialId, _currentUserId);
                });

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Nenhuma mensagem ainda.\nComece a conversa!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['user_id'] == _currentUserId;
                    final isRead = msg['read_at'] != null;

                    String timeStr = '';
                    if (msg['created_at'] != null) {
                       final date = DateTime.parse(msg['created_at']).toLocal();
                       timeStr = '${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}';
                    }

                    final isGlobal = msg['filial_id'] == 'GLOBAL';

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isGlobal 
                              ? Colors.orange.withOpacity(0.15) // Distinctive background for Global
                              : (isMe ? cardColorMyself : cardColorOthers),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                          ),
                          border: isGlobal ? Border.all(color: Colors.orange.withOpacity(0.5)) : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (isGlobal) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.campaign, size: 12, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'COMUNICADO GERAL',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            Text(
                              msg['mensagem'] ?? '',
                              style: TextStyle(
                                color: isGlobal 
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isMe ? Colors.white : textColorOthers),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Time + Read Receipt Row
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  timeStr,
                                  style: TextStyle(
                                    color: isGlobal 
                                      ? (isDark ? Colors.white70 : Colors.black54)
                                      : (isMe ? Colors.white.withOpacity(0.7) : Colors.grey[500]),
                                    fontSize: 10,
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.done_all,
                                    size: 14,
                                    color: isRead ? Colors.lightBlueAccent : Colors.white.withOpacity(0.5),
                                  ),
                                ]
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // Input Field (Hidden if readOnly)
          if (!widget.readOnly)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, -2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                      decoration: InputDecoration(
                        hintText: 'Digite uma mensagem...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              color: Theme.of(context).cardColor,
              child: Text(
                'Este canal é apenas para avisos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}
