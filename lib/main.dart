// Ponto de entrada do app. Só prepara o Firebase e a assinatura antes de
// abrir a tela principal — todo o resto do app foi dividido em arquivos
// menores, um por tela (veja app_shell.dart, login_page.dart, main_shell.dart
// e as outras abas em home_tab.dart, financeiro_tab.dart, resumo_tab.dart,
// perfil_tab.dart, meses_fechados_page.dart).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'assinatura.dart';
import 'app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Na Web o cache offline do Firestore vem desligado por padrão (diferente
  // do Android/iOS). Ligando aqui, os dados já lidos uma vez (saídas, dias,
  // gastos...) ficam salvos no IndexedDB do navegador — se uma leitura
  // falhar por causa de rede ou do token do Auth ainda não ter propagado
  // logo após um refresh, o app tem o cache local pra cair de volta em vez
  // de mostrar tudo vazio.
  if (kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  }
  await AssinaturaService.init();
  AssinaturaService.iniciarEscutaGlobal();
  runApp(const MotocaPremiumApp());
}
