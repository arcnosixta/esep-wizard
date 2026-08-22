import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/app_shell.dart';
import 'screens/appraiser_dashboard.dart';
import 'screens/admin_dashboard.dart';
import 'screens/onboarding_screen.dart';
import 'screens/wizard_home_screen.dart';
import 'providers/app_settings.dart';
import 'l10n/app_strings.dart';
import 'models/user_profile.dart';
import 'services/supabase_service.dart';

const supabaseUrl = 'https://rphsqxhwfrkavvxzvnuv.supabase.co';
const supabaseAnonKey =
    'eyJhbG...h_TU';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: kIsWeb ? AuthFlowType.pkce : AuthFlowType.implicit,
    ),
  );

  await appSettings.load();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFFAF8F5),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const EsepApp());
}

final supabase = Supabase.instance.client;

class EsepApp extends StatelessWidget {
  const EsepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
        return MaterialApp(
          title: 'ESEP Wizard',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: appSettings.themeMode,
          themeAnimationDuration: const Duration(milliseconds: 450),
          themeAnimationCurve: Curves.easeInOutCubic,
          locale: appSettings.locale,
          supportedLocales: const [
            Locale('ru'),
            Locale('kk'),
            Locale('en'),
          ],
          localizationsDelegates: const [
            AppStringsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStream;
  UserRole? _userRole;
  bool _loadingRole = false;

  @override
  void initState() {
    super.initState();
    _authStream = Supabase.instance.client.auth.onAuthStateChange;
    _checkCurrentSession();
  }

  Future<void> _checkCurrentSession() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      await _loadRole();
    }
  }

  Future<void> _loadRole() async {
    setState(() => _loadingRole = true);
    try {
      final role = await SupabaseService.getUserRole();
      if (mounted) {
        setState(() {
          _userRole = role;
          _loadingRole = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userRole = UserRole.client;
          _loadingRole = false;
        });
      }
    }
  }

  Widget _buildHomeForRole(UserRole? role, String userId) {
    switch (role) {
      case UserRole.admin:
        return const AdminDashboard();
      case UserRole.appraiser:
        return const AppraiserDashboard();
      case UserRole.client:
      case null:
        // Wizard: новому пользователю — приветствие + «Начать»
        if (!appSettings.onboardingDoneFor(userId)) {
          return OnboardingScreen(
            onDone: () => appSettings.completeOnboarding(userId),
            onSkip: () => appSettings.completeOnboarding(userId, withTour: false),
          );
        }
        // После онбординга — wizard home, а не AppShell
        // При нажатии на Menu (три точки) открывается AppShell или отдельные экраны
        return const WizardHomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStream,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        if (session == null) {
          _userRole = null;
          return const SplashScreen();
        }

        if (_loadingRole) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_userRole == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadRole());
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return _buildHomeForRole(_userRole, session.user.id);
      },
    );
  }
}
