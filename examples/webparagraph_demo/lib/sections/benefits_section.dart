import 'package:flutter/material.dart';

class BenefitsSection extends StatefulWidget {
  const BenefitsSection({super.key});

  @override
  State<BenefitsSection> createState() => _BenefitsSectionState();
}

class _BenefitsSectionState extends State<BenefitsSection> {
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title & Description
        const Text(
          'UNDER THE HOOD: ARCHITECTURE & COMPARISON',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.cyan,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'By refactoring Flutter Web\'s text layout to utilize Chrome\'s new TextCluster API, we eliminate the need for heavy WASM-compiled layout libraries and custom font fallbacks. Compare the architectural pipelines and capabilities below.',
          style: TextStyle(color: Colors.white70, height: 1.5, fontSize: 14),
        ),
        const SizedBox(height: 32),

        // 1. Architecture Flowcharts Side-by-Side
        const Text(
          'PIPELINE COMPARISON',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white38,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final double flowWidth = isMobile
                ? constraints.maxWidth
                : (constraints.maxWidth - 24) / 2;
            final flowCharts = [
              _buildPipelineCard(
                title: 'NORMAL CANVASKIT PIPELINE',
                subtitle: 'Heavy WASM Emulation Stack',
                accentColor: Colors.amberAccent,
                width: flowWidth,
                steps: [
                  const _PipelineStep(
                    title: 'Flutter Framework',
                    desc: 'Triggers Paragraph.layout()',
                    icon: Icons.layers,
                  ),
                  const _PipelineStep(
                    title: 'CanvasKit WASM',
                    desc: 'Forwards to Skia/Impeller text layer',
                    icon: Icons.code,
                  ),
                  const _PipelineStep(
                    title: 'HarfBuzz & FreeType',
                    desc: 'Shapes and rasterizes text inside WASM memory',
                    icon: Icons.settings_input_component,
                    warning: 'Adds ~1.5MB to WASM bundle',
                  ),
                  const _PipelineStep(
                    title: 'Brotli & Fallback Font Fetch',
                    desc: 'Downloads Noto Sans TTF subsets over network',
                    icon: Icons.cloud_download,
                    warning: 'Adds up to 10MB network payload',
                  ),
                  const _PipelineStep(
                    title: 'Canvas Rendering',
                    desc: 'Draws glyph contours into GPU texture',
                    icon: Icons.brush,
                  ),
                ],
              ),
              if (isMobile)
                const SizedBox(height: 24)
              else
                const SizedBox(width: 24),
              _buildPipelineCard(
                title: 'WEBPARAGRAPH PIPELINE',
                subtitle: 'Streamlined Native Browser Stack',
                accentColor: Colors.cyan,
                width: flowWidth,
                steps: [
                  const _PipelineStep(
                    title: 'Flutter Framework',
                    desc: 'Triggers Paragraph.layout()',
                    icon: Icons.layers,
                  ),
                  const _PipelineStep(
                    title: 'CanvasKit WASM',
                    desc: 'Bypasses internal text shaping',
                    icon: Icons.code,
                  ),
                  const _PipelineStep(
                    title: 'WebParagraph JS Bridge',
                    desc: 'Calls Chrome\'s TextCluster API directly',
                    icon: Icons.bolt,
                    success: 'Instant C++ native layout',
                  ),
                  const _PipelineStep(
                    title: 'Native OS Font Engine',
                    desc: 'Uses pre-installed system font fallbacks',
                    icon: Icons.laptop_windows,
                    success: '0 Bytes downloaded from network',
                  ),
                  const _PipelineStep(
                    title: 'Canvas Rendering',
                    desc: 'Draws using browser native canvas text context',
                    icon: Icons.brush,
                  ),
                ],
              ),
            ];

            return isMobile
                ? Column(children: flowCharts)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: flowCharts,
                  );
          },
        ),
        const SizedBox(height: 48),

        // 2. Architectural Capabilities Matrix
        const Text(
          'ARCHITECTURAL CAPABILITIES COMPARISON',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white38,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _buildFeatureMatrix(isMobile),
      ],
    );
  }

  Widget _buildPipelineCard({
    required String title,
    required String subtitle,
    required Color accentColor,
    required double width,
    required List<_PipelineStep> steps,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF12141C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const Divider(height: 24, color: Colors.white10),

          // Steps list
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            final isLast = index == steps.length - 1;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step Number/Icon
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0B0E),
                            border: Border.all(
                                color: accentColor.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(step.icon, color: accentColor, size: 16),
                        ),
                        if (!isLast)
                          Container(
                            width: 1.5,
                            height: 40,
                            color: accentColor.withValues(alpha: 0.2),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),

                    // Step Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            step.desc,
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                                height: 1.3),
                          ),
                          if (step.warning != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: Colors.amberAccent, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  step.warning!,
                                  style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                          if (step.success != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.check_circle_outline_rounded,
                                    color: Colors.greenAccent, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  step.success!,
                                  style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFeatureMatrix(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11131A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Table(
          columnWidths: isMobile
              ? const {
                  0: FlexColumnWidth(1.0), // Feature Name
                  1: FlexColumnWidth(0.9), // Normal CanvasKit
                  2: FlexColumnWidth(0.9), // WebParagraph
                }
              : const {
                  0: FlexColumnWidth(1.2), // Feature Name
                  1: FlexColumnWidth(1.0), // Normal CanvasKit
                  2: FlexColumnWidth(1.0), // WebParagraph
                },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            // Table Header Row
            _buildHeaderRow(),
            // Feature Rows
            _buildFeatureRow(
              feature: 'System Font Access',
              ckText: 'Blocked (Requires Web Fonts)',
              ckSuccess: false,
              wpText: 'Native OS Font Stack',
              wpSuccess: true,
            ),
            _buildFeatureRow(
              feature: 'Initial Font Payload',
              ckText: 'Roboto/Noto Fetch (~30KB+)',
              ckSuccess: false,
              wpText: '0 Bytes (Local Fallback)',
              wpSuccess: true,
            ),
            _buildFeatureRow(
              feature: 'Complex Emojis (ZWJ)',
              ckText: 'Emulated / Requires Emoji Font',
              ckSuccess: false,
              wpText: 'Native OS Styles (0B)',
              wpSuccess: true,
            ),
          ],
        ),
      ),
    );
  }

  TableRow _buildHeaderRow() {
    return TableRow(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0F14),
        border: Border(bottom: BorderSide(color: Colors.white10, width: 1)),
      ),
      children: [
        _buildHeaderCell('CAPABILITY'),
        _buildHeaderCell('NORMAL CANVASKIT'),
        _buildHeaderCell('WEBPARAGRAPH MODE', isCyan: true),
      ],
    );
  }

  Widget _buildHeaderCell(String text, {bool isCyan = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Text(
        text,
        style: TextStyle(
          color: isCyan ? Colors.cyan : Colors.white60,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  TableRow _buildFeatureRow({
    required String feature,
    required String ckText,
    required bool ckSuccess,
    required String wpText,
    required bool wpSuccess,
  }) {
    return TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      children: [
        // Feature description
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Text(
            feature,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        // Normal CanvasKit capability cell
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(
                ckSuccess
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline,
                color: ckSuccess ? Colors.greenAccent : Colors.amberAccent,
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ckText,
                  style: TextStyle(
                    color: ckSuccess
                        ? Colors.white.withValues(alpha: 0.85)
                        : Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        // WebParagraph capability cell
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(
                wpSuccess
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline,
                color: wpSuccess ? Colors.greenAccent : Colors.amberAccent,
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  wpText,
                  style: TextStyle(
                    color: wpSuccess
                        ? Colors.cyanAccent
                        : Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: wpSuccess ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PipelineStep {
  final String title;
  final String desc;
  final IconData icon;
  final String? warning;
  final String? success;

  const _PipelineStep({
    required this.title,
    required this.desc,
    required this.icon,
    this.warning,
    this.success,
  });
}
