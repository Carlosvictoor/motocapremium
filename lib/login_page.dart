// Tela de login: onde o usuário digita email e senha pra entrar no app.
// Também é aqui que a conta de admin é reconhecida (email/senha especiais
// levam direto pro painel administrativo, sem passar pelo login normal).
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'database.dart';
import 'assinatura.dart';
import 'admin.dart';
import 'auth_service.dart';
import 'chat/chat_service.dart';
import 'main_shell.dart';
import 'register_page.dart';
import 'restaurante/restaurante_dashboard.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final senhaController = TextEditingController();
  bool _senhaVisivel = false;
  bool _carregando = false;
  bool _salvarLogin = true;
  String? _erro;

  @override
  void dispose() {
    emailController.dispose();
    senhaController.dispose();
    super.dispose();
  }

  /// Tenta logar com o email/senha digitados. Se for a conta de admin,
  /// pula direto pro painel administrativo. Se for um usuário normal,
  /// valida a conta, salva a sessão (se "Salvar login" estiver marcado) e
  /// decide pra onde ir: paywall (se a assinatura venceu) ou tela principal.
  Future<void> _entrar() async {
    final email = emailController.text.trim();
    final senha = senhaController.text.trim();

    if (email.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Preencha todos os campos.');
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    // Verifica conta admin
    if (isAdminCredentials(email, senha)) {
      if (!mounted) return;
      setState(() => _carregando = false);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => AdminDashboard(
            onLogout: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (_) => false,
            ),
          ),
        ),
        (_) => false,
      );
      return;
    }

    final ok = await AuthService.login(email: email, senha: senha);

    if (!mounted) return;
    setState(() => _carregando = false);

    if (ok) {
      if (_salvarLogin) {
        await DB.salvarSessao(AuthService.nomeLogado);
        await DB.salvarSessaoEmail(email);
      }

      // Login de restaurante (ver Fase 11): pula direto pra tela dele, sem
      // checar assinatura/trial — isso é só pra motoboy.
      final meuUid = ChatService.meuUid;
      if (meuUid != null && await ChatService.buscarTipoUsuario(meuUid) == 'restaurante') {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => RestauranteDashboard(
              onLogout: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (_) => false,
              ),
            ),
          ),
          (_) => false,
        );
        return;
      }

      AssinaturaService.setEmailAtual(email);
      final estado = await AssinaturaService.verificar(email: email);
      if (!mounted) return;
      if (estado == EstadoAssinatura.expirado) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => PaywallPage(
              trialExpirado: true,
              onAssinado: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MainShell()),
                (_) => false,
              ),
            ),
          ),
          (_) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainShell()),
          (_) => false,
        );
      }
    } else {
      setState(() => _erro = 'Email ou senha incorretos.');
    }
  }

  /// Abre um diálogo pra confirmar o email e manda o link de redefinição de
  /// senha do Firebase pra ele.
  Future<void> _recuperarSenha() async {
    final controller = TextEditingController(text: emailController.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.lock_reset, color: Colors.blue),
          SizedBox(width: 10),
          Text('Recuperar senha'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Digite o email da sua conta. Vamos mandar um link pra você criar uma senha nova.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'seu@email.com',
                filled: true,
                fillColor: const Color(0xFF1B2435),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Enviar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.isEmpty) return;

    try {
      await ChatService.enviarEmailRecuperacaoSenha(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Se $email tiver uma conta, o email de recuperação já foi enviado.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'invalid-email') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Email inválido.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      if (e.code == 'user-not-found') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Email não cadastrado.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível enviar agora. Tente de novo.'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erro de conexão. Tente de novo.'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),

              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.3), width: 2),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'imagens/iconeapp.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Center(child: Text('🏍️', style: TextStyle(fontSize: 52))),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Motoca Premium',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Seu parceiro nas entregas',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),

              const SizedBox(height: 10),

              const Text(
                'Caso não tenha cartão fale com o suporte (13)981865074',
                style: TextStyle(color: Colors.white38, fontSize: 13),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Entrar',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),

                    _campoTexto(
                      controller: emailController,
                      titulo: 'Email',
                      hint: 'seu@email.com',
                      icone: Icons.email_outlined,
                      tipo: TextInputType.emailAddress,
                    ),

                    _campoSenha(
                      controller: senhaController,
                      titulo: 'Senha',
                      hint: '••••••••',
                      visivel: _senhaVisivel,
                      onToggle: () =>
                          setState(() => _senhaVisivel = !_senhaVisivel),
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _carregando ? null : _recuperarSenha,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Esqueci minha senha',
                            style: TextStyle(color: Colors.blue, fontSize: 13)),
                      ),
                    ),

                    if (_erro != null) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_erro!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 14)),
                        ),
                      ]),
                    ],

                    const SizedBox(height: 12),

                    GestureDetector(
                      onTap: () => setState(() => _salvarLogin = !_salvarLogin),
                      child: Row(children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _salvarLogin,
                            onChanged: (v) => setState(() => _salvarLogin = v ?? true),
                            activeColor: Colors.blue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('Salvar login',
                            style: TextStyle(color: Colors.white70, fontSize: 15)),
                      ]),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                        ),
                        onPressed: _carregando ? null : _entrar,
                        child: _carregando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Entrar',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Não tem conta? ',
                      style: TextStyle(color: Colors.white54, fontSize: 15)),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const RegisterPage())),
                    child: const Text(
                      'Criar conta',
                      style: TextStyle(
                          color: Colors.blue,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Campo de texto padrão (email, nome etc.) com título em cima e ícone.
  Widget _campoTexto({
    required TextEditingController controller,
    required String titulo,
    required String hint,
    required IconData icone,
    TextInputType tipo = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: tipo,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icone, color: Colors.blue),
              filled: true,
              fillColor: const Color(0xFF1B2435),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }

  /// Campo de senha com botão de mostrar/esconder o texto digitado.
  Widget _campoSenha({
    required TextEditingController controller,
    required String titulo,
    required String hint,
    required bool visivel,
    required VoidCallback onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: !visivel,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(Icons.lock_outline, color: Colors.blue),
              suffixIcon: GestureDetector(
                onTap: onToggle,
                child: Icon(
                    visivel ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white38),
              ),
              filled: true,
              fillColor: const Color(0xFF1B2435),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }
}
