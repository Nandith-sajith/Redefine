import 'dart:async';

import 'package:flutter/material.dart';
import 'package:redefine_ui/redefine_ui.dart';

import '../api.dart';
import '../logic.dart';
import '../widgets.dart';
import 'add_property.dart';
import 'billing_screen.dart';
import 'job_detail.dart';
import 'property_views.dart';

Future<Account> _loadAccount() async {
  late Settings settings;
  late Billing billing;
  await Future.wait([
    api.settings().then((value) => settings = value),
    api.billing().then((value) => billing = value),
  ]);
  return Account(settings: settings, billing: billing);
}

/// The customer's home: their properties as tabs, and under the selected one
/// whatever its state calls for — a quote to wait for or answer, a plough to
/// request, or a job to follow.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final _props = RLiveController<List<Property>>(_loadProperties);
  final _account = RLiveController<Account>(_loadAccount);

  /// How many loads of the properties have been started, and which of them
  /// each loaded list came from: a list from a load that began before an
  /// action here took effect may not include it.
  int _propertyLoads = 0;
  final _loadOf = Expando<int>();

  /// What requesting or cancelling here made of a property's job (by property
  /// id), shown until the properties have been loaded afresh.
  final _jobChanges = <String, JobChange>{};

  /// Past jobs per property, loaded when the property is first selected.
  final _history = <String, RLiveController<List<Job>>>{};

  /// The unfinished job being followed on each property (property id -> job
  /// id), so its ending can be announced.
  var _following = <String, String>{};

  /// Jobs cancelled from this screen, which reported their own ending.
  final _cancelledHere = <String>{};
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _props.addListener(_onProperties);
    _account.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _props
      ..removeListener(_onProperties)
      ..dispose();
    _account.dispose();
    for (final history in _history.values) {
      history.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the window: RLive reloads the properties, this the rest.
    if (state == AppLifecycleState.resumed) _refreshRest();
  }

  Future<List<Property>> _loadProperties() async {
    final load = ++_propertyLoads;
    final properties = await api.properties();
    _loadOf[properties] = load;
    return properties;
  }

  RLiveController<List<Job>> _historyOf(String propertyId) => _history.putIfAbsent(
    propertyId,
    () => RLiveController(() => api.jobs(propertyId: propertyId)),
  );

  /// Loads the selected property's past jobs once it is active; [reload]
  /// also refreshes a list that is already there.
  void _syncHistory({bool reload = false}) {
    final selected = (_props.data ?? const <Property>[]).where((p) => p.id == _selectedId);
    if (selected.isEmpty || selected.first.status != PropertyStatus.active) return;
    final history = _historyOf(selected.first.id);
    if (history.hasData) {
      if (reload) history.refresh(silent: true);
    } else if (!history.loading && (reload || history.error == null)) {
      // A load that failed is retried when the property is opened again.
      history.refresh();
    }
  }

  void _onProperties() {
    final properties = _props.data;
    if (properties == null || !mounted) return;
    // Properties loaded since an action here took effect speak for themselves.
    final load = _loadOf[properties];
    if (load != null) _jobChanges.removeWhere((_, change) => change.knownTo(load));
    final followed = followActiveJobs(_following, properties, _jobChanges);
    setState(() {
      _following = followed.following;
      _selectedId = keepSelection(_selectedId, properties);
    });
    _syncHistory();
    for (final job in followed.ended) {
      if (!_cancelledHere.contains(job.jobId)) _announceEnded(job.propertyId, job.jobId);
    }
  }

  /// A followed job is no longer under way: say how it ended and reload what
  /// it changed.
  Future<void> _announceEnded(String propertyId, String jobId) async {
    _history[propertyId]?.refresh(silent: true);
    _account.refresh(silent: true);
    try {
      final message = jobOutcomeMessage(await api.job(jobId));
      if (mounted && message != null) showRSnack(context, message);
    } on ApiException {
      // The property and its past ploughs already show how it ended.
    }
  }

  void _select(String propertyId) {
    if (propertyId == _selectedId) return;
    setState(() => _selectedId = propertyId);
    _syncHistory(reload: true);
  }

  void _refreshProperties() => _props.refresh(silent: true);

  /// Reloads [controllers] quietly. With [report], for a reload the customer
  /// asked for, a failure that leaves older details on screen is said: they
  /// would otherwise pass for fresh. (A part with nothing to show yet
  /// displays its own error.)
  Future<void> _reload(List<RLiveController<Object?>> controllers, {bool report = false}) async {
    await Future.wait([for (final c in controllers) c.refresh(silent: true)]);
    if (!report || !mounted) return;
    final stale = controllers.where((c) => c.hasData && c.error != null).firstOrNull;
    final error = stale?.error;
    if (error != null) {
      showRSnack(
        context,
        'Some details could not be refreshed. ${friendlyError(error)}',
        error: true,
      );
    }
  }

  /// Reloads what the properties' own refresh leaves out: settings, billing
  /// and the selected property's past ploughs.
  Future<void> _refreshRest({bool report = false}) =>
      _reload([_account, ?_history[_selectedId]], report: report);

  void _refreshAll() {
    _props.refresh();
    _refreshRest(report: true);
  }

  /// Reloads what a request for [propertyId] is priced and paid from (the
  /// property's price, the shovelling price, the card), so that the
  /// confirmation states what the server will charge. Null when there is
  /// nothing to confirm: the reload failed, which is said, or the property can
  /// no longer take a request, which the screen shows from the next frame on.
  Future<RequestTerms?> _requestTerms(String propertyId) async {
    await Future.wait([_account.refresh(silent: true), _props.refresh(silent: true)]);
    final error = _account.error ?? _props.error;
    if (error != null) {
      if (mounted) {
        showRSnack(
          context,
          "Couldn't check the current price. ${friendlyError(error)}",
          error: true,
        );
      }
      return null;
    }
    final account = _account.data;
    final property = _props.data?.where((p) => p.id == propertyId).firstOrNull;
    final price = property?.price;
    if (account == null ||
        property == null ||
        price == null ||
        property.status != PropertyStatus.active ||
        shownJob(property, _jobChanges) != null) {
      return null;
    }
    return (price: price, account: account);
  }

  /// Shows the property as an action just returned it, ahead of the next poll.
  void _replace(Property property) {
    final properties = _props.data;
    if (properties == null) return;
    _props.setData([
      for (final p in properties)
        if (p.id == property.id) property else p,
    ]);
  }

  Future<void> _addProperty() async {
    final created = await Navigator.of(
      context,
    ).push(MaterialPageRoute<Property>(builder: (_) => const AddPropertyScreen()));
    if (created == null || !mounted) return;
    _selectedId = created.id;
    _props.setData([
      for (final p in _props.data ?? const <Property>[])
        if (p.id != created.id) p,
      created,
    ]);
  }

  Future<void> _openBilling() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const BillingScreen()));
    // A card may have been added or replaced there.
    unawaited(_reload([_account], report: true));
  }

  /// A request cannot go ahead for want of a card. When it is the server that
  /// said so, what this screen knows about billing is out of date.
  void _cardRequired() {
    _account.refresh(silent: true);
    if (!mounted) return;
    showRSnack(context, 'Add a card to request a plough.');
    _openBilling();
  }

  void _openJob(Job job) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => JobDetailScreen(jobId: job.id, initial: job),
    ),
  );

  /// Shows what an action here made of the property's job straight from the
  /// action's own result: the reload of the properties that follows can fail.
  void _showJobChange(String propertyId, Job? job) {
    _jobChanges[propertyId] = JobChange(job, afterLoad: _propertyLoads);
    _onProperties();
  }

  void _onRequested(Job job) {
    _showJobChange(job.propertyId, job);
    _props.refresh(silent: true);
  }

  void _onCancelled(Job job) {
    // Announced here, from the result, rather than when the poll notices.
    _cancelledHere.add(job.id);
    _showJobChange(job.propertyId, null);
    final message = jobOutcomeMessage(job);
    if (mounted && message != null) showRSnack(context, message);
    // It is the newest of the property's jobs, so it heads the past ploughs.
    final history = _history[job.propertyId];
    final past = history?.data;
    if (history != null && past != null) {
      history.setData([
        job,
        for (final j in past)
          if (j.id != job.id) j,
      ]);
    }
    history?.refresh(silent: true);
    _account.refresh(silent: true);
    _props.refresh(silent: true);
  }

  Widget _withAccount(Widget Function(Account account) builder) =>
      LiveSection<Account>(controller: _account, builder: (_, account) => builder(account));

  Widget _propertyView(Property property) {
    final price = property.price;
    final job = shownJob(property, _jobChanges);
    return switch (property.status) {
      PropertyStatus.quoteRequested => QuoteWaitingView(property: property),
      PropertyStatus.quoted when price != null => _withAccount(
        (account) => QuoteReceivedView(
          key: ValueKey('quote:${property.id}'),
          property: property,
          price: price,
          account: account,
          onChanged: _replace,
          onRefresh: _refreshProperties,
        ),
      ),
      PropertyStatus.declined => DeclinedView(
        key: ValueKey('declined:${property.id}'),
        property: property,
        onChanged: _replace,
        onRefresh: _refreshProperties,
      ),
      PropertyStatus.active when job != null => JobTrackerCard(
        key: ValueKey('job:${job.id}'),
        job: job,
        onCancelled: _onCancelled,
        onRefresh: _refreshProperties,
      ),
      PropertyStatus.active when price != null => _withAccount(
        (account) => RequestPloughCard(
          key: ValueKey('request:${property.id}'),
          property: property,
          price: price,
          account: account,
          onBeforeRequest: () => _requestTerms(property.id),
          onRequested: _onRequested,
          onOpenBilling: _openBilling,
          onCardRequired: _cardRequired,
          onRefresh: _refreshProperties,
        ),
      ),
      _ => UnavailablePropertyView(onRefresh: _refreshAll),
    };
  }

  Widget _content(BuildContext context, List<Property> properties) {
    final selectedId = keepSelection(_selectedId, properties);
    final selected = properties.where((p) => p.id == selectedId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PropertyTabStrip(
          properties: properties,
          selectedId: selectedId,
          attention: (p) => needsAttention(p, _jobChanges),
          onSelect: _select,
          onAdd: _addProperty,
        ),
        if (selected == null)
          EmptyPropertiesView(onAdd: _addProperty)
        else
          Padding(
            // The strip's scrollbar band is part of the gap above the name.
            padding: const EdgeInsets.fromLTRB(22, 16 - PropertyTabStrip.scrollbarBand, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selected.name, style: RText.h2),
                const SizedBox(height: 2),
                Text(selected.address, style: RText.muted),
                const SizedBox(height: 16),
                _propertyView(selected),
                if (selected.status == PropertyStatus.active) ...[
                  const SizedBox(height: 24),
                  PastPloughs(controller: _historyOf(selected.id), onOpen: _openJob),
                ],
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: RAppHeader(
                actions: [
                  RMenuAction('Billing', Icons.credit_card_outlined, _openBilling),
                  RMenuAction('Refresh', Icons.refresh_rounded, _refreshAll),
                ],
              ),
            ),
            Expanded(
              // RLive's own pull to refresh reloads the properties; this
              // spinner-less one rides along to reload everything else.
              child: RefreshIndicator.noSpinner(
                onRefresh: () => _refreshRest(report: true),
                child: RLive<List<Property>>(
                  controller: _props,
                  pollEvery: propertiesPollInterval(_props.data ?? const [], _jobChanges),
                  builder: _content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
