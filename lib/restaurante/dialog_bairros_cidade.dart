// Diálogo "Adicionar vários bairros" do painel do restaurante (Fase
// 13.2): escolhe estado + cidade (IBGE), busca os bairros conhecidos no
// OpenStreetMap, marca quais quer e um valor pra todos de uma vez — com
// opção de adicionar manualmente o que o OpenStreetMap não souber.
import 'package:flutter/material.dart';
import 'geo_api.dart';
import 'restaurante_service.dart';

/// Mostra o diálogo; devolve `true` se salvou pelo menos um bairro (pra
/// quem chamou saber se precisa recarregar a lista).
Future<bool> mostrarDialogAdicionarBairrosPorCidade(
  BuildContext context,
  String restauranteUid,
) async {
  final resultado = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogBairrosCidade(restauranteUid: restauranteUid),
  );
  return resultado ?? false;
}

class _DialogBairrosCidade extends StatefulWidget {
  final String restauranteUid;
  const _DialogBairrosCidade({required this.restauranteUid});

  @override
  State<_DialogBairrosCidade> createState() => _DialogBairrosCidadeState();
}

class _DialogBairrosCidadeState extends State<_DialogBairrosCidade> {
  List<Estado> _estados = [];
  List<String> _municipios = [];
  String? _ufSelecionada;
  String? _cidadeSelecionada;

  bool _carregandoEstados = true;
  bool _carregandoMunicipios = false;
  bool _buscandoBairros = false;
  bool _jaBuscou = false;
  bool _erroNaBusca = false;
  bool _salvando = false;

  List<String> _bairrosEncontrados = [];
  final Set<String> _bairrosMarcados = {};
  final _taxaController = TextEditingController(text: '5,00');
  final _bairroManualController = TextEditingController();
  final _filtroController = TextEditingController();
  String _filtro = '';
  TextEditingController? _cidadeFieldController;

  List<String> get _bairrosFiltrados => _filtro.isEmpty
      ? _bairrosEncontrados
      : _bairrosEncontrados
            .where((b) => b.toLowerCase().contains(_filtro.toLowerCase()))
            .toList();

  @override
  void initState() {
    super.initState();
    _carregarEstados();
  }

  @override
  void dispose() {
    _taxaController.dispose();
    _bairroManualController.dispose();
    _filtroController.dispose();
    super.dispose();
  }

  Future<void> _carregarEstados() async {
    final estados = await GeoApi.listarEstados();
    if (!mounted) return;
    setState(() {
      _estados = estados;
      _carregandoEstados = false;
    });
  }

  Future<void> _selecionarEstado(Estado estado) async {
    _filtroController.clear();
    _cidadeFieldController?.clear();
    setState(() {
      _ufSelecionada = estado.sigla;
      _cidadeSelecionada = null;
      _municipios = [];
      _bairrosEncontrados = [];
      _bairrosMarcados.clear();
      _filtro = '';
      _jaBuscou = false;
      _carregandoMunicipios = true;
    });
    final municipios = await GeoApi.listarMunicipios(estado.sigla);
    if (!mounted) return;
    setState(() {
      _municipios = municipios;
      _carregandoMunicipios = false;
    });
  }

  Future<void> _buscarBairros() async {
    final cidade = _cidadeSelecionada;
    if (cidade == null) return;
    setState(() {
      _buscandoBairros = true;
      _jaBuscou = false;
      _erroNaBusca = false;
    });
    final resultado = await GeoApi.buscarBairros(cidade);
    if (!mounted) return;
    setState(() {
      _bairrosEncontrados = resultado.bairros;
      _bairrosMarcados
        ..clear()
        ..addAll(resultado.bairros);
      _buscandoBairros = false;
      _erroNaBusca = resultado.erro;
      _jaBuscou = true;
    });
  }

  void _adicionarBairroManual() {
    final nome = _bairroManualController.text.trim();
    if (nome.isEmpty) return;
    setState(() {
      if (!_bairrosEncontrados.contains(nome)) _bairrosEncontrados.add(nome);
      _bairrosMarcados.add(nome);
      _bairroManualController.clear();
    });
  }

  Future<void> _salvar() async {
    final taxa =
        double.tryParse(_taxaController.text.trim().replaceAll(',', '.')) ?? 0;
    if (_bairrosMarcados.isEmpty) return;

    setState(() => _salvando = true);
    await Future.wait(
      _bairrosMarcados.map(
        (nome) => RestauranteService.salvarBairro(
          widget.restauranteUid,
          nome: nome,
          taxa: taxa,
        ),
      ),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Adicionar vários bairros'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Escolhe a cidade e eu busco os bairros conhecidos pra você marcar de uma vez.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 14),
                _campoBuscaEstado(),
                const SizedBox(height: 12),
                _campoBuscaCidade(),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.blue),
                    ),
                    onPressed: (_cidadeSelecionada == null || _buscandoBairros)
                        ? null
                        : _buscarBairros,
                    icon: _buscandoBairros
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              color: Colors.blue,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.search,
                            color: Colors.blue,
                            size: 18,
                          ),
                    label: const Text(
                      'Buscar bairros dessa cidade',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                ),
                if (_jaBuscou) ...[
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 480) {
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: _colunaLista()),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: _painelAcoes()),
                            ],
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _colunaLista(),
                          const SizedBox(height: 16),
                          _painelAcoes(),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context, false),
          child: const Text('Fechar', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  Widget _colunaLista() {
    if (_bairrosEncontrados.isEmpty && _erroNaBusca) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'O servidor do OpenStreetMap não respondeu agora (instável às vezes, é gratuito e público) — tenta de novo, ou adiciona manualmente ao lado.',
            style: TextStyle(color: Colors.red, fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.blue),
            ),
            onPressed: _buscandoBairros ? null : _buscarBairros,
            icon: const Icon(Icons.refresh, color: Colors.blue, size: 16),
            label: const Text(
              'Tentar de novo',
              style: TextStyle(color: Colors.blue, fontSize: 12),
            ),
          ),
        ],
      );
    }
    if (_bairrosEncontrados.isEmpty) {
      return const Text(
        'Não encontrei bairros conhecidos pra essa cidade (comum em cidades menores) — adiciona manualmente ao lado.',
        style: TextStyle(color: Colors.orange, fontSize: 12),
      );
    }

    final todosMarcados = _bairrosMarcados.length == _bairrosEncontrados.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _filtroController,
          onChanged: (v) => setState(() => _filtro = v),
          decoration: InputDecoration(
            hintText: 'Buscar bairro...',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            prefixIcon: const Icon(
              Icons.search,
              color: Colors.white38,
              size: 20,
            ),
            filled: true,
            fillColor: const Color(0xFF1B2435),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: todosMarcados,
          activeColor: Colors.blue,
          title: const Text(
            'Selecionar todos',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          onChanged: (v) => setState(() {
            if (v == true) {
              _bairrosMarcados
                ..clear()
                ..addAll(_bairrosEncontrados);
            } else {
              _bairrosMarcados.clear();
            }
          }),
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _bairrosFiltrados.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nenhum bairro com esse nome.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: _bairrosFiltrados.map((nome) {
                    final marcado = _bairrosMarcados.contains(nome);
                    return CheckboxListTile(
                      dense: true,
                      value: marcado,
                      activeColor: Colors.blue,
                      title: Text(nome, style: const TextStyle(fontSize: 13)),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _bairrosMarcados.add(nome);
                        } else {
                          _bairrosMarcados.remove(nome);
                        }
                      }),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Lista vinda do OpenStreetMap — pode não estar 100% completa.',
          style: TextStyle(color: Colors.white24, fontSize: 11),
        ),
        const SizedBox(height: 14),
        const Text(
          'Bairro que não apareceu na lista?',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _bairroManualController,
                onSubmitted: (_) => _adicionarBairroManual(),
                decoration: InputDecoration(
                  hintText: 'Nome do bairro',
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF1B2435),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _adicionarBairroManual,
              icon: const Icon(Icons.add_circle, color: Colors.blue),
            ),
          ],
        ),
      ],
    );
  }

  Widget _painelAcoes() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2435),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_outlined, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_bairrosMarcados.length} bairros selecionados',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Taxa de entrega',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _taxaController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: 'R\$ ',
              filled: true,
              fillColor: const Color(0xFF0D1117),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Essa taxa será aplicada a todos os bairros selecionados.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (_bairrosMarcados.isEmpty || _salvando)
                  ? null
                  : _salvar,
              icon: _salvando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: const Text(
                'Aplicar taxa aos selecionados',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _salvando ? null : () => Navigator.pop(context, false),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Dá pra ajustar a taxa de um bairro específico depois, editando ele na lista.',
            style: TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _campoBuscaEstado() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Estado',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 6),
        if (_carregandoEstados)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: Colors.blue,
                strokeWidth: 2,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              return Autocomplete<Estado>(
                displayStringForOption: (e) => '${e.nome} (${e.sigla})',
                optionsBuilder: (valor) {
                  if (valor.text.isEmpty) return _estados;
                  final busca = valor.text.toLowerCase();
                  return _estados.where(
                    (e) =>
                        e.nome.toLowerCase().contains(busca) ||
                        e.sigla.toLowerCase().contains(busca),
                  );
                },
                onSelected: _selecionarEstado,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          hintText: 'Buscar estado...',
                          hintStyle: const TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.white38,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1B2435),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                        ),
                      );
                    },
                optionsViewBuilder: (context, onSelected, options) =>
                    _listaOpcoes(
                      maxWidth: constraints.maxWidth,
                      itens: options.toList(),
                      onSelected: onSelected,
                      rotulo: (e) => e.nome,
                      subRotulo: (e) => e.sigla,
                    ),
              );
            },
          ),
      ],
    );
  }

  Widget _campoBuscaCidade() {
    final habilitado = _ufSelecionada != null && !_carregandoMunicipios;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cidade',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 6),
        if (_carregandoMunicipios)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: Colors.blue,
                strokeWidth: 2,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              return Autocomplete<String>(
                optionsBuilder: (valor) {
                  if (!habilitado) return const Iterable<String>.empty();
                  if (valor.text.isEmpty) return _municipios;
                  final busca = valor.text.toLowerCase();
                  return _municipios.where(
                    (m) => m.toLowerCase().contains(busca),
                  );
                },
                onSelected: (v) => setState(() => _cidadeSelecionada = v),
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      _cidadeFieldController = controller;
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: habilitado,
                        decoration: InputDecoration(
                          hintText: _ufSelecionada == null
                              ? 'Escolha o estado primeiro'
                              : 'Buscar cidade...',
                          hintStyle: const TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.white38,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1B2435),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                        ),
                      );
                    },
                optionsViewBuilder: (context, onSelected, options) =>
                    _listaOpcoes(
                      maxWidth: constraints.maxWidth,
                      itens: options.toList(),
                      onSelected: onSelected,
                      rotulo: (m) => m,
                      subRotulo: null,
                    ),
              );
            },
          ),
      ],
    );
  }

  /// Lista de sugestões do Autocomplete, mesmo visual em Estado e Cidade.
  Widget _listaOpcoes<T>({
    required double maxWidth,
    required List<T> itens,
    required void Function(T) onSelected,
    required String Function(T) rotulo,
    required String Function(T)? subRotulo,
  }) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: const Color(0xFF1B2435),
        borderRadius: BorderRadius.circular(12),
        elevation: 4,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 240),
          child: itens.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nada encontrado.',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: itens.length,
                  itemBuilder: (context, index) {
                    final item = itens[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        rotulo(item),
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: subRotulo == null
                          ? null
                          : Text(
                              subRotulo(item),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                      onTap: () => onSelected(item),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
