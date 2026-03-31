import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences keys for provider-specific web model settings.
class ProviderPreferenceHelper {
  static String imageWebToolKey(String provider) => 'image_web_tool_$provider';
  static String imageWebModelKey(String provider) =>
      'image_web_model_$provider';
  static String videoWebToolKey(String provider) => 'video_web_tool_$provider';
  static String videoWebModelKey(String provider) =>
      'video_web_model_$provider';
  static String videoWebModeKey(String provider) => 'video_web_mode_$provider';

  static const String _legacyImageWebToolKey = 'image_web_tool';
  static const String _legacyImageWebModelKey = 'image_web_model';
  static const String _legacyVideoWebToolKey = 'video_web_tool';
  static const String _legacyVideoWebModelKey = 'video_web_model';
  static const String _legacyVideoWebModeKey = 'video_web_mode';

  static String videoWatermarkFreeKey(String provider) {
    return provider == 'vidu'
        ? 'vidu_watermark_free'
        : 'video_watermark_free_$provider';
  }

  static String? getImageWebTool(SharedPreferences prefs, String provider) {
    final scopedValue = prefs.getString(imageWebToolKey(provider));
    if (scopedValue != null) {
      return scopedValue;
    }
    final activeProvider = prefs.getString('image_provider');
    if (activeProvider == provider) {
      return prefs.getString(_legacyImageWebToolKey);
    }
    return null;
  }

  static String? getImageWebModel(SharedPreferences prefs, String provider) {
    final scopedValue = prefs.getString(imageWebModelKey(provider));
    if (scopedValue != null) {
      return scopedValue;
    }
    final activeProvider = prefs.getString('image_provider');
    if (activeProvider == provider) {
      return prefs.getString(_legacyImageWebModelKey);
    }
    return null;
  }

  static String? getVideoWebTool(SharedPreferences prefs, String provider) {
    final scopedValue = prefs.getString(videoWebToolKey(provider));
    if (scopedValue != null) {
      return scopedValue;
    }
    final activeProvider = prefs.getString('video_provider');
    if (activeProvider == provider) {
      return prefs.getString(_legacyVideoWebToolKey);
    }
    return null;
  }

  static String? getVideoWebModel(SharedPreferences prefs, String provider) {
    final scopedValue = prefs.getString(videoWebModelKey(provider));
    if (scopedValue != null) {
      return scopedValue;
    }
    final activeProvider = prefs.getString('video_provider');
    if (activeProvider == provider) {
      return prefs.getString(_legacyVideoWebModelKey);
    }
    return null;
  }

  static String? getVideoWebMode(SharedPreferences prefs, String provider) {
    final scopedValue = prefs.getString(videoWebModeKey(provider));
    if (scopedValue != null) {
      return scopedValue;
    }
    final activeProvider = prefs.getString('video_provider');
    if (activeProvider == provider) {
      return prefs.getString(_legacyVideoWebModeKey);
    }
    return null;
  }

  static bool getVideoWatermarkFree(SharedPreferences prefs, String provider) {
    return prefs.getBool(videoWatermarkFreeKey(provider)) ?? false;
  }

  static Future<bool> setImageWebTool(
    SharedPreferences prefs,
    String provider,
    String value,
  ) {
    return prefs.setString(imageWebToolKey(provider), value);
  }

  static Future<bool> setImageWebModel(
    SharedPreferences prefs,
    String provider,
    String value,
  ) {
    return prefs.setString(imageWebModelKey(provider), value);
  }

  static Future<bool> setVideoWebTool(
    SharedPreferences prefs,
    String provider,
    String value,
  ) {
    return prefs.setString(videoWebToolKey(provider), value);
  }

  static Future<bool> setVideoWebModel(
    SharedPreferences prefs,
    String provider,
    String value,
  ) {
    return prefs.setString(videoWebModelKey(provider), value);
  }

  static Future<bool> setVideoWebMode(
    SharedPreferences prefs,
    String provider,
    String value,
  ) {
    return prefs.setString(videoWebModeKey(provider), value);
  }

  static Future<bool> setVideoWatermarkFree(
    SharedPreferences prefs,
    String provider,
    bool value,
  ) {
    return prefs.setBool(videoWatermarkFreeKey(provider), value);
  }

  static Future<bool> deleteImageWebTool(
    SharedPreferences prefs,
    String provider,
  ) async {
    final results = <bool>[await prefs.remove(imageWebToolKey(provider))];
    if (prefs.getString('image_provider') == provider) {
      results.add(await prefs.remove(_legacyImageWebToolKey));
    }
    return results.any((result) => result);
  }

  static Future<bool> deleteImageWebModel(
    SharedPreferences prefs,
    String provider,
  ) async {
    final results = <bool>[await prefs.remove(imageWebModelKey(provider))];
    if (prefs.getString('image_provider') == provider) {
      results.add(await prefs.remove(_legacyImageWebModelKey));
    }
    return results.any((result) => result);
  }

  static Future<bool> deleteVideoWebTool(
    SharedPreferences prefs,
    String provider,
  ) async {
    final results = <bool>[await prefs.remove(videoWebToolKey(provider))];
    if (prefs.getString('video_provider') == provider) {
      results.add(await prefs.remove(_legacyVideoWebToolKey));
    }
    return results.any((result) => result);
  }

  static Future<bool> deleteVideoWebModel(
    SharedPreferences prefs,
    String provider,
  ) async {
    final results = <bool>[await prefs.remove(videoWebModelKey(provider))];
    if (prefs.getString('video_provider') == provider) {
      results.add(await prefs.remove(_legacyVideoWebModelKey));
    }
    return results.any((result) => result);
  }

  static Future<bool> deleteVideoWebMode(
    SharedPreferences prefs,
    String provider,
  ) async {
    final results = <bool>[await prefs.remove(videoWebModeKey(provider))];
    if (prefs.getString('video_provider') == provider) {
      results.add(await prefs.remove(_legacyVideoWebModeKey));
    }
    return results.any((result) => result);
  }

  static Future<bool> deleteVideoWatermarkFree(
    SharedPreferences prefs,
    String provider,
  ) async {
    return prefs.remove(videoWatermarkFreeKey(provider));
  }
}
