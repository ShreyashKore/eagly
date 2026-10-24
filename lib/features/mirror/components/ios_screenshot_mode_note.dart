import 'package:flutter/material.dart';

import '../../../constants/app_constants.dart';
import '../../../presentation/components/hint_note.dart';
import '../../../utils/url_launcher.dart';

/// Warns that an iPhone mirror shows screenshots rather than live video:
/// what that costs, and, where [suggestIos27] (Windows / Linux, which have no
/// live route on older iOS), that iOS 27 is the way to live video. Links to
/// the README's section on it.
class const IosScreenshotModeNote({
  super.key,
  required final bool suggestIos27,
  final ValueChanged<String> openUrl = openExternalUrl,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return HintNote(
      icon: Icons.warning_amber_rounded,
      title: 'Screenshots, not live video',
      text: [
        'Two or three pictures a second, each up to a second old. While it '
            'runs, copying files or installing apps on the iPhone is slower, '
            'and older computers may skip frames.',
        if (suggestIos27)
          'Live video here needs iOS 27 on the iPhone, which an upcoming '
              'Eagly update will use.',
      ].join(' '),
      action: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          onPressed: () => openUrl(AppConstants.iosScreenshotMirrorUrl),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Read more'),
        ),
      ),
    );
  }
}
