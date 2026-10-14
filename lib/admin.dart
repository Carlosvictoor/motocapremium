// Painel exclusivo do administrador do app: mostra todo mundo que já se
// cadastrou (lendo do Firebase, então funciona pra usuários de qualquer
// aparelho) e permite liberar/revogar o acesso premium de cada um, além de
// gerar códigos de acesso pra vender manualmente.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'codigos.dart';
import 'chat/chat_service.dart';
import 'admin_motoboys_page.dart';
import 'restaurante/criar_restaurante_page.dart';

// ─── Admin credentials ────────────────────────────────────────────────────────

const String kAdminEmail = 'victorjg10@admin.com';
const String kAdminSenha = '199612@Vs';

/// Chave fixa que autentica as rotas /admin/* do backend do Motoca Premium
/// (ver backend/src/routes/adminLojas.ts) — mesmo padrão do kAdminSenha
/// acima, só que validada no servidor em vez do app.
const String kAdminApiKey = '48475d002b0b2db8bf817d72df51e17f4da7645b84a860651a04bdcc3cb71cd0';

/// Verifica se o email/senha digitados na tela de login são os do admin
/// (em vez de uma conta de usuário comum).
bool isAdminCredentials(String email, String senha) =>
    email.trim() == kAdminEmail && senha.trim() == kAdminSenha;

// ─── AdminDashboard ───────────────────────────────────────────────────────────

class AdminDashboard extends StatefulWidget {
  final VoidCallback onLogout;
  const AdminDashboard({super.key, required this.onLogout});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  String _busca = '';
  late final Future<void> _autenticacao;

  @override
  void initState() {
    super.initState();
    _autenticacao = _garantirAutenticado();
  }

  /// Garante que o admin está autenticado no Firebase antes de abrir o
  /// stream — sem uma conta Firebase logada, as regras de segurança do
  /// Firestore bloqueiam a leitura.
  Future<void> _garantirAutenticado() async {
    if (ChatService.meuUid == null) {
      await ChatService.sincronizarConta(nome: 'Admin', email: kAdminEmail, senha: kAdminSenha);
    }
  }

  /// Lista de usuários filtrada pelo texto digitado na busca (por nome ou
  /// email); se a busca estiver vazia, mostra todo mundo.
  List<Map<String, dynamic>> _filtrados(List<Map<String, dynamic>> usuarios) {
    if (_busca.isEmpty) return usuarios;
    final q = _busca.toLowerCase();
    return usuarios
        .where((u) =>
            (u['nome'] as String).toLowerCase().contains(q) ||
            (u['email'] as String).toLowerCase().contains(q))
        .toList();
  }

  /// Quantos usuários têm assinatura ativa.
  int _totalPagos(List<Map<String, dynamic>> usuarios) =>
      usuarios.where((u) => (u['subscricao_ativa'] as int) == 1).length;

  /// Quantos usuários não têm assinatura ativa.
  int _totalNaoPagos(List<Map<String, dynamic>> usuarios) =>
      usuarios.where((u) => (u['subscricao_ativa'] as int) == 0).length;

  /// Quantos são motoboys (contas de restaurante têm `tipo: 'restaurante'`;
  /// qualquer conta sem esse campo é motoboy, ver ChatService._usuarioDoDocumento).
  int _totalMotoboys(List<Map<String, dynamic>> usuarios) =>
      usuarios.where((u) => u['tipo'] != 'restaurante').length;

  /// Quantos são contas de restaurante.
  int _totalRestaurantes(List<Map<String, dynamic>> usuarios) =>
      usuarios.where((u) => u['tipo'] == 'restaurante').length;

  /// Gera um código de acesso novo (30 dias) e mostra num popup pra
  /// copiar e enviar ao cliente.
  Future<void> _gerarCodigo() async {
    final codigo = CodigoAcesso.gerar();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.vpn_key_outlined, color: Colors.orange),
          SizedBox(width: 10),
          Text('Código gerado!'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Envie este código para o cliente. Ele libera 30 dias de acesso.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: codigo));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Código copiado!'),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      codigo,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.copy, color: Colors.orange, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Toque no código para copiar',
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Pergunta se quer mesmo liberar/revogar o acesso premium desse
  /// usuário e, se confirmar, atualiza no Firebase.
  Future<void> _toggleSubscricao(Map<String, dynamic> u) async {
    final uid = u['uid'] as String;
    final ativa = (u['subscricao_ativa'] as int) == 1;
    final nome = u['nome'] as String;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(ativa ? Icons.lock_outline : Icons.lock_open,
              color: ativa ? Colors.red : Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ativa ? 'Revogar acesso?' : 'Liberar acesso?',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ]),
        content: Text(
          ativa
              ? 'Revogar a assinatura de $nome?'
              : 'Liberar acesso premium para $nome?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ativa ? Colors.red : Colors.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ativa ? 'Revogar' : 'Liberar',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await ChatService.setSubscricaoUsuarioAdmin(uid, !ativa);
    // Não precisa recarregar manualmente — o stream do painel atualiza sozinho.

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ativa
            ? 'Acesso de $nome revogado.'
            : 'Acesso de $nome liberado!'),
        backgroundColor: ativa ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.purple.withValues(alpha: 0.4), width: 2),
                    ),
                    child: const Icon(Icons.admin_panel_settings,
                        color: Colors.purple, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Painel Admin',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
                        Text('Motoca Premium',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const AdminMotoboysPage())),
                    tooltip: 'Adicionar motoboy',
                    icon: const Icon(Icons.person_add_alt_1, color: Colors.blue),
                  ),
                  IconButton(
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const CriarRestaurantePage())),
                    tooltip: 'Criar restaurante',
                    icon: const Icon(Icons.storefront, color: Colors.green),
                  ),
                  IconButton(
                    onPressed: _gerarCodigo,
                    tooltip: 'Gerar código de acesso',
                    icon: const Icon(Icons.vpn_key_outlined, color: Colors.orange),
                  ),
                  GestureDetector(
                    onTap: widget.onLogout,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.logout, color: Colors.red, size: 16),
                        SizedBox(width: 6),
                        Text('Sair',
                            style: TextStyle(color: Colors.red, fontSize: 13)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Busca (fora do stream — não precisa recarregar a cada letra)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (v) => setState(() => _busca = v),
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Buscar por nome ou email...',
                  hintStyle:
                      const TextStyle(color: Colors.white38, fontSize: 14),
                  prefixIcon:
                      const Icon(Icons.search, color: Colors.white38, size: 20),
                  filled: true,
                  fillColor: const Color(0xFF111827),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Cards + lista, em tempo real (StreamBuilder no Firestore).
            Expanded(
              child: FutureBuilder<void>(
                future: _autenticacao,
                builder: (context, autenticado) {
                  if (autenticado.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(color: Colors.blue));
                  }
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: ChatService.streamTodosUsuariosAdmin(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text('Não foi possível carregar os usuários: ${snapshot.error}',
                              style: const TextStyle(color: Colors.red)),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: Colors.blue));
                      }
                      final usuarios = snapshot.data!;
                      final filtrados = _filtrados(usuarios);

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                Expanded(child: _statCard(
                                  Icons.people_outline, 'Total', usuarios.length.toString(), Colors.blue,
                                )),
                                const SizedBox(width: 10),
                                Expanded(child: _statCard(
                                  Icons.check_circle_outline, 'Pagaram', _totalPagos(usuarios).toString(), Colors.green,
                                )),
                                const SizedBox(width: 10),
                                Expanded(child: _statCard(
                                  Icons.cancel_outlined, 'Não pagaram', _totalNaoPagos(usuarios).toString(), Colors.red,
                                )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                Expanded(child: _statCard(
                                  Icons.two_wheeler, 'Motoboys', _totalMotoboys(usuarios).toString(), Colors.orange,
                                )),
                                const SizedBox(width: 10),
                                Expanded(child: _statCard(
                                  Icons.storefront, 'Restaurantes', _totalRestaurantes(usuarios).toString(), Colors.purple,
                                )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: filtrados.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.people_outline, color: Colors.white24, size: 60),
                                        const SizedBox(height: 12),
                                        Text(
                                          _busca.isEmpty
                                              ? 'Nenhum usuário cadastrado ainda'
                                              : 'Nenhum resultado para "$_busca"',
                                          style: const TextStyle(color: Colors.white38, fontSize: 16),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                    itemCount: filtrados.length,
                                    itemBuilder: (_, i) => _usuarioCard(filtrados[i]),
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Um dos 3 cards de resumo no topo (Total, Pagaram, Não pagaram).
  Widget _statCard(IconData icone, String titulo, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icone, color: cor, size: 22),
          const SizedBox(height: 6),
          Text(valor,
              style: TextStyle(
                  color: cor, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(titulo,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  /// Card de um usuário na lista: avatar com a inicial do nome, nome,
  /// email, data de cadastro e o botão de liberar/revogar acesso.
  Widget _usuarioCard(Map<String, dynamic> u) {
    final ativo = (u['subscricao_ativa'] as int) == 1;
    final nome = u['nome'] as String;
    final email = u['email'] as String;
    final dataCadastro = u['data_cadastro'] as String?;

    String dataStr = '';
    if (dataCadastro != null) {
      try {
        final dt = DateTime.parse(dataCadastro);
        dataStr =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ativo
              ? Colors.green.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ativo
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: ativo ? Colors.green : Colors.white54),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(email,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                if (dataStr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('Cadastro: $dataStr',
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 11)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: ativo
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  ativo ? 'Pago' : 'Não pago',
                  style: TextStyle(
                    color: ativo ? Colors.green : Colors.red,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _toggleSubscricao(u),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: ativo
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: ativo
                            ? Colors.red.withValues(alpha: 0.3)
                            : Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    ativo ? 'Revogar' : 'Liberar',
                    style: TextStyle(
                      color: ativo ? Colors.red : Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
