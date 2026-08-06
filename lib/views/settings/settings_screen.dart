import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_settings.dart';
import '../../data/score_repository.dart';
import '../../services/api_key_service.dart';
import '../../services/backfill_service.dart';
import '../../services/gemini_service.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/closet_viewmodel.dart';
import '../../viewmodels/combinations_viewmodel.dart';
import '../widgets/common.dart';

/// Where the user installs their own Gemini key, and clears the score cache.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();

  bool _obscured = true;
  bool _testing = false;
  String? _error;
  String? _success;
  int? _cachedPairs;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final count = await context.read<ScoreRepository>().count();
    if (!mounted) return;
    setState(() => _cachedPairs = count);
  }

  Future<void> _testAndSave() async {
    final raw = _controller.text;

    final formatProblem = ApiKeyService.checkFormat(raw);
    if (formatProblem != null) {
      setState(() {
        _error = formatProblem;
        _success = null;
      });
      return;
    }

    setState(() {
      _testing = true;
      _error = null;
      _success = null;
    });

    // Both resolved before the first await: reading a provider off `context`
    // after an async gap is exactly the pattern that breaks when the widget is
    // disposed mid-request.
    final gemini = context.read<GeminiService>();
    final keys = context.read<ApiKeyService>();

    try {
      await gemini.validateKey(raw);
      await keys.save(raw);
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _success = 'Key saved. Scoring is ready.';
        _testing = false;
      });
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _testing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<ApiKeyService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.huge),
        children: [
          const SectionLabel('Gemini API key'),
          const SizedBox(height: Gap.md),
          const Text(
            'Scoring and previews run on your key. It is stored encrypted on '
            'this device, is never uploaded, and usage is billed to your own '
            'Google account.',
            style: Type.bodyMuted,
          ),
          const SizedBox(height: Gap.xl),

          if (keys.hasKey) ...[
            Panel(
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Accent.eucalyptus,
                    size: 20,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Key installed', style: Type.body),
                        const SizedBox(height: 2),
                        Text(keys.masked, style: Type.mono),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _removeKey,
                    style: TextButton.styleFrom(foregroundColor: Accent.clay),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.xl),
          ],

          Text(
            keys.hasKey ? 'Replace it' : 'Paste your key',
            style: Type.section,
          ),
          const SizedBox(height: Gap.md),
          TextField(
            controller: _controller,
            obscureText: _obscured,
            enabled: !_testing,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(
              color: Bone.full,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'AIza...',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscured ? Icons.visibility_off : Icons.visibility,
                  color: Bone.muted,
                  size: 20,
                ),
                tooltip: _obscured ? 'Show key' : 'Hide key',
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: Gap.md),
            ErrorNotice(message: _error!),
          ],
          if (_success != null) ...[
            const SizedBox(height: Gap.md),
            Row(
              children: [
                const Icon(Icons.check, size: 16, color: Accent.eucalyptus),
                const SizedBox(width: Gap.sm),
                Text(
                  _success!,
                  style: Type.small.copyWith(color: Accent.eucalyptus),
                ),
              ],
            ),
          ],

          const SizedBox(height: Gap.lg),
          FilledButton(
            onPressed: _testing ? null : _testAndSave,
            child:
                _testing
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Test and save'),
          ),

          const SizedBox(height: Gap.xl),
          const Panel(
            background: Ink0.raised,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Where to get one', style: Type.section),
                SizedBox(height: Gap.sm),
                Text(
                  'Open Google AI Studio, sign in, and create an API key. The '
                  'free tier covers scoring; heavy preview rendering needs '
                  'billing enabled.',
                  style: Type.bodyMuted,
                ),
                SizedBox(height: Gap.md),
                SelectableText(
                  'aistudio.google.com/apikey',
                  style: TextStyle(
                    color: Accent.brass,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                    decorationColor: Accent.brass,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Gap.huge),
          const Divider(),
          const SizedBox(height: Gap.xl),

          const SectionLabel('Score cache'),
          const SizedBox(height: Gap.md),
          Text(
            _cachedPairs == null
                ? 'Counting…'
                : '$_cachedPairs pairing${_cachedPairs == 1 ? '' : 's'} stored. '
                    'Cached scores display instantly and cost nothing to view.',
            style: Type.bodyMuted,
          ),
          const SizedBox(height: Gap.lg),
          OutlinedButton(
            onPressed: _cachedPairs == 0 ? null : _clearCache,
            child: const Text('Clear cached scores'),
          ),
          const SizedBox(height: Gap.sm),
          const Text(
            'Everything will be rescored the next time you ask, which spends '
            'against your key again.',
            style: Type.small,
          ),

          const SizedBox(height: Gap.huge),
          const Divider(),
          const SizedBox(height: Gap.xl),
          _backfillSection(),

          const SizedBox(height: Gap.huge),
          const Divider(),
          const SizedBox(height: Gap.xl),
          const SectionLabel('Models'),
          const SizedBox(height: Gap.md),
          _modelRow('Scoring', GeminiService.scoringModel),
          const SizedBox(height: Gap.sm),
          _modelRow('Preview', GeminiService.imageModel),
          const SizedBox(height: Gap.sm),
          _modelRow('Rubric version', '${GeminiService.promptVersion}'),
        ],
      ),
    );
  }

  Widget _backfillSection() {
    final settings = context.watch<AppSettings>();
    final backfill = context.watch<BackfillService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Automatic scoring'),
        const SizedBox(height: Gap.md),
        Text(
          'When on, garments you add get scored against the rest of your closet '
          'in the background. That is what lets the app tell you a different '
          'piece would score higher without being asked.',
          style: Type.bodyMuted,
        ),
        const SizedBox(height: Gap.lg),
        Panel(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Score in the background', style: Type.body),
                        const SizedBox(height: 2),
                        Text(
                          settings.backfillEnabled
                              ? 'Up to ${settings.backfillCap} pairings per run'
                              : 'Off — score manually from Combos',
                          style: Type.small,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: settings.backfillEnabled,
                    activeTrackColor: Accent.brass,
                    onChanged: (value) => _toggleBackfill(value: value),
                  ),
                ],
              ),
              if (backfill.pending > 0) ...[
                const Divider(height: Gap.xl),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${backfill.pending} pairing'
                        '${backfill.pending == 1 ? '' : 's'} outstanding',
                        style: Type.small,
                      ),
                    ),
                    TextButton(
                      onPressed:
                          backfill.isRunning
                              ? backfill.pause
                              : () => backfill.start(
                                context.read<ClosetViewModel>().all,
                              ),
                      child: Text(backfill.isRunning ? 'Stop' : 'Score now'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          'Only pairings across different categories are scored — two tops are '
          'never worn together, so judging them would spend your quota on an '
          'answer nobody needs.',
          style: Type.small,
        ),
      ],
    );
  }

  /// Turning this on spends money unattended, so the first time asks plainly.
  Future<void> _toggleBackfill({required bool value}) async {
    final settings = context.read<AppSettings>();

    if (!value) {
      await settings.setBackfillEnabled(false);
      return;
    }

    if (!settings.backfillConsented) {
      final pending = context.read<BackfillService>().pending;
      final agreed = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Score in the background?'),
              content: Text(
                'Each pairing is one Gemini request billed to your key. There '
                '${pending == 1 ? 'is' : 'are'} $pending outstanding right now, and '
                'runs are capped at ${AppSettings.defaultCap} at a time.\n\n'
                'You can stop a run at any point from Combos, and anything already '
                'scored is kept.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Turn on'),
                ),
              ],
            ),
      );

      if (agreed != true || !mounted) return;
      await settings.setBackfillConsented(true);
    }

    await settings.setBackfillEnabled(true);
  }

  Widget _modelRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Type.small),
        Text(value, style: Type.mono.copyWith(color: Bone.full)),
      ],
    );
  }

  Future<void> _removeKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Remove API key?'),
            content: const Text(
              'Scoring and previews stop working until you add a key again. Your '
              'closet, looks, and cached scores are untouched.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Accent.clay),
                child: const Text('Remove'),
              ),
            ],
          ),
    );

    if (confirmed != true || !mounted) return;
    await context.read<ApiKeyService>().clear();
    if (!mounted) return;
    setState(() {
      _success = null;
      _error = null;
    });
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Clear cached scores?'),
            content: const Text(
              'Every pairing will need rescoring, which spends against your API '
              'key. Your garments and saved looks stay.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Accent.clay),
                child: const Text('Clear'),
              ),
            ],
          ),
    );

    if (confirmed != true || !mounted) return;

    await context.read<CombinationsViewModel>().clearCache();
    if (!mounted) return;
    await _loadStats();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Cached scores cleared.')));
  }
}
