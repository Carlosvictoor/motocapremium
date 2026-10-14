// Avisa o backend toda vez que o motoboy aperta "Zerar o dia" no
// Financeiro (ver lib/main_shell.dart _zerarODia) — só um sinal de
// sincronização pro relatório do painel do restaurante (Fase 12,
// backend/src/routes/motoboyZerarDia.ts), não guarda nenhum dado
// financeiro em si. Sempre best-effort: falha de rede aqui não deve
// travar nem avisar o motoboy, o "Zerar o dia" local já aconteceu.
import 'dart:async';
import 'package:http/http.dart' as http;
import 'chat/chat_service.dart';

class MotoboyZerarDiaApi {
  static const _baseUrl = 'https://motoca-premium-backend.motoca-premium.workers.dev';

  static Future<void> avisar() async {
    try {
      final token = await ChatService.getIdToken();
      if (token == null) return;
      await http
          .post(
            Uri.parse('$_baseUrl/api/motoboy/zerar-dia'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best-effort — sem sinal de sincronização o relatório do
      // restaurante só usa o corte padrão (meia-noite) em vez do horário
      // exato, não é motivo pra travar o app do motoboy.
    }
  }
}
