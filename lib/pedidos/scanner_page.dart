// Tela cheia de câmera pra ler o código de barras do cupom. Não faz nenhuma
// chamada de rede aqui — só devolve o texto lido (Navigator.pop) pra quem
// abriu decidir o que fazer (ver pedidos_tab.dart).
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _jaLeu = false; // trava novas leituras depois da primeira, evita disparo duplicado

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _aoDetectar(BarcodeCapture captura) {
    if (_jaLeu || captura.barcodes.isEmpty) return;
    final codigo = captura.barcodes.first.rawValue;
    if (codigo == null || codigo.isEmpty) return;
    _jaLeu = true;
    Navigator.pop(context, codigo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Escanear pedido'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _aoDetectar,
        errorBuilder: (context, error, child) => _erroCamera(error),
      ),
    );
  }

  /// Trata câmera negada/indisponível com uma mensagem clara em vez de tela
  /// preta sem explicação.
  Widget _erroCamera(MobileScannerException error) {
    final negada = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white54, size: 56),
            const SizedBox(height: 16),
            Text(
              negada
                  ? 'Permissão da câmera negada. Ative o acesso à câmera nas configurações do app pra escanear.'
                  : 'Não consegui abrir a câmera. Tente de novo.',
              style: const TextStyle(color: Colors.white70, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
