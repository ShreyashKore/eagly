import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/hint_note.dart';
import '../../../services/tools/avd_manager_tool.dart';
import '../data/device_profile.dart';
import '../data/system_image.dart';

/// What the user filled in.
@immutable
class CreateEmulatorRequest {
  const CreateEmulatorRequest({
    required this.name,
    required this.packagePath,
    this.deviceProfileId,
  });

  final String name;
  final String packagePath;
  final String? deviceProfileId;
}

/// Asks for the three things `avdmanager create avd` needs: a name, a system
/// image, and a hardware profile.
///
/// Only images already installed are offered. Downloading one means
/// `sdkmanager`, a licence prompt and gigabytes of transfer — a different
/// feature, deliberately out of scope, so an SDK with no images says so
/// instead of pretending.
class CreateEmulatorSheet extends StatefulWidget {
  const CreateEmulatorSheet({
    super.key,
    required this.systemImages,
    required this.deviceProfiles,
    required this.isLoading,
    required this.existingNames,
  });

  final List<SystemImage> systemImages;
  final List<DeviceProfile> deviceProfiles;
  final bool isLoading;

  /// Checked here so a clash is caught while the field still has focus, rather
  /// than after a second and a half of JVM start.
  final Set<String> existingNames;

  @override
  State<CreateEmulatorSheet> createState() => _CreateEmulatorSheetState();
}

class _CreateEmulatorSheetState extends State<CreateEmulatorSheet> {
  late final TextEditingController _nameController = TextEditingController();
  SystemImage? _image;
  DeviceProfile? _profile;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _image = widget.systemImages.firstOrNull;
    _profile = _compatibleProfiles.firstOrNull;
  }

  @override
  void didUpdateWidget(CreateEmulatorSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The options arrive asynchronously; adopt them once, without overwriting
    // a choice the user has already made.
    _image ??= widget.systemImages.firstOrNull;
    _profile ??= _compatibleProfiles.firstOrNull;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Profiles that suit the selected image.
  ///
  /// The pairing is not cosmetic: a phone image on a TV profile produces an
  /// AVD that boots to a blank screen, so the mismatch is never offered.
  List<DeviceProfile> get _compatibleProfiles {
    final image = _image;
    if (image == null) return widget.deviceProfiles;
    return widget.deviceProfiles
        .where(
          (profile) => profile.tag == null
              ? image.isHandheld
              : profile.tag == image.tagId,
        )
        .toList(growable: false);
  }

  void _submit() {
    final name = _nameController.text.trim();
    final invalid = AvdManagerTool.describeInvalidName(name);
    if (invalid != null) {
      setState(() => _nameError = invalid);
      return;
    }
    if (widget.existingNames.contains(name)) {
      setState(() => _nameError = 'An emulator called $name already exists.');
      return;
    }
    final image = _image;
    if (image == null) return;

    Navigator.of(context).pop(
      CreateEmulatorRequest(
        name: name,
        packagePath: image.packagePath,
        deviceProfileId: _profile?.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = _compatibleProfiles;

    return AlertDialog(
      icon: const Icon(Icons.add_to_queue_outlined),
      title: const Text('New emulator'),
      content: SizedBox(
        width: 460,
        child: widget.isLoading && widget.systemImages.isEmpty
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.systemImages.isEmpty) ...[
                    const HintNote(
                      title: 'No system images installed',
                      text:
                          'An emulator needs a system image, and Eagly only '
                          'uses ones already downloaded. Install one from '
                          'Android Studio’s SDK Manager, under SDK Platforms, '
                          'then refresh.',
                    ),
                  ] else ...[
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: 'Pixel_7_API_34',
                        errorText: _nameError,
                        helperText:
                            'Letters, numbers, dots, underscores '
                            'and hyphens',
                      ),
                      onChanged: (_) {
                        if (_nameError != null) {
                          setState(() => _nameError = null);
                        }
                      },
                      onSubmitted: (_) => _submit(),
                    ),
                    const Gap(20),
                    DropdownButtonFormField<SystemImage>(
                      initialValue: _image,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'System image',
                      ),
                      items: [
                        for (final image in widget.systemImages)
                          DropdownMenuItem(
                            value: image,
                            child: Text(
                              image.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (image) => setState(() {
                        _image = image;
                        // The old profile may belong to another device class.
                        if (!_compatibleProfiles.contains(_profile)) {
                          _profile = _compatibleProfiles.firstOrNull;
                        }
                      }),
                    ),
                    const Gap(20),
                    DropdownButtonFormField<DeviceProfile>(
                      initialValue: profiles.contains(_profile)
                          ? _profile
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Hardware profile',
                        helperText: profiles.isEmpty
                            ? 'None available — a generic device will be used'
                            : null,
                      ),
                      items: [
                        for (final profile in profiles)
                          DropdownMenuItem(
                            value: profile,
                            child: Text(
                              profile.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (profile) =>
                          setState(() => _profile = profile),
                    ),
                    if (widget.isLoading) ...[
                      const Gap(16),
                      Row(
                        children: [
                          const SizedBox.square(
                            dimension: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const Gap(10),
                          Text(
                            'Loading hardware profiles…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: widget.systemImages.isEmpty ? null : _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
