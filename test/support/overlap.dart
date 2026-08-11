// Finds text that paints on top of other text.
//
// ## Why this exists
//
// The render suite fails on *overflow*, and overflow is the only layout
// mistake Flutter reports on its own. Two widgets drawn over each other is a
// perfectly legal layout: nothing asserts, no yellow stripes, every existing
// test stays green. That is how a SliverAppBar shipped with its TabBar
// painting straight through the chips underneath it — 494 tests passed over
// the top of it.
//
// So this walks the real render tree after a pump and asks the question the
// framework never asks: does any glyph land on any other glyph?
//
// ## What it does to avoid crying wolf
//
//   * **Glyph boxes, not widget boxes.** A centred `Text` in a full-width box
//     is mostly empty space; comparing widget rects would flag neighbours that
//     never touch. `getBoxesForSelection` gives the boxes the glyphs actually
//     occupy, per line.
//   * **Only what is on screen.** Rects are intersected with every clipping
//     ancestor — viewports, ClipRect/RRect/Oval/Path — so a row scrolled out
//     of a list is not a finding.
//   * **Only what is painted.** Skips subtrees under `Offstage`, zero
//     `Opacity`, and the unselected children of an `IndexedStack` — all of
//     which are laid out with real geometry and never drawn.
//   * **Opaque backdrops are not overlaps.** Content scrolling under a sticky
//     bottom bar overlaps it in the tree, but the bar paints a solid surface
//     in between, so nothing is *visibly* on top of anything. If the later-
//     painted text sits inside an ancestor that fills the intersection with an
//     opaque colour, the pair is dropped.
//
// ## What it deliberately cannot see
//
// Paint order is derived from tree order, which is right for Stack, Column,
// Row and slivers but wrong anywhere a render object reorders its children.
// Translucent overlays (a 55% scrim) still count as see-through, which is the
// conservative choice: a label under a scrim is usually a real problem. And
// this says nothing about text over a *photo* — that is the whole visual
// language of the app.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two runs of text whose glyphs land on each other.
class TextOverlap {
  const TextOverlap({
    required this.over,
    required this.under,
    required this.area,
    required this.at,
  });

  /// The text painted on top.
  final String over;

  /// The text it lands on.
  final String under;

  /// Overlapping glyph area, in logical pixels.
  final double area;

  /// Where on screen, for pointing a human at it.
  final Rect at;

  @override
  String toString() => '"${_clip(over)}" paints over "${_clip(under)}" '
      '(${area.round()} px² at ${at.left.round()},${at.top.round()})';

  static String _clip(String s) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= 40 ? one : '${one.substring(0, 39)}…';
  }
}

/// Every visible text-on-text collision in the currently pumped tree.
///
/// [minArea] ignores hairline touches — antialiasing and a 1px descender
/// crossing a divider are not what this is looking for.
List<TextOverlap> findTextOverlaps(WidgetTester tester, {double minArea = 12}) {
  final painted = <_Run>[];

  for (final paragraph in tester.allRenderObjects.whereType<RenderParagraph>()) {
    if (!paragraph.attached || !paragraph.hasSize) continue;
    final plain = paragraph.text.toPlainText();
    if (plain.trim().isEmpty) continue;
    if (_isIconGlyph(plain)) continue;
    if (!_isPainted(paragraph)) continue;

    // Rects are mapped through the full transform, not merely shifted by the
    // origin: a `FittedBox` (the ticket scales the wordmark into one) or a
    // `Transform` changes the *size* a glyph occupies on screen as well as
    // its position. Shifting alone reported the scaled-down wordmark at its
    // unscaled size, which read as a collision with its own tagline.
    final toGlobal = paragraph.getTransformTo(null);
    // A paragraph's own layout box is the ceiling on what it may collide
    // with. Selection boxes come from the font's ascent and descent, which
    // routinely exceed the line height when a style sets `height` tighter
    // than the face's natural leading — and the widget suite runs on a
    // fallback font whose metrics are not the shipped one's. Left unclipped,
    // every stacked pair in a Column reads as an overlap: `FlowWordmark`
    // reported FLOW colliding with OWN THE WIND, which a Column cannot do.
    final own = MatrixUtils.transformRect(
        toGlobal, Offset.zero & paragraph.size);
    final clip = _clipBounds(paragraph);
    final boxes = <Rect>[];
    for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: plain.length))) {
      var rect =
          MatrixUtils.transformRect(toGlobal, box.toRect()).intersect(own);
      if (clip != null) rect = rect.intersect(clip);
      if (rect.width > 0 && rect.height > 0) boxes.add(rect);
    }
    if (boxes.isEmpty) continue;

    // A widget that paints the same string twice in the same place is using a
    // rendering technique, not colliding with itself: `TabBar` stacks a
    // selected-colour copy of every label over the unselected one, and a
    // shadowed title does the same. Collapsing them keeps one real collision
    // from being reported four times.
    final already = painted.any((r) =>
        r.text == plain &&
        r.boxes.length == boxes.length &&
        Iterable<int>.generate(boxes.length)
            .every((i) => _sameRect(r.boxes[i], boxes[i])));
    if (already) continue;

    painted.add(_Run(paragraph, plain, boxes));
  }

  final found = <TextOverlap>[];
  for (var i = 0; i < painted.length; i++) {
    for (var j = i + 1; j < painted.length; j++) {
      final a = painted[i], b = painted[j];
      var area = 0.0;
      Rect? where;
      for (final ra in a.boxes) {
        for (final rb in b.boxes) {
          final hit = ra.intersect(rb);
          if (hit.width <= 0 || hit.height <= 0) continue;
          area += hit.width * hit.height;
          where ??= hit;
        }
      }
      if (where == null || area < minArea) continue;

      final aOnTop = _paintsAfter(a.node, b.node);
      final over = aOnTop ? a : b;
      final under = aOnTop ? b : a;
      if (_hasOpaqueBackdrop(over.node, where, _commonAncestor(a.node, b.node))) {
        continue;
      }
      found.add(TextOverlap(
          over: over.text, under: under.text, area: area, at: where));
    }
  }

  found.sort((x, y) => y.area.compareTo(x.area));
  return found;
}

/// Icons are `RenderParagraph`s too — a Material Symbols codepoint in the
/// private use area. They are excluded: an icon under a label is the app's
/// normal visual language (a count badge on a bell, placeholder art behind a
/// title), so including them would report design as defect. Text over text is
/// the signal that is almost never intentional.
bool _isIconGlyph(String text) {
  final trimmed = text.trim();
  if (trimmed.runes.length != 1) return false;
  final code = trimmed.runes.first;
  return code >= 0xE000 && code <= 0xF8FF;
}

bool _sameRect(Rect a, Rect b) =>
    (a.left - b.left).abs() < 0.5 &&
    (a.top - b.top).abs() < 0.5 &&
    (a.right - b.right).abs() < 0.5 &&
    (a.bottom - b.bottom).abs() < 0.5;

class _Run {
  _Run(this.node, this.text, this.boxes);
  final RenderParagraph node;
  final String text;
  final List<Rect> boxes;
}

// ── visibility ───────────────────────────────────────────────────────────

bool _isPainted(RenderObject node) {
  RenderObject child = node;
  RenderObject? parent = node.parent;
  while (parent != null) {
    if (parent is RenderOpacity && parent.opacity == 0) return false;
    if (parent is RenderAnimatedOpacity && parent.opacity.value == 0) {
      return false;
    }
    if (parent is RenderOffstage && parent.offstage) return false;
    if (parent is RenderIndexedStack) {
      final shown = _indexedChild(parent);
      if (!identical(shown, child)) return false;
    }
    child = parent;
    parent = parent.parent;
  }
  return true;
}

RenderObject? _indexedChild(RenderIndexedStack stack) {
  final index = stack.index;
  if (index == null) return null;
  RenderBox? child = stack.firstChild;
  var i = 0;
  while (child != null && i < index) {
    child = stack.childAfter(child);
    i++;
  }
  return child;
}

/// The intersection of every clipping ancestor's bounds, or null when nothing
/// clips this node.
Rect? _clipBounds(RenderObject node) {
  Rect? bounds;
  RenderObject? parent = node.parent;
  while (parent != null) {
    if (parent is RenderBox && parent.hasSize && _clips(parent)) {
      final rect = _globalRect(parent);
      bounds = bounds == null ? rect : bounds.intersect(rect);
    }
    parent = parent.parent;
  }
  return bounds;
}

/// A box's on-screen rect, through any scale or rotation above it.
Rect _globalRect(RenderBox box) => MatrixUtils.transformRect(
    box.getTransformTo(null), Offset.zero & box.size);

bool _clips(RenderBox box) =>
    box is RenderClipRect ||
    box is RenderClipRRect ||
    box is RenderClipOval ||
    box is RenderClipPath ||
    box is RenderAbstractViewport;

// ── paint order ──────────────────────────────────────────────────────────

List<RenderObject> _ancestry(RenderObject node) {
  final chain = <RenderObject>[node];
  RenderObject? parent = node.parent;
  while (parent != null) {
    chain.add(parent);
    parent = parent.parent;
  }
  return chain.reversed.toList(growable: false);
}

RenderObject? _commonAncestor(RenderObject a, RenderObject b) {
  final ca = _ancestry(a), cb = _ancestry(b);
  RenderObject? shared;
  for (var i = 0; i < ca.length && i < cb.length; i++) {
    if (!identical(ca[i], cb[i])) break;
    shared = ca[i];
  }
  return shared;
}

/// Whether [a] is drawn after — and therefore on top of — [b].
///
/// Children paint in visit order, so the branch that diverges later at the
/// lowest common ancestor is the one on top.
bool _paintsAfter(RenderObject a, RenderObject b) {
  final ca = _ancestry(a), cb = _ancestry(b);
  var i = 0;
  while (i < ca.length && i < cb.length && identical(ca[i], cb[i])) {
    i++;
  }
  if (i == 0) return false;
  if (i >= ca.length) return false; // a is an ancestor of b — b paints later
  if (i >= cb.length) return true;

  final siblings = <RenderObject>[];
  ca[i - 1].visitChildren(siblings.add);
  final ia = siblings.indexWhere((c) => identical(c, ca[i]));
  final ib = siblings.indexWhere((c) => identical(c, cb[i]));
  if (ia < 0 || ib < 0) return false;
  return ia > ib;
}

// ── opaque backdrops ─────────────────────────────────────────────────────

/// Whether the text at [node] sits on something solid that fills [area],
/// which means whatever is underneath is hidden rather than showing through.
bool _hasOpaqueBackdrop(RenderObject node, Rect area, RenderObject? stopAt) {
  RenderObject? parent = node.parent;
  while (parent != null && !identical(parent, stopAt)) {
    if (parent is RenderBox && parent.hasSize && _isOpaque(parent)) {
      final bounds = _globalRect(parent);
      // A shrunk-by-a-hair containment test: floating point on a rect that
      // was itself derived from an intersection.
      if (bounds.inflate(0.5).contains(area.topLeft) &&
          bounds.inflate(0.5).contains(area.bottomRight)) {
        return true;
      }
    }
    parent = parent.parent;
  }
  return false;
}

bool _isOpaque(RenderBox box) {
  if (box is RenderDecoratedBox) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration) {
      final color = decoration.color;
      if (color != null && color.a >= 1) return true;
      final gradient = decoration.gradient;
      if (gradient != null && gradient.colors.every((c) => c.a >= 1)) {
        return true;
      }
    }
  }
  if (box is RenderPhysicalModel) return box.color.a >= 1;
  if (box is RenderPhysicalShape) return box.color.a >= 1;
  // `ColoredBox` renders through a private class, and it is far too common a
  // way to paint a solid background to skip on a technicality.
  if (box.runtimeType.toString() == '_RenderColoredBox') {
    final colored = box as dynamic;
    try {
      return (colored.color as Color).a >= 1;
    } catch (_) {
      return false;
    }
  }
  return false;
}

/// Fails with every collision listed, rather than the first.
void expectNoTextOverlaps(WidgetTester tester, {required String where}) {
  final overlaps = findTextOverlaps(tester);
  if (overlaps.isEmpty) return;
  fail('$where — ${overlaps.length} text overlap'
      '${overlaps.length == 1 ? '' : 's'}:\n'
      '${overlaps.map((o) => '  • $o').join('\n')}');
}
