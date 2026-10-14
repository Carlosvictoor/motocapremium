// Versão do banco de dados pra rodar no navegador (web), onde SQLite não
// funciona. Os dados de verdade (saídas, dias, gastos, meses fechados, KM,
// assinatura/trial) ficam salvos no Cloud Firestore, na conta de quem tá
// logado (usuarios/{uid}) — assim não somem ao atualizar a página e
// aparecem de novo em qualquer navegador que entrar com a mesma conta. O
// cadastro/login local de usuários continua só em memória (é um cache que
// a autenticação de verdade via Firebase, em auth_service.dart, sempre
// sobrepõe no login) — ver database_io.dart pra a versão usada no
// Android/iOS/desktop (SQLite local), que é a referência do schema/
// comportamento que essa versão replica.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'chat/chat_service.dart';

class DB {
  static final _firestore = FirebaseFirestore.instance;

  /// Uid de quem está logado agora — os métodos de dados (saídas, dias,
  /// gastos etc.) só fazem sentido depois do login, quando isso já está
  /// disponível (o mesmo uid que a feature de Pedidos usa).
  static String _uid() {
    final uid = ChatService.meuUid;
    if (uid == null) {
      throw StateError('Nenhum usuário logado — não é possível acessar os dados.');
    }
    return uid;
  }

  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection('usuarios').doc(uid);

  static CollectionReference<Map<String, dynamic>> _col(String uid, String nome) =>
      _userDoc(uid).collection(nome);

  /// Pega o próximo id inteiro sequencial pra essa conta (substitui o
  /// AUTOINCREMENT do SQLite, já que documentos do Firestore não têm id
  /// numérico nativo) — usado como o dbId dos models, pra nenhuma tela do
  /// app precisar mudar.
  static Future<int> _proximoId(String uid) {
    final ref = _userDoc(uid);
    return _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final atual = (snap.data()?['proximoId'] as int?) ?? 1;
      tx.set(ref, {'proximoId': atual + 1}, SetOptions(merge: true));
      return atual;
    });
  }

  /// Lê os campos simples salvos direto no doc da conta (trial, assinatura,
  /// km, sessão etc.).
  static Future<Map<String, dynamic>> _dadosConta(String uid) async {
    final snap = await _userDoc(uid).get();
    return snap.data() ?? {};
  }

  static Future<void> _salvarNaConta(String uid, Map<String, dynamic> dados) =>
      _userDoc(uid).set(dados, SetOptions(merge: true));

  // ── Usuários (cache local — a autenticação de verdade é via Firebase,
  // ver auth_service.dart) ─────────────────────────────────────────────────

  static final List<Map<String, String>> _usuarios = [];

  /// Cria uma conta nova na memória. Retorna false se o email já existir.
  static Future<bool> registrarUsuario(String nome, String email, String senha) async {
    if (_usuarios.any((u) => u['email'] == email)) return false;
    _usuarios.add({'nome': nome, 'email': email, 'senha': senha});
    return true;
  }

  /// Confere email/senha e devolve o nome se bater, senão null.
  static Future<String?> loginUsuario(String email, String senha) async {
    final u = _usuarios.firstWhere(
      (u) => u['email'] == email && u['senha'] == senha,
      orElse: () => {},
    );
    return u.isEmpty ? null : u['nome'];
  }

  /// Verifica se esse email tem assinatura marcada como ativa.
  static Future<bool> isSubscricaoAtivaParaEmail(String email) async {
    final u = _usuarios.firstWhere((u) => u['email'] == email, orElse: () => {});
    return u['subscricao_ativa'] == '1';
  }

  /// Lista os usuários cadastrados (usado pelo painel admin local antigo).
  static Future<List<Map<String, dynamic>>> getUsuariosAdmin() async =>
      _usuarios.map((u) => Map<String, dynamic>.from(u)).toList();

  /// Liga/desliga a assinatura de um usuário.
  static Future<void> setSubscricaoUsuario(int id, bool ativa) async {
    final i = _usuarios.indexWhere((u) => u['id'] == id.toString());
    if (i >= 0) _usuarios[i]['subscricao_ativa'] = ativa ? '1' : '0';
  }

  // ── Saídas ativas (dia em aberto) ────────────────────────────────────────

  /// Adiciona uma saída à lista do dia em aberto.
  static Future<int> inserirSaidaAtiva(Saida s) async {
    final uid = _uid();
    final id = await _proximoId(uid);
    await _col(uid, 'saidasAtivas').doc(id.toString()).set({
      'id': id,
      ..._saidaParaMapa(s),
    });
    return id;
  }

  /// Remove uma saída do dia em aberto.
  static Future<void> deletarSaidaAtiva(int id) async {
    await _col(_uid(), 'saidasAtivas').doc(id.toString()).delete();
  }

  /// Corrige a comanda e/ou a taxa de uma saída já registrada hoje (caso o
  /// motoboy erre ao digitar).
  static Future<void> atualizarSaidaAtiva(int id, {String? comanda, String? taxa}) async {
    await _col(_uid(), 'saidasAtivas').doc(id.toString()).update({'comandas': comanda, 'taxa': taxa});
  }

  /// Lista as saídas do dia em aberto.
  static Future<List<Saida>> getSaidasAtivas() async {
    final snap = await _col(_uid(), 'saidasAtivas').get();
    final saidas = snap.docs.map((d) => _saidaDaMapa(d.data())).toList();
    saidas.sort((a, b) => (b.dbId ?? 0).compareTo(a.dbId ?? 0));
    return saidas;
  }

  /// Limpa as saídas do dia em aberto.
  static Future<void> limparSaidasAtivas() async {
    final uid = _uid();
    final snap = await _col(uid, 'saidasAtivas').get();
    final batch = _firestore.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // ── Dias ─────────────────────────────────────────────────────────────────

  /// Salva um dia no histórico (com as saídas dele embutidas, igual
  /// saidas_historico no SQLite, já que são sempre lidas/escritas juntas).
  static Future<void> salvarDia(DiaRegistro dia, {int? mesFechadoId}) async {
    final uid = _uid();
    final id = await _proximoId(uid);
    await _col(uid, 'dias').doc(id.toString()).set({
      'id': id,
      'data': Timestamp.fromDate(dia.data),
      'mesFechadoId': mesFechadoId,
      'kmRodado': dia.kmRodado,
      'tempoOnlineMin': dia.tempoOnlineMin,
      'saidas': dia.saidas.map(_saidaParaMapa).toList(),
    });
  }

  /// Lista os dias salvos — sem [mesFechadoId], só os do mês em aberto; com
  /// ele, os do mês já fechado.
  static Future<List<DiaRegistro>> getDias({int? mesFechadoId}) async {
    final uid = _uid();
    final snap = await _col(uid, 'dias')
        .where('mesFechadoId', isEqualTo: mesFechadoId)
        .get();
    final dias = snap.docs.map((d) {
      final r = d.data();
      final saidas = (r['saidas'] as List<dynamic>? ?? [])
          .map((s) => _saidaDaMapa(Map<String, dynamic>.from(s as Map)))
          .toList();
      return DiaRegistro(
        dbId: r['id'] as int,
        data: (r['data'] as Timestamp).toDate(),
        kmRodado: (r['kmRodado'] as num?)?.toDouble() ?? 0,
        tempoOnlineMin: (r['tempoOnlineMin'] as int?) ?? 0,
        saidas: saidas,
      );
    }).toList();
    dias.sort((a, b) => (b.dbId ?? 0).compareTo(a.dbId ?? 0));
    return dias;
  }

  /// Remove um dia do histórico.
  static Future<void> deletarDia(int id) async {
    await _col(_uid(), 'dias').doc(id.toString()).delete();
  }

  // ── Gastos ────────────────────────────────────────────────────────────────

  /// Salva um gasto novo.
  static Future<void> inserirGasto(Gasto g, {int? mesFechadoId}) async {
    final uid = _uid();
    final id = await _proximoId(uid);
    await _col(uid, 'gastos').doc(id.toString()).set({
      'id': id,
      'descricao': g.descricao,
      'valor': g.valor,
      'data': Timestamp.fromDate(g.data),
      'categoria': g.categoria,
      'mesFechadoId': mesFechadoId,
    });
  }

  /// Lista os gastos — sem [mesFechadoId], só os do mês em aberto; com ele,
  /// os do mês já fechado.
  static Future<List<Gasto>> getGastos({int? mesFechadoId}) async {
    final uid = _uid();
    final snap = await _col(uid, 'gastos')
        .where('mesFechadoId', isEqualTo: mesFechadoId)
        .get();
    final gastos = snap.docs.map((d) {
      final r = d.data();
      final cat = r['categoria'] as String;
      return Gasto(
        dbId: r['id'] as int,
        descricao: r['descricao'] as String,
        valor: (r['valor'] as num).toDouble(),
        data: (r['data'] as Timestamp).toDate(),
        categoria: cat,
        cor: _corCategoria(cat),
        icone: _iconeCategoria(cat),
      );
    }).toList();
    gastos.sort((a, b) => (b.dbId ?? 0).compareTo(a.dbId ?? 0));
    return gastos;
  }

  /// Remove um gasto.
  static Future<void> deletarGasto(int id) async {
    await _col(_uid(), 'gastos').doc(id.toString()).delete();
  }

  // ── Meses fechados ────────────────────────────────────────────────────────

  /// Cria o registro de um mês fechado.
  static Future<int> inserirMesFechado(int mes, int ano) async {
    final uid = _uid();
    final id = await _proximoId(uid);
    await _col(uid, 'mesesFechados').doc(id.toString()).set({'id': id, 'mes': mes, 'ano': ano});
    return id;
  }

  /// Vincula todos os dias/gastos que ainda estavam em aberto ao mês recém
  /// fechado.
  static Future<void> vincularAoMes(int mesFechadoId) async {
    final uid = _uid();
    final batch = _firestore.batch();
    final dias = await _col(uid, 'dias').where('mesFechadoId', isEqualTo: null).get();
    for (final d in dias.docs) {
      batch.update(d.reference, {'mesFechadoId': mesFechadoId});
    }
    final gastos = await _col(uid, 'gastos').where('mesFechadoId', isEqualTo: null).get();
    for (final g in gastos.docs) {
      batch.update(g.reference, {'mesFechadoId': mesFechadoId});
    }
    await batch.commit();
  }

  /// Vincula ao mês fechado só os dias/gastos que caem dentro daquele
  /// mês/ano específico.
  static Future<void> vincularAoMesPorMesAno(int mesFechadoId, int mes, int ano) async {
    final uid = _uid();
    final inicio = DateTime(ano, mes);
    final fim = DateTime(ano, mes + 1);
    bool dentro(Timestamp ts) {
      final data = ts.toDate();
      return !data.isBefore(inicio) && data.isBefore(fim);
    }

    final batch = _firestore.batch();
    final dias = await _col(uid, 'dias').where('mesFechadoId', isEqualTo: null).get();
    for (final d in dias.docs) {
      if (dentro(d.data()['data'] as Timestamp)) {
        batch.update(d.reference, {'mesFechadoId': mesFechadoId});
      }
    }
    final gastos = await _col(uid, 'gastos').where('mesFechadoId', isEqualTo: null).get();
    for (final g in gastos.docs) {
      if (dentro(g.data()['data'] as Timestamp)) {
        batch.update(g.reference, {'mesFechadoId': mesFechadoId});
      }
    }
    await batch.commit();
  }

  /// Lista todos os meses já fechados, com os dias e gastos de cada um.
  static Future<List<MesFechado>> getMesesFechados() async {
    final uid = _uid();
    final snap = await _col(uid, 'mesesFechados').get();
    final result = <MesFechado>[];
    for (final d in snap.docs) {
      final r = d.data();
      final id = r['id'] as int;
      result.add(MesFechado(
        dbId: id,
        mes: r['mes'] as int,
        ano: r['ano'] as int,
        dias: await getDias(mesFechadoId: id),
        gastos: await getGastos(mesFechadoId: id),
      ));
    }
    result.sort((a, b) => (b.dbId ?? 0).compareTo(a.dbId ?? 0));
    return result;
  }

  /// Apaga um mês fechado inteiro (dias e gastos que pertenciam a ele).
  static Future<void> deletarMesFechado(int id) async {
    final uid = _uid();
    final batch = _firestore.batch();
    final dias = await _col(uid, 'dias').where('mesFechadoId', isEqualTo: id).get();
    for (final d in dias.docs) {
      batch.delete(d.reference);
    }
    final gastos = await _col(uid, 'gastos').where('mesFechadoId', isEqualTo: id).get();
    for (final g in gastos.docs) {
      batch.delete(g.reference);
    }
    batch.delete(_col(uid, 'mesesFechados').doc(id.toString()));
    await batch.commit();
  }

  // ── Helpers de serialização ─────────────────────────────────────────────

  static Map<String, dynamic> _saidaParaMapa(Saida s) => {
        'hora': Timestamp.fromDate(s.hora),
        'paga': s.paga,
        'taxa': s.taxa,
        'gorjeta': s.gorjeta,
        'comandas': s.comandas,
      };

  static Saida _saidaDaMapa(Map<String, dynamic> m) => Saida(
        dbId: m['id'] as int?,
        hora: (m['hora'] as Timestamp).toDate(),
        paga: m['paga'] as String?,
        taxa: m['taxa'] as String?,
        gorjeta: m['gorjeta'] as String?,
        comandas: m['comandas'] as String?,
      );

  /// Cor associada a cada categoria de gasto (mesmo mapeamento do
  /// database_io.dart — não fica salvo, é recalculado na leitura).
  static Color _corCategoria(String cat) {
    switch (cat) {
      case "Combustível": return Colors.orange;
      case "Alimentação": return Colors.green;
      case "Manutenção": return Colors.red;
      default: return Colors.grey;
    }
  }

  /// Ícone associado a cada categoria de gasto.
  static IconData _iconeCategoria(String cat) {
    switch (cat) {
      case "Combustível": return Icons.local_gas_station;
      case "Alimentação": return Icons.restaurant;
      case "Manutenção": return Icons.build;
      default: return Icons.more_horiz;
    }
  }

  // ── Sessão salva ─────────────────────────────────────────────────────────

  /// Salva o nome da sessão.
  static Future<void> salvarSessao(String nome) async =>
      _salvarNaConta(_uid(), {'sessaoNome': nome});

  /// Salva o email da sessão.
  static Future<void> salvarSessaoEmail(String email) async =>
      _salvarNaConta(_uid(), {'sessaoEmail': email});

  /// Nome salvo da sessão atual (null também se ninguém tiver restaurado
  /// login nenhum no Firebase Auth ainda — não é erro, só quer dizer que
  /// não tem sessão salva pra restaurar).
  static Future<String?> getSessao() async {
    if (ChatService.meuUid == null) return null;
    return (await _dadosConta(_uid()))['sessaoNome'] as String?;
  }

  /// Email salvo da sessão atual.
  static Future<String?> getSessaoEmail() async {
    if (ChatService.meuUid == null) return null;
    return (await _dadosConta(_uid()))['sessaoEmail'] as String?;
  }

  /// Apaga a sessão salva.
  static Future<void> limparSessao() async =>
      _salvarNaConta(_uid(), {'sessaoNome': null, 'sessaoEmail': null});

  // ── Subscrição por código ─────────────────────────────────────────────────

  /// Data de vencimento da assinatura por código.
  static Future<DateTime?> getSubscricaoExpira() async {
    final ts = (await _dadosConta(_uid()))['subscricaoExpira'] as Timestamp?;
    return ts?.toDate();
  }

  /// Salva a nova data de vencimento.
  static Future<void> salvarSubscricaoExpira(DateTime expira) async =>
      _salvarNaConta(_uid(), {'subscricaoExpira': Timestamp.fromDate(expira)});

  /// Verifica se um código já foi usado.
  static Future<bool> isCodigoJaUsado(String codigo) async {
    final codigos = (await _dadosConta(_uid()))['codigosUsados'] as Map<String, dynamic>?;
    return codigos?[codigo] == true;
  }

  /// Marca um código como usado.
  static Future<void> marcarCodigoUsado(String codigo) async =>
      _salvarNaConta(_uid(), {'codigosUsados.$codigo': true});

  // ── Perfil (telefone, CPF, foto, veículo) ────────────────────────────────

  /// Telefone salvo no perfil.
  static Future<String?> getTelefone() async => (await _dadosConta(_uid()))['telefone'] as String?;

  /// Salva o telefone do perfil.
  static Future<void> salvarTelefone(String telefone) async =>
      _salvarNaConta(_uid(), {'telefone': telefone});

  /// CPF salvo no perfil.
  static Future<String?> getCpf() async => (await _dadosConta(_uid()))['cpf'] as String?;

  /// Salva o CPF do perfil.
  static Future<void> salvarCpf(String cpf) async => _salvarNaConta(_uid(), {'cpf': cpf});

  /// Foto de perfil em base64.
  static Future<String?> getFotoPerfil() async => (await _dadosConta(_uid()))['fotoPerfil'] as String?;

  /// Salva a foto de perfil (já em base64, redimensionada pequena).
  static Future<void> salvarFotoPerfil(String base64) async =>
      _salvarNaConta(_uid(), {'fotoPerfil': base64});

  /// Dados do veículo (descricao, cor, ano, placa, ativo).
  static Future<Map<String, dynamic>?> getVeiculo() async {
    final v = (await _dadosConta(_uid()))['veiculo'];
    return v == null ? null : Map<String, dynamic>.from(v as Map);
  }

  /// Salva os dados do veículo.
  static Future<void> salvarVeiculo(Map<String, dynamic> veiculo) async =>
      _salvarNaConta(_uid(), {'veiculo': veiculo});

  // ── Assinatura / Trial ────────────────────────────────────────────────────

  /// Marca o início do teste grátis, só na primeira vez.
  static Future<void> registrarPrimeiroAcesso() async {
    final uid = _uid();
    final atual = (await _dadosConta(uid))['trialInicio'];
    if (atual == null) {
      await _salvarNaConta(uid, {'trialInicio': Timestamp.fromDate(DateTime.now())});
    }
  }

  /// Data em que o teste grátis começou.
  static Future<DateTime?> getTrialInicio() async {
    final ts = (await _dadosConta(_uid()))['trialInicio'] as Timestamp?;
    return ts?.toDate();
  }

  /// Verifica se assinou de verdade.
  static Future<bool> isAssinado() async => (await _dadosConta(_uid()))['assinado'] == true;

  /// Marca que assinou.
  static Future<void> salvarAssinatura() async => _salvarNaConta(_uid(), {'assinado': true});

  // ── KM rodados ────────────────────────────────────────────────────────────

  /// KM acumulado desde o último "Zerar o dia".
  static Future<double> getKmTotal() async =>
      ((await _dadosConta(_uid()))['kmTotal'] as num?)?.toDouble() ?? 0;

  /// Soma mais KM ao total.
  static Future<void> adicionarKm(double km) async {
    final uid = _uid();
    final atual = ((await _dadosConta(uid))['kmTotal'] as num?)?.toDouble() ?? 0;
    await _salvarNaConta(uid, {'kmTotal': atual + km});
  }

  /// Zera o KM do dia.
  static Future<void> zerarKmTotal() async => _salvarNaConta(_uid(), {'kmTotal': 0});

  // ── KM manual (botão Iniciar/Finalizar) ─────────────────────────────────────

  /// KM inicial digitado ao apertar "Iniciar contagem".
  static Future<double?> getKmManualInicio() async =>
      ((await _dadosConta(_uid()))['kmManualInicio'] as num?)?.toDouble();

  /// Salva o KM inicial digitado ao começar a contagem manual.
  static Future<void> salvarKmManualInicio(double kmInicial) async =>
      _salvarNaConta(_uid(), {'kmManualInicio': kmInicial});

  /// Apaga o KM inicial pendente.
  static Future<void> zerarKmManualInicio() async =>
      _salvarNaConta(_uid(), {'kmManualInicio': null});

  // ── Tempo online ──────────────────────────────────────────────────────────

  /// Horário em que o "Tempo online" começou a contar hoje.
  static Future<DateTime?> getOnlineInicio() async {
    final ts = (await _dadosConta(_uid()))['onlineInicio'] as Timestamp?;
    return ts?.toDate();
  }

  /// Salva o horário de início do "Tempo online".
  static Future<void> salvarOnlineInicio(DateTime inicio) async =>
      _salvarNaConta(_uid(), {'onlineInicio': Timestamp.fromDate(inicio)});

  /// Para o relógio do "Tempo online".
  static Future<void> zerarOnlineInicio() async =>
      _salvarNaConta(_uid(), {'onlineInicio': null});
}
