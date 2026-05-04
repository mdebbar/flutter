import 'package:flutter/material.dart';

class CustomFontsSection extends StatefulWidget {
  const CustomFontsSection({super.key});

  @override
  State<CustomFontsSection> createState() => _CustomFontsSectionState();
}

class _CustomFontsSectionState extends State<CustomFontsSection> {
  String _customText = 'The quick brown fox jumps over the lazy dog.';
  double _fontSize = 32.0;
  double _letterSpacing = 0.0;
  double _lineHeight = 1.2;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info Card
        _buildInfoCard(
          'Custom Asset & System Fonts',
          'WebParagraph isn\'t limited to system fonts. Under the hood, the Flutter Web engine registers custom font assets (defined in your pubspec.yaml) directly into the browser\'s FontFaceSet registry. This allows the native layout engine to treat your custom .ttf/.otf assets with the exact same performance and layout fidelity as built-in system fonts.',
        ),
        const SizedBox(height: 32),

        // Playground Controls Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF11131A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune, color: Colors.cyan, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'TYPOGRAPHY PLAYGROUND',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.cyan,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24, color: Colors.white10),

              // Live Text Input
              const Text(
                'TEST PHRASE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: _customText)
                  ..selection = TextSelection.fromPosition(
                      TextPosition(offset: _customText.length)),
                onChanged: (val) {
                  setState(() {
                    _customText = val;
                  });
                },
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Type custom text to preview...',
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
              const SizedBox(height: 24),

              // Multi-sliders layout
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;

                  final sliders = [
                    // Size
                    Expanded(
                      flex: isWide ? 1 : 0,
                      child: _buildSlider(
                        label: 'FONT SIZE',
                        value: _fontSize,
                        min: 16.0,
                        max: 64.0,
                        displayValue: '${_fontSize.toInt()}px',
                        onChanged: (val) => setState(() => _fontSize = val),
                      ),
                    ),
                    if (isWide) const SizedBox(width: 24),
                    // Spacing
                    Expanded(
                      flex: isWide ? 1 : 0,
                      child: _buildSlider(
                        label: 'LETTER SPACING',
                        value: _letterSpacing,
                        min: -2.0,
                        max: 8.0,
                        displayValue: '${_letterSpacing.toStringAsFixed(1)}px',
                        onChanged: (val) =>
                            setState(() => _letterSpacing = val),
                      ),
                    ),
                    if (isWide) const SizedBox(width: 24),
                    // Line Height
                    Expanded(
                      flex: isWide ? 1 : 0,
                      child: _buildSlider(
                        label: 'LINE HEIGHT',
                        value: _lineHeight,
                        min: 0.8,
                        max: 2.5,
                        displayValue: _lineHeight.toStringAsFixed(1),
                        onChanged: (val) => setState(() => _lineHeight = val),
                      ),
                    ),
                  ];

                  return isWide
                      ? Row(children: sliders)
                      : Column(
                          children: sliders
                              .map((s) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 16.0),
                                    child: Row(children: [s]),
                                  ))
                              .toList());
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Font Samples
        _buildFontSampleCard(
          familyLabel: 'Homemade Apple',
          typeLabel: 'Asset Font (Cursive)',
          fontFamily: 'HomemadeApple',
          description:
              'Loaded dynamically from assets/fonts/HomemadeApple.ttf. Ideal for handwriting, signatures, and artistic headings.',
          accentColor: Colors.pinkAccent,
        ),
        const SizedBox(height: 20),
        _buildFontSampleCard(
          familyLabel: 'Monospace',
          typeLabel: 'System Font (Default Monospace)',
          fontFamily: 'monospace',
          description:
              'Uses the browser\'s native monospace rendering. Ideal for code blocks, technical readouts, and tabular data alignments.',
          accentColor: Colors.cyanAccent,
        ),
        const SizedBox(height: 20),
        _buildFontSampleCard(
          familyLabel: 'Serif',
          typeLabel: 'System Font (Default Serif)',
          fontFamily: 'serif',
          description:
              'Uses the browser\'s native serif rendering. Perfect for long-form literary texts, providing classic newspaper/book legibility.',
          accentColor: Colors.amberAccent,
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
              const Icon(Icons.font_download_outlined,
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

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white38,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              displayValue,
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
            trackHeight: 3.0,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildFontSampleCard({
    required String familyLabel,
    required String typeLabel,
    required String fontFamily,
    required String description,
    required Color accentColor,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF14161D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header of Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      familyLabel.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.text_fields, color: accentColor, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),

          // Rendered Text Box
          Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0B0E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
              ),
              child: Text(
                _customText,
                style: TextStyle(
                  fontSize: _fontSize,
                  fontFamily: fontFamily,
                  letterSpacing: _letterSpacing,
                  height: _lineHeight,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // Description Footer
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
            child: Text(
              description,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
