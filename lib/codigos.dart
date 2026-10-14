// Gera e confere os códigos de acesso (tipo "MOTO-AB12CD-XYZ") que o admin
// vende manualmente pra liberar 30 dias de app pra quem não tem cartão. Não
// precisa de internet pra conferir — o código carrega sua própria "prova"
// de que é válido (checksum), calculada com uma chave secreta.
import 'dart:math';

// Chave secreta usada para calcular o checksum — não altere após publicar
const _kChave = 'MOTOPREMIUM_2024_VJ';
const _kChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sem 0/O/I/1 pra evitar confusão

class CodigoAcesso {
  // ── Geração ──────────────────────────────────────────────────────────────

  /// Gera um código novo aleatório no formato "MOTO-XXXXXX-YYY", onde YYY
  /// é o checksum calculado a partir da parte aleatória.
  static String gerar() {
    final random = Random.secure();
    final parte = List.generate(6, (_) => _kChars[random.nextInt(_kChars.length)]).join();
    final check = _checksum(parte);
    return 'MOTO-$parte-$check';
  }

  // ── Validação ─────────────────────────────────────────────────────────────

  /// Confere se um código digitado tem o formato certo e se o checksum
  /// bate — ou seja, se é um código que realmente foi gerado por
  /// [gerar] (e não inventado por alguém tentando burlar).
  static bool validar(String codigo) {
    final partes = codigo.trim().toUpperCase().split('-');
    if (partes.length != 3) return false;
    if (partes[0] != 'MOTO') return false;
    if (partes[1].length != 6) return false;
    if (partes[2].length != 3) return false;
    return _checksum(partes[1]) == partes[2];
  }

  // ── Checksum (algoritmo determinístico com chave secreta) ─────────────────

  /// Calcula as 3 letras/números de checksum a partir da parte aleatória
  /// do código, misturando cada caractere com a chave secreta. O mesmo
  /// texto de entrada sempre gera o mesmo checksum.
  static String _checksum(String parte) {
    var h = 5381;
    for (var i = 0; i < parte.length; i++) {
      final p = parte.codeUnitAt(i);
      final k = _kChave.codeUnitAt(i % _kChave.length);
      h = (((h << 5) + h) ^ p ^ k) & 0x3FFFFFFF;
    }
    final c1 = _kChars[(h >> 10) % _kChars.length];
    final c2 = _kChars[(h >> 5) % _kChars.length];
    final c3 = _kChars[h % _kChars.length];
    return '$c1$c2$c3';
  }
}
