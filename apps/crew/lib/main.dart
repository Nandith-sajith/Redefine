import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import 'api.dart';
import 'gate.dart';

void main() => runApp(const CrewApp());

const crewPersona = AuthPersona(
  role: 'crew',
  label: 'CREW',
  icon: Icons.work_outline,
  pillBg: RColors.lime,
  pillFg: RColors.ink,
  loginSubtitle: 'Sign in to pick up plough requests and keep track of your pay.',
  signupTitle: 'Join the crew',
  signupSubtitle:
      'Apply with your details. Once the office approves you, you can accept plough '
      'requests and get paid for every job.',
  demoEmail: 'marcus@redefine.co',
  demoPassword: 'redefine',
  extra: AuthExtraField(
    key: 'phone',
    label: 'Phone number',
    icon: Icons.phone_outlined,
    placeholder: 'So the office can reach you',
  ),
);

class CrewApp extends StatelessWidget {
  const CrewApp({super.key});

  @override
  Widget build(BuildContext context) => RedefineApp(
    title: 'Redefine Snow — Crew',
    persona: crewPersona,
    session: session,
    home: (_) => const CrewGate(),
  );
}
