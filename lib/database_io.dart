// Acesso ao banco de dados local (SQLite) — usado no Android/iOS/desktop.
// No navegador (web) essa versão não é usada; entra o database_stub.dart no
// lugar (que guarda tudo só na memória, sem gravar em disco de verdade).
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'models.dart';

class DB {
  static Database? _db;

  /// Devolve a conexão com o banco, abrindo ela na primeira vez que for
  /// pedida e reaproveitando depois.
  static Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  /// Abre (ou cria, se ainda não existir) o arquivo do banco de dados.
  static Future<Database> _init() async {
    final caminho = join(await getDatabasesPath(), 'motoca_premium.db');
    return openDatabase(caminho, version: 4, onCreate: _criar, onUpgrade: _migrar);
  }

  /// Roda quando o app é atualizado e a versão do banco mudou — vai
  /// aplicando as alterações de estrutura (novas colunas/tabelas) uma por
  /// uma, na ordem, sem apagar os dados que já existiam.
  static Future<void> _migrar(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS config (
          chave TEXT PRIMARY KEY,
          valor TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE usuarios ADD COLUMN subscricao_ativa INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE usuarios ADD COLUMN data_cadastro TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE dias ADD COLUMN km_rodado REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE dias ADD COLUMN tempo_online_min INTEGER NOT NULL DEFAULT 0');
    }
  }

  /// Cria todas as tabelas do zero, usado só na primeira vez que o app
  /// abre num aparelho novo (sem banco de dados ainda).
  static Future<void> _criar(Database db, int version) async {
    await db.execute('''
      CREATE TABLE usuarios (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        nome              TEXT NOT NULL,
        email             TEXT UNIQUE NOT NULL,
        senha             TEXT NOT NULL,
        subscricao_ativa  INTEGER NOT NULL DEFAULT 0,
        data_cadastro     TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE saidas_ativas (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        hora     TEXT NOT NULL,
        paga     TEXT,
        taxa     TEXT,
        gorjeta  TEXT,
        comandas TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE meses_fechados (
        id  INTEGER PRIMARY KEY AUTOINCREMENT,
        mes INTEGER NOT NULL,
        ano INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE dias (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        data              TEXT NOT NULL,
        mes_fechado_id    INTEGER,
        km_rodado         REAL NOT NULL DEFAULT 0,
        tempo_online_min  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE saidas_historico (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        dia_id   INTEGER NOT NULL,
        hora     TEXT NOT NULL,
        paga     TEXT,
        taxa     TEXT,
        gorjeta  TEXT,
        comandas TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE config (
        chave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE gastos (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        descricao       TEXT NOT NULL,
        valor           REAL NOT NULL,
        data            TEXT NOT NULL,
        categoria       TEXT NOT NULL,
        mes_fechado_id  INTEGER
      )
    ''');
  }

  // ── Usuários ──────────────────────────────────────────────────────────────

  /// Cria uma conta local nova. Retorna false se o email já estiver
  /// cadastrado (a coluna email é única no banco).
  static Future<bool> registrarUsuario(String nome, String email, String senha) async {
    final db = await database;
    try {
      await db.insert('usuarios', {
        'nome': nome,
        'email': email,
        'senha': senha,
        'subscricao_ativa': 0,
        'data_cadastro': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Confere se email/senha batem com uma conta salva localmente; se sim,
  /// devolve o nome da pessoa, senão devolve null.
  static Future<String?> loginUsuario(String email, String senha) async {
    final db = await database;
    final rows = await db.query(
      'usuarios',
      columns: ['nome'],
      where: 'email = ? AND senha = ?',
      whereArgs: [email, senha],
    );
    return rows.isEmpty ? null : rows.first['nome'] as String;
  }

  /// Verifica se esse email tem a assinatura marcada como ativa
  /// localmente (liberada pelo admin antigo, por aparelho).
  static Future<bool> isSubscricaoAtivaParaEmail(String email) async {
    final db = await database;
    final rows = await db.query('usuarios',
        columns: ['subscricao_ativa'], where: 'email = ?', whereArgs: [email]);
    if (rows.isEmpty) return false;
    return (rows.first['subscricao_ativa'] as int) == 1;
  }

  // ── Admin ─────────────────────────────────────────────────────────────────
  // (O painel admin hoje usa a lista global do Firebase — ver
  // ChatService.getTodosUsuariosAdmin — mas esses métodos locais continuam
  // aqui como registro de cadastro no próprio aparelho.)

  /// Lista os usuários cadastrados localmente neste aparelho.
  static Future<List<Map<String, dynamic>>> getUsuariosAdmin() async {
    final db = await database;
    return db.query('usuarios', columns: ['id', 'nome', 'email', 'subscricao_ativa', 'data_cadastro'], orderBy: 'id DESC');
  }

  /// Liga/desliga a assinatura de um usuário no banco local.
  static Future<void> setSubscricaoUsuario(int id, bool ativa) async {
    final db = await database;
    await db.update('usuarios', {'subscricao_ativa': ativa ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  // ── Saídas ativas (dia atual) ─────────────────────────────────────────────

  /// Salva uma saída nova no dia em aberto (ainda não zerado).
  static Future<int> inserirSaidaAtiva(Saida s) async {
    final db = await database;
    return db.insert('saidas_ativas', {
      'hora':     s.hora.toIso8601String(),
      'paga':     s.paga,
      'taxa':     s.taxa,
      'gorjeta':  s.gorjeta,
      'comandas': s.comandas,
    });
  }

  /// Remove uma saída do dia em aberto.
  static Future<void> deletarSaidaAtiva(int id) async {
    final db = await database;
    await db.delete('saidas_ativas', where: 'id = ?', whereArgs: [id]);
  }

  /// Corrige a comanda e/ou a taxa de uma saída já registrada hoje (caso o
  /// motoboy erre ao digitar).
  static Future<void> atualizarSaidaAtiva(int id, {String? comanda, String? taxa}) async {
    final db = await database;
    await db.update('saidas_ativas', {'comandas': comanda, 'taxa': taxa}, where: 'id = ?', whereArgs: [id]);
  }

  /// Lista todas as saídas do dia em aberto (mais recente primeiro).
  static Future<List<Saida>> getSaidasAtivas() async {
    final db = await database;
    final rows = await db.query('saidas_ativas', orderBy: 'id DESC');
    return rows.map((r) => Saida(
      dbId:     r['id'] as int,
      hora:     DateTime.parse(r['hora'] as String),
      paga:     r['paga'] as String?,
      taxa:     r['taxa'] as String?,
      gorjeta:  r['gorjeta'] as String?,
      comandas: r['comandas'] as String?,
    )).toList();
  }

  /// Apaga todas as saídas do dia em aberto (usado ao "Zerar o dia", depois
  /// de já ter salvo elas no histórico).
  static Future<void> limparSaidasAtivas() async {
    final db = await database;
    await db.delete('saidas_ativas');
  }

  // ── Dias ─────────────────────────────────────────────────────────────────

  /// Salva um dia inteiro (com todas as saídas dele) no histórico.
  static Future<void> salvarDia(DiaRegistro dia, {int? mesFechadoId}) async {
    final db = await database;
    final diaId = await db.insert('dias', {
      'data':             dia.data.toIso8601String(),
      'mes_fechado_id':   mesFechadoId,
      'km_rodado':        dia.kmRodado,
      'tempo_online_min': dia.tempoOnlineMin,
    });
    for (final s in dia.saidas) {
      await db.insert('saidas_historico', {
        'dia_id':   diaId,
        'hora':     s.hora.toIso8601String(),
        'paga':     s.paga,
        'taxa':     s.taxa,
        'gorjeta':  s.gorjeta,
        'comandas': s.comandas,
      });
    }
  }

  /// Lista os dias salvos. Sem [mesFechadoId], traz só os dias do mês
  /// ainda em aberto; com ele, traz os dias daquele mês já fechado.
  static Future<List<DiaRegistro>> getDias({int? mesFechadoId}) async {
    final db = await database;
    final rows = mesFechadoId == null
        ? await db.query('dias', where: 'mes_fechado_id IS NULL', orderBy: 'id DESC')
        : await db.query('dias', where: 'mes_fechado_id = ?', whereArgs: [mesFechadoId], orderBy: 'id DESC');

    final List<DiaRegistro> result = [];
    for (final r in rows) {
      final diaId = r['id'] as int;
      final sRows = await db.query(
        'saidas_historico',
        where: 'dia_id = ?',
        whereArgs: [diaId],
        orderBy: 'id DESC',
      );
      result.add(DiaRegistro(
        dbId: diaId,
        data: DateTime.parse(r['data'] as String),
        kmRodado: (r['km_rodado'] as num?)?.toDouble() ?? 0,
        tempoOnlineMin: (r['tempo_online_min'] as int?) ?? 0,
        saidas: sRows.map((s) => Saida(
          hora:     DateTime.parse(s['hora'] as String),
          paga:     s['paga'] as String?,
          taxa:     s['taxa'] as String?,
          gorjeta:  s['gorjeta'] as String?,
          comandas: s['comandas'] as String?,
        )).toList(),
      ));
    }
    return result;
  }

  /// Remove um dia do histórico (e as saídas que pertenciam a ele).
  static Future<void> deletarDia(int id) async {
    final db = await database;
    await db.delete('saidas_historico', where: 'dia_id = ?', whereArgs: [id]);
    await db.delete('dias', where: 'id = ?', whereArgs: [id]);
  }

  // ── Gastos ────────────────────────────────────────────────────────────────

  /// Salva um gasto novo.
  static Future<void> inserirGasto(Gasto g, {int? mesFechadoId}) async {
    final db = await database;
    await db.insert('gastos', {
      'descricao':      g.descricao,
      'valor':          g.valor,
      'data':           g.data.toIso8601String(),
      'categoria':      g.categoria,
      'mes_fechado_id': mesFechadoId,
    });
  }

  /// Lista os gastos. Sem [mesFechadoId], traz só os gastos do mês ainda
  /// em aberto; com ele, traz os gastos daquele mês já fechado.
  static Future<List<Gasto>> getGastos({int? mesFechadoId}) async {
    final db = await database;
    final rows = mesFechadoId == null
        ? await db.query('gastos', where: 'mes_fechado_id IS NULL', orderBy: 'id DESC')
        : await db.query('gastos', where: 'mes_fechado_id = ?', whereArgs: [mesFechadoId], orderBy: 'id DESC');
    return rows.map((r) {
      final cat = r['categoria'] as String;
      return Gasto(
        dbId:      r['id'] as int,
        descricao: r['descricao'] as String,
        valor:     (r['valor'] as num).toDouble(),
        data:      DateTime.parse(r['data'] as String),
        categoria: cat,
        cor:       _corCategoria(cat),
        icone:     _iconeCategoria(cat),
      );
    }).toList();
  }

  /// Remove um gasto.
  static Future<void> deletarGasto(int id) async {
    final db = await database;
    await db.delete('gastos', where: 'id = ?', whereArgs: [id]);
  }

  // ── Meses fechados ────────────────────────────────────────────────────────

  /// Cria o registro de um mês fechado (ainda sem os dias/gastos
  /// vinculados — isso é feito por [vincularAoMes]/[vincularAoMesPorMesAno]).
  static Future<int> inserirMesFechado(int mes, int ano) async {
    final db = await database;
    return db.insert('meses_fechados', {'mes': mes, 'ano': ano});
  }

  /// Vincula todos os dias/gastos que ainda estavam em aberto ao mês recém
  /// fechado (usado no fechamento manual do mês atual).
  static Future<void> vincularAoMes(int mesFechadoId) async {
    final db = await database;
    await db.update('dias',   {'mes_fechado_id': mesFechadoId}, where: 'mes_fechado_id IS NULL');
    await db.update('gastos', {'mes_fechado_id': mesFechadoId}, where: 'mes_fechado_id IS NULL');
  }

  /// Vincula ao mês fechado só os dias/gastos que caem dentro daquele
  /// mês/ano específico (usado no fechamento automático de meses antigos
  /// esquecidos em aberto).
  static Future<void> vincularAoMesPorMesAno(int mesFechadoId, int mes, int ano) async {
    final db = await database;
    final inicio = DateTime(ano, mes).toIso8601String();
    final fim = DateTime(ano, mes + 1).toIso8601String();
    await db.update('dias', {'mes_fechado_id': mesFechadoId},
        where: "mes_fechado_id IS NULL AND data >= ? AND data < ?",
        whereArgs: [inicio, fim]);
    await db.update('gastos', {'mes_fechado_id': mesFechadoId},
        where: "mes_fechado_id IS NULL AND data >= ? AND data < ?",
        whereArgs: [inicio, fim]);
  }

  /// Lista todos os meses já fechados, com os dias e gastos de cada um.
  static Future<List<MesFechado>> getMesesFechados() async {
    final db = await database;
    final rows = await db.query('meses_fechados', orderBy: 'id DESC');
    final List<MesFechado> result = [];
    for (final r in rows) {
      final id = r['id'] as int;
      result.add(MesFechado(
        dbId:   id,
        mes:    r['mes'] as int,
        ano:    r['ano'] as int,
        dias:   await getDias(mesFechadoId: id),
        gastos: await getGastos(mesFechadoId: id),
      ));
    }
    return result;
  }

  /// Apaga um mês fechado inteiro (dias, saídas daqueles dias e gastos).
  static Future<void> deletarMesFechado(int id) async {
    final db = await database;
    final dias = await db.query('dias', columns: ['id'], where: 'mes_fechado_id = ?', whereArgs: [id]);
    for (final d in dias) {
      await db.delete('saidas_historico', where: 'dia_id = ?', whereArgs: [d['id']]);
    }
    await db.delete('dias',           where: 'mes_fechado_id = ?', whereArgs: [id]);
    await db.delete('gastos',         where: 'mes_fechado_id = ?', whereArgs: [id]);
    await db.delete('meses_fechados', where: 'id = ?',             whereArgs: [id]);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Cor associada a cada categoria de gasto.
  static Color _corCategoria(String cat) {
    switch (cat) {
      case "Combustível": return Colors.orange;
      case "Alimentação": return Colors.green;
      case "Manutenção":  return Colors.red;
      default:            return Colors.grey;
    }
  }

  /// Ícone associado a cada categoria de gasto.
  static IconData _iconeCategoria(String cat) {
    switch (cat) {
      case "Combustível": return Icons.local_gas_station;
      case "Alimentação": return Icons.restaurant;
      case "Manutenção":  return Icons.build;
      default:            return Icons.more_horiz;
    }
  }

  // ── Sessão salva ─────────────────────────────────────────────────────────
  // (Pra manter o usuário logado entre uma abertura e outra do app, quando
  // "Salvar login" está marcado.)

  /// Salva o nome de quem está logado, pra restaurar a sessão depois.
  static Future<void> salvarSessao(String nome) async {
    final db = await database;
    await db.insert('config', {'chave': 'sessao_nome', 'valor': nome},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Salva o email de quem está logado, pra restaurar a sessão depois.
  static Future<void> salvarSessaoEmail(String email) async {
    final db = await database;
    await db.insert('config', {'chave': 'sessao_email', 'valor': email},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Nome salvo da sessão (null se ninguém tiver marcado "Salvar login").
  static Future<String?> getSessao() async {
    final db = await database;
    final rows = await db.query('config', where: 'chave = ?', whereArgs: ['sessao_nome']);
    return rows.isEmpty ? null : rows.first['valor'] as String;
  }

  /// Email salvo da sessão.
  static Future<String?> getSessaoEmail() async {
    final db = await database;
    final rows = await db.query('config', where: 'chave = ?', whereArgs: ['sessao_email']);
    return rows.isEmpty ? null : rows.first['valor'] as String;
  }

  /// Apaga a sessão salva (usado ao clicar em "Sair do sistema").
  static Future<void> limparSessao() async {
    final db = await database;
    await db.delete('config', where: "chave IN ('sessao_nome','sessao_email')");
  }

  // ── Subscrição por código ─────────────────────────────────────────────────

  /// Data em que a assinatura ativada por código vence (null se nunca
  /// tiver ativado um código).
  static Future<DateTime?> getSubscricaoExpira() async {
    final db = await database;
    final rows = await db.query('config', where: 'chave = ?', whereArgs: ['subscricao_expira']);
    if (rows.isEmpty) return null;
    try { return DateTime.parse(rows.first['valor'] as String); } catch (_) { return null; }
  }

  /// Salva a nova data de vencimento da assinatura por código.
  static Future<void> salvarSubscricaoExpira(DateTime expira) async {
    final db = await database;
    await db.insert('config', {'chave': 'subscricao_expira', 'valor': expira.toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Verifica se um código de acesso já foi usado antes (pra não deixar
  /// usar o mesmo código duas vezes).
  static Future<bool> isCodigoJaUsado(String codigo) async {
    final db = await database;
    final chave = 'cod_${codigo.replaceAll('-', '')}';
    final rows = await db.query('config', where: 'chave = ?', whereArgs: [chave]);
    return rows.isNotEmpty;
  }

  /// Marca um código de acesso como já usado.
  static Future<void> marcarCodigoUsado(String codigo) async {
    final db = await database;
    final chave = 'cod_${codigo.replaceAll('-', '')}';
    await db.insert('config', {'chave': chave, 'valor': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Assinatura / Trial ────────────────────────────────────────────────────

  /// Marca quando o usuário abriu o app pela primeira vez, dando início à
  /// contagem do teste grátis (só grava uma vez).
  static Future<void> registrarPrimeiroAcesso() async {
    final db = await database;
    final existing = await db.query('config', where: 'chave = ?', whereArgs: ['trial_inicio']);
    if (existing.isEmpty) {
      await db.insert('config', {
        'chave': 'trial_inicio',
        'valor': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Data em que o teste grátis começou (null se ainda não começou).
  static Future<DateTime?> getTrialInicio() async {
    final db = await database;
    final rows = await db.query('config', where: 'chave = ?', whereArgs: ['trial_inicio']);
    if (rows.isEmpty) return null;
    return DateTime.parse(rows.first['valor'] as String);
  }

  /// Verifica se o usuário assinou de verdade (pela Play Store).
  static Future<bool> isAssinado() async {
    final db = await database;
    final rows = await db.query('config', where: 'chave = ?', whereArgs: ['assinado']);
    return rows.isNotEmpty && rows.first['valor'] == '1';
  }

  /// Marca que o usuário assinou pela Play Store.
  static Future<void> salvarAssinatura() async {
    final db = await database;
    await db.insert(
      'config',
      {'chave': 'assinado', 'valor': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── KM rodados ────────────────────────────────────────────────────────────

  /// KM acumulado desde o último "Zerar o dia".
  static Future<double> getKmTotal() async {
    final db = await database;
    final rows = await db.query('config', where: "chave = 'km_total'");
    if (rows.isEmpty) return 0;
    return double.tryParse(rows.first['valor'] as String) ?? 0;
  }

  /// Soma mais KM ao total do dia (chamado pelo odômetro a cada trecho
  /// percorrido).
  static Future<void> adicionarKm(double km) async {
    final db = await database;
    final atual = await getKmTotal();
    await db.insert('config', {'chave': 'km_total', 'valor': (atual + km).toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Zera o KM do dia (usado ao "Zerar o dia", depois de já ter salvo o
  /// valor no histórico).
  static Future<void> zerarKmTotal() async {
    final db = await database;
    await db.insert('config', {'chave': 'km_total', 'valor': '0'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── KM manual (botão Iniciar/Finalizar) ─────────────────────────────────────

  /// KM inicial digitado ao apertar "Iniciar contagem" — fica salvo
  /// enquanto a contagem manual estiver em andamento (null se nenhuma
  /// contagem estiver aberta).
  static Future<double?> getKmManualInicio() async {
    final db = await database;
    final rows = await db.query('config', where: "chave = 'km_manual_inicio'");
    if (rows.isEmpty) return null;
    return double.tryParse(rows.first['valor'] as String);
  }

  /// Salva o KM inicial digitado ao começar a contagem manual.
  static Future<void> salvarKmManualInicio(double kmInicial) async {
    final db = await database;
    await db.insert('config', {'chave': 'km_manual_inicio', 'valor': kmInicial.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Apaga o KM inicial pendente (usado depois de "Finalizar" ou ao zerar
  /// o dia).
  static Future<void> zerarKmManualInicio() async {
    final db = await database;
    await db.delete('config', where: "chave = 'km_manual_inicio'");
  }

  // ── Tempo online ──────────────────────────────────────────────────────────

  /// Horário em que o "Tempo online" começou a contar hoje (null se ainda
  /// não começou — só liga na primeira saída registrada).
  static Future<DateTime?> getOnlineInicio() async {
    final db = await database;
    final rows = await db.query('config', where: "chave = 'online_inicio'");
    if (rows.isEmpty) return null;
    try {
      return DateTime.parse(rows.first['valor'] as String);
    } catch (_) {
      return null;
    }
  }

  /// Salva o horário em que o "Tempo online" começou a contar.
  static Future<void> salvarOnlineInicio(DateTime inicio) async {
    final db = await database;
    await db.insert('config', {'chave': 'online_inicio', 'valor': inicio.toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Para o relógio do "Tempo online" (usado ao "Zerar o dia" — só volta a
  /// contar na próxima saída registrada).
  static Future<void> zerarOnlineInicio() async {
    final db = await database;
    await db.delete('config', where: "chave = 'online_inicio'");
  }

  // ── Perfil (telefone, CPF, foto, veículo) ────────────────────────────────

  /// Telefone salvo no perfil (null se ainda não preencheu).
  static Future<String?> getTelefone() async {
    final db = await database;
    final rows = await db.query('config', where: "chave = 'telefone'");
    return rows.isEmpty ? null : rows.first['valor'] as String;
  }

  /// Salva o telefone do perfil.
  static Future<void> salvarTelefone(String telefone) async {
    final db = await database;
    await db.insert('config', {'chave': 'telefone', 'valor': telefone},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// CPF salvo no perfil (null se ainda não preencheu).
  static Future<String?> getCpf() async {
    final db = await database;
    final rows = await db.query('config', where: "chave = 'cpf'");
    return rows.isEmpty ? null : rows.first['valor'] as String;
  }

  /// Salva o CPF do perfil.
  static Future<void> salvarCpf(String cpf) async {
    final db = await database;
    await db.insert('config', {'chave': 'cpf', 'valor': cpf},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Foto de perfil em base64 (null se ainda não escolheu nenhuma).
  static Future<String?> getFotoPerfil() async {
    final db = await database;
    final rows = await db.query('config', where: "chave = 'foto_perfil'");
    return rows.isEmpty ? null : rows.first['valor'] as String;
  }

  /// Salva a foto de perfil (já em base64, redimensionada pequena).
  static Future<void> salvarFotoPerfil(String base64) async {
    final db = await database;
    await db.insert('config', {'chave': 'foto_perfil', 'valor': base64},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Dados do veículo (descricao, cor, ano, placa, ativo) — null se ainda
  /// não preencheu nada.
  static Future<Map<String, dynamic>?> getVeiculo() async {
    final db = await database;
    final rows = await db.query('config', where: "chave = 'veiculo'");
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.first['valor'] as String) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Salva os dados do veículo.
  static Future<void> salvarVeiculo(Map<String, dynamic> veiculo) async {
    final db = await database;
    await db.insert('config', {'chave': 'veiculo', 'valor': jsonEncode(veiculo)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
