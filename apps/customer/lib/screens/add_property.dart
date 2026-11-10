import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../logic.dart';
import '../widgets.dart';

/// Adds a property, which asks for a quote: pick an illustration, then give
/// the details. Pops with the created [Property].
class AddPropertyScreen extends StatefulWidget {
  const AddPropertyScreen({super.key});

  @override
  State<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends State<AddPropertyScreen> with BusyState {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  final _nameFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _noteFocus = FocusNode();

  String _illustration = kIllustrations.first;

  /// False on the illustration step, true on the details step.
  bool _onDetails = false;
  PropertyFormErrors _errors = const PropertyFormErrors();

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _note.dispose();
    _nameFocus.dispose();
    _addressFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final address = _address.text.trim();
    final note = _note.text.trim();
    final errors = validatePropertyForm(name: name, address: address, note: note);
    setState(() => _errors = errors);
    if (!errors.isEmpty) {
      final invalid = errors.name != null
          ? _nameFocus
          : errors.address != null
          ? _addressFocus
          : _noteFocus;
      invalid.requestFocus();
      return;
    }
    final created = await run(
      () =>
          api.createProperty(name: name, address: address, illustration: _illustration, note: note),
      success: "Quote requested for $name. We'll be in touch.",
    );
    if (created != null && mounted) Navigator.of(context).pop(created.property);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Property>(
      // Back from the details returns to the illustrations first.
      canPop: !_onDetails,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) setState(() => _onDetails = false);
      },
      child: PushedScreen(
        backLabel: _onDetails ? 'Back to illustrations' : 'Back',
        bottom: _onDetails
            ? RPrimaryButton('Request a quote', busy: busy, onPressed: _submit)
            : RPrimaryButton('Continue', onPressed: () => setState(() => _onDetails = true)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
          child: _onDetails ? _details(context) : _picker(),
        ),
      ),
    );
  }

  Widget _stepHeader(String step, String title, String lead) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(step, style: RText.eyebrow),
      const SizedBox(height: 6),
      Text(title, style: RText.h1),
      const SizedBox(height: 6),
      Text(
        lead,
        style: GoogleFonts.plusJakartaSans(fontSize: 13, color: RColors.inkMuted, height: 1.5),
      ),
      const SizedBox(height: 18),
    ],
  );

  Widget _picker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stepHeader(
        'STEP 1 OF 2',
        'Pick an illustration',
        'It helps you spot this property at a glance.',
      ),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: kIllustrations.length,
        itemBuilder: (_, i) {
          final key = kIllustrations[i];
          return _IllustrationTile(
            illustration: key,
            selected: key == _illustration,
            onTap: () => setState(() => _illustration = key),
          );
        },
      ),
    ],
  );

  Widget _details(BuildContext context) {
    final user = SessionScope.of(context).user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(
          'STEP 2 OF 2',
          'Tell us about your driveway',
          "We'll visit, price your driveway and send you a quote. "
              'Nothing is charged until you request a plough.',
        ),
        RTextField(
          label: 'Property name',
          hint: 'What you call this place',
          icon: illustrationIcon(_illustration),
          controller: _name,
          focusNode: _nameFocus,
          maxLength: propertyNameMax,
          autofocus: true,
          enabled: !busy,
          errorText: _errors.name,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _addressFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
        RTextField(
          label: 'Address',
          hint: 'Street address and town',
          icon: Icons.place_outlined,
          controller: _address,
          focusNode: _addressFocus,
          maxLength: propertyAddressMax,
          keyboardType: TextInputType.streetAddress,
          enabled: !busy,
          errorText: _errors.address,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 14),
        RTextField(
          label: 'Notes for the crew (optional)',
          hint: 'e.g. gravel driveway, mind the hedge',
          controller: _note,
          focusNode: _noteFocus,
          maxLines: 3,
          maxLength: propertyNoteMax,
          enabled: !busy,
          errorText: _errors.note,
        ),
        if (user != null) ...[
          const SizedBox(height: 22),
          const RSectionLabel("We'll contact you at"),
          const SizedBox(height: 10),
          _ContactField('Name', user.name),
          _ContactField('Email', user.email),
          if (user.phone.isNotEmpty) _ContactField('Phone', user.phone),
        ],
      ],
    );
  }
}

class _IllustrationTile extends StatelessWidget {
  const _IllustrationTile({
    required this.illustration,
    required this.selected,
    required this.onTap,
  });
  final String illustration;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(12);
    return Semantics(
      button: true,
      selected: selected,
      label: illustration,
      child: Material(
        color: selected ? RColors.tealTint : RColors.paper2,
        borderRadius: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: shape,
                    border: Border.all(
                      color: selected ? RColors.teal : RColors.border,
                      width: selected ? 2 : 0.6,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      illustrationIcon(illustration),
                      size: 46,
                      color: illustrationColor(illustration),
                    ),
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(color: RColors.lime, shape: BoxShape.circle),
                    child: const Icon(Icons.check, size: 12, color: RColors.ink),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One read-only line of the signed-in customer's contact details.
class _ContactField extends StatelessWidget {
  const _ContactField(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: RColors.border, width: 0.6)),
      ),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: RText.eyebrow),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: RColors.ink,
            ),
          ),
        ],
      ),
    ),
  );
}
