// Os "moldes" de dados do feed (post, comentário) e o helper de avatar por
// iniciais/cor (antes vivia no chat, reaproveitado aqui pro autor do post).
// Cada modelo sabe se transformar a partir de um documento do Firestore
// (fromDoc) — quem lê/grava de verdade é o FeedService.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Paleta de cores usada nos avatares — cada usuário sempre pega a mesma
/// cor, calculada a partir do próprio uid (ver [corParaNome]).
const List<Color> coresAvatar = [
  Colors.blue,
  Colors.green,
  Colors.orange,
  Colors.purple,
  Colors.pink,
  Colors.teal,
  Colors.indigo,
  Colors.red,
];

/// Escolhe sempre a mesma cor da paleta pra uma mesma chave (uid), somando
/// o código de cada letra e tirando o resto da divisão pela quantidade de
/// cores.
Color corParaNome(String chave) {
  final soma = chave.codeUnits.fold<int>(0, (s, c) => s + c);
  return coresAvatar[soma % coresAvatar.length];
}

/// Pega as iniciais do nome pra mostrar no avatar (ex: "João Silva" → "JS").
String iniciaisNome(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) return partes[0].substring(0, 1).toUpperCase();
  return (partes.first.substring(0, 1) + partes.last.substring(0, 1)).toUpperCase();
}

/// Um post no feed da comunidade: texto + estatísticas do dia de quem
/// publicou (faturamento, entregas, km).
class Post {
  final String id;
  final String authorUid;
  final String authorNome;
  final String texto;
  final double faturamento;
  final int entregas;
  final double km;
  final DateTime? timestamp;
  final List<String> likedBy;
  final int commentsCount;

  Post({
    required this.id,
    required this.authorUid,
    required this.authorNome,
    required this.texto,
    required this.faturamento,
    required this.entregas,
    required this.km,
    required this.timestamp,
    required this.likedBy,
    required this.commentsCount,
  });

  /// Monta um Post a partir de um documento lido do Firestore.
  factory Post.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Post(
      id: doc.id,
      authorUid: d['authorUid'] as String? ?? '',
      authorNome: d['authorNome'] as String? ?? '',
      texto: d['texto'] as String? ?? '',
      faturamento: (d['faturamento'] as num?)?.toDouble() ?? 0,
      entregas: (d['entregas'] as num?)?.toInt() ?? 0,
      km: (d['km'] as num?)?.toDouble() ?? 0,
      timestamp: (d['timestamp'] as Timestamp?)?.toDate(),
      likedBy: List<String>.from(d['likedBy'] as List? ?? []),
      commentsCount: (d['commentsCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Um comentário num post.
class Comentario {
  final String id;
  final String autorUid;
  final String autorNome;
  final String texto;
  final DateTime? timestamp;

  Comentario({
    required this.id,
    required this.autorUid,
    required this.autorNome,
    required this.texto,
    required this.timestamp,
  });

  /// Monta um Comentario a partir de um documento lido do Firestore.
  factory Comentario.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Comentario(
      id: doc.id,
      autorUid: d['autorUid'] as String? ?? '',
      autorNome: d['autorNome'] as String? ?? '',
      texto: d['texto'] as String? ?? '',
      timestamp: (d['timestamp'] as Timestamp?)?.toDate(),
    );
  }
}
