import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/refs.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/media.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/firestore_paths.dart';
import '../../data/models/app_user.dart';
import '../../data/models/booking.dart';
import '../../data/models/catalogue.dart';
import '../../data/models/social.dart';
import '../../providers/providers.dart';
import '../../services/image_service.dart';
import '../sessions/review_composer.dart';

/// Rider view of an individual trainer (§3.4) — and the trainer's own
/// "public profile" self-view.
class TrainerProfileScreen extends ConsumerWidget {
  const TrainerProfileScreen({super.key, required this.trainerId});

  final String trainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(trainerProfileProvider(trainerId));

    return Scaffold(
      body: AsyncView<AppUser?>(
        value: profile,
        onRetry: () => ref.invalidate(trainerProfileProvider(trainerId)),
        data: (trainer) {
          if (trainer == null) {
            return EmptyView(
              icon: Symbols.person_off_rounded,
              title: 'Trainer not found',
              subtitle: 'This profile may have been removed.',
              action: OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Go back')),
            );
          }
          return _TrainerProfileBody(trainer: trainer);
        },
      ),
    );
  }
}

class _TrainerProfileBody extends ConsumerStatefulWidget {
  const _TrainerProfileBody({required this.trainer});
  final AppUser trainer;

  @override
  ConsumerState<_TrainerProfileBody> createState() =>
      _TrainerProfileBodyState();
}

class _TrainerProfileBodyState extends ConsumerState<_TrainerProfileBody> {
  final _page = PageController();
  int _pageIndex = 0;

  /// Checked before render, not just on submit (§3.4, §8.9).
  Booking? _reviewableBooking;
  bool _reviewEligibilityChecked = false;

  @override
  void initState() {
    super.initState();
    _checkReviewEligibility();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _checkReviewEligibility() async {
    final session = ref.read(sessionProvider);
    if (session.isTrainer || session.uid == widget.trainer.uid) {
      setState(() => _reviewEligibilityChecked = true);
      return;
    }
    try {
      final booking = await ref
          .read(reviewRepositoryProvider)
          .findReviewableBooking(
              trainerId: widget.trainer.uid, riderId: session.uid);
      if (mounted) {
        setState(() {
          _reviewableBooking = booking;
          _reviewEligibilityChecked = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _reviewEligibilityChecked = true);
    }
  }

  List<String> get _images => [
        if (widget.trainer.photoUrl != null) widget.trainer.photoUrl!,
        ...widget.trainer.gallery,
      ];

  @override
  Widget build(BuildContext context) {
    final trainer = widget.trainer;
    final session = ref.watch(sessionProvider);
    final isSelf = session.uid == trainer.uid;
    final tones = context.tones;
    final reviews = ref.watch(trainerReviewsProvider(trainer.uid));
    final rating = RatingSummary.from(reviews.value ?? const []);
    final me = ref.watch(currentUserProvider).value;
    final isFav = me?.favorites.contains(trainer.uid) ?? false;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 320,
                leading: ScrimIconButton(
                  icon: Symbols.arrow_back_rounded,
                  tooltip: 'Back',
                  onTap: () => context.pop(),
                ),
                actions: [
                  if (!isSelf) ...[
                    ScrimIconButton(
                      icon: Symbols.favorite_rounded,
                      // Fill is the state carrier; the red is reinforcement.
                      fill: isFav ? 1 : 0,
                      tooltip: isFav
                          ? 'Remove from favourites'
                          : 'Add to favourites',
                      color: isFav ? const Color(0xFFFF5D72) : null,
                      onTap: me == null
                          ? null
                          : () {
                              Haptics.light();
                              ref
                                  .read(userRepositoryProvider)
                                  .setFavorite(me.uid, trainer.uid, !isFav)
                                  .ignore();
                            },
                    ),
                    ScrimIconButton(
                      icon: Symbols.flag_rounded,
                      tooltip: 'Report trainer',
                      onTap: () => _openReportSheet(context, trainer),
                    ),
                  ],
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _GalleryHeader(
                    images: _images,
                    controller: _page,
                    pageIndex: _pageIndex,
                    onPageChanged: (i) => setState(() => _pageIndex = i),
                    onTap: () => _openViewer(context),
                    badge: _CertBadge(label: _certLabel(trainer.ikoId)),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isSelf)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TagPill('YOUR PUBLIC PROFILE',
                              icon: Symbols.visibility_rounded),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(trainer.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .displaySmall),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: 'Verified trainer',
                                  child: Icon(Symbols.verified_rounded,
                                      fill: 1, color: tones.azureBrand, size: 24),
                                ),
                              ],
                            ),
                          ),
                          // Capped and scaled down, so the rate cannot take
                          // the width the name needs. Unbounded, `EGP 550`
                          // claims ~100px of a 320px header and pushes the
                          // surname past the line, where Flutter breaks it
                          // mid-word — `Bergströ` over a lone `m`.
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 96),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(money(trainer.displayRate),
                                      style: display(24, 760,
                                          color: tones.azureBrand,
                                          spacing: -.5)),
                                  Text('per hour',
                                      style: inter(11.5, 560,
                                          color: tones.textFaint)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Stars(value: rating.average, size: 17),
                          const SizedBox(width: 8),
                          Text(rating.display,
                              style: interNum(14, 720,
                                  color: context.scheme.onSurface)),
                          Flexible(
                            child: Text(
                              '  ·  ${rating.count} review${rating.count == 1 ? '' : 's'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: inter(14, 480, color: tones.textFaint),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // Certification used to sit here, level with the place
                      // name — the same weight for "is this person qualified"
                      // as for "where are they". It floats on the photo now,
                      // which leaves Location the tile it always wanted: one
                      // that fits a real spot name without ellipsing it.
                      InfoTile(
                        icon: Symbols.place_rounded,
                        label: 'Location',
                        value: trainer.location ?? 'Red Sea',
                        onTap: trainer.mapsLink == null
                            ? null
                            : () => launchUrl(Uri.parse(trainer.mapsLink!),
                                mode: LaunchMode.externalApplication),
                      ),
                      if ((trainer.bio ?? '').isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const SectionHeader('About'),
                        Text(trainer.bio!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge!
                                .copyWith(height: 1.55)),
                      ],
                      if (trainer.languages.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const SectionHeader('Speaks'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final lang in trainer.languages)
                              TagPill(lang, icon: Symbols.language_rounded),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ReviewsSection(
                    trainer: trainer,
                    reviews: reviews,
                    reviewableBooking:
                        _reviewEligibilityChecked ? _reviewableBooking : null,
                    onReviewed: () {
                      setState(() => _reviewableBooking = null);
                      _checkReviewEligibility();
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
        _BottomBar(trainer: trainer, isSelf: isSelf),
      ],
    );
  }

  void _openViewer(BuildContext context) =>
      showFullScreenImages(context, _images, initialIndex: _pageIndex,
          maxScale: 4);

  /// Reason (fixed list) + free-text details + optional screenshots (§3.4).
  /// A session with this trainer can be attached, stamping the report with
  /// the `FLW-…` reference the console can search.
  void _openReportSheet(BuildContext context, AppUser trainer) {
    String? reason;
    final details = TextEditingController();
    final shots = <XFile>[];
    var busy = false;
    Booking? about;

    showFlowSheet<void>(
      context,
      title: 'Report ${trainer.name}',
      subtitle: 'Our moderation team reviews every report.',
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in FlowConst.reportReasons)
                  FlowChoiceChip(
                    label: r,
                    selected: reason == r,
                    onTap: () {
                      Haptics.select();
                      setSheet(() => reason = r);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: details,
              maxLines: 4,
              enabled: !busy,
              decoration:
                  const InputDecoration(hintText: 'What happened? (optional)'),
            ),
            // The complaint's session, when it is about one — only sessions
            // with this trainer are offered, and none is required.
            Consumer(builder: (context, ref, _) {
              final mine =
                  ref.watch(riderBookingsProvider).value ?? const <Booking>[];
              final withThem = [
                for (final b in mine)
                  if (b.instructorId == trainer.uid) b
              ];
              if (withThem.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  Text('ABOUT A SESSION? — OPTIONAL',
                      style: microLabel(context.tones.textFaint, size: 10)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in withThem.take(6))
                        FlowChoiceChip(
                          label: '${prettyYmd(b.date)} · ${b.timeRange}',
                          selected: about?.id == b.id,
                          onTap: busy
                              ? () {}
                              : () {
                                  Haptics.select();
                                  setSheet(() =>
                                      about = about?.id == b.id ? null : b);
                                },
                        ),
                    ],
                  ),
                ],
              );
            }),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final picked = await ImageService.pickMulti();
                      if (picked.isNotEmpty) {
                        setSheet(() => shots.addAll(picked));
                      }
                    },
              icon: const Icon(Symbols.attach_file_rounded, size: 20),
              label: Text(shots.isEmpty
                  ? 'Attach screenshots (optional)'
                  : '${shots.length} attachment${shots.length == 1 ? '' : 's'}'),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Submit report',
              destructive: true,
              busy: busy,
              // Submit disabled until a reason is chosen (§9.7).
              onPressed: reason == null
                  ? null
                  : () async {
                      setSheet(() => busy = true);
                      try {
                        final session = ref.read(sessionProvider);
                        final urls = await ref
                            .read(storageRepositoryProvider)
                            .uploadAll(
                                folder: StorageFolder.reports,
                                files: shots,
                                ownerId: session.uid);
                        await ref.read(supportRepositoryProvider).reportUser(
                              reporterId: session.uid,
                              reporterName: session.displayName,
                              reportedUserId: trainer.uid,
                              reportedUserName: trainer.name,
                              reason: reason!,
                              details: details.text,
                              attachments: urls,
                              sessionId: about?.id,
                              sessionRef: about == null
                                  ? null
                                  : sessionRef(about!.id, about!.date),
                            );
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                          showFlowToast(context,
                              'Report sent. Thanks for keeping FLOW safe.');
                        }
                      } catch (e) {
                        if (sheetContext.mounted) {
                          setSheet(() => busy = false);
                          showFlowToast(sheetContext,
                              "Couldn't send the report. ${ErrorView.friendly(e)}");
                        }
                      }
                    },
            ),
          ],
        ),
      ),
      // Sheet-scoped, but still a ChangeNotifier that needs releasing.
    ).whenComplete(details.dispose);
  }
}

class _GalleryHeader extends StatelessWidget {
  const _GalleryHeader({
    required this.images,
    required this.controller,
    required this.pageIndex,
    required this.onPageChanged,
    required this.onTap,
    this.badge,
  });

  final List<String> images;
  final PageController controller;
  final int pageIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTap;

  /// Floated bottom-left over the photo. Null shows nothing.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    // The no-photo case used to return early, straight out of this method —
    // which meant the credential badge below was never built for a trainer
    // with an empty gallery. That is not an edge case while Storage is
    // unprovisioned: it is every trainer in the app. The empty state is now a
    // layer in the same stack, so anything floated over the photo is floated
    // over the placeholder too.
    final empty = images.isEmpty;

    return GestureDetector(
      onTap: empty ? null : onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (empty)
            const FlowImage(url: null, height: double.infinity)
          else
            PageView.builder(
              controller: controller,
              onPageChanged: (i) {
                Haptics.select();
                onPageChanged(i);
              },
              itemCount: images.length,
              itemBuilder: (_, i) => FlowImage(url: images[i]),
            ),
          // Bottom gradient so the page dots always read.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 70,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: .45),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (images.length > 1)
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: PageDots(
                count: images.length,
                index: pageIndex,
                activeColor: Colors.white,
                inactiveColor: Colors.white.withValues(alpha: .5),
              ),
            ),
          // Sits above the dots rather than beside them: centred dots and a
          // left-aligned badge collide on a narrow phone at the moment the
          // credential gets long, which is exactly when it matters.
          if (badge != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: images.length > 1 ? 42 : 16,
              child: Align(alignment: Alignment.centerLeft, child: badge!),
            ),
        ],
      ),
    );
  }
}

/// The credential as a label, without saying IKO twice.
///
/// `ikoId` is stored with its issuer prefix already on it (`IKO-0ZMVF2`), and
/// both this badge and the fact tile it replaced prepended another — the hero
/// read "IKO IKO-0ZMVF2". Checked rather than assumed, because nothing
/// guarantees the prefix: an id entered without it still gets one.
String _certLabel(String? ikoId) {
  final id = ikoId?.trim();
  if (id == null || id.isEmpty) return 'VERIFIED TRAINER';
  return ikoLabel(id);
}

/// Prefixes an issuer id that has not already got one.
///
/// Public because the admin console shows the same credential on an
/// applicant card and was building the string by hand — every applicant read
/// `IKO IKO-4471PQ`, which is the exact defect the badge above documents.
String ikoLabel(String id) =>
    id.toUpperCase().startsWith('IKO') ? id : 'IKO $id';

/// The trainer's credential, floated over their photo.
///
/// It was a tile in the fact grid below, level with "Location" — which is to
/// say the one thing a rider is trying to establish about a stranger they are
/// about to get in the water with had the same weight as a place name. On the
/// photo it is the first thing read.
///
/// Fixed dark colours: this is one of the documented exceptions, a surface
/// that sits over a photograph in both themes.
class _CertBadge extends StatelessWidget {
  const _CertBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: FlowRadii.pill,
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.workspace_premium_rounded,
                size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: inter(11.5, 700, color: Colors.white, spacing: .4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewsSection extends ConsumerWidget {
  const _ReviewsSection({
    required this.trainer,
    required this.reviews,
    required this.reviewableBooking,
    required this.onReviewed,
  });

  final AppUser trainer;
  final AsyncValue<List<Review>> reviews;
  final Booking? reviewableBooking;
  final VoidCallback onReviewed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Reviews'),
        if (reviewableBooking != null) ...[
          ReviewComposerCard(
            trainerId: trainer.uid,
            bookingId: reviewableBooking!.id,
            onSubmitted: onReviewed,
          ),
          const SizedBox(height: 14),
        ],
        switch (reviews) {
          AsyncValue(hasValue: true, value: final list?) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No reviews yet — be the first after your session.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : Column(
                  children: [
                    for (final r in list)
                      _ReviewTile(
                        review: r,
                        canDelete: r.userId == session.uid,
                        onDelete: () async {
                          final ok = await confirmAction(
                            context,
                            title: 'Delete your review?',
                            body: 'This removes your rating and comment.',
                            confirmLabel: 'Delete',
                            destructive: true,
                          );
                          if (!ok) return;
                          try {
                            await ref
                                .read(reviewRepositoryProvider)
                                .delete(r.id);
                          } catch (_) {
                            if (context.mounted) {
                              showFlowToast(context,
                                  "Couldn't delete your review. Try again.");
                            }
                            return;
                          }
                          // Two async gaps sit between the tap and here, and
                          // onReviewed() drives setState on the parent — a
                          // rider who backs out to Explore while the delete
                          // is in flight would hit "setState() called after
                          // dispose()".
                          if (context.mounted) onReviewed();
                        },
                      ),
                  ],
                ),
          AsyncValue(hasError: true) => Text(
              "Couldn't load reviews.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SkeletonCard(height: 72),
            ),
        },
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.review,
    required this.canDelete,
    required this.onDelete,
  });

  final Review review;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return FlowCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FlowAvatar(name: review.userName, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.userName,
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(timeAgo(review.createdAt),
                        style: inter(11.5, 480, color: tones.textFaint)),
                  ],
                ),
              ),
              Stars(value: review.rating.toDouble(), size: 14),
              if (canDelete)
                IconButton(
                  onPressed: onDelete,
                  tooltip: 'Delete review',
                  iconSize: 18,
                  icon: const Icon(Symbols.delete_outline_rounded),
                ),
            ],
          ),
          if ((review.comment ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(review.comment!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(height: 1.5)),
          ],
        ],
      ),
    );
  }
}

/// Sticky bottom bar: rate · Message · Book now — or Edit profile when the
/// viewer *is* this trainer (§3.4).
class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.trainer, required this.isSelf});

  final AppUser trainer;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    return StickyBar(
      child: isSelf
          ? PrimaryButton(
              label: 'Edit profile',
              icon: Symbols.edit_rounded,
              onPressed: () => context.push('/profile/edit'),
            )
          // The price shrinks rather than pushes, and Message is icon-only.
          //
          // `EGP 1,200` is roughly twice as wide as the `€65` this bar was
          // laid out for. Flexing all three children stopped the overflow but
          // bought something worse: the Message label wrapped to `Mes/sag/e`,
          // one glyph on the last line. That is legal layout, so no overflow
          // assertion could ever see it — only rendering the screen does.
          // There is no room for a price and two labelled buttons at 360px,
          // let alone 320px at 1.3x, so the secondary action gives up its
          // label and keeps its 48dp target and its name for screen readers.
          : Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 92),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(money(trainer.displayRate),
                            style: display(20, 760, color: tones.azureBrand)),
                        Text('per hour',
                            style: inter(11.5, 540, color: tones.textFaint)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.outlined(
                    onPressed: () {
                      final session = ref.read(sessionProvider);
                      ref.read(chatRepositoryProvider).openThread(
                            me: session.uid,
                            myName: session.displayName,
                            partnerId: trainer.uid,
                            partnerName: trainer.name,
                          );
                      context.push(
                          '/chat/${trainer.uid}?name=${Uri.encodeComponent(trainer.name)}');
                    },
                    tooltip: 'Message',
                    icon: const Icon(Symbols.chat_bubble_outline_rounded,
                        size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    label: 'Book now',
                    expand: true,
                    onPressed: () => context.push(
                      '/book/${trainer.uid}',
                      extra: BookingTarget(
                        providerId: trainer.uid,
                        title: trainer.name,
                        rate: trainer.displayRate,
                        subtitle: trainer.location,
                        imageUrl: trainer.photoUrl,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
