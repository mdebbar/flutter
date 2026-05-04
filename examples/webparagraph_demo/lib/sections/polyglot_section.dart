import 'package:flutter/material.dart';

class PolyglotSection extends StatefulWidget {
  const PolyglotSection({super.key});

  @override
  State<PolyglotSection> createState() => _PolyglotSectionState();
}

class _PolyglotSectionState extends State<PolyglotSection> {
  int _selectedSampleIndex = 0;
  String _activeRegion = 'All';

  // Custom text per sample, initialized on demand or kept in memory
  final Map<int, String> _customTexts = {};

  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _updateTextController();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _updateTextController() {
    final filtered = _filteredSamples;
    if (filtered.isEmpty) return;
    final activeSample = filtered[
        _selectedSampleIndex >= filtered.length ? 0 : _selectedSampleIndex];
    final mainIndex = _samples.indexOf(activeSample);
    final activeText = _customTexts[mainIndex] ?? activeSample.defaultText;
    _textController.value = TextEditingValue(
      text: activeText,
      selection: TextSelection.collapsed(offset: activeText.length),
    );
  }

  static const List<_LanguageSample> _samples = [
    _LanguageSample(
      name: 'Japanese',
      nativeName: '日本語',
      region: 'East Asia',
      defaultText: 'こんにちは、元気ですか？これは WebParagraph のデモです。',
      simulatedFontName: 'NotoSansJP-Regular.ttf',
      simulatedSizeKb: 4500,
    ),
    _LanguageSample(
      name: 'Korean',
      nativeName: '한국어',
      region: 'East Asia',
      defaultText: '안녕하세요, 어떻게 지내세요? 이것은 한국어 데모입니다.',
      simulatedFontName: 'NotoSansKR-Regular.ttf',
      simulatedSizeKb: 3800,
    ),
    _LanguageSample(
      name: 'Hindi',
      nativeName: 'हिन्दी',
      region: 'South Asia',
      defaultText: 'नमस्ते, आप कैसे हैं? यह वेब पैराग्राफ का एक उदाहरण है।',
      simulatedFontName: 'NotoSansDevanagari-Regular.ttf',
      simulatedSizeKb: 1250,
    ),
    _LanguageSample(
      name: 'Bengali',
      nativeName: 'বাংলা',
      region: 'South Asia',
      defaultText: 'নমস্কার, আপনি কেমন আছেন? এটি একটি বহুভাষিক প্রদর্শন।',
      simulatedFontName: 'NotoSansBengali-Regular.ttf',
      simulatedSizeKb: 1180,
    ),
    _LanguageSample(
      name: 'Tamil',
      nativeName: 'தமிழ்',
      region: 'South Asia',
      defaultText: 'வணக்கம், நீங்கள் எப்படி இருக்கிறீர்கள்? இது ஒரு தமிழ் உரை.',
      simulatedFontName: 'NotoSansTamil-Regular.ttf',
      simulatedSizeKb: 680,
    ),
    _LanguageSample(
      name: 'Telugu',
      nativeName: 'తెలుగు',
      region: 'South Asia',
      defaultText: 'నమస్కారం, మీరు ఎలా ఉన్నారు? ఇది తెలుగు వచనం.',
      simulatedFontName: 'NotoSansTelugu-Regular.ttf',
      simulatedSizeKb: 720,
    ),
    _LanguageSample(
      name: 'Kannada',
      nativeName: 'ಕನ್ನಡ',
      region: 'South Asia',
      defaultText: 'ನಮಸ್ಕಾರ, ನೀವು ಹೇಗಿದ್ದೀರಿ? ಇದು ಕನ್ನಡ ಪಠ್ಯ.',
      simulatedFontName: 'NotoSansKannada-Regular.ttf',
      simulatedSizeKb: 740,
    ),
    _LanguageSample(
      name: 'Thai',
      nativeName: 'ไทย',
      region: 'SE Asia',
      defaultText:
          'สวัสดีครับ คุณเป็นอย่างไรบ้าง? นี่คือตัวอย่างข้อความภาษาไทย',
      simulatedFontName: 'NotoSansThai-Regular.ttf',
      simulatedSizeKb: 450,
    ),
    _LanguageSample(
      name: 'Khmer',
      nativeName: 'ខ្មែរ',
      region: 'SE Asia',
      defaultText: 'សួស្តី តើអ្នកសុខសប្បាយជាទេ? នេះគឺជាអត្ថបទខ្មែរ।',
      simulatedFontName: 'NotoSansKhmer-Regular.ttf',
      simulatedSizeKb: 580,
    ),
    _LanguageSample(
      name: 'Lao',
      nativeName: 'ລາວ',
      region: 'SE Asia',
      defaultText: 'ສະបາຍດີ, ເຈົ້າເປັນແນວໃດ? ນີ້ແມ່ນຕົວຢ່າງພາສາລາວ.',
      simulatedFontName: 'NotoSansLao-Regular.ttf',
      simulatedSizeKb: 290,
    ),
    _LanguageSample(
      name: 'Burmese',
      nativeName: 'မြန်မာစာ',
      region: 'SE Asia',
      defaultText: 'မင်္ဂလာပါ၊ သင်နေကောင်းလား। ဤသည်မှာ မြန်မာစာသားဖြစ်သည်။',
      simulatedFontName: 'NotoSansMyanmar-Regular.ttf',
      simulatedSizeKb: 920,
    ),
    _LanguageSample(
      name: 'Tibetan',
      nativeName: 'བོད་སྐད།',
      region: 'Central Asia',
      defaultText: 'བཀྲ་ཤིས་བདེ་ལེགས། ཁྱེད་རང་སྐུ་གཟུགས་བདེ་པོ་ཡིན་པས།',
      simulatedFontName: 'NotoSansTibetan-Regular.ttf',
      simulatedSizeKb: 1350,
    ),
    _LanguageSample(
      name: 'Amharic',
      nativeName: 'አማርኛ',
      region: 'Africa',
      defaultText: 'ሰላም፣ እንደምን ነህ? ይህ የአማርኛ ጽሑፍ ማሳያ ነው።',
      simulatedFontName: 'NotoSansEthiopic-Regular.ttf',
      simulatedSizeKb: 1420,
    ),
    _LanguageSample(
      name: 'Georgian',
      nativeName: 'ქართული',
      region: 'Caucasus',
      defaultText: 'გამარჯობა, როგორ ხართ? ეს არის ქართული ტექსტის ნიმუში.',
      simulatedFontName: 'NotoSansGeorgian-Regular.ttf',
      simulatedSizeKb: 210,
    ),
    _LanguageSample(
      name: 'Armenian',
      nativeName: 'Հայերեն',
      region: 'Caucasus',
      defaultText: 'Բարև, ինչպե՞ս եք։ Սա հայերեն տեքստի նմուշ է։',
      simulatedFontName: 'NotoSansArmenian-Regular.ttf',
      simulatedSizeKb: 180,
    ),
    _LanguageSample(
      name: 'Arabic',
      nativeName: 'العربية',
      region: 'Middle East',
      defaultText: 'مرحبًا، كيف حالك؟ هذا نموذج لنص باللغة العربية.',
      isRtl: true,
      simulatedFontName: 'NotoSansArabic-Regular.ttf',
      simulatedSizeKb: 840,
    ),
    _LanguageSample(
      name: 'Hebrew',
      nativeName: 'עברית',
      region: 'Middle East',
      defaultText: 'שלום, איך אתה מרגיש היום? זוהי הדוגמה של טקסט בעברית.',
      isRtl: true,
      simulatedFontName: 'NotoSansHebrew-Regular.ttf',
      simulatedSizeKb: 310,
    ),
  ];

  List<String> get _regions {
    final list = <String>['All'];
    for (final s in _samples) {
      if (!list.contains(s.region)) {
        list.add(s.region);
      }
    }
    return list;
  }

  List<_LanguageSample> get _filteredSamples {
    if (_activeRegion == 'All') return _samples;
    return _samples.where((s) => s.region == _activeRegion).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSamples;
    // Bounds checking
    if (_selectedSampleIndex >= filtered.length) {
      _selectedSampleIndex = 0;
    }
    final activeSample =
        filtered.isNotEmpty ? filtered[_selectedSampleIndex] : _samples[0];

    // Find the original index in the main list
    final mainIndex = _samples.indexOf(activeSample);
    final activeText = _customTexts[mainIndex] ?? activeSample.defaultText;

    final isMobile = MediaQuery.of(context).size.width < 1000;

    final mainContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        const Text(
          'GLOBAL SCRIPT EXPLORER',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.cyan,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Explore how WebParagraph effortlessly renders diverse global scripts natively. Toggle geographical regions, type custom script phrases, and compare the font loading behaviors.',
          style: TextStyle(color: Colors.white70, height: 1.5, fontSize: 14),
        ),
        const SizedBox(height: 24),

        // Region Filter Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _regions.map((region) {
              final isSelected = _activeRegion == region;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(region),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _activeRegion = region;
                        _selectedSampleIndex = 0;
                        _updateTextController();
                      });
                    }
                  },
                  selectedColor: Colors.cyan.withValues(alpha: 0.15),
                  backgroundColor: const Color(0xFF14161D),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.cyan : Colors.white38,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? Colors.cyan.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Script Tabs
        SizedBox(
          height: 58,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final sample = filtered[index];
              final isSelected = _selectedSampleIndex == index;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0, bottom: 4),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedSampleIndex = index;
                      _updateTextController();
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1B1E28)
                          : const Color(0xFF11131A),
                      border: Border.all(
                        color: isSelected
                            ? Colors.cyan.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.04),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sample.name,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13.5,
                          ),
                        ),
                        if (isSelected)
                          Text(
                            sample.nativeName,
                            style: TextStyle(
                              color: Colors.cyan.withValues(alpha: 0.7),
                              fontSize: 10.0,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Typography Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0E12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${activeSample.region.toUpperCase()}  |  ${activeSample.name.toUpperCase()} (${activeSample.nativeName})  |  ${activeSample.isRtl ? 'RTL' : 'LTR'}',
                      style: const TextStyle(
                        color: Colors.cyan,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const Text(
                    'LIVE RENDERING',
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Big Render Box
              SizedBox(
                width: double.infinity,
                height: 180,
                child: Center(
                  child: SingleChildScrollView(
                    child: Text(
                      activeText,
                      textAlign:
                          activeSample.isRtl ? TextAlign.right : TextAlign.left,
                      textDirection: activeSample.isRtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 28,
                        height: 1.6,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 32, color: Colors.white10),

              // Custom Text Editor for this script
              const Text(
                'EDIT TEXT IN THIS SCRIPT',
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
                    _customTexts[mainIndex] = val;
                  });
                },
                textAlign:
                    activeSample.isRtl ? TextAlign.right : TextAlign.left,
                textDirection:
                    activeSample.isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Type custom phrase in ${activeSample.name}...',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF0A0B0E),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final simulatorPanel = _buildSimulatorPanel(activeSample);

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          mainContent,
          const SizedBox(height: 24),
          simulatorPanel,
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
            child: simulatorPanel,
          ),
        ],
      );
    }
  }

  Widget _buildSimulatorPanel(_LanguageSample sample) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF12141C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
          const Row(
            children: [
              Icon(Icons.network_check, color: Colors.cyan, size: 20),
              SizedBox(width: 10),
              Text(
                'NETWORK SIMULATOR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.cyan,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: Colors.white10),

          const Text(
            'Under the hood comparison for font fallbacks when loading this script:',
            style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 20),

          // 1. Normal CanvasKit Panel
          _buildEngineCompCard(
            title: 'Normal CanvasKit',
            badge: 'DOWNLOAD FALLBACKS',
            badgeColor: Colors.amberAccent,
            color: const Color(0xFF1A1510),
            borderColor: Colors.amber.withValues(alpha: 0.2),
            icon: Icons.cloud_download_outlined,
            details: [
              _buildMetricDetail(
                  'Fallback Font', 'Google Fonts (Noto Sans ${sample.name})'),
              _buildMetricDetail(
                  'Network Payload', 'Multiple split .woff2 segments'),
              _buildMetricDetail('TTI Delay', 'Waiting for network fetch...'),
              _buildMetricDetail('Initial State', 'Tofu boxes (口口)'),
            ],
          ),
          const SizedBox(height: 16),

          // 2. WebParagraph Mode
          _buildEngineCompCard(
            title: 'WebParagraph Mode',
            badge: '0B DOWNLOAD - INSTANT',
            badgeColor: Colors.greenAccent,
            color: const Color(0xFF101A15),
            borderColor: Colors.green.withValues(alpha: 0.2),
            icon: Icons.shield_outlined,
            details: [
              _buildMetricDetail('Fallback Font', 'Host OS System Font'),
              _buildMetricDetail('Network Payload', '0 Bytes (Local)'),
              _buildMetricDetail('TTI Delay', 'Instant (0ms)'),
              _buildMetricDetail('Initial State', 'Perfect native text'),
            ],
          ),

          const SizedBox(height: 20),
          // Technical Explanation & How-to-Verify instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0B0E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.cyan.withValues(alpha: 0.15)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.cyan, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Normal CanvasKit cannot render text without downloading web fonts. It must download web fonts (such as Roboto for Latin text, or Noto subsets for other scripts) as network requests to shape and paint glyphs. WebParagraph bypasses this entirely by letting the browser\'s native C++ engine lay out and render text using local system fonts already installed on the host OS.',
                        style: TextStyle(
                            color: Colors.white60, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ],
                ),
                Divider(height: 24, color: Colors.white10),
                Text(
                  '🔍 HOW TO VERIFY IN YOUR BROWSER:',
                  style: TextStyle(
                    color: Colors.cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '1. Open Chrome DevTools (Press F12 or Cmd+Option+I).\n'
                  '2. Navigate to the "Network" tab, select the "Fetch/XHR" filter, and type "fonts" in the filter text box.\n'
                  '3. Toggle between the "Normal CK" and "WebParagraph" modes via the URL query parameters (?ck vs ?wp).\n'
                  '4. Under WebParagraph, notice that switching tabs triggers local rendering without network font fetches. In Normal CanvasKit, notice that the engine makes Fetch/XHR requests to download multiple split font files as new scripts are encountered.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngineCompCard({
    required String title,
    required String badge,
    required Color badgeColor,
    required Color color,
    required Color borderColor,
    required IconData icon,
    required List<Widget> details,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: badgeColor, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: details,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          Text(
            value,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _LanguageSample {
  final String name;
  final String nativeName;
  final String region;
  final String defaultText;
  final bool isRtl;
  final String simulatedFontName;
  final int simulatedSizeKb;

  const _LanguageSample({
    required this.name,
    required this.nativeName,
    required this.region,
    required this.defaultText,
    this.isRtl = false,
    required this.simulatedFontName,
    required this.simulatedSizeKb,
  });
}
