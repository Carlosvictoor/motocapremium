// Widget raiz do app (MaterialApp) e a telinha de splash que decide pra
// onde mandar o usuário assim que o app abre: login, paywall (assinatura
// vencida) ou direto pra tela principal.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'database.dart';
import 'assinatura.dart';
import 'auth_service.dart';
import 'chat/chat_service.dart';
import 'login_page.dart';
import 'main_shell.dart';
import 'restaurante/restaurante_dashboard.dart';

class MotocaPremiumApp extends StatelessWidget {
  const MotocaPremiumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Motoca Premium',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050816),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData(brightness: Brightness.dark).textTheme),
      ),
      home: const _InicioPagina(),
    );
  }
}

/// Tela de carregamento que aparece assim que o app abre, enquanto decide
/// se o usuário já tem sessão salva e se a assinatura ainda está válida.
class _InicioPagina extends StatefulWidget {
  const _InicioPagina();
  @override
  State<_InicioPagina> createState() => _InicioPaginaState();
}

class _InicioPaginaState extends State<_InicioPagina> {
  @override
  void initState() {
    super.initState();
    _verificar();
  }

  /// Checa se existe uma sessão salva no aparelho. Se não tiver, manda pro
  /// login. Se tiver, checa o estado da assinatura: se venceu, mostra a
  /// tela de pagamento (paywall); senão, entra direto no app.
  Future<void> _verificar() async {
    // No navegador o Firebase Auth restaura a sessão salva de forma
    // assíncrona (IndexedDB) — sem esperar isso aqui, DB.getSessao() na Web
    // (que precisa do uid logado pra ler o Firestore) rodaria cedo demais e
    // travaria o app na tela de carregamento.
    await ChatService.aguardarAuthPronto();
    if (!mounted) return;

    final nome = await DB.getSessao();
    if (!mounted) return;
    if (nome == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }
    AuthService.setNome(nome);
    final email = await DB.getSessaoEmail() ?? '';
    AuthService.setEmail(email);

    // Login de restaurante (ver Fase 11): pula direto pra tela dele, sem
    // checar assinatura/trial — isso é só pra motoboy.
    final meuUid = ChatService.meuUid;
    if (meuUid != null && await ChatService.buscarTipoUsuario(meuUid) == 'restaurante') {
      if (!mounted) return;
      Navigator.pushReplacement(
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
      );
      return;
    }

    AssinaturaService.setEmailAtual(email);
    final estado = await AssinaturaService.verificar(email: email);
    if (!mounted) return;
    if (estado == EstadoAssinatura.expirado) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => PaywallPage(
          trialExpirado: true,
          onAssinado: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MainShell()),
            (_) => false,
          ),
        ),
      ));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainShell()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF050816),
      body: Center(child: CircularProgressIndicator(color: Colors.blue)),
    );
  }
}
