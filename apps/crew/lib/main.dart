import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'api.dart';
import 'shell.dart';

void main() => runApp(const CrewApp());

const _persona = AuthPersona(
  role: 'crew',
  label: 'CREW',
  icon: Icons.work_outline,
  pillBg: RColors.lime,
  pillFg: RColors.ink,
  loginSubtitle: "Sign in to see today's jobs and pick up your pay.",
  signupTitle: 'Join the crew',
  signupSubtitle: 'Create your account to claim jobs and get paid.',
  demoEmail: 'marcus@redefine.co',
  extra: AuthExtraField(
    key: 'phone',
    label: 'PHONE NUMBER',
    icon: Icons.phone_outlined,
    placeholder: '(807) 555-0111',
  ),
);

class CrewApp extends StatelessWidget {
  const CrewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Redefine — Crew',
      debugShowCheckedModeBanner: false,
      theme: redefineTheme(),
      builder: (context, child) => RPhoneFrame(child: child ?? const SizedBox()),
      home: LoginScreen(persona: _persona, api: api, home: (_) => const CrewShell()),
    );
  }
}
