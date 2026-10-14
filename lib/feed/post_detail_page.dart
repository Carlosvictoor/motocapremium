// Tela de um post: texto + estatísticas, curtir, e a lista de comentários
// com campo pra comentar embaixo.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'feed_models.dart';
import 'feed_service.dart';
import 'feed_tab.dart' show tempoRelativo;

class PostDetailPage extends StatefulWidget {
  final Post post;
  final String meuUid;
  final String meuNome;

  const PostDetailPage({
    super.key,
    required this.post,
    required this.meuUid,
    required this.meuNome,
  });

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final _comentarioController = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _comentarioController.dispose();
    super.dispose();
  }

  Future<void> _comentar() async {
    final texto = _comentarioController.text.trim();
    if (texto.isEmpty) return;
    setState(() => _enviando = true);
    try {
      await FeedService.comentar(postId: widget.post.id, autorNome: widget.meuNome, texto: texto);
      _comentarioController.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não deu pra comentar agora. Tente novamente.'),
          backgroundColor: Colors.red,
        ));
      }
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050816),
        title: const Text('Post'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _PostCard(post: widget.post, meuUid: widget.meuUid),
                  const SizedBox(height: 20),
                  const Text('Comentários',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70)),
                  const SizedBox(height: 10),
                  StreamBuilder<List<Comentario>>(
                    stream: FeedService.streamComentarios(widget.post.id),
                    builder: (context, snap) {
                      final comentarios = snap.data ?? [];
                      if (comentarios.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Nenhum comentário ainda.',
                              style: TextStyle(color: Colors.white38, fontSize: 13)),
                        );
                      }
                      return Column(
                        children: comentarios.map((c) => _ComentarioTile(
                              comentario: c,
                              podeExcluir: c.autorUid == widget.meuUid,
                              onExcluir: () => FeedService.excluirComentario(widget.post.id, c),
                            )).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _comentarioController,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Escreva um comentário...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF111827),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _enviando
                        ? const SizedBox(
                            width: 40,
                            height: 40,
                            child: Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            onPressed: _comentar,
                            icon: const Icon(Icons.send_rounded, color: Colors.blue),
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O post em si (autor, texto, estatísticas, curtir), com o contador de
/// curtidas ao vivo enquanto essa tela estiver aberta.
class _PostCard extends StatelessWidget {
  final Post post;
  final String meuUid;

  const _PostCard({required this.post, required this.meuUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('posts').doc(post.id).snapshots(),
      builder: (context, snap) {
        final atual = snap.data != null && snap.data!.exists ? Post.fromDoc(snap.data!) : post;
        final curti = atual.likedBy.contains(meuUid);
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: corParaNome(atual.authorUid),
                    child: Text(iniciaisNome(atual.authorNome),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(atual.authorNome, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(tempoRelativo(atual.timestamp),
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(atual.texto, style: const TextStyle(fontSize: 15, height: 1.4)),
              const SizedBox(height: 16),
              _Estatisticas(post: atual),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => curti ? FeedService.descurtir(atual.id) : FeedService.curtir(atual.id),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(curti ? Icons.favorite : Icons.favorite_border,
                          color: curti ? Colors.red : Colors.white54, size: 20),
                      const SizedBox(width: 6),
                      Text('${atual.likedBy.length}', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Estatisticas extends StatelessWidget {
  final Post post;
  const _Estatisticas({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: const Color(0xFF0D1117), borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat(Icons.payments_outlined, Colors.green, 'R\$ ${post.faturamento.toStringAsFixed(2)}', 'Faturamento'),
          _stat(Icons.local_shipping_outlined, Colors.orange, '${post.entregas}', 'Entregas'),
          _stat(Icons.location_on_outlined, Colors.blue, '${post.km.toStringAsFixed(1)} km', 'Rodados'),
        ],
      ),
    );
  }

  Widget _stat(IconData icone, Color cor, String valor, String rotulo) {
    return Column(
      children: [
        Icon(icone, color: cor, size: 18),
        const SizedBox(height: 4),
        Text(valor, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(rotulo, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }
}

class _ComentarioTile extends StatelessWidget {
  final Comentario comentario;
  final bool podeExcluir;
  final VoidCallback onExcluir;

  const _ComentarioTile({required this.comentario, required this.podeExcluir, required this.onExcluir});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: corParaNome(comentario.autorUid),
            child: Text(iniciaisNome(comentario.autorNome),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(comentario.autorNome, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(comentario.texto, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
          if (podeExcluir)
            IconButton(
              onPressed: onExcluir,
              icon: const Icon(Icons.close, size: 16, color: Colors.white38),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
