// Serviço de conta de restaurante: criação da conta (usado só pelo admin,
// ver criar_restaurante_page.dart) e os dados que o próprio restaurante
// gerencia depois de logado (taxa por bairro, motoboys vinculados) — tudo
// no Firestore, subcoleções de usuarios/{uid} (ver firestore.rules).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import '../chat/chat_service.dart';

class Bairro {
  final String id;
  final String nome;
  final double taxa;

  Bairro({required this.id, required this.nome, required this.taxa});

  factory Bairro.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) => Bairro(
        id: doc.id,
        nome: doc.data()['nome'] as String? ?? '',
        taxa: (doc.data()['taxa'] as num?)?.toDouble() ?? 0,
      );
}

class MotoboyVinculado {
  final String uid;
  final String nome;
  final String email;

  MotoboyVinculado({required this.uid, required this.nome, required this.email});

  factory MotoboyVinculado.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) => MotoboyVinculado(
        uid: doc.id,
        nome: doc.data()['nome'] as String? ?? '',
        email: doc.data()['email'] as String? ?? '',
      );
}

class RestauranteService {
  static final _db = FirebaseFirestore.instance;

  /// Cria a conta Firebase de um restaurante novo (chamado só pelo admin).
  /// Usa uma segunda instância do Firebase App pra não derrubar a sessão
  /// de quem está criando (o app principal continua logado como admin).
  /// Devolve o uid criado.
  static Future<String> criarContaRestaurante({
    required String nome,
    required String email,
    required String senha,
  }) async {
    final nomeApp = 'criar_restaurante_${DateTime.now().millisecondsSinceEpoch}';
    final appSecundario = await Firebase.initializeApp(
      name: nomeApp,
      options: DefaultFirebaseOptions.currentPlatform,
    );
    try {
      final authSecundario = FirebaseAuth.instanceFor(app: appSecundario);
      final cred = await authSecundario.createUserWithEmailAndPassword(email: email, password: senha);
      final uid = cred.user!.uid;

      final firestoreSecundario = FirebaseFirestore.instanceFor(app: appSecundario);
      await firestoreSecundario.collection('usuarios').doc(uid).set({
        'nome': nome,
        'email': email,
        'tipo': 'restaurante',
        'criadoEm': FieldValue.serverTimestamp(),
      });

      await authSecundario.signOut();
      return uid;
    } finally {
      await appSecundario.delete();
    }
  }

  /// Nome cadastrado na própria conta — só pra pré-preencher o campo "Nome
  /// do restaurante" ao gerar credenciais Saipos (ver restaurante_dashboard.dart),
  /// continua editável já que o restaurante pode ter mais de uma filial/loja.
  static Future<String> getNomeConta(String restauranteUid) async {
    final doc = await _db.collection('usuarios').doc(restauranteUid).get();
    return doc.data()?['nome'] as String? ?? '';
  }

  // ── Sobreposição de taxa por bairro ─────────────────────────────────────

  /// Se ligado, a taxa mostrada/registrada pro motoboy usa o valor
  /// configurado no bairro do Motoca Premium em vez do valor que veio no
  /// pedido (ver lib/restaurante/taxa_override_service.dart).
  static Future<bool> getUsarTaxaMotocaPremium(String restauranteUid) async {
    final doc = await _db.collection('usuarios').doc(restauranteUid).get();
    return doc.data()?['usarTaxaMotocaPremium'] as bool? ?? false;
  }

  static Future<void> definirUsarTaxaMotocaPremium(String restauranteUid, bool valor) =>
      _db.collection('usuarios').doc(restauranteUid).set({'usarTaxaMotocaPremium': valor}, SetOptions(merge: true));

  // ── Bairros ──────────────────────────────────────────────────────────────

  static Future<List<Bairro>> listarBairros(String restauranteUid) async {
    final snap = await _db.collection('usuarios').doc(restauranteUid).collection('bairros').get();
    final bairros = snap.docs.map(Bairro.fromDoc).toList();
    bairros.sort((a, b) => a.nome.compareTo(b.nome));
    return bairros;
  }

  static Future<void> salvarBairro(String restauranteUid, {String? id, required String nome, required double taxa}) async {
    final colecao = _db.collection('usuarios').doc(restauranteUid).collection('bairros');
    if (id != null) {
      await colecao.doc(id).update({'nome': nome, 'taxa': taxa});
    } else {
      await colecao.add({'nome': nome, 'taxa': taxa});
    }
  }

  static Future<void> removerBairro(String restauranteUid, String id) =>
      _db.collection('usuarios').doc(restauranteUid).collection('bairros').doc(id).delete();

  // ── Motoboys vinculados ─────────────────────────────────────────────────

  static Future<List<MotoboyVinculado>> listarMotoboysVinculados(String restauranteUid) async {
    final snap = await _db.collection('usuarios').doc(restauranteUid).collection('motoboys').get();
    return snap.docs.map(MotoboyVinculado.fromDoc).toList();
  }

  static Future<void> vincularMotoboy(String restauranteUid, {required String motoboyUid, required String nome, required String email}) =>
      _db.collection('usuarios').doc(restauranteUid).collection('motoboys').doc(motoboyUid).set({
        'nome': nome,
        'email': email,
        'vinculadoEm': FieldValue.serverTimestamp(),
      });

  static Future<void> desvincularMotoboy(String restauranteUid, String motoboyUid) =>
      _db.collection('usuarios').doc(restauranteUid).collection('motoboys').doc(motoboyUid).delete();

  /// Lista de todos os motoboys cadastrados no app (pra escolher qual
  /// vincular) — mesma fonte que o admin já usa, excluindo outras contas
  /// de restaurante da lista.
  static Future<List<Map<String, dynamic>>> listarTodosMotoboys() async {
    final todos = await ChatService.getTodosUsuariosAdmin();
    return todos.where((u) => u['tipo'] != 'restaurante').toList();
  }
}
