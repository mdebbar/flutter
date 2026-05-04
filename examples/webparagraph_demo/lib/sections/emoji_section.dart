import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class EmojiSection extends StatefulWidget {
  const EmojiSection({super.key});

  @override
  State<EmojiSection> createState() => _EmojiSectionState();
}

class _EmojiSectionState extends State<EmojiSection>
    with TickerProviderStateMixin {
  late Ticker _ticker;
  final List<_EmojiParticle> _particles = [];
  final GlobalKey _stackKey = GlobalKey();

  // Active ZWJ Sequence for the Synthesis Lab
  int _activeZwjIndex = 0;

  static const List<_ZwjSequence> _zwjSequences = [
    _ZwjSequence(
      name: 'Family (4 members)',
      combined: '👨‍👩‍👧‍👦',
      components: [
        ('👨', 'Man', 'U+1F468'),
        ('🔗', 'ZWJ', 'U+200D'),
        ('👩', 'Woman', 'U+1F469'),
        ('🔗', 'ZWJ', 'U+200D'),
        ('👧', 'Girl', 'U+1F467'),
        ('🔗', 'ZWJ', 'U+200D'),
        ('👦', 'Boy', 'U+1F466'),
      ],
      description:
          'Combines four separate people into a single family glyph. WebParagraph renders this as a single, perfectly scaled vector cluster.',
    ),
    _ZwjSequence(
      name: 'Couple in Love',
      combined: '👩‍❤️‍👨',
      components: [
        ('👩', 'Woman', 'U+1F469'),
        ('🔗', 'ZWJ', 'U+200D'),
        ('❤️', 'Heart', 'U+2764'),
        ('🔗', 'ZWJ', 'U+200D'),
        ('👨', 'Man', 'U+1F468'),
      ],
      description:
          'Combines two people and a heart. Native rendering ensures the heart and couple are aligned perfectly according to the OS design language.',
    ),
    _ZwjSequence(
      name: 'Woman Astronaut',
      combined: '👩‍🚀',
      components: [
        ('👩', 'Woman', 'U+1F469'),
        ('🔗', 'ZWJ', 'U+200D'),
        ('🚀', 'Rocket', 'U+1F680'),
      ],
      description:
          'Synthesizes a profession emoji by joining a person with an object. Native engines resolve this instantly without requiring custom graphics.',
    ),
    _ZwjSequence(
      name: 'Rainbow Flag',
      combined: '🏳️‍🌈',
      components: [
        ('🏳️', 'White Flag', 'U+1F3F3'),
        ('🔗', 'ZWJ', 'U+200D'),
        ('🌈', 'Rainbow', 'U+1F308'),
      ],
      description:
          'Overlays a white waving flag with a rainbow to create the Pride flag, rendered with anti-aliased native curves.',
    ),
    _ZwjSequence(
      name: 'Woman Runner',
      combined: '🏃‍♀️',
      components: [
        ('🏃', 'Runner', 'U+1F3C3'),
        ('🔗', 'ZWJ', 'U+200D'),
        ('♀️', 'Female Sign', 'U+2640'),
      ],
      description:
          'Applies a gender modifier to an action glyph, showing how modern emoji layouts adapt dynamically.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Start ticker for particle physics
    _ticker = createTicker(_updateParticles);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _updateParticles(Duration elapsed) {
    if (_particles.isEmpty) return;
    setState(() {
      for (int i = _particles.length - 1; i >= 0; i--) {
        final p = _particles[i];
        p.x += p.vx;
        p.y += p.vy;
        p.vy += 0.2; // Gravity
        p.rotation += p.vRotation;
        p.life -= 0.02; // Fade out
        if (p.life <= 0) {
          _particles.removeAt(i);
        }
      }
    });
  }

  void _spawnParticles(String emoji, Offset localPos) {
    final random = math.Random();
    setState(() {
      for (int i = 0; i < 12; i++) {
        final angle = random.nextDouble() * 2 * math.pi;
        final speed = random.nextDouble() * 5 + 3;
        _particles.add(_EmojiParticle(
          x: localPos.dx,
          y: localPos.dy,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed - 4, // Initial upward burst
          emoji: emoji,
          rotation: random.nextDouble() * 2 * math.pi,
          vRotation: (random.nextDouble() - 0.5) * 0.2,
          scale: random.nextDouble() * 0.4 + 0.6,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: _stackKey,
      children: [
        // Main Content
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Header
            _buildInfoCard(
              'Platform-Native Emojis',
              'WebParagraph delegates emoji rendering to the host operating system. This guarantees that all emojis—including complex ZWJ sequences—are rendered at crisp vector resolutions using the platform\'s native style (Apple Color Emoji, Segoe UI Emoji, or Noto Color Emoji) with zero asset overhead.',
            ),
            const SizedBox(height: 32),

            // Synthesis Lab Section
            _buildSynthesisLab(),
            const SizedBox(height: 40),

            // Emoji Grids
            _buildGrid('Modern & Expressive Emojis', [
              '🫨',
              '🫠',
              '🫡',
              '🫣',
              '🫤',
              '🫥',
              '🫧',
              '🪪',
              '🫦',
              '🫶',
              '🫰',
              '🦾'
            ]),
            const SizedBox(height: 32),
            _buildGrid('ZWJ Compound Sequences', [
              '👨‍👩‍👧‍👦',
              '👩‍❤️‍👨',
              '🏳️‍🌈',
              '🏳️‍⚧️',
              '🏃‍♀️',
              '🕵️‍♂️',
              '👮‍♀️',
              '🧑‍🎨',
              '🧑‍🚀'
            ]),
            const SizedBox(height: 32),
            _buildGrid('Flags & Objects', [
              '🇺🇳',
              '🇪🇺',
              '🏴‍☠️',
              '🏁',
              '🧶',
              '🧵',
              '🧷',
              '🧹',
              '🧺',
              '🧻',
              '🧼',
              '🧽'
            ]),
          ],
        ),

        // Floating Particles Overlay
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ParticlePainter(particles: _particles),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(String title, String description) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.cyan.withValues(alpha: 0.05),
        border: Border.all(color: Colors.cyan.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_emotions_outlined,
                  color: Colors.cyan, size: 22),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(height: 1.5, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildSynthesisLab() {
    final activeSeq = _zwjSequences[_activeZwjIndex];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF11131A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.science_outlined, color: Colors.cyan, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'EMOJI SYNTHESIS LAB',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.cyan,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              // Preset Selector
              DropdownButton<int>(
                value: _activeZwjIndex,
                dropdownColor: const Color(0xFF11131A),
                iconEnabledColor: Colors.cyan,
                underline: Container(),
                items: List.generate(_zwjSequences.length, (index) {
                  return DropdownMenuItem(
                    value: index,
                    child: Text(
                      _zwjSequences[index].name,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  );
                }),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _activeZwjIndex = val;
                    });
                  }
                },
              ),
            ],
          ),
          const Divider(height: 20, color: Colors.white10),
          const SizedBox(height: 12),

          // Synthesis Visual Flow
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              final contents = [
                // Input components
                Expanded(
                  flex: isWide ? 3 : 0,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: activeSeq.components.map((c) {
                      final isZwj = c.$1 == '🔗';
                      return Tooltip(
                        message: '${c.$2} (${c.$3})',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isZwj
                                ? Colors.cyan.withValues(alpha: 0.1)
                                : const Color(0xFF0A0B0E),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isZwj
                                  ? Colors.cyan.withValues(alpha: 0.3)
                                  : Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                c.$1,
                                style: TextStyle(fontSize: isZwj ? 14 : 28),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                c.$2,
                                style: TextStyle(
                                  fontSize: 8,
                                  color: isZwj ? Colors.cyan : Colors.white38,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Arrow
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: isWide ? 0.0 : 16.0),
                  child: Icon(
                    isWide ? Icons.arrow_forward : Icons.arrow_downward,
                    color: Colors.cyan,
                    size: 32,
                  ),
                ),

                // Combined Output
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0B0E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.cyan.withValues(alpha: 0.4), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyan.withValues(alpha: 0.05),
                        blurRadius: 15,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTapDown: (details) {
                            final renderBox = _stackKey.currentContext
                                ?.findRenderObject() as RenderBox?;
                            if (renderBox != null) {
                              final localPos = renderBox
                                  .globalToLocal(details.globalPosition);
                              _spawnParticles(activeSeq.combined, localPos);
                            }
                          },
                          child: Tooltip(
                            message: 'Click to pop!',
                            child: Text(
                              activeSeq.combined,
                              style: const TextStyle(fontSize: 64),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'SYNTHESIZED RESULT',
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.cyan,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ];

              return isWide
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: contents,
                    )
                  : Column(
                      children: contents,
                    );
            },
          ),

          const SizedBox(height: 20),
          // Description
          Text(
            activeSeq.description,
            style: const TextStyle(
                color: Colors.white54, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(String label, List<String> emojis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white38,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: emojis.map((e) => _buildEmojiBox(e)).toList(),
        ),
      ],
    );
  }

  Widget _buildEmojiBox(String emoji) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) {
          // Get the click position relative to the main stack
          final renderBox =
              _stackKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final localPos = renderBox.globalToLocal(details.globalPosition);
            _spawnParticles(emoji, localPos);
          }
        },
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF14161D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Hero(
            tag: 'emoji-$emoji',
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 32),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZwjSequence {
  final String name;
  final String combined;
  final List<(String, String, String)> components;
  final String description;

  const _ZwjSequence({
    required this.name,
    required this.combined,
    required this.components,
    required this.description,
  });
}

class _EmojiParticle {
  double x;
  double y;
  final double vx;
  double vy;
  final String emoji;
  double rotation;
  final double vRotation;
  final double scale;
  double life = 1.0;

  _EmojiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.emoji,
    required this.rotation,
    required this.vRotation,
    required this.scale,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_EmojiParticle> particles;

  _ParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final p in particles) {
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      canvas.scale(p.scale);

      final textSpan = TextSpan(
        text: p.emoji,
        style: TextStyle(
          fontSize: 24,
          color: Colors.white.withValues(alpha: p.life),
        ),
      );

      textPainter.text = textSpan;
      textPainter.layout();
      // Draw centered
      textPainter.paint(
          canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}
