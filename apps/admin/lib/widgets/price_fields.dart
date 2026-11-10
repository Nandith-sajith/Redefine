// The two amounts the office sets for a property: what the customer pays per
// plough and what the crew member earns for it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

const maxPrice = 10000;

typedef PricingErrors = ({String? price, String? crewPay});
typedef Pricing = ({int price, int crewPay});

int? _wholeNumber(String text) {
  final trimmed = text.trim();
  return RegExp(r'^\d{1,9}$').hasMatch(trimmed) ? int.parse(trimmed) : null;
}

/// Checks the two fields as typed: whole dollars, price 1..10000 and
/// 0 <= crew pay <= price. A null entry means that field is fine.
PricingErrors validatePricing(String price, String crewPay) {
  const notWhole = 'Use whole dollars, digits only.';
  final priceValue = _wholeNumber(price);
  final crewValue = _wholeNumber(crewPay);

  String? priceError;
  if (price.trim().isEmpty) {
    priceError = 'Enter the price per plough.';
  } else if (priceValue == null) {
    priceError = notWhole;
  } else if (priceValue < 1 || priceValue > maxPrice) {
    priceError = 'Enter a price from ${money(1)} to ${money(maxPrice)}.';
  }

  String? crewError;
  if (crewPay.trim().isEmpty) {
    crewError = 'Enter the crew pay per plough.';
  } else if (crewValue == null) {
    crewError = notWhole;
  } else if (priceError == null && crewValue > priceValue!) {
    crewError = "Crew pay can't be more than the price.";
  }
  return (price: priceError, crewPay: crewError);
}

/// The amounts as numbers, or null while either field is invalid.
Pricing? parsePricing(String price, String crewPay) {
  final errors = validatePricing(price, crewPay);
  if (errors.price != null || errors.crewPay != null) return null;
  return (price: _wholeNumber(price)!, crewPay: _wholeNumber(crewPay)!);
}

/// "Price per plough" and "Crew pay per plough" with live validation and a
/// line saying what is left per plough. The parent owns the controllers and
/// rebuilds on [onChanged].
///
/// Enter in the price field moves on to the crew pay; only Enter in the crew
/// pay field calls [onSubmitted], so the pair is never sent half edited.
class PriceFields extends StatelessWidget {
  const PriceFields({
    super.key,
    required this.price,
    required this.crewPay,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });
  final TextEditingController price, crewPay;
  final bool enabled, autofocus;
  final VoidCallback? onChanged, onSubmitted;

  @override
  Widget build(BuildContext context) {
    final errors = validatePricing(price.text, crewPay.text);
    final pricing = parsePricing(price.text, crewPay.text);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RTextField(
          label: 'Price per plough',
          controller: price,
          prefixText: r'$',
          hint: '0',
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          maxLength: 5,
          enabled: enabled,
          autofocus: autofocus,
          textInputAction: TextInputAction.next,
          // An empty field is not an error until the form is used.
          errorText: price.text.trim().isEmpty ? null : errors.price,
          onChanged: (_) => onChanged?.call(),
        ),
        const SizedBox(height: 12),
        RTextField(
          label: 'Crew pay per plough',
          controller: crewPay,
          prefixText: r'$',
          hint: '0',
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          maxLength: 5,
          enabled: enabled,
          errorText: crewPay.text.trim().isEmpty ? null : errors.crewPay,
          onChanged: (_) => onChanged?.call(),
          onSubmitted: (_) => onSubmitted?.call(),
        ),
        const SizedBox(height: 10),
        Text(
          pricing == null
              ? 'The crew pay comes out of the price. What is left is your margin.'
              : 'Margin: ${money(pricing.price - pricing.crewPay)} per plough',
          style: pricing == null
              ? RText.muted
              : GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: RColors.tealDeep,
                ),
        ),
      ],
    );
  }
}

/// Asks for a new price and crew pay. Resolves to the amounts, or null when
/// cancelled.
Future<Pricing?> showEditPriceDialog(
  BuildContext context, {
  required String title,
  int? initialPrice,
  int? initialCrewPay,
  String? note,
}) => showDialog<Pricing>(
  context: context,
  builder: (_) => _EditPriceDialog(
    title: title,
    initialPrice: initialPrice,
    initialCrewPay: initialCrewPay,
    note: note,
  ),
);

class _EditPriceDialog extends StatefulWidget {
  const _EditPriceDialog({required this.title, this.initialPrice, this.initialCrewPay, this.note});
  final String title;
  final int? initialPrice, initialCrewPay;
  final String? note;

  @override
  State<_EditPriceDialog> createState() => _EditPriceDialogState();
}

class _EditPriceDialogState extends State<_EditPriceDialog> {
  late final _price = TextEditingController(text: widget.initialPrice?.toString() ?? '');
  late final _crewPay = TextEditingController(text: widget.initialCrewPay?.toString() ?? '');

  @override
  void dispose() {
    _price.dispose();
    _crewPay.dispose();
    super.dispose();
  }

  void _save() {
    final pricing = parsePricing(_price.text, _crewPay.text);
    if (pricing != null) Navigator.of(context).pop(pricing);
  }

  @override
  Widget build(BuildContext context) {
    final label = GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600);
    final note = widget.note;
    final valid = parsePricing(_price.text, _crewPay.text) != null;
    return AlertDialog(
      title: Text(widget.title, style: RText.h2),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              PriceFields(
                price: _price,
                crewPay: _crewPay,
                autofocus: true,
                onChanged: () => setState(() {}),
                onSubmitted: _save,
              ),
              if (note != null) ...[
                const SizedBox(height: 10),
                Text(note, style: RText.muted.copyWith(height: 1.4)),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: RColors.ink, textStyle: label),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: valid ? _save : null,
          style: FilledButton.styleFrom(
            backgroundColor: RColors.teal,
            foregroundColor: RColors.white,
            textStyle: label,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
