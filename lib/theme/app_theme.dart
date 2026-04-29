import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/log_level.dart';

extension ThemeModeExt on ThemeMode {
  String get label => switch (this) {
    ThemeMode.system => 'Auto',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  String get description => switch (this) {
    ThemeMode.system => 'Follow the operating system appearance.',
    ThemeMode.light => 'Always use the light appearance.',
    ThemeMode.dark => 'Always use the dark appearance.',
  };
}

@immutable
class LogViewTheme extends ThemeExtension<LogViewTheme> {
  const LogViewTheme({
    required this.logBodyStyle,
    required this.logCompactStyle,
    required this.logHeaderStyle,
    required this.statusBarStyle,
    required this.verboseColor,
    required this.debugColor,
    required this.infoColor,
    required this.warningColor,
    required this.errorColor,
    required this.logBadgeForeground,
    required this.searchMatchColor,
    required this.searchCurrentMatchColor,
    required this.searchCurrentRowColor,
    required this.searchHighlightForeground,
    required this.searchNoResultsFillColor,
    required this.searchNoResultsTextColor,
    required this.inlineNoticeBackground,
    required this.inlineNoticeForeground,
    required this.statusLiveColor,
    required this.statusPausedColor,
    required this.statusStoppedColor,
    required this.cardShadowColor,
  });

  final TextStyle logBodyStyle;
  final TextStyle logCompactStyle;
  final TextStyle logHeaderStyle;
  final TextStyle statusBarStyle;
  final Color verboseColor;
  final Color debugColor;
  final Color infoColor;
  final Color warningColor;
  final Color errorColor;
  final Color logBadgeForeground;
  final Color searchMatchColor;
  final Color searchCurrentMatchColor;
  final Color searchCurrentRowColor;
  final Color searchHighlightForeground;
  final Color searchNoResultsFillColor;
  final Color searchNoResultsTextColor;
  final Color inlineNoticeBackground;
  final Color inlineNoticeForeground;
  final Color statusLiveColor;
  final Color statusPausedColor;
  final Color statusStoppedColor;
  final Color cardShadowColor;

  Color logLevelColor(String level) {
    return switch (LogLevel.fromStored(level).code) {
      'fault' || 'error' => errorColor,
      'warning' => warningColor,
      'default' || 'info' => infoColor,
      'debug' => debugColor,
      _ => verboseColor,
    };
  }

  @override
  LogViewTheme copyWith({
    TextStyle? logBodyStyle,
    TextStyle? logCompactStyle,
    TextStyle? logHeaderStyle,
    TextStyle? statusBarStyle,
    Color? verboseColor,
    Color? debugColor,
    Color? infoColor,
    Color? warningColor,
    Color? errorColor,
    Color? logBadgeForeground,
    Color? searchMatchColor,
    Color? searchCurrentMatchColor,
    Color? searchCurrentRowColor,
    Color? searchHighlightForeground,
    Color? searchNoResultsFillColor,
    Color? searchNoResultsTextColor,
    Color? inlineNoticeBackground,
    Color? inlineNoticeForeground,
    Color? statusLiveColor,
    Color? statusPausedColor,
    Color? statusStoppedColor,
    Color? cardShadowColor,
  }) {
    return LogViewTheme(
      logBodyStyle: logBodyStyle ?? this.logBodyStyle,
      logCompactStyle: logCompactStyle ?? this.logCompactStyle,
      logHeaderStyle: logHeaderStyle ?? this.logHeaderStyle,
      statusBarStyle: statusBarStyle ?? this.statusBarStyle,
      verboseColor: verboseColor ?? this.verboseColor,
      debugColor: debugColor ?? this.debugColor,
      infoColor: infoColor ?? this.infoColor,
      warningColor: warningColor ?? this.warningColor,
      errorColor: errorColor ?? this.errorColor,
      logBadgeForeground: logBadgeForeground ?? this.logBadgeForeground,
      searchMatchColor: searchMatchColor ?? this.searchMatchColor,
      searchCurrentMatchColor:
          searchCurrentMatchColor ?? this.searchCurrentMatchColor,
      searchCurrentRowColor:
          searchCurrentRowColor ?? this.searchCurrentRowColor,
      searchHighlightForeground:
          searchHighlightForeground ?? this.searchHighlightForeground,
      searchNoResultsFillColor:
          searchNoResultsFillColor ?? this.searchNoResultsFillColor,
      searchNoResultsTextColor:
          searchNoResultsTextColor ?? this.searchNoResultsTextColor,
      inlineNoticeBackground:
          inlineNoticeBackground ?? this.inlineNoticeBackground,
      inlineNoticeForeground:
          inlineNoticeForeground ?? this.inlineNoticeForeground,
      statusLiveColor: statusLiveColor ?? this.statusLiveColor,
      statusPausedColor: statusPausedColor ?? this.statusPausedColor,
      statusStoppedColor: statusStoppedColor ?? this.statusStoppedColor,
      cardShadowColor: cardShadowColor ?? this.cardShadowColor,
    );
  }

  @override
  LogViewTheme lerp(ThemeExtension<LogViewTheme>? other, double t) {
    if (other is! LogViewTheme) {
      return this;
    }

    return LogViewTheme(
      logBodyStyle: TextStyle.lerp(logBodyStyle, other.logBodyStyle, t)!,
      logCompactStyle: TextStyle.lerp(
        logCompactStyle,
        other.logCompactStyle,
        t,
      )!,
      logHeaderStyle: TextStyle.lerp(logHeaderStyle, other.logHeaderStyle, t)!,
      statusBarStyle: TextStyle.lerp(statusBarStyle, other.statusBarStyle, t)!,
      verboseColor: Color.lerp(verboseColor, other.verboseColor, t)!,
      debugColor: Color.lerp(debugColor, other.debugColor, t)!,
      infoColor: Color.lerp(infoColor, other.infoColor, t)!,
      warningColor: Color.lerp(warningColor, other.warningColor, t)!,
      errorColor: Color.lerp(errorColor, other.errorColor, t)!,
      logBadgeForeground: Color.lerp(
        logBadgeForeground,
        other.logBadgeForeground,
        t,
      )!,
      searchMatchColor: Color.lerp(
        searchMatchColor,
        other.searchMatchColor,
        t,
      )!,
      searchCurrentMatchColor: Color.lerp(
        searchCurrentMatchColor,
        other.searchCurrentMatchColor,
        t,
      )!,
      searchCurrentRowColor: Color.lerp(
        searchCurrentRowColor,
        other.searchCurrentRowColor,
        t,
      )!,
      searchHighlightForeground: Color.lerp(
        searchHighlightForeground,
        other.searchHighlightForeground,
        t,
      )!,
      searchNoResultsFillColor: Color.lerp(
        searchNoResultsFillColor,
        other.searchNoResultsFillColor,
        t,
      )!,
      searchNoResultsTextColor: Color.lerp(
        searchNoResultsTextColor,
        other.searchNoResultsTextColor,
        t,
      )!,
      inlineNoticeBackground: Color.lerp(
        inlineNoticeBackground,
        other.inlineNoticeBackground,
        t,
      )!,
      inlineNoticeForeground: Color.lerp(
        inlineNoticeForeground,
        other.inlineNoticeForeground,
        t,
      )!,
      statusLiveColor: Color.lerp(statusLiveColor, other.statusLiveColor, t)!,
      statusPausedColor: Color.lerp(
        statusPausedColor,
        other.statusPausedColor,
        t,
      )!,
      statusStoppedColor: Color.lerp(
        statusStoppedColor,
        other.statusStoppedColor,
        t,
      )!,
      cardShadowColor: Color.lerp(cardShadowColor, other.cardShadowColor, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  LogViewTheme get logViewTheme => Theme.of(this).extension<LogViewTheme>()!;
}

class AppTheme {
  static const Color seedColor = Color(0xFF4F7CFF);

  static final ThemeData lightTheme = _buildTheme(
    _lightColorScheme,
    _themeTokens(_lightColorScheme),
  );

  static final ThemeData darkTheme = _buildTheme(
    _darkColorScheme,
    _themeTokens(_darkColorScheme),
  );

  static final ColorScheme _lightColorScheme = () {
    final seeded = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
      surfaceContainerLowest: Colors.grey.shade200,
      onSurface: Color(0xFF181818),
      onSurfaceVariant: Color(0xFF262626),
    );
    return seeded;
  }();

  static final ColorScheme _darkColorScheme = () {
    final seeded = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      surface: Colors.grey.shade900,
      surfaceContainerLowest: Color(0xFF0E0E0E),
      onSurface: Color(0xFFF1F1F1),
      onSurfaceVariant: Color(0xFF969696),
    );
    return seeded;
  }();

  static ThemeData _buildTheme(ColorScheme colorScheme, LogViewTheme tokens) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      colorScheme: colorScheme,
      brightness: colorScheme.brightness,
    );

    final textTheme = GoogleFonts.interTextTheme(baseTheme.textTheme).apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    final cursorStyle = WidgetStatePropertyAll(SystemMouseCursors.click);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
      textTheme: textTheme,
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHighest,
        ),
        headingTextStyle: tokens.logHeaderStyle,
        dataTextStyle: tokens.logCompactStyle,
        dividerThickness: 1,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.4),
        selectionHandleColor: colorScheme.primary,
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity(vertical: -4, horizontal: -4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(
          alpha: colorScheme.brightness == Brightness.dark ? 0.3 : 0.72,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.3),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 1.3),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          mouseCursor: cursorStyle,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: cursorStyle,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          mouseCursor: cursorStyle,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      // iconTheme: IconThemeData(size: 20),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          mouseCursor: cursorStyle,
          iconSize: WidgetStatePropertyAll(18),
          minimumSize: WidgetStatePropertyAll(const Size(24, 24)),
          maximumSize: WidgetStatePropertyAll(const Size(32, 32)),
          padding: WidgetStatePropertyAll(const EdgeInsets.all(6)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      extensions: [tokens],
    );
  }

  static LogViewTheme _themeTokens(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final mono = GoogleFonts.notoSansMono();

    return LogViewTheme(
      logBodyStyle: mono.copyWith(fontSize: 12, height: 1.2),
      logCompactStyle: mono.copyWith(fontSize: 11, height: 1.2),
      logHeaderStyle: mono.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
      statusBarStyle: mono.copyWith(fontSize: 13, height: 1.15),
      verboseColor: isDark ? colorScheme.onSurfaceVariant : colorScheme.outline,
      debugColor: colorScheme.primary,
      infoColor: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF0F766E),
      warningColor: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
      errorColor: isDark ? const Color(0xFFFCA5A5) : colorScheme.error,
      logBadgeForeground: isDark
          ? const Color(0xFF1E1F21)
          : const Color(0xFFDCE2F3),
      searchMatchColor: isDark
          ? const Color(0xFFFDE68A)
          : const Color(0xFFFDE68A),
      searchCurrentMatchColor: isDark
          ? const Color(0xFFFBBF24)
          : const Color(0xFFF59E0B),
      searchCurrentRowColor: colorScheme.secondaryContainer.withValues(
        alpha: isDark ? 0.26 : 0.42,
      ),
      searchHighlightForeground: const Color(0xFF111827),
      searchNoResultsFillColor: colorScheme.errorContainer,
      searchNoResultsTextColor: colorScheme.onErrorContainer,
      inlineNoticeBackground: colorScheme.secondaryContainer,
      inlineNoticeForeground: colorScheme.onSecondaryContainer,
      statusLiveColor: isDark
          ? const Color(0xFF4ADE80)
          : const Color(0xFF15803D),
      statusPausedColor: isDark
          ? const Color(0xFFFBBF24)
          : const Color(0xFFB45309),
      statusStoppedColor: isDark ? const Color(0xFFF87171) : colorScheme.error,
      cardShadowColor: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
    );
  }
}
