// Tela que abre, dentro do próprio app, a página pública oficial de
// "Confirmação de entrega própria" da 99Food ou do iFood — não é uma API
// nossa, é a mesma ferramenta que qualquer entregador de entrega própria já
// usa (só precisa do código localizador de 8 dígitos da comanda, sem login
// nem vínculo de restaurante nenhum, funciona pra qualquer um). Só existe
// nas versões nativas (Android/iOS/desktop) — na Web, home_tab.dart abre
// isso numa aba nova em vez de usar essa tela, porque esses sites podem
// bloquear ser exibidos dentro de outra página (frame bloqueado).
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ConfirmarEntregaPage extends StatefulWidget {
  final String titulo;
  final String url;

  const ConfirmarEntregaPage({super.key, required this.titulo, required this.url});

  @override
  State<ConfirmarEntregaPage> createState() => _ConfirmarEntregaPageState();
}

class _ConfirmarEntregaPageState extends State<ConfirmarEntregaPage> {
  late final WebViewController _controller;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _carregando = true),
          onPageFinished: (_) => setState(() => _carregando = false),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF050816),
        title: Text(widget.titulo),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_carregando) const Center(child: CircularProgressIndicator(color: Colors.blue)),
        ],
      ),
    );
  }
}
