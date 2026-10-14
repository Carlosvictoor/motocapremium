// Funções auxiliares pequenas, usadas por várias telas do app (Home,
// Financeiro, Resumo, Meses Fechados). Ficam aqui pra não precisar repetir
// o mesmo código em cada arquivo.
import 'models.dart';

// Nomes dos meses em português, na ordem do calendário. A posição 0 fica
// vazia de propósito porque os meses são numerados de 1 (Janeiro) a 12
// (Dezembro), então dá pra usar o número do mês direto como índice da lista.
const List<String> nomesMeses = [
  '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

/// Monta o texto "Nome do Mês Ano" (ex: "Julho 2026") a partir do número
/// do mês (1-12) e do ano.
String labelMes(int mes, int ano) => '${nomesMeses[mes]} $ano';

/// Conta quantas saídas da lista realmente "contam" como uma entrega de
/// verdade. Uma saída só conta quando tem Taxa e/ou Comanda preenchida —
/// registrar apenas Paga e/ou Gorjeta é tratado como um valor avulso, não
/// como uma entrega nova (ver Saida.contaComoSaida em models.dart).
int contarSaidas(List<Saida> lista) => lista.where((s) => s.contaComoSaida).length;

/// Transforma um total de minutos em texto no formato "01h 30min", usado
/// pra mostrar o tempo online e outras durações na tela.
String formatarDuracaoMin(int totalMinutos) {
  final h = totalMinutos ~/ 60;
  final m = totalMinutos % 60;
  return '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}min';
}
