/// Importing a PGN: pick, name, watch it parse, read what happened.
///
/// Nothing here is a training screen, so titles, file names and study names are
/// shown freely. That distinction is the whole design: evidence about a
/// position is fine everywhere except in front of a player who is calculating.
library;

import 'package:chess_trainer/data/import_service.dart';
import 'package:chess_trainer/domain/errors.dart';
import 'package:chess_trainer/domain/library/collection.dart';
import 'package:chess_trainer/domain/lichess/account.dart';
import 'package:chess_trainer/ui/library/import_report_view.dart';
import 'package:chess_trainer/ui/library/connection_controller.dart';
import 'package:chess_trainer/ui/library/library_controller.dart';
import 'package:chess_trainer/ui/library/study_picker_screen.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _studyLink = TextEditingController();

  XFile? _file;
  ImportProgress? _progress;
  bool _running = false;

  /// Held so the player can confirm a duplicate without re-parsing the file.
  CollectionOrigin? _pendingOrigin;

  /// Why "My studies" went nowhere, when it did (FR-017).
  String? _studiesNeedAccount;

  @override
  void dispose() {
    _name.dispose();
    _studyLink.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await ref.read(importServiceProvider).pickFile();
    if (picked == null || !mounted) return;

    setState(() {
      _file = picked;
      _progress = null;
      if (_name.text.trim().isEmpty) {
        _name.text = _defaultNameFor(picked.name);
      }
    });
  }

  /// The file's name without its extension: a decent first guess, and the
  /// player can change it before importing.
  String _defaultNameFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    return stem.trim().isEmpty ? 'Imported positions' : stem.trim();
  }

  Future<void> _import() async {
    final file = _file;
    if (file == null) return;

    final name = _name.text.trim().isEmpty
        ? _defaultNameFor(file.name)
        : _name.text.trim();

    setState(() {
      _running = true;
      _progress = const ImportAcquiring();
      _pendingOrigin = FileOrigin(file.name);
    });

    await for (final progress
        in ref.read(importServiceProvider).importFile(file, name: name)) {
      if (!mounted) return;
      setState(() => _progress = progress);
    }

    if (!mounted) return;
    setState(() => _running = false);
    _refreshLibrary();
  }

  /// Imports a study from Lichess (US2).
  ///
  /// The fetch is the only new part: once the PGN is in hand it goes through
  /// exactly the same parse, duplicate check, storage and report as a file
  /// (003 research D7).
  Future<void> _importStudy(String input, String name) async {
    setState(() {
      _running = true;
      _progress = const ImportAcquiring();
      _file = null;
    });

    await for (final progress in ref
        .read(studyImporterProvider)
        .importStudy(input, name: name)) {
      if (!mounted) return;
      setState(() => _progress = progress);
    }

    if (!mounted) return;
    setState(() => _running = false);
    _refreshLibrary();
  }

  /// Opens the picker — but only with an account to pick from (FR-017).
  ///
  /// **Import does not offer a login** (FR-015). Navigating to a screen whose
  /// only content is "you need to log in somewhere else" is a dead end that has
  /// to be backed out of, so this stops here and says where the account lives
  /// (004 research D7).
  Future<void> _pickStudy() async {
    final account = await ref.read(lichessAccountProvider.future);
    if (!mounted) return;

    if (account is! AccountConnected) {
      setState(() {
        // An expired login and no login at all are different problems with
        // different fixes, so they get different sentences — and neither is
        // the "that study is not public" wording, which belongs to a pasted
        // address and says nothing true about this request.
        _studiesNeedAccount = account is AccountExpired
            ? messageForNetworkError(LoginExpiredError())
            : studiesNeedAccountMessage;
      });
      return;
    }

    setState(() => _studiesNeedAccount = null);
    final picked = await Navigator.of(context).push<PickedStudy>(
      MaterialPageRoute<PickedStudy>(
        builder: (context) => const StudyPickerScreen(),
      ),
    );
    if (picked == null || !mounted) return;

    _name.text = picked.name;
    await _importStudy(picked.id, picked.name);
  }

  Future<void> _importPastedStudy() async {
    final input = _studyLink.text.trim();
    if (input.isEmpty) return;

    final name =
        _name.text.trim().isEmpty ? 'Lichess study' : _name.text.trim();
    await _importStudy(input, name);
  }

  Future<void> _confirmDuplicate(ImportDuplicate duplicate) async {
    final file = _file;
    if (file == null) return;

    final name = _name.text.trim().isEmpty
        ? _defaultNameFor(file.name)
        : _name.text.trim();

    setState(() => _running = true);
    final result = await ref.read(importServiceProvider).confirmDuplicate(
          duplicate.outcome,
          name: name,
          origin: _pendingOrigin ?? FileOrigin(file.name),
          contentHash: duplicate.contentHash,
        );

    if (!mounted) return;
    setState(() {
      _running = false;
      _progress = result;
    });
    _refreshLibrary();
  }

  void _refreshLibrary() {
    ref.invalidate(collectionsProvider);
    ref.invalidate(availablePositionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;

    return Scaffold(
      appBar: AppBar(title: const Text('Import positions')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Import a PGN file — a study exported from Lichess, or any '
                'file of positions. Each entry needs a starting position to '
                'be trainable.',
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const Key('pick-file'),
                onPressed: _running ? null : _pick,
                icon: const Icon(Icons.folder_open),
                label: Text(_file == null ? 'Choose a file' : _file!.name),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('collection-name'),
                controller: _name,
                enabled: !_running,
                decoration: const InputDecoration(
                  labelText: 'Name this collection',
                  helperText: 'Only you see this, and never while training.',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('start-import'),
                onPressed: _file == null || _running ? null : _import,
                child: const Text('Import'),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              Text('From Lichess',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              // Reworded in feature 004. It used to say "pick one of your own
              // after logging in", which told the player to do something this
              // screen no longer offers and did not say where to do it — found
              // on the device, because the tests asserted the absence of login
              // *controls* and nobody had asserted the prose.
              const Text(
                'Paste a study address, or pick one of your own. A public '
                'study needs no account; picking your own uses the Lichess '
                'account connected on the home screen.',
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('study-link'),
                controller: _studyLink,
                enabled: !_running,
                decoration: const InputDecoration(
                  labelText: 'Study address',
                  hintText: 'lichess.org/study/abcd1234',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('import-study-link'),
                      onPressed: _running ? null : _importPastedStudy,
                      child: const Text('Import study'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('pick-my-studies'),
                      onPressed: _running ? null : _pickStudy,
                      child: const Text('My studies'),
                    ),
                  ),
                ],
              ),
              if (_studiesNeedAccount != null) ...[
                const SizedBox(height: 12),
                Text(
                  _studiesNeedAccount!,
                  key: const Key('studies-need-account'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 32),
              if (progress != null) _ProgressView(
                progress: progress,
                onConfirmDuplicate: _confirmDuplicate,
                onDone: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({
    required this.progress,
    required this.onConfirmDuplicate,
    required this.onDone,
  });

  final ImportProgress progress;
  final void Function(ImportDuplicate) onConfirmDuplicate;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return switch (progress) {
      ImportAcquiring() => const Row(
          key: Key('import-acquiring'),
          children: [
            SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Reading the file…'),
          ],
        ),
      ImportParsing(:final done, :final total) => Column(
          key: const Key('import-parsing'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(total == 0 ? 'Reading…' : 'Reading $done of $total'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: total == 0 ? null : done / total),
          ],
        ),
      ImportDuplicate(:final existing) => Column(
          key: const Key('import-duplicate'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This looks like "${existing.name}", which you already have.',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Importing it again adds a second copy. Nothing is merged or '
              'replaced.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('confirm-duplicate'),
              onPressed: () =>
                  onConfirmDuplicate(progress as ImportDuplicate),
              child: const Text('Import it anyway'),
            ),
          ],
        ),
      ImportReported(:final collection, :final outcome) => Column(
          key: const Key('import-report'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${collection.name}"', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ImportReportView(outcome: outcome),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('import-done'),
              onPressed: onDone,
              child: const Text('Done'),
            ),
          ],
        ),
      ImportFailed(:final message, :final outcome) => Column(
          key: const Key('import-failed'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message,
                key: const Key('import-failure-message'),
                style: theme.textTheme.bodyLarge),
            if (outcome != null) ...[
              const SizedBox(height: 16),
              ImportReportView(outcome: outcome),
            ],
          ],
        ),
    };
  }
}
