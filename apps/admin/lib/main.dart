import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'api.dart';
import 'shell.dart';

void main() => runApp(const AdminApp());

const _persona = AuthPersona(
  role: 'admin',
  label: 'ADMIN',
  icon: Icons.shield_outlined,
  loginSubtitle: 'Sign in to run the day — quotes, crews, and the schedule.',
  signupTitle: 'Create your operator account',
  signupSubtitle: 'Set up your business and start taking on customers.',
  demoEmail: 'lia@redefine.co',
  extra: AuthExtraField(
    key: 'business',
    label: 'BUSINESS NAME',
    icon: Icons.business_outlined,
    placeholder: 'Redefine Lawn Care',
  ),
);

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Redefine — Admin',
      debugShowCheckedModeBanner: false,
      theme: redefineTheme(),
      builder: (context, child) => RPhoneFrame(child: child ?? const SizedBox()),
      home: LoginScreen(persona: _persona, api: api, home: (_) => const AdminShell()),
    );
  }
}
