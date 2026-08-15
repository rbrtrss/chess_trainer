/// The Lichess account, on the screen a session starts from.
///
/// Feature 003 put the login two screens inside import, which made the account
/// read as a property of importing and meant the only way to find out whether
/// you were connected was to start an import you might not want to make. This
/// is where it lives instead: the foot of the home screen, legible without
/// tapping anything (004 FR-001).
///
/// Three rules shape it, and each is easy to break by accident:
///
/// - **It never waits, and never guesses.** The read is local but asynchronous,
///   so there is a window where the answer is not known. That window renders as
///   reserved space — not a spinner, which is a wait, and not "Not connected",
///   which is a guess that flips to a username a frame later (research D5).
/// - **It is the same height in every state**, so the first frame does not
///   reflow when the read lands. That height is 56 and it is a hard budget: see
///   [accountBarHeight] for what was measured, and what had to move out of the
///   bar to fit inside it.
/// - **It must not dominate.** This screen's job is to start a session. The
///   account is a footnote on it, and a player who never connects should be
///   able to use this app for a year without being asked twice (FR-006).
library;

import 'package:chess_trainer/domain/lichess/account.dart';
import 'package:chess_trainer/ui/library/connection_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the app tells the player it is asking for, before it asks.
///
/// Moved verbatim from the log-in prompt this feature deleted. Lichess's own
/// authorization page is the authoritative disclosure — it names the scope,
/// under a client id that is this repository's URL precisely so the player can
/// go and read what they are granting to — and this is the summary shown before
/// they leave the app (FR-007, research D6).
const String lichessPermissionsLine =
    'The app asks only to read your studies. It never posts anything, and '
    'nothing about your sessions is sent anywhere.';

/// The height every state occupies, whatever it has to say (research D5).
///
/// **56, and the number was measured rather than chosen.** The design called
/// for the permissions line to sit in the bar as small print, which needs about
/// 88; at 72 and above the Start button drops below the fold on a 400×900
/// phone that is also showing the offer to resume an unfinished session, and
/// pushing the screen's primary action off the screen to make room for a
/// footnote is the wrong trade. The disclosure moved to the sheet instead
/// (research D6, revised).
const double accountBarHeight = 56;

class AccountBar extends ConsumerStatefulWidget {
  const AccountBar({super.key});

  @override
  ConsumerState<AccountBar> createState() => _AccountBarState();
}

class _AccountBarState extends ConsumerState<AccountBar> {
  /// True while a login or a disconnect is in flight.
  ///
  /// Disables the buttons. Deliberately does not show a progress indicator:
  /// the browser is what the player is looking at during a login, and a spinner
  /// on this screen would be a spinner they never see finish.
  bool _busy = false;

  /// Shows what the login grants, then starts it if the player still wants it.
  ///
  /// The disclosure is here rather than in the bar because the bar has no room
  /// for it (see [accountBarHeight]). It costs a tap, which SC-002 did not
  /// budget for; the alternative was dropping the disclosure or dropping the
  /// Start button off the screen, and this is the least bad of the three.
  Future<void> _offerLogIn() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const Key('connect-lichess-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Connect to Lichess',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text(lichessPermissionsLine),
              const SizedBox(height: 8),
              const Text(
                'Lichess will ask you to approve this on its own page, and '
                'shows the same permissions there.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('confirm-log-in'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Log in to Lichess'),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    await _logIn();
  }

  Future<void> _logIn() async {
    setState(() => _busy = true);
    try {
      await ref.read(connectionControllerProvider).logIn();
      // A null return means the player backed out, which is a normal outcome
      // and is reported as nothing at all (FR-009).
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('account-login-failure'),
            content: Text(messageForNetworkError(error)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logOut() async {
    setState(() => _busy = true);
    try {
      // Imported collections are untouched: they are local content now, not a
      // view onto the account (FR-011).
      await ref.read(connectionControllerProvider).logOut();
    } on Object {
      // Revoking server-side is best-effort and already swallowed; what reaches
      // here is the local credential failing to clear, which leaves the player
      // connected. Without this the exception escapes the button callback as an
      // unhandled async error and the bar goes on saying "Connected" with
      // nothing to explain why the tap did nothing — an app stopping for
      // reasons of its own, which is what every message in this project exists
      // to prevent.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: Key('account-logout-failure'),
            content: Text(disconnectFailedMessage),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(lichessAccountProvider);

    return SizedBox(
      height: accountBarHeight,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: account.when(
              // A local read that failed is not worth a sentence on this
              // screen: the player cannot act on it, and anything they try to
              // do with the account will report it properly.
              loading: _unknown,
              error: (_, _) => _unknown(),
              data: (state) => switch (state) {
                AccountDisconnected() => _disconnected(),
                AccountConnected(:final username) => _connected(username),
                AccountExpired(:final username) => _expired(username),
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Before the read lands: the space, and nothing in it (research D5).
  Widget _unknown() => const SizedBox.expand(key: Key('account-bar-unknown'));

  Widget _disconnected() => _Bar(
        key: const Key('account-disconnected'),
        title: 'Lichess',
        detail: 'Not connected',
        actions: [
          TextButton(
            key: const Key('connect-lichess'),
            onPressed: _busy ? null : _offerLogIn,
            child: const Text('Connect'),
          ),
        ],
      );

  Widget _connected(String username) => _Bar(
        key: const Key('account-connected'),
        title: 'Lichess',
        detail: 'Connected as $username',
        actions: [
          TextButton(
            key: const Key('disconnect-lichess'),
            onPressed: _busy ? null : _logOut,
            child: const Text('Disconnect'),
          ),
        ],
      );

  /// Lichess issues no refresh tokens, so this offers a login rather than a
  /// renewal — there is no renewal to offer (FR-013, constitution).
  ///
  /// **Disconnect is here too**: a player who does not want to log in again
  /// needs a way to clear the notice (FR-011).
  Widget _expired(String username) => _Bar(
        key: const Key('account-expired'),
        title: 'Lichess',
        detail: '$username — your login has expired',
        actions: [
          TextButton(
            key: const Key('log-in-again'),
            onPressed: _busy ? null : _offerLogIn,
            child: const Text('Log in again'),
          ),
          TextButton(
            key: const Key('disconnect-lichess'),
            onPressed: _busy ? null : _logOut,
            child: const Text('Disconnect'),
          ),
        ],
      );
}

/// One line about the account, and one row of actions.
///
/// Nothing here reads the library, the chosen collection, or anything about a
/// session. The bar says one thing about the account and nothing about the
/// content, so it can carry no information about the position on the other side
/// of the Start button (FR-021).
class _Bar extends StatelessWidget {
  const _Bar({
    super.key,
    required this.title,
    required this.detail,
    required this.actions,
  });

  final String title;
  final String detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            '$title · $detail',
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ...actions,
      ],
    );
  }
}
