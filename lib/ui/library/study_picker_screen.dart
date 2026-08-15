/// Choosing one of the player's own Lichess studies (FR-013).
///
/// Needs a login, because private studies are the reason this exists — a public
/// study can be imported by pasting its address without one (FR-011).
library;

import 'package:chess_trainer/ui/library/connection_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the player picked: the study's id and its name.
typedef PickedStudy = ({String id, String name});

class StudyPickerScreen extends ConsumerWidget {
  const StudyPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(lichessConnectionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your Lichess studies')),
      body: SafeArea(
        child: connection.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Message(text: messageForNetworkError(error)),
          data: (connected) {
            if (connected == null) return const _LogInPrompt();
            return const _StudyList();
          },
        ),
      ),
    );
  }
}

class _LogInPrompt extends ConsumerStatefulWidget {
  const _LogInPrompt();

  @override
  ConsumerState<_LogInPrompt> createState() => _LogInPromptState();
}

class _LogInPromptState extends ConsumerState<_LogInPrompt> {
  bool _busy = false;
  String? _failure;

  Future<void> _logIn() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref.read(connectionControllerProvider).logIn();
    } on Object catch (error) {
      if (mounted) setState(() => _failure = messageForNetworkError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('lichess-login-prompt'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Log in to Lichess to see your own studies, including private '
              'ones.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'The app asks only to read your studies. It never posts '
              'anything, and nothing about your sessions is sent anywhere.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('log-in-to-lichess'),
              onPressed: _busy ? null : _logIn,
              child: const Text('Log in to Lichess'),
            ),
            if (_failure != null) ...[
              const SizedBox(height: 16),
              Text(_failure!, key: const Key('login-failure')),
            ],
          ],
        ),
      ),
    );
  }
}

class _StudyList extends ConsumerWidget {
  const _StudyList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studies = ref.watch(myStudiesProvider);

    return studies.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(text: messageForNetworkError(error)),
      data: (all) {
        if (all.isEmpty) {
          return const _Message(
            text: 'This account has no studies to import.',
          );
        }
        return ListView.builder(
          key: const Key('study-list'),
          itemCount: all.length,
          itemBuilder: (context, index) {
            final study = all[index];
            return ListTile(
              key: Key('study-${study.id}'),
              title: Text(study.name),
              subtitle: Text('Updated ${_when(study.updatedAt)}'),
              onTap: () => Navigator.of(context)
                  .pop<PickedStudy>((id: study.id, name: study.name)),
            );
          },
        );
      },
    );
  }

  String _when(DateTime moment) {
    final local = moment.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text,
              key: const Key('study-picker-message'),
              textAlign: TextAlign.center),
        ),
      );
}
