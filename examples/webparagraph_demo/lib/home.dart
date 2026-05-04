import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:web/web.dart' hide Text;
import 'sections/polyglot_section.dart';
import 'sections/emoji_section.dart';
import 'sections/metrics_section.dart';
import 'sections/custom_fonts_section.dart';
import 'sections/benefits_section.dart';
import 'web_paragraph_detection.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _bgAnimationController;

  final List<(_SectionInfo, Widget)> _sections = [
    (
      const _SectionInfo(
        title: 'Polyglot Text',
        subtitle: 'Multi-script layout without fallback fonts',
        icon: Icons.translate,
      ),
      const PolyglotSection(),
    ),
    (
      const _SectionInfo(
        title: 'Native Emojis',
        subtitle: 'High-fidelity platform rendering',
        icon: Icons.emoji_emotions_outlined,
      ),
      const EmojiSection(),
    ),
    (
      const _SectionInfo(
        title: 'Metrics X-Ray',
        subtitle: 'Precision text cluster visualization',
        icon: Icons.biotech_outlined,
      ),
      const MetricsSection(),
    ),
    (
      const _SectionInfo(
        title: 'Asset Fonts',
        subtitle: 'Custom font support in WebParagraph',
        icon: Icons.font_download_outlined,
      ),
      const CustomFontsSection(),
    ),
    (
      const _SectionInfo(
        title: 'The Benefits',
        subtitle: 'Engine architecture & payload size',
        icon: Icons.speed_outlined,
      ),
      const BenefitsSection(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Continuous animation for the mesh background
    _bgAnimationController = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _bgAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final isEnabled = isWebParagraphEnabled();

    return Scaffold(
      backgroundColor: const Color(0xFF07080B),
      body: Stack(
        children: [
          // 1. Glowing Mesh Gradient Background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgAnimationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _MeshBackgroundPainter(
                    animationValue: _bgAnimationController.value,
                  ),
                );
              },
            ),
          ),

          // 2. Main Layout (Sidebar + Body)
          Row(
            children: [
              if (!isMobile) _buildSidebar(context),
              Expanded(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    // Styled SliverAppBar
                    SliverAppBar(
                      floating: true,
                      pinned: true,
                      elevation: 0,
                      stretch: true,
                      expandedHeight: isMobile ? 140.0 : 110.0,
                      backgroundColor:
                          const Color(0xFF07080B).withValues(alpha: 0.7),
                      flexibleSpace: FlexibleSpaceBar(
                        stretchModes: const [StretchMode.zoomBackground],
                        background: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.white.withValues(alpha: 0.05),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                        titlePadding: EdgeInsets.only(
                          left: 32.0,
                          bottom: isMobile ? 68.0 : 16.0,
                        ),
                        title: Text(
                          _sections[_selectedIndex].$1.title.toUpperCase(),
                          style: const TextStyle(
                            letterSpacing: 2.5,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black45,
                                offset: Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                      bottom: isMobile
                          ? PreferredSize(
                              preferredSize: const Size.fromHeight(60),
                              child: _buildMobileTabs(),
                            )
                          : null,
                    ),

                    // Page Content
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32.0, vertical: 24.0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Engine Context Banner
                            _buildContextBanner(isEnabled),
                            const SizedBox(height: 16),
                            _sections[_selectedIndex].$2,
                            const SizedBox(height: 60), // bottom spacing
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContextBanner(bool isEnabled) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: isEnabled
            ? const Color(0xFF101C1A).withValues(alpha: 0.8)
            : const Color(0xFF1C1410).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.amber.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isEnabled
                ? Icons.offline_bolt_rounded
                : Icons.warning_amber_rounded,
            color: isEnabled ? Colors.greenAccent : Colors.amberAccent,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEnabled
                      ? 'ACTIVE: CHROMIUM TEXT CLUSTERS ENGINE'
                      : 'ACTIVE: NORMAL CANVASKIT SHAPING ENGINE',
                  style: TextStyle(
                    color: isEnabled ? Colors.greenAccent : Colors.amberAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isEnabled
                      ? 'Flutter is bypassing HarfBuzz/FreeType WASM layers and delegating text layouts directly to the browser\'s native C++ engine.'
                      : 'Flutter is compiling and shaping text inside WebAssembly using custom font files downloaded over the network.',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final isEnabled = isWebParagraphEnabled();
    final supportsTextClusters = browserSupportsTextClusters();

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14).withValues(alpha: 0.85),
        border: Border(
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sidebar Header
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 28.0, top: 40.0, right: 28.0, bottom: 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'WEB\nPARAGRAPH',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              height: 0.85,
                              letterSpacing: -1,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.cyan.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color:
                                          Colors.cyan.withValues(alpha: 0.3)),
                                ),
                                child: const Text(
                                  'DEMO APP',
                                  style: TextStyle(
                                    color: Colors.cyan,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusBadge(
                                isEnabled: isEnabled,
                                supportsTextClusters: supportsTextClusters,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Engine Toggle Buttons
                          const Text(
                            'ENGINE SELECTION',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.white24,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _ModeButton(
                                  label: 'Normal CK',
                                  active: !isEnabled,
                                  onPressed: () => _toggleMode('ck'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _ModeButton(
                                  label: 'WebParagraph',
                                  active: isEnabled,
                                  onPressed: () => _toggleMode('wp'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    const SizedBox(height: 16),

                    // Navigation Links
                    for (int index = 0; index < _sections.length; index++) ...[
                      Builder(
                        builder: (context) {
                          final info = _sections[index].$1;
                          final isSelected = _selectedIndex == index;

                          return _SidebarTile(
                            title: info.title,
                            subtitle: info.subtitle,
                            icon: info.icon,
                            isSelected: isSelected,
                            onTap: () => setState(() => _selectedIndex = index),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _toggleMode(String mode) {
    final uri = Uri.parse(window.location.href);
    final newParams = Map<String, String>.from(uri.queryParameters);

    if (mode == 'ck') {
      newParams.remove('wp');
      newParams['ck'] = '';
    } else {
      newParams.remove('ck');
      newParams['wp'] = '';
    }

    window.location.href = uri.replace(queryParameters: newParams).toString();
  }

  Widget _buildMobileTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(_sections.length, (index) {
          final info = _sections[index].$1;
          final isSelected = _selectedIndex == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(info.title),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) setState(() => _selectedIndex = index);
              },
              selectedColor: Colors.cyan.withValues(alpha: 0.15),
              backgroundColor: const Color(0xFF14161D),
              side: BorderSide(
                color: isSelected
                    ? Colors.cyan.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.05),
              ),
              labelStyle: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.cyan : Colors.white38,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.isSelected ? Colors.cyan : Colors.white38;
    final titleColor = widget.isSelected
        ? Colors.white
        : (_isHovered ? Colors.white70 : Colors.white38);
    final subtitleColor = widget.isSelected
        ? Colors.cyan.withValues(alpha: 0.7)
        : (_isHovered ? Colors.white30 : Colors.white12);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? Colors.cyan.withValues(alpha: 0.08)
                : (_isHovered
                    ? Colors.white.withValues(alpha: 0.02)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isSelected
                  ? Colors.cyan.withValues(alpha: 0.2)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              // Left glowing vertical line
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 3,
                height: widget.isSelected ? 24 : 0,
                decoration: BoxDecoration(
                  color: Colors.cyan,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyan.withValues(alpha: 0.8),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: widget.isSelected ? 12 : 0,
              ),

              // Icon with slide via AnimatedPadding
              AnimatedPadding(
                padding: EdgeInsets.only(
                    left: _isHovered && !widget.isSelected ? 4.0 : 0.0),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 16),

              // Text details with slide via AnimatedPadding
              Expanded(
                child: AnimatedPadding(
                  padding: EdgeInsets.only(
                      left: _isHovered && !widget.isSelected ? 4.0 : 0.0),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: widget.isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: subtitleColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onPressed;

  const _ModeButton({
    required this.label,
    required this.active,
    required this.onPressed,
  });

  @override
  State<_ModeButton> createState() => _ModeButtonState();
}

class _ModeButtonState extends State<_ModeButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor:
          widget.active ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.active ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.active
                ? Colors.cyan.withValues(alpha: 0.12)
                : (_isHovered
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.transparent),
            border: Border.all(
              color: widget.active
                  ? Colors.cyan.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              if (widget.active)
                BoxShadow(
                  color: Colors.cyan.withValues(alpha: 0.05),
                  blurRadius: 8,
                ),
            ],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.active ? Colors.white : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatefulWidget {
  final bool isEnabled;
  final bool supportsTextClusters;

  const _StatusBadge({
    required this.isEnabled,
    required this.supportsTextClusters,
  });

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isEnabled
        ? Colors.greenAccent
        : (widget.supportsTextClusters
            ? Colors.orangeAccent
            : Colors.redAccent);
    final label = widget.isEnabled
        ? 'ENABLED'
        : (widget.supportsTextClusters ? 'DISABLED' : 'NOT SUPPORTED');

    return Tooltip(
      message: widget.isEnabled
          ? 'WebParagraph is active'
          : (widget.supportsTextClusters
              ? 'Browser supports WebParagraph but it is not enabled'
              : 'Browser does not support Text Clusters API'),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color:
                    color.withValues(alpha: 0.2 + 0.3 * _pulseController.value),
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(
                      alpha: 0.05 + 0.15 * _pulseController.value),
                  blurRadius: 8 * _pulseController.value,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glowing pulsing indicator dot
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color,
                        blurRadius: 4 * _pulseController.value + 2,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionInfo {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SectionInfo({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

// Custom Painter for the cyber mesh background
class _MeshBackgroundPainter extends CustomPainter {
  final double animationValue;

  _MeshBackgroundPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Base background dark color
    paint.color = const Color(0xFF06070B);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Dynamic, moving radial glow 1 (Cyan/Teal) - moves in an orbit
    final double x1 =
        size.width * 0.2 + math.cos(animationValue * 2 * math.pi) * 100;
    final double y1 =
        size.height * 0.3 + math.sin(animationValue * 2 * math.pi) * 80;
    final radius1 = math.min(size.width, size.height) * 0.7;
    final paintGlow1 = Paint()
      ..shader = ui.Gradient.radial(
        Offset(x1, y1),
        radius1,
        [
          Colors.cyan.withValues(alpha: 0.04),
          Colors.transparent,
        ],
      );
    canvas.drawCircle(Offset(x1, y1), radius1, paintGlow1);

    // Dynamic, moving radial glow 2 (Indigo/Purple) - moves in a counter-orbit
    final double x2 = size.width * 0.8 +
        math.cos(-animationValue * 2 * math.pi + math.pi) * 150;
    final double y2 = size.height * 0.7 +
        math.sin(-animationValue * 2 * math.pi + math.pi) * 100;
    final radius2 = math.min(size.width, size.height) * 0.8;
    final paintGlow2 = Paint()
      ..shader = ui.Gradient.radial(
        Offset(x2, y2),
        radius2,
        [
          Colors.indigoAccent.withValues(alpha: 0.03),
          Colors.transparent,
        ],
      );
    canvas.drawCircle(Offset(x2, y2), radius2, paintGlow2);

    // Draw subtle grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.007)
      ..strokeWidth = 1.0;

    const double step = 60.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MeshBackgroundPainter oldDelegate) =>
      animationValue != oldDelegate.animationValue;
}
