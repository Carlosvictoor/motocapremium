// Guarda quem está logado no momento (nome e email) e cuida de criar/entrar
// na conta, tanto localmente (SQLite) quanto no Firebase (pro chat e pra
// liberar acesso de qualquer aparelho).
import 'database.dart';
import 'chat/chat_service.dart';

class AuthService {
  static String _nomeLogado = '';
  static String _emailLogado = '';

  /// Nome de quem está logado agora.
  static String get nomeLogado => _nomeLogado;

  /// Email de quem está logado agora.
  static String get emailLogado => _emailLogado;

  /// Define o nome do usuário logado (usado ao restaurar uma sessão salva).
  static void setNome(String nome) => _nomeLogado = nome;

  /// Define o email do usuário logado (usado ao restaurar uma sessão salva).
  static void setEmail(String email) => _emailLogado = email;

  /// Cria uma conta nova: salva localmente e também cria a conta no Firebase
  /// (pra poder usar o chat e ter o acesso liberado de qualquer aparelho).
  /// Se o Firebase estiver indisponível no momento, o cadastro local ainda
  /// funciona normalmente — a sincronização acontece no próximo login.
  static Future<bool> registrar({
    required String nome,
    required String email,
    required String senha,
  }) async {
    final ok = await DB.registrarUsuario(nome, email, senha);
    if (ok) {
      try {
        await ChatService.registrarConta(nome: nome, email: email, senha: senha);
      } catch (_) {
        // Chat online indisponível agora (ex.: Firebase ainda não configurado)
        // — não impede o uso do app; a conta é sincronizada no próximo login.
      }
    }
    return ok;
  }

  /// Faz login. Primeiro tenta achar a conta salva localmente no aparelho;
  /// se não achar (ex.: app foi desinstalado e reinstalado, ou é um
  /// aparelho novo), tenta recuperar a conta pelo Firebase e recria o
  /// registro local, pra tudo continuar funcionando como antes.
  /// Retorna true se conseguiu logar, false se o email/senha estão errados.
  static Future<bool> login({required String email, required String senha}) async {
    final nome = await DB.loginUsuario(email, senha);
    if (nome != null) {
      _nomeLogado = nome;
      _emailLogado = email;
      try {
        await ChatService.sincronizarConta(nome: nome, email: email, senha: senha);
      } catch (_) {
        // Chat online indisponível agora — login local segue funcionando.
      }
      return true;
    }

    // Não achou localmente — pode ser reinstalação ou aparelho novo. A conta
    // continua existindo no Firebase; recria o registro local pra manter a
    // sessão e as telas de assinatura/perfil funcionando como antes.
    try {
      final nomeOnline = await ChatService.loginOnline(email: email, senha: senha);
      if (nomeOnline != null) {
        await DB.registrarUsuario(nomeOnline, email, senha);
        _nomeLogado = nomeOnline;
        _emailLogado = email;
        return true;
      }
    } catch (_) {
      // Sem internet/Firebase indisponível — não há como recuperar a conta agora.
    }
    return false;
  }
}
