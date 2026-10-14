// Aba "Feed": lista os posts da comunidade em tempo real, com botão pra
// publicar um novo. Cada card mostra autor, texto, estatísticas do dia,
// curtir e nº de comentários (abre o post ao tocar).
import 'package:flutter/material.dart';
import 'feed_models.dart';
import 'feed_service.dart';
import 'post_composer_page.dart';
import 'post_detail_page.dart';

/// Formata um horário como "agora", "25 min", "3 h" ou "2 d" — usado nos
/// cards do feed e na tela de detalhe do post.
String tempoRelativo(DateTime? data) {
  if (data == null) return 'agora';
  final diff = DateTime.now().difference(data);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min';
  if (diff.inHours < 24) return '${diff.inHours} h';
  return '${diff.inDays} d';
}

class FeedTab extends StatefulWidget {
  final String? meuUid;
  final String meuNome;
  final double faturamentoHoje;
  final int entregasHoje;
  final double kmHoje;

  const FeedTab({
    super.key,
    required this.meuUid,
    required this.meuNome,
    required this.faturamentoHoje,
    required this.entregasHoje,
    required this.kmHoje,
  });

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  Future<void> _abrirComposer() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => PostComposerPage(
        meuNome: widget.meuNome,
        faturamentoHoje: widget.faturamentoHoje,
        entregasHoje: widget.entregasHoje,
        kmHoje: widget.kmHoje,
      ),
    ));
  }

  void _abrirDetalhe(Post post) {
    final uid = widget.meuUid;
    if (uid == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PostDetailPage(post: post, meuUid: uid, meuNome: widget.meuNome),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Feed', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      Text('Comunidade Motoca Premium',
                          style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Post>>(
                stream: FeedService.streamPosts(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.blue));
                  }
                  final posts = snap.data ?? [];
                  if (posts.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Ainda não tem nenhum post. Seja o primeiro a contar como foi o seu dia!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: posts.length,
                    itemBuilder: (context, i) => _PostCardFeed(
                      post: posts[i],
                      meuUid: widget.meuUid,
                      onTap: () => _abrirDetalhe(posts[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirComposer,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _PostCardFeed extends StatelessWidget {
  final Post post;
  final String? meuUid;
  final VoidCallback onTap;

  const _PostCardFeed({required this.post, required this.meuUid, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final curti = meuUid != null && post.likedBy.contains(meuUid);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: corParaNome(post.authorUid),
                child: Text(iniciaisNome(post.authorNome),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.authorNome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(tempoRelativo(post.timestamp),
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(post.texto, style: const TextStyle(fontSize: 14, height: 1.4)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(color: const Color(0xFF0D1117), borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat(Icons.payments_outlined, Colors.green, 'R\$ ${post.faturamento.toStringAsFixed(2)}'),
                _stat(Icons.local_shipping_outlined, Colors.orange, '${post.entregas} entregas'),
                _stat(Icons.location_on_outlined, Colors.blue, '${post.km.toStringAsFixed(1)} km'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              InkWell(
                onTap: meuUid == null
                    ? null
                    : () => curti ? FeedService.descurtir(post.id) : FeedService.curtir(post.id),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(curti ? Icons.favorite : Icons.favorite_border,
                          color: curti ? Colors.red : Colors.white54, size: 19),
                      const SizedBox(width: 6),
                      Text('${post.likedBy.length}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline, color: Colors.white54, size: 17),
                      const SizedBox(width: 6),
                      Text('${post.commentsCount}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icone, Color cor, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, color: cor, size: 15),
        const SizedBox(width: 4),
        Text(texto, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
