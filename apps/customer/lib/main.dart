import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'api.dart';
import 'screens/timeline_screen.dart';

void main() => runApp(const CustomerApp());

const _persona = AuthPersona(
  role: 'customer',
  label: 'HOMEOWNER',
  icon: Icons.home_outlined,
  loginSubtitle: 'Sign in to track visits and manage your lawn.',
  signupTitle: 'Create your account',
  signupSubtitle: 'Get a quote and book your first visit.',
  demoEmail: 'sarah.m@gmail.com',
);

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Redefine — Customer',
      debugShowCheckedModeBanner: false,
      theme: redefineTheme(),
      builder: (context, child) => RPhoneFrame(child: child ?? const SizedBox()),
      home: LoginScreen(persona: _persona, api: api, home: (_) => const TimelineScreen()),
    );
  }
}
