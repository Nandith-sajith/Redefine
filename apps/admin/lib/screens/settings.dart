import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../widgets/common.dart';

const maxShovelPrice = 1000;
const maxExpiryHours = 120;

typedef SettingsErrors = ({String? shovelPrice, String? crewShovelBonus, String? expiryHours});
typedef SettingsValues = ({int shovelPrice, int crewShovelBonus, int expiryHours});

int? _wholeNumber(String text) {
  final trimmed = text.trim();
  return RegExp(r'^\d{1,9}$').hasMatch(trimmed) ? int.parse(trimmed) : null;
}

/// Checks the three fields as typed: whole numbers, shovelling price
/// 0..1000, 0 <= crew bonus <= shovelling price, expiry 1..120 hours.
SettingsErrors validateSettings(String shovelPrice, String crewShovelBonus, String expiryHours) {
  const notWhole = 'Use a whole number, digits only.';
  final price = _wholeNumber(shovelPrice);
  final bonus = _wholeNumber(crewShovelBonus);
  final hours = _wholeNumber(expiryHours);

  String? priceError;
  if (shovelPrice.trim().isEmpty) {
    priceError = 'Enter the shovelling price.';
  } else if (price == null) {
    priceError = notWhole;
  } else if (price > maxShovelPrice) {
    priceError = 'Enter at most ${money(maxShovelPrice)}.';
  }

  String? bonusError;
  if (crewShovelBonus.trim().isEmpty) {
    bonusError = 'Enter the crew bonus.';
  } else if (bonus == null) {
    bonusError = notWhole;
  } else if (priceError == null && bonus > price!) {
    bonusError = "The bonus can't be more than the shovelling price.";
  }

  String? hoursError;
  if (expiryHours.trim().isEmpty) {
    hoursError = 'Enter a number of hours.';
  } else if (hours == null) {
    hoursError = notWhole;
  } else if (hours < 1 || hours > maxExpiryHours) {
    hoursError = 'Enter 1 to $maxExpiryHours hours.';
  }
  return (shovelPrice: priceError, crewShovelBonus: bonusError, expiryHours: hoursError);
}

/// The fields as numbers, or null while any of them is invalid.
SettingsValues? parseSettings(String shovelPrice, String crewShovelBonus, String expiryHours) {
  final errors = validateSettings(shovelPrice, crewShovelBonus, expiryHours);
  if (errors.shovelPrice != null || errors.crewShovelBonus != null || errors.expiryHours != null) {
    return null;
  }
  return (
    shovelPrice: _wholeNumber(shovelPrice)!,
    crewShovelBonus: _wholeNumber(crewShovelBonus)!,
    expiryHours: _wholeNumber(expiryHours)!,
  );
}

/// The business-wide numbers: shovelling price and crew bonus, and how long
/// a request may wait for a crew member. Opened from the account menu.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with BusyState<SettingsScreen> {
  late final RLiveController<Settings> _settings = RLiveController(_load);
  final _shovelPrice = TextEditingController();
  final _crewBonus = TextEditingController();
  final _expiryHours = TextEditingController();
  bool _prefilled = false;

  @override
  void dispose() {
    _settings.dispose();
    _shovelPrice.dispose();
    _crewBonus.dispose();
    _expiryHours.dispose();
    super.dispose();
  }

  Future<Settings> _load() async {
    final settings = await api.settings();
    // Only the first load fills the form: a later refresh must not overwrite
    // what is being typed.
    if (mounted && !_prefilled) {
      _prefilled = true;
      _fill(settings);
    }
    return settings;
  }

  void _fill(Settings settings) {
    _shovelPrice.text = '${settings.shovelPrice}';
    _crewBonus.text = '${settings.crewShovelBonus}';
    _expiryHours.text = '${settings.openJobExpiryHours}';
  }

  Future<void> _save() async {
    final values = parseSettings(_shovelPrice.text, _crewBonus.text, _expiryHours.text);
    if (values == null) return;
    final saved = await run(
      () => api.updateSettings(
        shovelPrice: values.shovelPrice,
        crewShovelBonus: values.crewShovelBonus,
        openJobExpiryHours: values.expiryHours,
      ),
      success: 'Settings saved',
    );
    if (saved == null || !mounted) return;
    _fill(saved);
    _settings.setData(saved);
  }

  @override
  Widget build(BuildContext context) => PushedPage(
    child: RLive<Settings>(
      controller: _settings,
      padding: pagePadding,
      builder: (context, settings) => _body(settings),
    ),
  );

  Widget _body(Settings saved) {
    final errors = validateSettings(_shovelPrice.text, _crewBonus.text, _expiryHours.text);
    final values = parseSettings(_shovelPrice.text, _crewBonus.text, _expiryHours.text);
    final dirty =
        values == null ||
        values.shovelPrice != saved.shovelPrice ||
        values.crewShovelBonus != saved.crewShovelBonus ||
        values.expiryHours != saved.openJobExpiryHours;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    void changed(String _) => setState(() {});
    void submit(String _) {
      if (values != null && dirty) _save();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Settings', style: RText.h1),
        const SizedBox(height: 4),
        Text('Changes apply to requests made from now on.', style: RText.muted),
        const SizedBox(height: 18),
        const RSectionLabel('Shovelling'),
        const SizedBox(height: 8),
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RTextField(
                label: 'Shovelling price',
                controller: _shovelPrice,
                prefixText: r'$',
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                maxLength: 4,
                enabled: !busy,
                errorText: errors.shovelPrice,
                onChanged: changed,
                onSubmitted: submit,
              ),
              const SizedBox(height: 6),
              Text(
                "Added to the customer's total when they ask for walkways and steps.",
                style: RText.muted,
              ),
              const SizedBox(height: 14),
              RTextField(
                label: 'Crew shovelling bonus',
                controller: _crewBonus,
                prefixText: r'$',
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                maxLength: 4,
                enabled: !busy,
                errorText: errors.crewShovelBonus,
                onChanged: changed,
                onSubmitted: submit,
              ),
              const SizedBox(height: 6),
              Text(
                'Added to the crew pay for a job with shovelling. At most the shovelling price.',
                style: RText.muted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const RSectionLabel('Open requests'),
        const SizedBox(height: 8),
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RTextField(
                label: 'Expiry, in hours',
                controller: _expiryHours,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                maxLength: 3,
                enabled: !busy,
                errorText: errors.expiryHours,
                onChanged: changed,
                onSubmitted: submit,
              ),
              const SizedBox(height: 6),
              Text(
                'A request no crew member accepts within this time is cancelled and any '
                'card hold released.',
                style: RText.muted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const RSectionLabel('Payments'),
        const SizedBox(height: 8),
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (saved.paymentsMode) {
                PaymentMode.stripe => 'Stripe',
                PaymentMode.manual => 'Manual — no Stripe key configured',
                PaymentMode.unknown => 'Unknown',
              }, style: RText.title),
              const SizedBox(height: 4),
              Text(switch (saved.paymentsMode) {
                PaymentMode.stripe =>
                  'Customers save a card. A hold is placed when they request a plough and '
                      'charged when the job is done.',
                PaymentMode.manual =>
                  'A finished job becomes due. Mark it paid from the job page once the '
                      'customer has paid you.',
                PaymentMode.unknown => 'The server did not say how payments are taken.',
              }, style: RText.muted.copyWith(height: 1.45)),
              const SizedBox(height: 4),
              Text('Set on the server, not in this app.', style: RText.muted),
            ],
          ),
        ),
        const SizedBox(height: 22),
        RPrimaryButton(
          'Save settings',
          busy: busy,
          onPressed: values != null && dirty ? _save : null,
        ),
      ],
    );
  }
}
