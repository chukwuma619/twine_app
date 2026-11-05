import 'package:flutter/material.dart';

/// Spacing, radius, type, and controls for every Twine screen.
/// The scale comes from the trade thread, so a post, a chat, and a trade
/// sit on the same rhythm.
abstract final class TwineTokens {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;

  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusComposer = 24;
  static const double radiusBubbleTail = 6;
  static const double radiusPill = 999;

  static const double control = 48;
  static const double labelColumn = 88;
  static const double iconSm = 16;
  static const double iconMd = 20;

  /// Twine mark. The seed for [theme].
  static const Color ink = Color(0xFF3C245C);

  static const BorderRadius smRadius = BorderRadius.all(
    Radius.circular(radiusSm),
  );

  static const BorderRadius mdRadius = BorderRadius.all(
    Radius.circular(radiusMd),
  );

  static ButtonStyle get filled {
    return FilledButton.styleFrom(
      minimumSize: const Size(64, control),
      shape: const RoundedRectangleBorder(borderRadius: smRadius),
    );
  }

  static BoxDecoration dock(ColorScheme scheme) {
    return BoxDecoration(
      color: scheme.surfaceContainerLow,
      border: Border(top: BorderSide(color: scheme.outlineVariant)),
    );
  }

  static TextStyle title(ThemeData theme) {
    return (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w600,
      height: 1.15,
      letterSpacing: -0.2,
      color: theme.colorScheme.onSurface,
    );
  }

  static TextStyle price(ThemeData theme) {
    return (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w600,
      height: 1.15,
      letterSpacing: -0.2,
      color: theme.colorScheme.onSurface,
    );
  }

  static TextStyle body(ThemeData theme) {
    return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      height: 1.35,
      color: theme.colorScheme.onSurface,
    );
  }

  static TextStyle muted(ThemeData theme) {
    return (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.35,
    );
  }

  static TextStyle section(ThemeData theme) {
    return (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
  }

  static TextStyle error(ThemeData theme) {
    return body(theme).copyWith(color: theme.colorScheme.error);
  }

  static InputDecoration field(
    ThemeData theme, {
    required String label,
    String? suffix,
    String? hint,
    String? helper,
    bool alignLabelWithHint = false,
  }) {
    final scheme = theme.colorScheme;
    const radius = smRadius;
    const quiet = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      hintText: hint,
      helperText: helper,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: md, vertical: sm),
      border: quiet,
      enabledBorder: quiet,
      disabledBorder: quiet,
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
    );
  }

  static ThemeData theme([Brightness brightness = Brightness.light]) {
    final scheme = ColorScheme.fromSeed(
      seedColor: ink,
      brightness: brightness,
    );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
    );
    const quiet = OutlineInputBorder(
      borderRadius: smRadius,
      borderSide: BorderSide.none,
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: title(base).copyWith(fontSize: 18),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: smRadius),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: mdRadius),
      ),
      filledButtonTheme: FilledButtonThemeData(style: filled),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, control),
          shape: const RoundedRectangleBorder(borderRadius: smRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: md,
          vertical: sm,
        ),
        border: quiet,
        enabledBorder: quiet,
        disabledBorder: quiet,
        focusedBorder: OutlineInputBorder(
          borderRadius: smRadius,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: smRadius,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: smRadius,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
    );
  }

  static ThemeData darkTheme() => theme(Brightness.dark);
}
