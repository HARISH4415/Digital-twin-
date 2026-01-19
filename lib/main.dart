import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scalptamizhan/login.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (Use your actual credentials)
  await Supabase.initialize(
    url: 'https://ozalojrqwsedbvyjszrl.supabase.co',
    anonKey: 'sb_publishable_btA4SeUZQue-fSS5C0BjcQ_EvRWcw-c',
  );


  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital Twin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light, 
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      // Instead of HomeScreen, we point to the AuthGate
      home: const AuthGate(),
    );
  }
}

// --- AUTH GATE ---
// Listens to auth state and switches pages automatically
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // 1. Loading State
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 2. Check Session
        final session = snapshot.hasData ? snapshot.data!.session : null;

        if (session != null) {
          // USER IS LOGGED IN -> Show Dashboard
          // We wrap HomeScreen in the Provider here so it's only created when logged in
          return ChangeNotifierProvider(
            create: (context) => TwinProvider()..fetchLogs(),
            child: const HomeScreen(),
          );
        } else {
          // USER IS LOGGED OUT -> Show Login Page
          return const LoginPage();
        }
      },
    );
  }
}