import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'api.dart';
import 'screens/home_screen.dart';

void main() => runApp(const CustomerApp());

const customerPersona = AuthPersona(
  role: 'customer',
  label: 'HOMEOWNER',
  icon: Icons.home_outlined,
  loginSubtitle: 'Request a plough when it snows.',
  signupTitle: 'Create your account',
  signupSubtitle: 'Add your driveway, get a price, then request a plough whenever it snows.',
  demoEmail: 'sarah.m@gmail.com',
  demoPassword: 'redefine',
  extra: AuthExtraField(
    key: 'phone',
    label: 'Phone (optional)',
    icon: Icons.phone_outlined,
    placeholder: 'So the crew can reach you',
  ),
);

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) => RedefineApp(
    title: 'Redefine Snow — Customer',
    persona: customerPersona,
    session: session,
    home: (_) => const HomeScreen(),
  );
}
