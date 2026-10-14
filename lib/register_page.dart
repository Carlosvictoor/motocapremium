// Tela de criação de conta nova.
import 'package:flutter/material.dart';
import 'auth_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nomeController = TextEditingController();
  final emailController = TextEditingController();
  final senhaController = TextEditingController();
  final confirmaSenhaController = TextEditingController();
  bool _senhaVisivel = false;
  bool _confirmaSenhaVisivel = false;
  bool _carregando = false;
  String? _erro;

  @override
  void dispose() {
    nomeController.dispose();
    emailController.dispose();
    senhaController.dispose();
    confirmaSenhaController.dispose();
    super.dispose();
  }

  /// Valida os campos (nome, email, senha com 6+ caracteres, confirmação
  /// batendo) e cria a conta. Se der certo, volta pra tela de login.
  Future<void> _registrar() async {
    final nome = nomeController.text.trim();
    final email = emailController.text.trim();
    final senha = senhaController.text.trim();
    final confirma = confirmaSenhaController.text.trim();

    if (nome.isEmpty || email.isEmpty || senha.isEmpty || confirma.isEmpty) {
      setState(() => _erro = 'Preencha todos os campos.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _erro = 'Digite um email válido.');
      return;
    }
    if (senha.length < 6) {
      setState(() => _erro = 'A senha deve ter pelo menos 6 caracteres.');
      return;
    }
    if (senha != confirma) {
      setState(() => _erro = 'As senhas não coincidem.');
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    final ok = await AuthService.registrar(nome: nome, email: email, senha: senha);

    if (!mounted) return;
    setState(() => _carregando = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Conta criada! Faça login.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.pop(context);
    } else {
      setState(() => _erro = 'Este email já está cadastrado.');
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
              const SizedBox(height: 10),

              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 25),

              Container(
                width: 90,
                height: 90,
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
                        const Center(child: Text('🏍️', style: TextStyle(fontSize: 44))),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Criar conta',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Preencha seus dados para começar',
                style: TextStyle(color: Colors.white54, fontSize: 15),
              ),

              const SizedBox(height: 30),

              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _campoReg(
                      controller: nomeController,
                      titulo: 'Nome completo',
                      hint: 'Seu nome',
                      icone: Icons.person_outline,
                    ),
                    _campoReg(
                      controller: emailController,
                      titulo: 'Email',
                      hint: 'seu@email.com',
                      icone: Icons.email_outlined,
                      tipo: TextInputType.emailAddress,
                    ),
                    _campoSenhaReg(
                      controller: senhaController,
                      titulo: 'Senha',
                      hint: 'Mínimo 6 caracteres',
                      visivel: _senhaVisivel,
                      onToggle: () =>
                          setState(() => _senhaVisivel = !_senhaVisivel),
                    ),
                    _campoSenhaReg(
                      controller: confirmaSenhaController,
                      titulo: 'Confirmar senha',
                      hint: 'Repita a senha',
                      visivel: _confirmaSenhaVisivel,
                      onToggle: () => setState(
                          () => _confirmaSenhaVisivel = !_confirmaSenhaVisivel),
                    ),

                    if (_erro != null) ...[
                      const SizedBox(height: 4),
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
                      const SizedBox(height: 12),
                    ],

                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                        ),
                        onPressed: _carregando ? null : _registrar,
                        child: _carregando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Criar conta',
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
                  const Text('Já tem conta? ',
                      style: TextStyle(color: Colors.white54, fontSize: 15)),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      'Entrar',
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

  /// Campo de texto padrão do formulário de cadastro (nome, email...).
  Widget _campoReg({
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

  /// Campo de senha do cadastro, com botão de mostrar/esconder.
  Widget _campoSenhaReg({
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
