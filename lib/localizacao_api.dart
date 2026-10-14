// Salva a última posição conhecida do motoboy direto no Firestore (não
// passa pelo backend Cloudflare — é só um campo a mais no doc que já
// existe, mesmo padrão de outros campos simples do app). Chamado de
// lib/main_shell.dart, reaproveitando o GPS que já roda pro odômetro (ver
// _iniciarOdometro) — nunca liga um GPS novo nem pede permissão extra.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat/chat_service.dart';

class LocalizacaoApi {
  static final _db = FirebaseFirestore.instance;

  static Future<void> salvar(double lat, double lng) async {
    final uid = ChatService.meuUid;
    if (uid == null) return;
    try {
      await _db.collection('usuarios').doc(uid).set({
        'ultimaLocalizacao': {
          'lat': lat,
          'lng': lng,
          'atualizadoEm': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort — não deve travar nem avisar o motoboy, é só um sinal
      // secundário pro painel do restaurante.
    }
  }

  /// Lê a última localização salva de um motoboy. Devolve `null` se nunca
  /// salvou nenhuma ou se der erro.
  static Future<({double lat, double lng, DateTime? atualizadoEm})?> buscar(String motoboyUid) async {
    try {
      final doc = await _db.collection('usuarios').doc(motoboyUid).get();
      final dados = doc.data()?['ultimaLocalizacao'] as Map<String, dynamic>?;
      if (dados == null) return null;
      final lat = (dados['lat'] as num?)?.toDouble();
      final lng = (dados['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      final ts = dados['atualizadoEm'] as Timestamp?;
      return (lat: lat, lng: lng, atualizadoEm: ts?.toDate());
    } catch (_) {
      return null;
    }
  }

  /// Busca a localização de vários motoboys de uma vez (em paralelo) —
  /// usado na aba Localização do painel do restaurante (Fase 13.1). Só
  /// devolve quem realmente tem uma posição salva.
  static Future<List<({String uid, double lat, double lng, DateTime? atualizadoEm})>> buscarVarios(
    List<String> motoboyUids,
  ) async {
    final resultados = await Future.wait(motoboyUids.map((uid) async {
      final loc = await buscar(uid);
      return loc == null ? null : (uid: uid, lat: loc.lat, lng: loc.lng, atualizadoEm: loc.atualizadoEm);
    }));
    return resultados.where((r) => r != null).map((r) => r!).toList();
  }
}
