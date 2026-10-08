import 'package:flutter/services.dart';

/// The channel MainActivity answers with an Android share intent.
const String shareChannelName = 'com.jessicamumby.when_is_bin_app/share';

/// Hands text to the Android share sheet, so the user can send it on with
/// whatever they already use: email, a message, a note, or Copy.
///
/// Android only. iOS subscribes to the calendar feed on the phone, so nothing
/// there needs to share yet; a share plugin was weighed and rejected, because
/// share_plus 13 brings in JNI, objective_c and native-asset build hooks for
/// one button.
class ShareSheet {
  const ShareSheet();

  static const _channel = MethodChannel(shareChannelName);

  /// Shows the share sheet with [text], and [subject] for apps that take one
  /// (email). True once the sheet is up; false when it could not be shown,
  /// so the caller can offer another way.
  Future<bool> share({required String text, String? subject}) async {
    try {
      final shown = await _channel.invokeMethod<bool>('share', {
        'text': text,
        'subject': subject,
      });
      return shown ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
