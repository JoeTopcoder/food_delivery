import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/app_constants.dart';
import '../../../models/catalog/ad_model.dart';
import '../../../providers/auth_user/auth_provider.dart';
import '../../../providers/catalog/ads_provider.dart';
import '../../../providers/auth_user/user_provider.dart';
import '../../../utils/app_theme.dart';

/// "Advertise on HotBite" — restaurant dashboard entry. Three options:
/// upload a finished video ad, upload an image ad, or ask HotBite to produce
/// the ad. Shows the restaurant's requests with live status, quotes to accept,
/// and creatives to approve.
class RestaurantAdsScreen extends ConsumerWidget {
  const RestaurantAdsScreen({super.key});

  String _money(int cents) =>
      '${AppConstants.currencySymbol}${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider);
    final restAsync =
        uid == null ? null : ref.watch(restaurantByOwnerProvider(uid));

    return Scaffold(
      appBar: AppBar(title: const Text('Advertise on HotBite')),
      body: restAsync == null
          ? const Center(child: Text('Sign in as a restaurant to advertise.'))
          : restAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Could not load your restaurant.')),
              data: (rest) {
                if (rest == null) {
                  return const Center(child: Text('No restaurant found for this account.'));
                }
                final reqs = ref.watch(myAdRequestsProvider(rest.id));
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(myAdRequestsProvider(rest.id)),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _OptionCard(
                        icon: Icons.videocam_rounded,
                        title: 'Upload my video ad',
                        sub: 'Your finished promo video for paid placement',
                        onTap: () => _startSelfUpload(context, ref, rest.id, 'self_video'),
                      ),
                      _OptionCard(
                        icon: Icons.image_rounded,
                        title: 'Upload my image ad',
                        sub: 'Your promotional image for paid placement',
                        onTap: () => _startSelfUpload(context, ref, rest.id, 'self_image'),
                      ),
                      _OptionCard(
                        icon: Icons.auto_awesome_rounded,
                        title: 'Let HotBite create my ad',
                        sub: 'Send a brief — HotBite quotes production & optional placement',
                        onTap: () => _startProduce(context, ref, rest.id),
                      ),
                      const SizedBox(height: 16),
                      Text('Your campaigns & requests',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      reqs.when(
                        loading: () => const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator())),
                        error: (_, __) => const Text('Could not load requests.'),
                        data: (list) => list.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text('No ad requests yet.',
                                    style: TextStyle(color: Colors.grey)))
                            : Column(
                                children: list
                                    .map((r) => _RequestTile(request: r, money: _money))
                                    .toList(),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  // ── Self-upload (video / image) ────────────────────────────────────────────
  Future<void> _startSelfUpload(
      BuildContext context, WidgetRef ref, String restaurantId, String kind) async {
    final isVideo = kind == 'self_video';
    final messenger = ScaffoldMessenger.of(context);
    final res = await showModalBottomSheet<_SelfForm>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SelfAdSheet(isVideo: isVideo),
    );
    if (res == null) return;
    try {
      final svc = ref.read(restaurantAdsServiceProvider);
      final reqId = await svc.createRequest(
        restaurantId: restaurantId,
        kind: kind,
        title: res.title,
        headline: res.headline,
        wantsPlacement: true,
        rightsConfirmed: res.rights,
      );
      // pick + upload media
      final picker = ImagePicker();
      final XFile? file = isVideo
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (file == null) {
        messenger.showSnackBar(const SnackBar(content: Text('No file selected — saved as draft.')));
        ref.invalidate(myAdRequestsProvider(restaurantId));
        return;
      }
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last.toLowerCase();
      final contentType = isVideo
          ? (ext == 'mov' ? 'video/quicktime' : ext == 'webm' ? 'video/webm' : 'video/mp4')
          : (ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg');
      await svc.uploadCreative(
        requestId: reqId,
        restaurantId: restaurantId,
        mediaType: isVideo ? 'video' : 'image',
        bytes: bytes,
        contentType: contentType,
        ext: ext,
        rightsConfirmed: res.rights,
      );
      await svc.submitRequest(reqId);
      ref.invalidate(myAdRequestsProvider(restaurantId));
      messenger.showSnackBar(const SnackBar(
          content: Text('Submitted. HotBite will review before it goes live.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  // ── Produce (managed) ───────────────────────────────────────────────────────
  Future<void> _startProduce(BuildContext context, WidgetRef ref, String restaurantId) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await showModalBottomSheet<_ProduceForm>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ProduceSheet(),
    );
    if (res == null) return;
    try {
      final svc = ref.read(restaurantAdsServiceProvider);
      final reqId = await svc.createRequest(
        restaurantId: restaurantId,
        kind: 'produce',
        title: res.title,
        productionBrief: res.brief,
        wantsPlacement: res.wantsPlacement,
      );
      await svc.submitRequest(reqId);
      ref.invalidate(myAdRequestsProvider(restaurantId));
      messenger.showSnackBar(const SnackBar(
          content: Text('Request sent. HotBite will quote production & placement.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not submit: $e')));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  const _OptionCard({required this.icon, required this.title, required this.sub, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
          child: Icon(icon, color: AppTheme.primaryColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _RequestTile extends ConsumerWidget {
  final AdRequest request;
  final String Function(int) money;
  const _RequestTile({required this.request, required this.money});

  Color _statusColor(String s) => switch (s) {
        'approved' => const Color(0xFF16A34A),
        'submitted' || 'in_review' => const Color(0xFFD97706),
        'rejected' => const Color(0xFFDC2626),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ExpansionTile(
        title: Text(request.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(switch (request.kind) {
          'self_video' => 'Your video ad',
          'self_image' => 'Your image ad',
          _ => 'HotBite-produced',
        }),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _statusColor(request.status).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(request.status,
              style: TextStyle(color: _statusColor(request.status), fontWeight: FontWeight.w700, fontSize: 11)),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (request.reviewReason != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Note: ${request.reviewReason}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          _QuotesSection(requestId: request.id, money: money),
          _CreativesSection(requestId: request.id),
        ],
      ),
    );
  }
}

class _QuotesSection extends ConsumerWidget {
  final String requestId;
  final String Function(int) money;
  const _QuotesSection({required this.requestId, required this.money});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotes = ref.watch(adQuotesProvider(requestId));
    return quotes.maybeWhen(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text('Quotes', style: TextStyle(fontWeight: FontWeight.w700)),
            ...list.map((q) {
              final prod = q.items.where((i) => i.kind == 'production').fold<int>(0, (a, b) => a + b.amountCents);
              final place = q.items.where((i) => i.kind == 'placement').fold<int>(0, (a, b) => a + b.amountCents);
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('v${q.version} · ${q.status}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (prod > 0) Text('Production: ${money(prod)}'),
                    if (place > 0) Text('Placement: ${money(place)}'),
                    Text('Total: ${money(q.totalCents)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (q.status == 'issued')
                      Row(children: [
                        TextButton(
                          onPressed: () async {
                            await ref.read(restaurantAdsServiceProvider).respondQuote(q.id, true);
                            ref.invalidate(adQuotesProvider(requestId));
                          },
                          child: const Text('Accept'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await ref.read(restaurantAdsServiceProvider).respondQuote(q.id, false);
                            ref.invalidate(adQuotesProvider(requestId));
                          },
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Decline'),
                        ),
                      ]),
                  ],
                ),
              );
            }),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _CreativesSection extends ConsumerWidget {
  final String requestId;
  const _CreativesSection({required this.requestId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creatives = ref.watch(adCreativesProvider(requestId));
    return creatives.maybeWhen(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text('Creatives', style: TextStyle(fontWeight: FontWeight.w700)),
            ...list.map((c) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(c.isVideo ? Icons.videocam : Icons.image),
                  title: Text('v${c.version} · ${c.mediaType} · ${c.status}'),
                  subtitle: c.processingError != null
                      ? Text(c.processingError!, style: const TextStyle(color: Colors.red, fontSize: 11))
                      : (c.changeNotes != null ? Text('Notes: ${c.changeNotes}', style: const TextStyle(fontSize: 11)) : null),
                  trailing: c.status == 'pending_approval'
                      ? Wrap(spacing: 4, children: [
                          IconButton(
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            tooltip: 'Approve',
                            onPressed: () async {
                              await ref.read(restaurantAdsServiceProvider).decideCreative(c.id, true);
                              ref.invalidate(adCreativesProvider(requestId));
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_note, color: Colors.orange),
                            tooltip: 'Request changes',
                            onPressed: () async {
                              await ref.read(restaurantAdsServiceProvider)
                                  .decideCreative(c.id, false, notes: 'Changes requested');
                              ref.invalidate(adCreativesProvider(requestId));
                            },
                          ),
                        ])
                      : null,
                )),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ── Forms ────────────────────────────────────────────────────────────────────
class _SelfForm {
  final String title;
  final String? headline;
  final bool rights;
  _SelfForm(this.title, this.headline, this.rights);
}

class _SelfAdSheet extends StatefulWidget {
  final bool isVideo;
  const _SelfAdSheet({required this.isVideo});
  @override
  State<_SelfAdSheet> createState() => _SelfAdSheetState();
}

class _SelfAdSheetState extends State<_SelfAdSheet> {
  final _title = TextEditingController();
  final _headline = TextEditingController();
  bool _rights = false;
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _title.dispose();
    _headline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + inset),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.isVideo ? 'Upload a video ad' : 'Upload an image ad',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              widget.isVideo
                  ? 'MP4 / MOV / WebM · up to 50 MB · up to 20 seconds. Placement fees only (unless you request editing).'
                  : 'JPG / PNG / WebP · up to 50 MB. Placement fees only.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Campaign title', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _headline,
              decoration: const InputDecoration(labelText: 'Headline (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _rights,
              onChanged: (v) => setState(() => _rights = v ?? false),
              title: const Text(
                'I confirm I have permission to use this video/image, any music, and the advertised offers.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                onPressed: () {
                  if (!(_form.currentState?.validate() ?? false)) return;
                  if (!_rights) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please confirm you have usage rights.')));
                    return;
                  }
                  Navigator.pop(context,
                      _SelfForm(_title.text.trim(), _headline.text.trim().isEmpty ? null : _headline.text.trim(), _rights));
                },
                child: const Text('Choose file & submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProduceForm {
  final String title;
  final String brief;
  final bool wantsPlacement;
  _ProduceForm(this.title, this.brief, this.wantsPlacement);
}

class _ProduceSheet extends StatefulWidget {
  const _ProduceSheet();
  @override
  State<_ProduceSheet> createState() => _ProduceSheetState();
}

class _ProduceSheetState extends State<_ProduceSheet> {
  final _title = TextEditingController();
  final _brief = TextEditingController();
  bool _placement = true;
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _title.dispose();
    _brief.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + inset),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Let HotBite create my ad',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('HotBite staff produce the ad. You\'ll get a quote for production and, if you want it, placement.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Campaign title', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _brief,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Production brief — dishes/offer to feature, style, call to action',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Tell us what to make' : null,
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _placement,
              onChanged: (v) => setState(() => _placement = v ?? true),
              title: const Text('Also quote me for paid placement on HotBite', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                onPressed: () {
                  if (!(_form.currentState?.validate() ?? false)) return;
                  Navigator.pop(context, _ProduceForm(_title.text.trim(), _brief.text.trim(), _placement));
                },
                child: const Text('Send request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
