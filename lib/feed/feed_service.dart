// Toda a lógica do feed (posts, curtidas, comentários) no Cloud Firestore.
// É essa classe que fala de verdade com o Firestore — as telas do feed só
// chamam os métodos daqui.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'feed_models.dart';

class FeedService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static String? get _meuUid => _auth.currentUser?.uid;

  /// Escuta em tempo real os posts mais recentes do feed (os 50 últimos).
  static Stream<List<Post>> streamPosts({int limite = 50}) {
    return _db
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(limite)
        .snapshots()
        .map((s) => s.docs.map(Post.fromDoc).toList());
  }

  /// Publica um post novo com o texto e as estatísticas do dia.
  static Future<void> criarPost({
    required String texto,
    required String autorNome,
    required double faturamento,
    required int entregas,
    required double km,
  }) async {
    final uid = _meuUid;
    if (uid == null) return;
    await _db.collection('posts').add({
      'authorUid': uid,
      'authorNome': autorNome,
      'texto': texto,
      'faturamento': faturamento,
      'entregas': entregas,
      'km': km,
      'timestamp': FieldValue.serverTimestamp(),
      'likedBy': <String>[],
      'commentsCount': 0,
    });
  }

  /// Apaga um post (só o autor pode).
  static Future<void> excluirPost(Post post) async {
    await _db.collection('posts').doc(post.id).delete();
  }

  /// Curte um post.
  static Future<void> curtir(String postId) async {
    final uid = _meuUid;
    if (uid == null) return;
    await _db.collection('posts').doc(postId).update({
      'likedBy': FieldValue.arrayUnion([uid]),
    });
  }

  /// Descurte um post.
  static Future<void> descurtir(String postId) async {
    final uid = _meuUid;
    if (uid == null) return;
    await _db.collection('posts').doc(postId).update({
      'likedBy': FieldValue.arrayRemove([uid]),
    });
  }

  /// Escuta em tempo real os comentários de um post, mais antigos primeiro.
  static Stream<List<Comentario>> streamComentarios(String postId) {
    return _db
        .collection('posts')
        .doc(postId)
        .collection('comentarios')
        .orderBy('timestamp')
        .snapshots()
        .map((s) => s.docs.map(Comentario.fromDoc).toList());
  }

  /// Comenta num post e soma 1 no contador de comentários do post.
  static Future<void> comentar({
    required String postId,
    required String autorNome,
    required String texto,
  }) async {
    final uid = _meuUid;
    if (uid == null) return;
    final postRef = _db.collection('posts').doc(postId);
    final batch = _db.batch();
    batch.set(postRef.collection('comentarios').doc(), {
      'autorUid': uid,
      'autorNome': autorNome,
      'texto': texto,
      'timestamp': FieldValue.serverTimestamp(),
    });
    batch.update(postRef, {'commentsCount': FieldValue.increment(1)});
    await batch.commit();
  }

  /// Apaga um comentário (só o autor pode) e desconta 1 do contador do post.
  static Future<void> excluirComentario(String postId, Comentario comentario) async {
    final postRef = _db.collection('posts').doc(postId);
    final batch = _db.batch();
    batch.delete(postRef.collection('comentarios').doc(comentario.id));
    batch.update(postRef, {'commentsCount': FieldValue.increment(-1)});
    await batch.commit();
  }
}
