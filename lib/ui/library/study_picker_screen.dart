/// Choosing one of the player's own Lichess studies (003 FR-013).
///
/// Needs a connected account, because private studies are the reason this
/// exists — a public study can be imported by pasting its address without one
/// (003 FR-011).
///
/// **It does not offer to log in** (004 FR-015). Until feature 004 this screen
/// was where the login lived, which meant the only way to find out whether you
/// were connected was to start an import you might not want to make. The
/// account moved to the home screen; this screen assumes it.
library;

import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/lichess/account.dart';
import 'package:chess_trainer/ui/library/connection_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the player picked: the study's id and its name.
typedef PickedStudy = ({String id, String name});

class StudyPickerScreen extends ConsumerWidget {
  const StudyPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(lichessAccountProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your Lichess studies')),
      body: SafeArea(
        child: account.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Message(text: messageForNetworkError(error)),
          data: (connected) => switch (connected) {
            AccountConnected() => const _StudyList(),
            // No login button, by design (FR-015, 004 research D7): import does
            // not establish the account, it assumes one. This state should be
            // unreachable — the import screen checks before navigating — and it
            // exists because a login can expire between opening this screen and
            // reading it, and a screen that assumes it can only be reached in
            // one state eventually gets reached in another.
            AccountExpired() =>
              _Message(text: messageForNetworkError(LoginExpiredError())),
            AccountDisconnected() =>
              const _Message(text: studiesNeedAccountMessage),
          },
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
