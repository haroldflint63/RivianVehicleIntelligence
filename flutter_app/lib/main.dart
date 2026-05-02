// ── lib/main.dart ────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/dashboard_screen.dart';
import 'services/websocket_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF060810),
  ));
  // WS endpoint — override at build time:
  //   flutter build web --dart-define=WS_URL=wss://your.onrender.com
  const wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://localhost:8765',
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => WebSocketService(wsUrl),
      child: const RivianApp(),
    ),
  );
}

// ── Rivian Design Tokens ─────────────────────────────────────────────
// Palette tuned to Rivian's actual brand language:
// deep-space backgrounds, warm spring-green primary accent.
abstract class RivianColors {
  // ── Backgrounds (deep space navy) ────────────────────────────────
  static const bg0        = Color(0xFF060810);   // page canvas
  static const bg1        = Color(0xFF0C1018);   // card surface
  static const bg2        = Color(0xFF111827);   // elevated surface
  static const bg3        = Color(0xFF1C2535);   // pressed / hover

  // ── Rivian Spring Green ───────────────────────────────────────────
  // The warm meadow-green seen in Rivian's vehicle HMI & brand identity.
  static const green       = Color(0xFF6BE09B);
  static const greenBright = Color(0xFF9EFFC8);
  static const greenDim    = Color(0xFF0B2018);
  static const greenGlow   = Color(0x556BE09B);

  // ── Status ────────────────────────────────────────────────────────
  static const warning    = Color(0xFFFFB340);   // warm amber
  static const warningDim = Color(0xFF221400);
  static const danger     = Color(0xFFFF453A);   // Apple system red
  static const dangerDim  = Color(0xFF220808);
  static const info       = Color(0xFF60A5FA);   // electric blue
  static const infoDim    = Color(0xFF081428);
  static const purple     = Color(0xFFBF5AF2);   // motor / voltage
  static const purpleDim  = Color(0xFF18082A);
  static const ice        = Color(0xFF70D7F7);   // sub-zero cyan

  // ── Typography ────────────────────────────────────────────────────
  static const textPrimary   = Color(0xFFF0F2F7);
  static const textSecondary = Color(0xFF8896AA);
  static const textTertiary  = Color(0xFF3E4D62);

  // ── Borders ───────────────────────────────────────────────────────
  static const border       = Color(0xFF182030);
  static const borderBright = Color(0xFF253245);
  static const borderGlow   = Color(0x406BE09B);
}

abstract class RivianText {
  static const displayLg = TextStyle(
      fontSize: 44, fontWeight: FontWeight.w800,
      letterSpacing: -2.2, color: RivianColors.textPrimary, height: 1.0);
  static const displayMd = TextStyle(
      fontSize: 30, fontWeight: FontWeight.w700,
      letterSpacing: -1.2, color: RivianColors.textPrimary, height: 1.1);
  static const headingLg = TextStyle(
      fontSize: 19, fontWeight: FontWeight.w700,
      letterSpacing: -0.5, color: RivianColors.textPrimary);
  static const headingMd = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w600,
      letterSpacing: -0.3, color: RivianColors.textPrimary);
  static const bodyLg = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w400,
      color: RivianColors.textPrimary, height: 1.7);
  static const bodySm = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w400,
      color: RivianColors.textSecondary, height: 1.5);
  static const label = TextStyle(
      fontSize: 10, fontWeight: FontWeight.w700,
      letterSpacing: 1.6, color: RivianColors.textTertiary);
  static const caption = TextStyle(
      fontSize: 9, fontWeight: FontWeight.w500,
      letterSpacing: 0.5, color: RivianColors.textTertiary);
}

// ── Shadow / glow presets ────────────────────────────────────────────
abstract class RivianShadows {
  static const card = [
    BoxShadow(
        color: Color(0x28000000),
        blurRadius: 28,
        spreadRadius: -6,
        offset: Offset(0, 10)),
  ];
  static const logo = [
    BoxShadow(
        color: Color(0xA06BE09B),
        blurRadius: 24,
        spreadRadius: -4,
        offset: Offset(0, 6)),
  ];
  static List<BoxShadow> accent(Color c) => [
        BoxShadow(
            color: c.withValues(alpha: 0.28),
            blurRadius: 16,
            spreadRadius: -4,
            offset: const Offset(0, 4)),
      ];
}

// ── App ──────────────────────────────────────────────────────────────
class RivianApp extends StatelessWidget {
  const RivianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rivian Vehicle Intelligence',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: RivianColors.bg0,
        colorScheme: const ColorScheme.dark(
          primary: RivianColors.green,
          secondary: RivianColors.info,
          surface: RivianColors.bg1,
          error: RivianColors.danger,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
