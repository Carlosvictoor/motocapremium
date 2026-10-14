// Conta/autenticação no Firebase: cria/sincroniza a conta Firebase Auth,
// checa a assinatura online e alimenta o painel admin. Não tem mais nada de
// chat aqui (o chat foi removido) — o arquivo ficou nessa pasta por não
// valer a pena mover agora.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  /// Uid do Firebase de quem está logado agora (null se ninguém estiver
  /// conectado ao Firebase).
  static String? get meuUid => _auth.currentUser?.uid;

  /// Espera o Firebase Auth terminar de restaurar a sessão salva (no
  /// navegador ele guarda o login no IndexedDB e restaura sozinho, mas isso
  /// é assíncrono — logo depois de abrir o app [meuUid] pode ainda estar
  /// null mesmo que exista uma sessão pra restaurar). Só depois disso é
  /// seguro decidir se tem alguém logado ou não.
  ///
  /// Também força a renovação do ID token antes de liberar — na Web,
  /// mesmo com [meuUid] já preenchido, o SDK do Firestore às vezes ainda
  /// não recebeu o token internamente, e a primeira leitura falha com
  /// "permission-denied" (ver retry em main_shell.dart). Buscar o token
  /// aqui de propósito dá tempo do Firestore ficar pronto de verdade antes
  /// de qualquer leitura começar, em vez de só tentar de novo depois do erro.
  static Future<void> aguardarAuthPronto() async {
    await _auth.authStateChanges().first;
    await _auth.currentUser?.getIdToken();
  }

  /// Manda o email de redefinição de senha do Firebase pro endereço
  /// informado. O Firebase não avisa se o email existe ou não (por
  /// segurança, pra não deixar alguém descobrir quais emails têm conta) —
  /// então sempre retorna normalmente, a não ser que o próprio formato do
  /// email seja inválido.
  static Future<void> enviarEmailRecuperacaoSenha(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  /// ID token do Firebase de quem está logado agora — usado como Bearer nas
  /// chamadas ao backend do Motoca Premium (ver lib/pedidos/pedidos_api.dart).
  /// Null se ninguém estiver conectado ao Firebase.
  static Future<String?> getIdToken() => _auth.currentUser?.getIdToken() ?? Future.value(null);

  /// Guarda o motivo da última falha ao conectar a conta com o Firebase
  /// (login/registro), pra exibir na tela em vez de falhar em silêncio sem
  /// nenhuma pista do que aconteceu.
  static String? ultimoErroConta;

  // ── Migração / sincronização de conta ─────────────────────────────────────

  /// Garante que existe uma conta Firebase para este email/senha e que o
  /// perfil em `usuarios/{uid}` está atualizado. Não mexe nos dados locais.
  static Future<void> sincronizarConta({
    required String nome,
    required String email,
    required String senha,
  }) async {
    try {
      UserCredential cred;
      try {
        cred = await _auth.signInWithEmailAndPassword(email: email, password: senha);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          cred = await _auth.createUserWithEmailAndPassword(email: email, password: senha);
        } else {
          // Ex.: invalid-credential/wrong-password — conta já migrada com
          // senha diferente da local — não há como conciliar aqui.
          rethrow;
        }
      }
      await _db.collection('usuarios').doc(cred.user!.uid).set({
        'nome': nome,
        'email': email,
        'criadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      ultimoErroConta = null;
    } catch (e) {
      ultimoErroConta = e.toString();
      rethrow;
    }
  }

  /// Login quando a conta não existe mais localmente (app desinstalado e
  /// reinstalado, ou aparelho novo): valida a senha direto no Firebase Auth e
  /// devolve o nome salvo no perfil, pra quem chamou recriar o registro local.
  /// Retorna null se a conta não existir no Firebase (nunca foi sincronizada).
  static Future<String?> loginOnline({required String email, required String senha}) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: senha);
      final doc = await _db.collection('usuarios').doc(cred.user!.uid).get();
      final nome = doc.data()?['nome'] as String?;
      ultimoErroConta = null;
      return (nome == null || nome.isEmpty) ? null : nome;
    } on FirebaseAuthException catch (e) {
      ultimoErroConta = e.toString();
      return null;
    } catch (e) {
      ultimoErroConta = e.toString();
      rethrow;
    }
  }

  /// Registro novo: cria a conta Firebase; se o email já existir (outro
  /// aparelho), tenta logar com a mesma senha em vez de falhar.
  static Future<void> registrarConta({
    required String nome,
    required String email,
    required String senha,
  }) async {
    try {
      try {
        final cred = await _auth.createUserWithEmailAndPassword(email: email, password: senha);
        await _db.collection('usuarios').doc(cred.user!.uid).set({
          'nome': nome,
          'email': email,
          'criadoEm': FieldValue.serverTimestamp(),
        });
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          await sincronizarConta(nome: nome, email: email, senha: senha);
        } else {
          rethrow;
        }
      }
      ultimoErroConta = null;
    } catch (e) {
      ultimoErroConta = e.toString();
      rethrow;
    }
  }

  /// Se a assinatura do usuário logado foi liberada pelo admin pelo
  /// Firestore (funciona em qualquer aparelho, ao contrário do código local
  /// por dispositivo).
  static Future<bool> isSubscricaoAtivaOnline() async {
    final uid = meuUid;
    if (uid == null) return false;
    try {
      final doc = await _db.collection('usuarios').doc(uid).get();
      return doc.data()?['subscricaoAtiva'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Tipo da conta logada (`"motoboy"` ou `"restaurante"`) — usado no login
  /// pra decidir pra qual tela mandar. Contas antigas não têm esse campo
  /// salvo, então tratamos ausência como `"motoboy"` (comportamento de
  /// sempre).
  static Future<String> buscarTipoUsuario(String uid) async {
    try {
      final doc = await _db.collection('usuarios').doc(uid).get();
      return doc.data()?['tipo'] as String? ?? 'motoboy';
    } catch (_) {
      return 'motoboy';
    }
  }

  // ── Admin ────────────────────────────────────────────────────────────────

  /// Lista todos os usuários cadastrados no Firebase (todos os aparelhos),
  /// no mesmo formato que o painel admin já esperava do banco local.
  static Future<List<Map<String, dynamic>>> getTodosUsuariosAdmin() async {
    final snap = await _db.collection('usuarios').orderBy('criadoEm', descending: true).get();
    return snap.docs.map(_usuarioDoDocumento).toList();
  }

  /// Mesma lista de [getTodosUsuariosAdmin], mas como stream — atualiza
  /// sozinha assim que a assinatura de alguém mudar em qualquer aparelho,
  /// sem precisar de botão de atualizar no painel admin.
  static Stream<List<Map<String, dynamic>>> streamTodosUsuariosAdmin() {
    return _db
        .collection('usuarios')
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(_usuarioDoDocumento).toList());
  }

  static Map<String, dynamic> _usuarioDoDocumento(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final criadoEm = data['criadoEm'] as Timestamp?;
    return <String, dynamic>{
      'uid': d.id,
      'nome': (data['nome'] as String?) ?? '',
      'email': (data['email'] as String?) ?? '',
      'subscricao_ativa': data['subscricaoAtiva'] == true ? 1 : 0,
      'data_cadastro': criadoEm?.toDate().toIso8601String(),
      'tipo': (data['tipo'] as String?) ?? 'motoboy',
    };
  }

  /// Liga/desliga a assinatura de um usuário direto no Firestore — chamado
  /// pelo painel admin ao liberar/revogar o acesso de alguém.
  static Future<void> setSubscricaoUsuarioAdmin(String uid, bool ativa) async {
    await _db.collection('usuarios').doc(uid).set({
      'subscricaoAtiva': ativa,
    }, SetOptions(merge: true));
  }
}
