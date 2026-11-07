import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colour values for one brightness. Taken from the data-pharm-softwere ERP
/// (Pages/erp-shell.css and erp-ui.css), so the app and the ERP look alike.
class _Palette {
  const _Palette({
    required this.brand,
    required this.brandDark,
    required this.brandSoft,
    required this.accent,
    required this.onBrand,
    required this.green,
    required this.orange,
    required this.red,
    required this.greenSoft,
    required this.orangeSoft,
    required this.redSoft,
    required this.redLine,
    required this.solidGood,
    required this.solidBad,
    required this.heroStart,
    required this.heroEnd,
    required this.heroMuted,
    required this.bgTop,
    required this.bgMid,
    required this.bgBottom,
    required this.bgGlow,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.inputFill,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.hairline,
    required this.glassFill,
    required this.glassEdge,
    required this.navFill,
    required this.shadow,
    required this.skeletonBase,
  });

  final Color brand, brandDark, brandSoft, accent, onBrand;
  final Color green, orange, red, greenSoft, orangeSoft, redSoft, redLine;
  final Color solidGood, solidBad;
  final Color heroStart, heroEnd, heroMuted;
  final Color bgTop, bgMid, bgBottom, bgGlow;
  final Color background, surface, surfaceMuted, inputFill;
  final Color textPrimary, textSecondary, textTertiary;
  final Color hairline, glassFill, glassEdge, navFill, shadow, skeletonBase;
}

// ERP :root
const _light = _Palette(
  brand: Color(0xFF1F4E79), // --erp-primary
  brandDark: Color(0xFF173C5F), // --erp-primary-hover
  brandSoft: Color(0xFFE3EAF3), // --erp-primary-soft on white
  accent: Color(0xFF3F7FB8), // --erp-accent
  onBrand: Color(0xFFFFFFFF),
  green: Color(0xFF1E9E6A), // --erp-good
  orange: Color(0xFFD98E04), // --erp-warn
  red: Color(0xFFD1495B), // --erp-bad
  greenSoft: Color(0xFFE4F3ED),
  orangeSoft: Color(0xFFFBF1E0),
  redSoft: Color(0xFFFAE9EB),
  redLine: Color(0x4DD1495B),
  solidGood: Color(0xFF1A8F5F), // --erp-solid-good
  solidBad: Color(0xFFC93C4F), // --erp-solid-bad
  heroStart: Color(0xFF0F2742), // --erp-side-bg
  heroEnd: Color(0xFF2A6AA8), // towards --erp-accent
  heroMuted: Color(0xFFC6D3E2), // --erp-side-text
  // Page background: soft steel-blue sky fading into the ERP grey
  bgTop: Color(0xFFD6E3F3),
  bgMid: Color(0xFFEAF0F7),
  bgBottom: Color(0xFFF4F7FB),
  bgGlow: Color(0x333F7FB8),
  background: Color(0xFFF2F5F9), // --erp-bg
  surface: Color(0xFFFFFFFF), // --erp-card
  surfaceMuted: Color(0xFFF5F8FC), // --erp-soft
  inputFill: Color(0xFFFFFFFF),
  textPrimary: Color(0xFF1C2B3A), // --erp-text
  textSecondary: Color(0xFF6B7A8C), // --erp-muted
  textTertiary: Color(0xFF9AA6B4),
  hairline: Color(0xFFDCE3EC), // --erp-border
  glassFill: Color(0xCCFFFFFF), // white 80% over the sky
  glassEdge: Color(0xE6FFFFFF), // bright rim, like iOS glass
  navFill: Color(0xE6FFFFFF),
  shadow: Color(0x1F0F2742),
  skeletonBase: Color(0xFFE2E9F2),
);

// ERP [data-bs-theme="dark"]
const _dark = _Palette(
  brand: Color(0xFF5B9BD5),
  brandDark: Color(0xFF7FB1DF),
  brandSoft: Color(0xFF1A3352),
  accent: Color(0xFF5B9BD5),
  onBrand: Color(0xFF06121F), // ERP puts dark text on the light-blue primary
  green: Color(0xFF3EC58C),
  orange: Color(0xFFF0AA2A),
  red: Color(0xFFEF6B7C),
  greenSoft: Color(0xFF15363A),
  orangeSoft: Color(0xFF33311F),
  redSoft: Color(0xFF3A2433),
  redLine: Color(0x66EF6B7C),
  solidGood: Color(0xFF1F9D68),
  solidBad: Color(0xFFD34A5D),
  heroStart: Color(0xFF0B2447),
  heroEnd: Color(0xFF1D5799),
  heroMuted: Color(0xFFB9C6D6),
  // Page background: deep blue glow at the top fading to near-black
  bgTop: Color(0xFF0F2E5A),
  bgMid: Color(0xFF0A1830),
  bgBottom: Color(0xFF050A14),
  bgGlow: Color(0x592A6FC4),
  background: Color(0xFF09131F),
  surface: Color(0xFF101F33),
  surfaceMuted: Color(0xFF0C192A),
  inputFill: Color(0xFF0E1E33),
  textPrimary: Color(0xFFE8EEF5),
  textSecondary: Color(0xFF93A4B9),
  textTertiary: Color(0xFF61748C),
  hairline: Color(0xFF213654),
  glassFill: Color(0xB3112440), // navy 70% over the glow
  glassEdge: Color(0x24FFFFFF), // white 14% rim
  navFill: Color(0xD90E1D33),
  shadow: Color(0x66000000),
  skeletonBase: Color(0xFF172C47),
);

/// One place for every colour in the app. Values follow the current
/// brightness; [ThemeController] switches it and rebuilds the tree.
class AppColors {
  AppColors._();

  static _Palette _p = _light;
  static bool get isDark => identical(_p, _dark);

  /// Called by ThemeController only.
  static void setDark(bool dark) => _p = dark ? _dark : _light;

  // Brand (ERP navy / steel blue)
  static Color get brand => _p.brand;
  static Color get brandDark => _p.brandDark;
  static Color get brandSoft => _p.brandSoft;
  static Color get accent => _p.accent;
  static Color get onBrand => _p.onBrand;

  // Semantic (ERP good / warn / bad)
  static Color get green => _p.green;
  static Color get orange => _p.orange;
  static Color get red => _p.red;
  static Color get blue => _p.accent;
  static Color get greenSoft => _p.greenSoft;
  static Color get orangeSoft => _p.orangeSoft;
  static Color get redSoft => _p.redSoft;
  static Color get redLine => _p.redLine;
  static Color get solidGood => _p.solidGood; // filled success buttons
  static Color get solidBad => _p.solidBad; // filled danger buttons
  static Color get blueSoft => _p.brandSoft;

  // Hero header (ERP sidebar gradient)
  static Color get heroStart => _p.heroStart;
  static Color get heroEnd => _p.heroEnd;
  static Color get heroMuted => _p.heroMuted;

  // Page background gradient
  static Color get bgTop => _p.bgTop;
  static Color get bgMid => _p.bgMid;
  static Color get bgBottom => _p.bgBottom;
  static Color get bgGlow => _p.bgGlow;

  // Surfaces
  static Color get background => _p.background;
  static Color get surface => _p.surface;
  static Color get surfaceMuted => _p.surfaceMuted;
  static Color get inputFill => _p.inputFill;

  // Text
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textTertiary => _p.textTertiary;

  // Lines, glass, shadow
  static Color get hairline => _p.hairline;
  static Color get glassFill => _p.glassFill;
  static Color get glassBorder => _p.glassEdge;
  static Color get navFill => _p.navFill;
  static Color get shadow => _p.shadow;

  // Skeleton placeholders
  static Color get skeletonBase => _p.skeletonBase;
}

/// Font weights in use: regular (w400) and semibold (w600) only.
class AppText {
  AppText._();
  static const regular = FontWeight.w400;
  static const semibold = FontWeight.w600;
}

/// ERP radii: 10px inputs/buttons, 14px panels.
class AppRadius {
  AppRadius._();
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 26.0;
  static const pill = 999.0;
}

/// Shared glass decoration: translucent fill, light rim, soft shadow. No blur.
BoxDecoration glassDecoration({double radius = AppRadius.md}) => BoxDecoration(
      color: AppColors.glassFill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.glassBorder, width: 1),
      boxShadow: [
        BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: const Offset(0, 6)),
      ],
    );

/// The navy hero gradient used by Home and every page header.
LinearGradient heroGradient() => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.heroStart, AppColors.heroEnd],
    );

/// Text field look for every form: filled, 14px corners, optional icon.
class AppInput {
  AppInput._();

  static InputDecoration decoration(String label,
      {IconData? icon, String? hint, String? helper}) {
    final i = icon ?? iconFor(label);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixIcon: i == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(i, size: 20, color: AppColors.brand),
            ),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }

  /// A fitting icon from the field label, so older screens get icons free.
  static IconData? iconFor(String label) {
    final l = label.toLowerCase();
    if (l.contains('customer')) return Icons.storefront_outlined;
    if (l.contains('product')) return Icons.medication_outlined;
    if (l.contains('amount') || l.contains('(rs)')) {
      return Icons.payments_outlined;
    }
    if (l.contains('vendor')) return Icons.groups_2_outlined;
    if (l.contains('remark')) return Icons.notes_outlined;
    if (l.contains('qty')) return Icons.tag;
    if (l.contains('batch')) return Icons.qr_code_2;
    if (l.contains('user')) return Icons.person_outline;
    if (l.contains('password')) return Icons.lock_outline;
    if (l.contains('url')) return Icons.link;
    return null;
  }
}

class AppTheme {
  AppTheme._();

  /// Theme for the current [AppColors] brightness.
  static ThemeData current() {
    final dark = AppColors.isDark;
    final brightness = dark ? Brightness.dark : Brightness.light;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: brightness,
      primary: AppColors.brand,
      onPrimary: AppColors.onBrand,
      secondary: AppColors.accent,
      error: AppColors.red,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      outline: AppColors.hairline,
    );

    const text = TextTheme(
      titleLarge: TextStyle(fontSize: 20, fontWeight: AppText.semibold),
      titleMedium: TextStyle(fontSize: 16, fontWeight: AppText.semibold),
      titleSmall: TextStyle(fontSize: 14, fontWeight: AppText.semibold),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: AppText.regular),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: AppText.regular),
      bodySmall: TextStyle(fontSize: 12, fontWeight: AppText.regular),
      labelLarge: TextStyle(fontSize: 14, fontWeight: AppText.semibold),
      labelMedium: TextStyle(fontSize: 12, fontWeight: AppText.semibold),
      labelSmall: TextStyle(fontSize: 11, fontWeight: AppText.regular),
    );

    final rounded = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm));
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: AppColors.hairline),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // Pages are see-through: AppBackground paints the gradient behind them.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: AppColors.surface,
      textTheme: text.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      iconTheme: IconThemeData(color: AppColors.textSecondary),
      // One page moves (fade + short slide): cheapest built-in transition.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FluidPageTransitionsBuilder(),
        TargetPlatform.iOS: FluidPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: AppColors.hairline,
        centerTitle: false,
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: AppText.semibold,
          color: AppColors.textPrimary,
        ),
      ),
      // Cards are glass: translucent fill with a light rim.
      cardTheme: CardThemeData(
        color: AppColors.glassFill,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.shadow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
      ),
      dividerTheme: DividerThemeData(color: AppColors.hairline, thickness: 0.5),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: AppButtons.primary,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand,
          textStyle: const TextStyle(fontWeight: AppText.semibold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brand,
          side: BorderSide(color: AppColors.hairline),
          shape: rounded,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: TextStyle(color: AppColors.textSecondary),
        floatingLabelStyle:
            TextStyle(color: AppColors.brand, fontWeight: AppText.semibold),
        hintStyle: TextStyle(color: AppColors.textTertiary),
        helperStyle: TextStyle(color: AppColors.textSecondary),
        prefixIconColor: AppColors.brand,
        suffixIconColor: AppColors.textSecondary,
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: AppColors.brand, width: 1.6)),
        errorBorder:
            inputBorder.copyWith(borderSide: BorderSide(color: AppColors.red)),
        focusedErrorBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: AppColors.red, width: 1.6)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.brand,
        selectionColor: AppColors.brand.withValues(alpha: 0.25),
        selectionHandleColor: AppColors.brand,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.surface),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.brandSoft,
        side: BorderSide(color: AppColors.hairline),
        labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: AppText.regular,
            color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(AppColors.surface),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.green
                : AppColors.hairline),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: AppColors.brand),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: rounded,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: AppColors.red,
        textColor: Colors.white,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onBrand,
      ),
    );
  }
}

/// Button styles from the ERP UI kit (erp-ui.css .btn-*): 10px corners,
/// semibold labels, flat fills. Pick by meaning, not by colour:
///   primary     main action (Save, Sync, OK)
///   primarySoft secondary action (Add product, Edit)
///   success     filled confirm in green
///   successSoft quiet positive action (Export)
///   danger      filled destructive confirm (Delete)
///   dangerSoft  quiet destructive action (Clear, Logout, Start new)
///   neutral     Cancel / No / Back
class AppButtons {
  AppButtons._();

  /// Every button must stand out from the page behind it, in both themes:
  /// an edge line + a soft drop shadow in the button's own colour. (The old
  /// flat pale fills were almost the same colour as the light page.)
  static ButtonStyle _fill(
    Color bg,
    Color fg, {
    required Color edge,
    Color? glow,
  }) =>
      ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withValues(alpha: 0.5),
        disabledForegroundColor: fg.withValues(alpha: 0.7),
        elevation: 4,
        // Colour-tinted shadow looks lighter than grey and reads as "raised".
        shadowColor:
            (glow ?? edge).withValues(alpha: AppColors.isDark ? 0.60 : 0.50),
        surfaceTintColor: Colors.transparent,
        minimumSize: const Size(64, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(fontSize: 15, fontWeight: AppText.semibold),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(color: edge, width: 1),
        ),
      ).copyWith(
        // No floating shadow on a button that is switched off.
        elevation: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? 0.0 : 4.0),
        // Pressed: sink into the page.
        overlayColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.pressed)
                ? fg.withValues(alpha: 0.12)
                : null),
      );

  /// A pale fill of [tone] over the card colour, strong enough to see.
  static Color _tint(Color tone) =>
      Color.alphaBlend(tone.withValues(alpha: AppColors.isDark ? 0.22 : 0.16),
          AppColors.surface);

  /// Text colour for a pale button: darker than the icon colour in light
  /// mode (the plain green / red are too light to read on a pale fill).
  static Color _ink(Color tone) =>
      AppColors.isDark ? tone : Color.lerp(tone, Colors.black, 0.32)!;

  static ButtonStyle get primary => _fill(
        AppColors.brand,
        AppColors.onBrand,
        edge: AppColors.brandDark,
      );

  static ButtonStyle get primarySoft => _fill(
        _tint(AppColors.brand),
        AppColors.isDark ? AppColors.brandDark : AppColors.brand,
        edge: AppColors.brand.withValues(alpha: 0.55),
        glow: AppColors.brand,
      );

  static ButtonStyle get success => _fill(
        AppColors.solidGood,
        Colors.white,
        edge: Color.lerp(AppColors.solidGood, Colors.black, 0.2)!,
      );

  static ButtonStyle get successSoft => _fill(
        _tint(AppColors.green),
        _ink(AppColors.green),
        edge: AppColors.green.withValues(alpha: 0.6),
        glow: AppColors.green,
      );

  static ButtonStyle get danger => _fill(
        AppColors.solidBad,
        Colors.white,
        edge: Color.lerp(AppColors.solidBad, Colors.black, 0.2)!,
      );

  static ButtonStyle get dangerSoft => _fill(
        _tint(AppColors.red),
        _ink(AppColors.red),
        edge: AppColors.red.withValues(alpha: 0.6),
        glow: AppColors.red,
      );

  /// Cancel / No / Back: a card-coloured button with a clear grey edge.
  static ButtonStyle get neutral => _fill(
        AppColors.surface,
        AppColors.textPrimary,
        edge: AppColors.textSecondary.withValues(alpha: 0.5),
        glow: Colors.black,
      );
}

/// iOS-like page push: the new page glides in from the right while fading,
/// the old page drifts slightly left. Two transforms, no shadows or clips.
class FluidPageTransitionsBuilder extends PageTransitionsBuilder {
  const FluidPageTransitionsBuilder();

  static final _in = Tween(begin: const Offset(0.08, 0), end: Offset.zero);
  static final _out = Tween(begin: Offset.zero, end: const Offset(-0.04, 0));

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final a = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);
    final b =
        CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return SlideTransition(
      position: _out.animate(b),
      child: SlideTransition(
        position: _in.animate(a),
        child: FadeTransition(opacity: a, child: child),
      ),
    );
  }
}
