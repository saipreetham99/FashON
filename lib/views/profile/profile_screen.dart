import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/image_store.dart';
import '../../models/outfit.dart';
import '../../models/user_profile.dart';
import '../../services/backfill_service.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/closet_viewmodel.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../widgets/common.dart';

/// Who the wearer is.
///
/// Laid out by consequence rather than by topic: the fields that change what a
/// good pairing *is* are grouped and labelled as such, and everything that only
/// affects a rendered picture sits below. Someone should be able to tell at a
/// glance which edits cost money.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profileVm = context.watch<ProfileViewModel>();
    final profile = profileVm.profile;
    final images = context.read<ImageStore>();

    if (profileVm.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.huge),
        children: [
          _Portrait(profile: profile, images: images),
          const SizedBox(height: Gap.xxl),

          if (profileVm.error != null) ...[
            ErrorNotice(
              message: profileVm.error!,
              onDismiss: profileVm.clearError,
            ),
            const SizedBox(height: Gap.xl),
          ],

          // --- Styling ---
          const SectionLabel('How you want to be styled'),
          const SizedBox(height: Gap.md),
          Text(
            'These change what counts as a good pairing, so they are part of how '
            'scores are cached. Editing one means pairings get judged again, '
            'which spends against your key.',
            style: Type.small,
          ),
          const SizedBox(height: Gap.xl),

          _ChoiceField<Undertone>(
            label: 'Skin undertone',
            hint: 'Drives colour harmony, the heaviest pillar at 40%.',
            options: Undertone.values,
            active: profile.undertone,
            labelOf: (v) => v.label,
            onChanged:
                (v) => _saveStyling(context, () => profileVm.setUndertone(v)),
          ),
          const SizedBox(height: Gap.xl),

          _ChoiceField<HeightBand>(
            label: 'Height',
            hint:
                'A band, not a measurement — proportion advice only shifts at '
                'coarse thresholds.',
            options: HeightBand.values,
            active: profile.heightBand,
            labelOf: (v) => v.label,
            onChanged:
                (v) => _saveStyling(context, () => profileVm.setHeightBand(v)),
          ),
          const SizedBox(height: Gap.xl),

          _ChoiceField<BuildType>(
            label: 'Build',
            hint: 'Feeds silhouette and proportion, 20%.',
            options: BuildType.values,
            active: profile.build,
            labelOf: (v) => v.label,
            onChanged:
                (v) => _saveStyling(context, () => profileVm.setBuild(v)),
          ),
          const SizedBox(height: Gap.xl),

          Text('Usually dressing for', style: Type.section),
          const SizedBox(height: Gap.xs),
          Text(
            'Informs style and occasion cohesion. Pick any that apply.',
            style: Type.small,
          ),
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final tag in LookTag.values)
                _Chip(
                  label: tag.label,
                  active: profile.occasions.contains(tag),
                  onTap:
                      () => _saveStyling(
                        context,
                        () => profileVm.toggleOccasion(tag),
                      ),
                ),
            ],
          ),

          const SizedBox(height: Gap.huge),
          const Divider(),
          const SizedBox(height: Gap.xl),

          // --- Render only ---
          const SectionLabel('For previews only'),
          const SizedBox(height: Gap.md),
          Text(
            'Used to render the model in outfit previews. Previews are never '
            'cached, so changing anything here is free.',
            style: Type.small,
          ),
          const SizedBox(height: Gap.xl),
          _DetailsForm(profile: profile),

          const SizedBox(height: Gap.huge),
          const Divider(),
          const SizedBox(height: Gap.xl),
          const SectionLabel('Where this goes'),
          const SizedBox(height: Gap.md),
          Text(
            'Everything here is stored on this device only. The styling fields '
            'are sent as text with each scoring request. Your photo is sent only '
            'when you render a preview, and never otherwise.',
            style: Type.bodyMuted,
          ),
          if (profile.hasPhoto && !profile.mayUsePhotoAsLikeness) ...[
            const SizedBox(height: Gap.lg),
            Panel(
              child: Text(
                'Previews will render the garments without using your photo as '
                'a likeness.',
                style: Type.small,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Saves a styling change, then refreshes the pending count.
  ///
  /// Refresh rather than start: a styling edit turns the whole cache into misses,
  /// and kicking off scoring for an entire closet because someone tapped a chip
  /// would be a genuinely expensive surprise. The Combos banner offers the work
  /// instead, so the spend stays a decision.
  static Future<void> _saveStyling(
    BuildContext context,
    Future<void> Function() save,
  ) async {
    final backfill = context.read<BackfillService>();
    final closet = context.read<ClosetViewModel>();

    await save();
    await backfill.refresh(closet.all);
  }
}

class _Portrait extends StatelessWidget {
  final UserProfile profile;
  final ImageStore images;

  const _Portrait({required this.profile, required this.images});

  @override
  Widget build(BuildContext context) {
    final vm = context.read<ProfileViewModel>();
    final photo = profile.photoFileName;

    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _pickSource(context, vm),
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                color: Ink0.card,
                shape: BoxShape.circle,
                border: Border.all(
                  color: photo == null ? Bone.hairline : Accent.brass,
                  width: photo == null ? 1 : 2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child:
                  photo == null
                      ? const Center(
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          color: Bone.muted,
                          size: 26,
                        ),
                      )
                      : Image.file(
                        File(images.profilePathSync(photo)),
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                        errorBuilder:
                            (_, __, ___) => const Center(
                              child: Icon(
                                Icons.person_outline,
                                color: Bone.faint,
                              ),
                            ),
                      ),
            ),
          ),
          const SizedBox(height: Gap.md),
          Text(
            profile.displayName?.isNotEmpty == true
                ? profile.displayName!
                : 'Add a photo of yourself',
            style: Type.section,
          ),
          const SizedBox(height: Gap.xs),
          Text(
            photo == null
                ? 'Previews will use a generic model without one.'
                : 'Used to render previews that look like you.',
            style: Type.small,
            textAlign: TextAlign.center,
          ),
          if (photo != null)
            TextButton(
              onPressed: vm.removePhoto,
              style: TextButton.styleFrom(foregroundColor: Accent.clay),
              child: const Text('Remove photo'),
            ),
        ],
      ),
    );
  }

  Future<void> _pickSource(BuildContext context, ProfileViewModel vm) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder:
          (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.xl,
                Gap.xl,
                Gap.xl,
                Gap.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your photo', style: Type.title),
                  const SizedBox(height: Gap.sm),
                  Text(
                    'A clear, well-lit photo of yourself. Head and shoulders is '
                    'enough. It stays on this device.',
                    style: Type.bodyMuted,
                  ),
                  const SizedBox(height: Gap.xl),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined, size: 20),
                    label: const Text('Take a photo'),
                  ),
                  const SizedBox(height: Gap.md),
                  OutlinedButton.icon(
                    onPressed:
                        () => Navigator.pop(context, ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 20),
                    label: const Text('Choose from photos'),
                  ),
                ],
              ),
            ),
          ),
    );

    if (source == null) return;
    await vm.setPhoto(source);
  }
}

/// Single-choice row that also allows clearing the choice.
class _ChoiceField<T> extends StatelessWidget {
  final String label;
  final String hint;
  final List<T> options;
  final T? active;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  const _ChoiceField({
    required this.label,
    required this.hint,
    required this.options,
    required this.active,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Type.section),
        const SizedBox(height: Gap.xs),
        Text(hint, style: Type.small),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final option in options)
              _Chip(
                label: labelOf(option),
                active: option == active,
                // Tapping the active choice clears it, so a field can be left
                // unanswered without a separate "prefer not to say" option.
                onTap: () => onChanged(option == active ? null : option),
              ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        decoration: BoxDecoration(
          color: active ? Accent.brass : Ink0.card,
          borderRadius: const BorderRadius.all(Radius.circular(Radii.pill)),
          border: Border.all(color: active ? Accent.brass : Bone.hairline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Ink0.sunken : Bone.muted,
          ),
        ),
      ),
    );
  }
}

/// Render-only details, saved on blur rather than per keystroke.
class _DetailsForm extends StatefulWidget {
  final UserProfile profile;

  const _DetailsForm({required this.profile});

  @override
  State<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends State<_DetailsForm> {
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _presentation;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.displayName ?? '');
    _age = TextEditingController(text: widget.profile.age?.toString() ?? '');
    _height = TextEditingController(
      text: widget.profile.heightCm?.toString() ?? '',
    );
    _weight = TextEditingController(
      text: widget.profile.weightKg?.toString() ?? '',
    );
    _presentation = TextEditingController(
      text: widget.profile.presentation ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    _presentation.dispose();
    super.dispose();
  }

  void _commit() {
    context.read<ProfileViewModel>().setDetails(
      displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      age: int.tryParse(_age.text),
      heightCm: int.tryParse(_height.text),
      weightKg: int.tryParse(_weight.text),
      presentation:
          _presentation.text.trim().isEmpty ? null : _presentation.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Committing on focus loss rather than on every keystroke: each save is a
      // database write, and half-typed numbers are not worth persisting.
      onFocusChange: (hasFocus) {
        if (!hasFocus) _commit();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_name, 'Name', 'What previews should call you'),
          const SizedBox(height: Gap.lg),
          _field(
            _presentation,
            'How you dress',
            'e.g. menswear, womenswear, androgynous',
          ),
          const SizedBox(height: Gap.lg),
          Row(
            children: [
              Expanded(
                child: _field(_height, 'Height (cm)', null, number: true),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: _field(_weight, 'Weight (kg)', null, number: true),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          _field(_age, 'Age', null, number: true),
          const SizedBox(height: Gap.md),
          Text(
            'All optional. Anything left blank simply is not mentioned to the '
            'model.',
            style: Type.small,
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String? hint, {
    bool number = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: Type.tag),
        const SizedBox(height: Gap.sm),
        TextField(
          controller: controller,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          inputFormatters:
              number ? [FilteringTextInputFormatter.digitsOnly] : null,
          style: Type.body,
          decoration: InputDecoration(hintText: hint),
          onEditingComplete: () {
            _commit();
            FocusScope.of(context).unfocus();
          },
        ),
      ],
    );
  }
}
