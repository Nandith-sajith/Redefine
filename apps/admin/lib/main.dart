import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'api.dart';
import 'shell.dart';

void main() => runApp(const AdminApp());

const adminPersona = AuthPersona(
  role: 'admin',
  label: 'ADMIN',
  icon: Icons.shield_outlined,
  loginSubtitle: 'Sign in to run the snow operation: quotes, plough jobs, crew and payouts.',
  signupTitle: 'Create an admin account',
  signupSubtitle: 'Admin accounts are by invitation. Enter the invite code you were given.',
  demoEmail: 'lia@redefine.co',
  demoPassword: 'redefine',
  extra: AuthExtraField(
    key: 'inviteCode',
    label: 'INVITE CODE',
    icon: Icons.key_outlined,
    placeholder: 'Your invite code',
  ),
);

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) => RedefineApp(
    title: 'Redefine Snow — Admin',
    persona: adminPersona,
    session: session,
    home: (_) => const AdminShell(),
  );
}
