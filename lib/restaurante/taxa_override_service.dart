// Calcula a taxa efetiva de um pedido quando o restaurante dono dele tem a
// sobreposição por bairro ligada (ver restaurante_dashboard.dart, o switch
// "Usar taxas do Motoca Premium por bairro"). Casamento por texto: procura
// se o nome de algum bairro cadastrado aparece dentro do endereço do
// pedido — sem diferenciar maiúsculas/minúsculas nem acento. Sem raio em
// km por enquanto (fora de escopo, avisado ao usuário — Fase 11.1).
import 'restaurante_service.dart';

class TaxaOverrideService {
  static final Map<String, bool> _cacheLigado = {};
  static final Map<String, List<Bairro>> _cacheBairros = {};

  /// Limpa o cache — usar ao trocar de aba/tela pra não ficar com dado
  /// velho depois que o restaurante mexer na config dele.
  static void limparCache() {
    _cacheLigado.clear();
    _cacheBairros.clear();
  }

  static String _semAcento(String texto) {
    const comAcento = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const semAcento = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    var resultado = texto;
    for (var i = 0; i < comAcento.length; i++) {
      resultado = resultado.replaceAll(comAcento[i], semAcento[i]);
    }
    return resultado.toLowerCase();
  }

  /// Devolve a taxa final pra esse pedido: se o restaurante não existir,
  /// não tiver o switch ligado, ou nenhum bairro bater com o endereço,
  /// devolve [taxaOriginal] sem alterar nada. Nunca lança exceção — se a
  /// leitura no Firestore falhar por qualquer motivo (rede, permissão),
  /// cai pra [taxaOriginal] em vez de travar a aba Pedidos inteira (era
  /// exatamente esse silêncio que faltava; sem ele um erro aqui deixava o
  /// carregamento da aba preso pra sempre).
  static Future<double> taxaEfetiva({
    required String? restauranteUid,
    required String? endereco,
    required double taxaOriginal,
  }) async {
    if (restauranteUid == null || restauranteUid.isEmpty) return taxaOriginal;

    try {
      final ligado = _cacheLigado[restauranteUid] ??=
          await RestauranteService.getUsarTaxaMotocaPremium(restauranteUid);
      if (!ligado) return taxaOriginal;

      if (endereco == null || endereco.isEmpty) return taxaOriginal;

      final bairros = _cacheBairros[restauranteUid] ??=
          await RestauranteService.listarBairros(restauranteUid);
      if (bairros.isEmpty) return taxaOriginal;

      final enderecoNormalizado = _semAcento(endereco);
      for (final bairro in bairros) {
        if (bairro.nome.isEmpty) continue;
        if (enderecoNormalizado.contains(_semAcento(bairro.nome))) {
          return bairro.taxa;
        }
      }

      return taxaOriginal;
    } catch (_) {
      return taxaOriginal;
    }
  }
}
