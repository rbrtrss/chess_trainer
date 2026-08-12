import 'package:chess_trainer/ui/session/session_flow.dart';
import 'package:flutter/material.dart';

/// The application shell.
class ChessTrainerApp extends StatelessWidget {
  const ChessTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Trainer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4E6E58)),
        useMaterial3: true,
      ),
      home: const SessionFlow(),
    );
  }
}
