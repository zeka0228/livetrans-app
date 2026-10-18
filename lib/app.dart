import 'package:flutter/material.dart';

import 'features/connect/connect_screen.dart';
import 'features/mic/mic_screen.dart';

class LiveTransApp extends StatelessWidget {
  const LiveTransApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '실시간 방송 번역기',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [ConnectScreen(), MicScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.lan_outlined), label: '연결'),
          NavigationDestination(icon: Icon(Icons.mic_outlined), label: '마이크'),
        ],
      ),
    );
  }
}
