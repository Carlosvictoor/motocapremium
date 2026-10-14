// Gera o PDF do relatório (Fase 12) direto no Flutter, sem backend/API
// paga — pacotes `pdf` (monta o documento) + `printing` (abre o
// salvar/compartilhar/imprimir nativo, funciona em Android e Web).
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'restaurante_relatorio_api.dart';

Future<void> gerarEBaixarRelatorioPdf({
  required String nomeRestaurante,
  required RelatorioRestaurante relatorio,
  required String Function(String motoboyUid) nomeDoMotoboy,
}) async {
  final doc = pw.Document();
  final agora = DateTime.now();
  final dataStr =
      '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year} ${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';

  doc.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Header(level: 0, child: pw.Text('Relatório de entregas — $nomeRestaurante')),
        pw.Text('Gerado em $dataStr', style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Período aberto atual de cada motoboy (desde o último "Zerar o dia" dele).',
          style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
        ),
        if (relatorio.totalVendas > 0) ...[
          pw.SizedBox(height: 20),
          pw.Text('Formas de pagamento', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['Total de vendas', 'Crédito', 'Débito', 'Dinheiro', 'Pix'],
            data: [
              [
                'R\$ ${relatorio.totalVendas.toStringAsFixed(2)}',
                'R\$ ${relatorio.totalCredito.toStringAsFixed(2)}',
                'R\$ ${relatorio.totalDebito.toStringAsFixed(2)}',
                'R\$ ${relatorio.totalDinheiro.toStringAsFixed(2)}',
                'R\$ ${relatorio.totalPix.toStringAsFixed(2)}',
              ],
            ],
          ),
          if (relatorio.totalCartao > 0 || relatorio.totalOutros > 0) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Cartão não especificado: R\$ ${relatorio.totalCartao.toStringAsFixed(2)} · Outros: R\$ ${relatorio.totalOutros.toStringAsFixed(2)}',
              style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
            ),
          ],
        ],
        pw.SizedBox(height: 20),
        pw.Text('Resumo por motoboy', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Motoboy', 'Saídas', 'Total'],
          data: relatorio.motoboys
              .map((m) => [
                    nomeDoMotoboy(m.motoboyUid),
                    m.saidasHoje.toString(),
                    'R\$ ${m.totalHoje.toStringAsFixed(2)}',
                  ])
              .toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Text('Comandas', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Motoboy', 'Comanda', 'Valor', 'Horário'],
          data: [
            for (final m in relatorio.motoboys)
              for (final comanda in m.comandas)
                [nomeDoMotoboy(m.motoboyUid), comanda.referencia, 'R\$ ${comanda.taxa.toStringAsFixed(2)}', comanda.data],
          ],
        ),
      ],
    ),
  );

  await Printing.sharePdf(bytes: await doc.save(), filename: 'relatorio-motoca-premium.pdf');
}
