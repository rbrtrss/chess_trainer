import 'package:chess_trainer/ui/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a session is chosen and started.
///
/// The only choice offered is how many positions to work through. There is
/// nothing to pick between — no difficulty, no theme — because choosing by
/// theme would be choosing by answer.
class SessionSetupScreen extends ConsumerStatefulWidget {
  const SessionSetupScreen({super.key});

  @override
  ConsumerState<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends ConsumerState<SessionSetupScreen> {
  int _length = 3;

  @override
  Widget build(BuildContext context) {
    final positions = ref.watch(bundledPositionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chess Trainer')),
      body: SafeArea(
        child: positions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load the bundled positions.\n\n$error'),
            ),
          ),
          data: (available) {
            final maximum = available.length;
            final length = _length > maximum ? maximum : _length;

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'You will see each position once, with only the side to '
                    'move given. Nothing is revealed until the whole session '
                    'is over.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Text('Positions: $length',
                      key: const Key('session-length'),
                      textAlign: TextAlign.center),
                  Slider(
                    key: const Key('session-length-slider'),
                    value: length.toDouble(),
                    min: 1,
                    max: maximum.toDouble(),
                    divisions: maximum > 1 ? maximum - 1 : null,
                    label: '$length',
                    onChanged: (value) =>
                        setState(() => _length = value.round()),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    key: const Key('start-session'),
                    onPressed: () => ref
                        .read(sessionControllerProvider.notifier)
                        .start(available, length: length),
                    child: const Text('Start'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
