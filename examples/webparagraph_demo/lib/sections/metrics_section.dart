import 'package:flutter/material.dart';

class MetricsSection extends StatefulWidget {
  const MetricsSection({super.key});

  @override
  State<MetricsSection> createState() => _MetricsSectionState();
}

class _MetricsSectionState extends State<MetricsSection> {
  bool _showXRay = true;
  double _fontSize = 32.0;
  String _text = 'Precision layout via Chromium Text Clusters API. 👨‍👩‍👧‍👦';

  Offset? _hoverOffset;
  int? _lockedClusterIndex;
  int? _hoveredClusterIndex;

  // Active clusters computed during paint to share with the HUD
  List<_ClusterInfo> _clusters = [];

  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: _text);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  static const List<(String, String)> _presets = [
    ('English', 'Precision layout via Chromium Text Clusters API.'),
    ('Arabic Ligature', 'الجمهورية العربية السورية'),
    ('Devanagari', 'नमस्ते दोस्तो'),
    ('Tamil Script', 'தமிழ்நாடு'),
    ('ZWJ Emojis', '👨‍👩‍👧‍👦 👩‍❤️‍👨 🏳️‍🌈 🏃‍♀️'),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 1000;

    // Find the active cluster to display in the HUD
    _ClusterInfo? activeCluster;
    final activeIndex = _lockedClusterIndex ?? _hoveredClusterIndex;
    if (activeIndex != null &&
        activeIndex >= 0 &&
        activeIndex < _clusters.length) {
      activeCluster = _clusters[activeIndex];
    }

    final mainContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Description
        const Text(
          'METRICS X-RAY HUD',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.cyan,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Hover over the glyphs to inspect precise boundaries, sub-pixel alignments, and the underlying Unicode code points that compose each text cluster. Click a cluster to lock the inspector.',
          style: TextStyle(color: Colors.white70, height: 1.5, fontSize: 14),
        ),
        const SizedBox(height: 24),

        // Interactive Text Canvas Area
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0E12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _lockedClusterIndex != null
                  ? Colors.cyan.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              if (_lockedClusterIndex != null)
                BoxShadow(
                  color: Colors.cyan.withValues(alpha: 0.05),
                  blurRadius: 15,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return MouseRegion(
                  onHover: (event) {
                    setState(() {
                      _hoverOffset = event.localPosition;
                    });
                  },
                  onExit: (_) {
                    setState(() {
                      _hoverOffset = null;
                      _hoveredClusterIndex = null;
                    });
                  },
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_lockedClusterIndex == _hoveredClusterIndex) {
                          _lockedClusterIndex =
                              null; // Toggle off if clicked again
                        } else {
                          _lockedClusterIndex = _hoveredClusterIndex;
                        }
                      });
                    },
                    child: CustomPaint(
                      size: Size(constraints.maxWidth,
                          _calculateHeight(constraints.maxWidth)),
                      painter: _MetricsPainter(
                        text: _text,
                        fontSize: _fontSize,
                        showXRay: _showXRay,
                        hoverOffset: _hoverOffset,
                        lockedClusterIndex: _lockedClusterIndex,
                        onClustersUpdated: (clusters, hoveredIdx) {
                          // Update clusters list and hovered index asynchronously to avoid build-phase setState errors
                          if (_clusters.length != clusters.length ||
                              _hoveredClusterIndex != hoveredIdx) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() {
                                  _clusters = clusters;
                                  _hoveredClusterIndex = hoveredIdx;
                                });
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Controls Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF14161D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Custom Text Input
              const Text(
                'CUSTOM TEXT INPUT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _textController,
                onChanged: (val) {
                  setState(() {
                    _text = val;
                    _lockedClusterIndex = null;
                  });
                },
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Type something here...',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF0A0B0E),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.cyan, width: 1),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Glyph Size Slider & X-Ray Toggle
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'GLYPH SIZE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white38,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Text(
                              '${_fontSize.toInt()}px',
                              style: const TextStyle(
                                color: Colors.cyan,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.cyan,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: Colors.cyan,
                            overlayColor: Colors.cyan.withValues(alpha: 0.1),
                          ),
                          child: Slider(
                            value: _fontSize,
                            min: 16.0,
                            max: 72.0,
                            onChanged: (val) {
                              setState(() {
                                _fontSize = val;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SHOW GUIDES',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white38,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Switch(
                        value: _showXRay,
                        onChanged: (val) => setState(() => _showXRay = val),
                        activeThumbColor: Colors.cyan,
                        activeTrackColor: Colors.cyan.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Presets Row
              const Text(
                'PRESETS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presets.map((preset) {
                  final isSelected = _text == preset.$2;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _text = preset.$2;
                        _textController.text = preset.$2;
                        _lockedClusterIndex = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.cyan.withValues(alpha: 0.15)
                            : const Color(0xFF0A0B0E),
                        border: Border.all(
                          color: isSelected
                              ? Colors.cyan.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.05),
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        preset.$1,
                        style: TextStyle(
                          color: isSelected ? Colors.cyan : Colors.white70,
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );

    final hudPanel = _buildHUDPanel(activeCluster);

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          mainContent,
          const SizedBox(height: 24),
          hudPanel,
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: mainContent),
          const SizedBox(width: 32),
          SizedBox(
            width: 340,
            child: hudPanel,
          ),
        ],
      );
    }
  }

  double _calculateHeight(double maxWidth) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: _text,
        style: TextStyle(fontSize: _fontSize, height: 1.6),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: maxWidth);
    return textPainter.height + 20; // add some padding
  }

  Widget _buildHUDPanel(_ClusterInfo? cluster) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF12141C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cluster != null
              ? (cluster.isLocked
                  ? Colors.cyan.withValues(alpha: 0.5)
                  : Colors.cyan.withValues(alpha: 0.2))
              : Colors.white.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CLUSTER DETAILS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.cyan,
                  letterSpacing: 1.5,
                ),
              ),
              if (cluster != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cluster.isLocked
                        ? Colors.cyan.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    cluster.isLocked ? 'LOCKED' : 'LIVE',
                    style: TextStyle(
                      color: cluster.isLocked ? Colors.cyan : Colors.white38,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 24, color: Colors.white10),

          if (cluster == null) ...[
            const SizedBox(height: 60),
            const Center(
              child: Column(
                children: [
                  Icon(Icons.biotech, size: 48, color: Colors.white12),
                  SizedBox(height: 16),
                  Text(
                    'NO ACTIVE SELECTION',
                    style: TextStyle(
                      color: Colors.white24,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Hover or click on any glyph\nin the canvas to inspect.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white12, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 80),
          ] else ...[
            // Large Glyph Preview Box
            Center(
              child: Container(
                width: 100,
                height: 100,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0B0E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyan.withValues(alpha: 0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Text(
                  cluster.text,
                  style: const TextStyle(fontSize: 44, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Metrics specs
            _buildHudMetricRow(
                'Cluster Text', '"${cluster.text}"', Colors.white),
            _buildHudMetricRow(
                'UTF-16 Units', '${cluster.text.length} char(s)', Colors.cyan),
            _buildHudMetricRow(
                'Complex Cluster',
                cluster.text.runes.length > 1
                    ? 'YES (Multi-glyph)'
                    : 'NO (Single)',
                cluster.text.runes.length > 1
                    ? Colors.amberAccent
                    : Colors.white38),
            const SizedBox(height: 12),
            const Text(
              'BOUNDING BOX',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 1),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0B0E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildBoxMetric('X / Left',
                          '${cluster.rect.left.toStringAsFixed(2)}px'),
                      _buildBoxMetric('Y / Top',
                          '${cluster.rect.top.toStringAsFixed(2)}px'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildBoxMetric('Width',
                          '${cluster.rect.width.toStringAsFixed(2)}px'),
                      _buildBoxMetric('Height',
                          '${cluster.rect.height.toStringAsFixed(2)}px'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Hex Code Points decomposition
            const Text(
              'UNICODE CODE POINTS',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0B0E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(10),
                children: cluster.text.runes.map((rune) {
                  final hexStr =
                      'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}';
                  final charName = _getCharacterName(rune);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.cyan.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            hexStr,
                            style: const TextStyle(
                              color: Colors.cyan,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            charName,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            if (cluster.isLocked) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _lockedClusterIndex = null;
                    });
                  },
                  icon: const Icon(Icons.lock_open, size: 14),
                  label: const Text('UNLOCK INSPECTOR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyan,
                    side: const BorderSide(color: Colors.cyan, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHudMetricRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
                color: valueColor, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildBoxMetric(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white24, fontSize: 9),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  String _getCharacterName(int rune) {
    // A tiny dictionary for popular characters used in the demo to make it look premium
    if (rune == 0x200D) return 'Zero Width Joiner (ZWJ)';
    if (rune == 0xFE0F) return 'Variation Selector-16 (Emoji)';
    if (rune == 0x1F468) return 'Man';
    if (rune == 0x1F469) return 'Woman';
    if (rune == 0x1F467) return 'Girl';
    if (rune == 0x1F466) return 'Boy';
    if (rune == 0x2764) return 'Heavy Black Heart';
    if (rune == 0x1F48B) return 'Kiss Mark';
    if (rune == 0x1F3F3) return 'Waving Flag';
    if (rune == 0x1F3FC) return 'Emoji Modifier Fitzpatrick Type-3';
    if (rune == 0x1F3FD) return 'Emoji Modifier Fitzpatrick Type-4';
    if (rune == 0x1F3FE) return 'Emoji Modifier Fitzpatrick Type-5';

    // Devanagari Names
    if (rune >= 0x0900 && rune <= 0x097F) {
      if (rune == 0x0928) return 'Devanagari Letter NA';
      if (rune == 0x092B) return 'Devanagari Letter PHA';
      if (rune == 0x092E) return 'Devanagari Letter MA';
      if (rune == 0x0938) return 'Devanagari Letter SA';
      if (rune == 0x094D) return 'Devanagari Sign Virama (Halant)';
      if (rune == 0x0924) return 'Devanagari Letter TA';
      if (rune == 0x0947) return 'Devanagari Vowel Sign E';
      if (rune == 0x094B) return 'Devanagari Vowel Sign O';
      if (rune == 0x0926) return 'Devanagari Letter DA';
      if (rune == 0x0930) return 'Devanagari Letter RA';
      return 'Devanagari Glyph (0x${rune.toRadixString(16).toUpperCase()})';
    }

    // Arabic Names
    if (rune >= 0x0600 && rune <= 0x06FF) {
      if (rune == 0x0627) return 'Arabic Letter Alef';
      if (rune == 0x0644) return 'Arabic Letter Lam';
      if (rune == 0x062C) return 'Arabic Letter Jeem';
      if (rune == 0x0645) return 'Arabic Letter Meem';
      if (rune == 0x0647) return 'Arabic Letter Heh';
      if (rune == 0x0648) return 'Arabic Letter Waw';
      if (rune == 0x0631) return 'Arabic Letter Reh';
      if (rune == 0x064A) return 'Arabic Letter Yeh';
      if (rune == 0x0629) return 'Arabic Letter Teh Marbuta';
      if (rune == 0x0639) return 'Arabic Letter Ain';
      if (rune == 0x062B) return 'Arabic Letter Beh';
      if (rune == 0x0633) return 'Arabic Letter Seen';
      return 'Arabic Glyph (0x${rune.toRadixString(16).toUpperCase()})';
    }

    // Latin fallback names
    final char = String.fromCharCode(rune);
    if (rune >= 32 && rune <= 126) {
      return 'Latin Character "$char"';
    }
    return 'Unicode Character "$char"';
  }
}

class _ClusterInfo {
  final int index;
  final String text;
  final Rect rect;
  final bool isLocked;
  final int startOffset;

  const _ClusterInfo({
    required this.index,
    required this.text,
    required this.rect,
    required this.isLocked,
    required this.startOffset,
  });
}

class _MetricsPainter extends CustomPainter {
  final String text;
  final double fontSize;
  final bool showXRay;
  final Offset? hoverOffset;
  final int? lockedClusterIndex;
  final Function(List<_ClusterInfo>, int?) onClustersUpdated;

  _MetricsPainter({
    required this.text,
    required this.fontSize,
    required this.showXRay,
    required this.hoverOffset,
    required this.lockedClusterIndex,
    required this.onClustersUpdated,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      fontSize: fontSize,
      height: 1.6,
      color: Colors.white.withValues(alpha: showXRay ? 0.85 : 1.0),
      fontWeight: FontWeight.w400,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: size.width);

    // 1. Draw text
    textPainter.paint(canvas, Offset.zero);

    if (!showXRay) {
      onClustersUpdated([], null);
      return;
    }

    // 2. Collect all unique glyphs (grapheme clusters) in the text using native glyph metrics.
    // This queries getClosestGlyphForOffset using the center of each character's bounding box
    // to ensure correct behavior across both LTR and RTL scripts without infinite loops.
    final List<_ClusterInfo> clusters = [];
    int i = 0;
    while (i < text.length) {
      final boxes = textPainter.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      if (boxes.isEmpty) {
        i++;
        continue;
      }

      final center = boxes.first.toRect().center;
      final glyphInfo = textPainter.getClosestGlyphForOffset(center);
      if (glyphInfo == null) {
        i++;
        continue;
      }

      final start = glyphInfo.graphemeClusterCodeUnitRange.start;
      final end = glyphInfo.graphemeClusterCodeUnitRange.end;

      // Safety check to guarantee the loop index always advances, preventing freezes.
      if (end <= i) {
        i++;
        continue;
      }

      clusters.add(_ClusterInfo(
        index: clusters.length,
        text: text.substring(start, end),
        rect: glyphInfo.graphemeClusterLayoutBounds,
        isLocked: lockedClusterIndex == clusters.length,
        startOffset: start,
      ));
      // Advance past the entire grapheme cluster to the next unique glyph
      i = end;
    }

    // 3. Find which cluster is currently hovered
    int? hoveredClusterIdx;
    if (hoverOffset != null) {
      // Use TextPainter to locate the glyph info closest to the raw mouse offset.
      final glyphInfo = textPainter.getClosestGlyphForOffset(hoverOffset!);
      if (glyphInfo != null) {
        final start = glyphInfo.graphemeClusterCodeUnitRange.start;
        // Direct, O(1) spatial mapping using the start offset of the grapheme cluster
        final matchIdx = clusters.indexWhere((c) => c.startOffset == start);
        if (matchIdx != -1) {
          hoveredClusterIdx = matchIdx;
        }
      }
    }

    // 4. Draw cluster bounding boxes
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      final isHovered = i == hoveredClusterIdx;
      final isLocked = i == lockedClusterIndex;

      if (isLocked) {
        boxPaint.color = Colors.cyan;
        boxPaint.strokeWidth = 2.0;
        fillPaint.color = Colors.cyan.withValues(alpha: 0.15);
      } else if (isHovered) {
        boxPaint.color = Colors.cyan.withValues(alpha: 0.8);
        boxPaint.strokeWidth = 1.5;
        fillPaint.color = Colors.cyan.withValues(alpha: 0.08);
      } else {
        boxPaint.color = Colors.white.withValues(alpha: 0.15);
        boxPaint.strokeWidth = 1.0;
        fillPaint.color = Colors.white.withValues(alpha: 0.01);
      }

      canvas.drawRect(cluster.rect, fillPaint);

      if (isLocked) {
        // Draw locked corner marks for a premium futuristic feel
        final r = cluster.rect;
        const len = 6.0;
        canvas.drawRect(r, boxPaint);

        // Extra corner accents
        final accentPaint = Paint()
          ..color = Colors.cyan
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke;

        final path = Path()
          ..moveTo(r.left, r.top + len)
          ..lineTo(r.left, r.top)
          ..lineTo(r.left + len, r.top)
          ..moveTo(r.right, r.top + len)
          ..lineTo(r.right, r.top)
          ..lineTo(r.right - len, r.top)
          ..moveTo(r.left, r.bottom - len)
          ..lineTo(r.left, r.bottom)
          ..lineTo(r.left + len, r.bottom)
          ..moveTo(r.right, r.bottom - len)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.right - len, r.bottom);
        canvas.drawPath(path, accentPaint);
      } else {
        canvas.drawRect(cluster.rect, boxPaint);
      }
    }

    // 5. Draw horizontal guide lines (Baseline, Ascent, Descent) across the lines
    // We can extract lines from TextPainter (if supported) or estimate using line metrics.
    // For standard rendering, let's draw the lines based on the layout's height.
    final lineMetrics = textPainter.computeLineMetrics();
    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final metric in lineMetrics) {
      final baselineY = metric.baseline;
      final ascentY = baselineY - metric.ascent;
      final descentY = baselineY + metric.descent;

      // Draw Baseline (Purple)
      guidePaint.color = Colors.purpleAccent.withValues(alpha: 0.4);
      canvas.drawLine(
          Offset(0, baselineY), Offset(size.width, baselineY), guidePaint);

      // Draw Ascent (Green)
      guidePaint.color = Colors.greenAccent.withValues(alpha: 0.25);
      _drawDashedLine(
          canvas, Offset(0, ascentY), Offset(size.width, ascentY), guidePaint);

      // Draw Descent (Red)
      guidePaint.color = Colors.redAccent.withValues(alpha: 0.25);
      _drawDashedLine(canvas, Offset(0, descentY), Offset(size.width, descentY),
          guidePaint);
    }

    // Call callback to sync state with the main widget
    onClustersUpdated(clusters, hoveredClusterIdx);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    double distance = 0.0;
    final totalDistance = (end - start).distance;
    final direction = (end - start) / totalDistance;

    while (distance < totalDistance) {
      canvas.drawLine(
        start + direction * distance,
        start + direction * (distance + dashWidth),
        paint,
      );
      distance += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _MetricsPainter oldDelegate) =>
      text != oldDelegate.text ||
      fontSize != oldDelegate.fontSize ||
      showXRay != oldDelegate.showXRay ||
      hoverOffset != oldDelegate.hoverOffset ||
      lockedClusterIndex != oldDelegate.lockedClusterIndex;
}
