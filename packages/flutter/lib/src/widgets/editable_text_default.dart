// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui hide TextStyle;

import 'package:characters/characters.dart' show CharacterRange, StringCharacters;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'actions.dart';
import 'autofill.dart';
import 'automatic_keep_alive.dart';
import 'basic.dart';
import 'binding.dart';
import 'constants.dart';
import 'context_menu_button_item.dart';
import 'debug.dart';
import 'default_text_editing_shortcuts.dart';
import 'editable_text.dart';
import 'focus_manager.dart';
import 'focus_scope.dart';
import 'focus_traversal.dart';
import 'framework.dart';
import 'localizations.dart';
import 'media_query.dart';
import 'notification_listener.dart';
import 'scroll_configuration.dart';
import 'scroll_controller.dart';
import 'scroll_notification.dart';
import 'scroll_notification_observer.dart';
import 'scroll_position.dart';
import 'scrollable.dart';
import 'scrollable_helpers.dart';
import 'size_changed_layout_notifier.dart';
import 'spell_check.dart';
import 'tap_region.dart';
import 'text.dart';
import 'text_editing_intents.dart';
import 'text_selection.dart';
import 'text_selection_toolbar_anchors.dart';
import 'ticker_provider.dart';
import 'undo_history.dart';
import 'view.dart';
import 'widget_span.dart';

// Signature for a function that determines the target location of the given
// [TextPosition] after applying the given [TextBoundary].
typedef _ApplyTextBoundary = TextPosition Function(TextPosition, bool, TextBoundary);

// The time it takes for the cursor to fade from fully opaque to fully
// transparent and vice versa. A full cursor blink, from transparent to opaque
// to transparent, is twice this duration.
const Duration _kCursorBlinkHalfPeriod = Duration(milliseconds: 500);

// Number of cursor ticks during which the most recently entered character
// is shown in an obscured text field.
const int _kObscureShowLatestCharCursorTicks = 3;

class _CompositionCallback extends SingleChildRenderObjectWidget {
  const _CompositionCallback({ required this.compositeCallback, required this.enabled, super.child });
  final CompositionCallback compositeCallback;
  final bool enabled;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCompositionCallback(compositeCallback, enabled);
  }
  @override
  void updateRenderObject(BuildContext context, _RenderCompositionCallback renderObject) {
    super.updateRenderObject(context, renderObject);
    // `EditableTextStateDefault` always uses the same callback.
    assert(renderObject.compositeCallback == compositeCallback);
    renderObject.enabled = enabled;
  }
}

class _RenderCompositionCallback extends RenderProxyBox {
  _RenderCompositionCallback(this.compositeCallback, this._enabled);

  final CompositionCallback compositeCallback;
  VoidCallback? _cancelCallback;

  bool get enabled => _enabled;
  bool _enabled = false;
  set enabled(bool newValue) {
    _enabled = newValue;
    if (!newValue) {
      _cancelCallback?.call();
      _cancelCallback = null;
    } else if (_cancelCallback == null) {
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, ui.Offset offset) {
    if (enabled) {
      _cancelCallback ??= context.addCompositionCallback(compositeCallback);
    }
    super.paint(context, offset);
  }
}

// A time-value pair that represents a key frame in an animation.
class _KeyFrame {
  const _KeyFrame(this.time, this.value);
  // Values extracted from iOS 15.4 UIKit.
  static const List<_KeyFrame> iOSBlinkingCaretKeyFrames = <_KeyFrame>[
    _KeyFrame(0,       1),     // 0
    _KeyFrame(0.5,     1),     // 1
    _KeyFrame(0.5375,  0.75),  // 2
    _KeyFrame(0.575,   0.5),   // 3
    _KeyFrame(0.6125,  0.25),  // 4
    _KeyFrame(0.65,    0),     // 5
    _KeyFrame(0.85,    0),     // 6
    _KeyFrame(0.8875,  0.25),  // 7
    _KeyFrame(0.925,   0.5),   // 8
    _KeyFrame(0.9625,  0.75),  // 9
    _KeyFrame(1,       1),     // 10
  ];

  // The timing, in seconds, of the specified animation `value`.
  final double time;
  final double value;
}

class _DiscreteKeyFrameSimulation extends Simulation {
  _DiscreteKeyFrameSimulation.iOSBlinkingCaret() : this._(_KeyFrame.iOSBlinkingCaretKeyFrames, 1);
  _DiscreteKeyFrameSimulation._(this._keyFrames, this.maxDuration)
    : assert(_keyFrames.isNotEmpty),
      assert(_keyFrames.last.time <= maxDuration),
      assert(() {
        for (int i = 0; i < _keyFrames.length -1; i += 1) {
          if (_keyFrames[i].time > _keyFrames[i + 1].time) {
            return false;
          }
        }
        return true;
      }(), 'The key frame sequence must be sorted by time.');

  final double maxDuration;

  final List<_KeyFrame> _keyFrames;

  @override
  double dx(double time) => 0;

  @override
  bool isDone(double time) => time >= maxDuration;

  // The index of the KeyFrame corresponds to the most recent input `time`.
  int _lastKeyFrameIndex = 0;

  @override
  double x(double time) {
    final int length = _keyFrames.length;

    // Perform a linear search in the sorted key frame list, starting from the
    // last key frame found, since the input `time` usually monotonically
    // increases by a small amount.
    int searchIndex;
    final int endIndex;
    if (_keyFrames[_lastKeyFrameIndex].time > time) {
      // The simulation may have restarted. Search within the index range
      // [0, _lastKeyFrameIndex).
      searchIndex = 0;
      endIndex = _lastKeyFrameIndex;
    } else {
      searchIndex = _lastKeyFrameIndex;
      endIndex = length;
    }

    // Find the target key frame. Don't have to check (endIndex - 1): if
    // (endIndex - 2) doesn't work we'll have to pick (endIndex - 1) anyways.
    while (searchIndex < endIndex - 1) {
      assert(_keyFrames[searchIndex].time <= time);
      final _KeyFrame next = _keyFrames[searchIndex + 1];
      if (time < next.time) {
        break;
      }
      searchIndex += 1;
    }

    _lastKeyFrameIndex = searchIndex;
    return _keyFrames[_lastKeyFrameIndex].value;
  }
}

/// State for a [EditableTextDefault].
class EditableTextStateDefault extends State<EditableTextDefault> with AutomaticKeepAliveClientMixin<EditableTextDefault>, WidgetsBindingObserver, TickerProviderStateMixin<EditableTextDefault>, TextSelectionDelegate, TextInputClient implements AutofillClient {
  Timer? _cursorTimer;
  AnimationController get _cursorBlinkOpacityController {
    return _backingCursorBlinkOpacityController ??= AnimationController(
      vsync: this,
    )..addListener(_onCursorColorTick);
  }
  AnimationController? _backingCursorBlinkOpacityController;
  late final Simulation _iosBlinkCursorSimulation = _DiscreteKeyFrameSimulation.iOSBlinkingCaret();

  final ValueNotifier<bool> _cursorVisibilityNotifier = ValueNotifier<bool>(true);
  final GlobalKey _editableKey = GlobalKey();

  /// Detects whether the clipboard can paste.
  final ClipboardStatusNotifier clipboardStatus = kIsWeb
      // Web browsers will show a permission dialog when Clipboard.hasStrings is
      // called. In an EditableText, this will happen before the paste button is
      // clicked, often before the context menu is even shown. To avoid this
      // poor user experience, always show the paste button on web.
      ? _WebClipboardStatusNotifier()
      : ClipboardStatusNotifier();

  /// Detects whether the Live Text input is enabled.
  ///
  /// See also:
  ///  * [LiveText], where the availability of Live Text input can be obtained.
  final LiveTextInputStatusNotifier? _liveTextInputStatus =
      kIsWeb ? null : LiveTextInputStatusNotifier();

  TextInputConnection? _textInputConnection;
  bool get _hasInputConnection => _textInputConnection?.attached ?? false;

  TextSelectionOverlay? _selectionOverlay;
  ScrollNotificationObserverState? _scrollNotificationObserver;
  ({TextEditingValue value, Rect selectionBounds})? _dataWhenToolbarShowScheduled;
  bool _listeningToScrollNotificationObserver = false;

  bool get _webContextMenuEnabled => kIsWeb && BrowserContextMenu.enabled;

  final GlobalKey _scrollableKey = GlobalKey();
  ScrollController? _internalScrollController;
  ScrollController get _scrollController => widget.scrollController ?? (_internalScrollController ??= ScrollController());

  final LayerLink _toolbarLayerLink = LayerLink();
  final LayerLink _startHandleLayerLink = LayerLink();
  final LayerLink _endHandleLayerLink = LayerLink();

  bool _didAutoFocus = false;

  AutofillGroupState? _currentAutofillScope;
  @override
  AutofillScope? get currentAutofillScope => _currentAutofillScope;

  AutofillClient get _effectiveAutofillClient => widget.autofillClient ?? this;

  late SpellCheckConfiguration _spellCheckConfiguration;
  late TextStyle _style;

  /// Configuration that determines how spell check will be performed.
  ///
  /// If possible, this configuration will contain a default for the
  /// [SpellCheckService] if it is not otherwise specified.
  ///
  /// See also:
  ///  * [DefaultSpellCheckService], the spell check service used by default.
  @visibleForTesting
  SpellCheckConfiguration get spellCheckConfiguration => _spellCheckConfiguration;

  /// Whether or not spell check is enabled.
  ///
  /// Spell check is enabled when a [SpellCheckConfiguration] has been specified
  /// for the widget.
  bool get spellCheckEnabled => _spellCheckConfiguration.spellCheckEnabled;

  /// The most up-to-date spell check results for text input.
  ///
  /// These results will be updated via calls to spell check through a
  /// [SpellCheckService] and used by this widget to build the [TextSpan] tree
  /// for text input and menus for replacement suggestions of misspelled words.
  SpellCheckResults? spellCheckResults;

  bool get _spellCheckResultsReceived => spellCheckEnabled && spellCheckResults != null && spellCheckResults!.suggestionSpans.isNotEmpty;

  /// The text processing service used to retrieve the native text processing actions.
  final ProcessTextService _processTextService = DefaultProcessTextService();

  /// The list of native text processing actions provided by the engine.
  final List<ProcessTextAction> _processTextActions = <ProcessTextAction>[];

  /// Whether to create an input connection with the platform for text editing
  /// or not.
  ///
  /// Read-only input fields do not need a connection with the platform since
  /// there's no need for text editing capabilities (e.g. virtual keyboard).
  ///
  /// On the web, we always need a connection because we want some browser
  /// functionalities to continue to work on read-only input fields like:
  ///
  /// - Relevant context menu.
  /// - cmd/ctrl+c shortcut to copy.
  /// - cmd/ctrl+a to select all.
  /// - Changing the selection using a physical keyboard.
  bool get _shouldCreateInputConnection => kIsWeb || !widget.readOnly;

  // The time it takes for the floating cursor to snap to the text aligned
  // cursor position after the user has finished placing it.
  static const Duration _floatingCursorResetTime = Duration(milliseconds: 125);

  AnimationController? _floatingCursorResetController;

  Orientation? _lastOrientation;

  @override
  bool get wantKeepAlive => widget.focusNode.hasFocus;

  Color get _cursorColor {
    final double effectiveOpacity = math.min(widget.cursorColor.alpha / 255.0, _cursorBlinkOpacityController.value);
    return widget.cursorColor.withOpacity(effectiveOpacity);
  }

  @override
  bool get cutEnabled {
    if (widget.selectionControls is! TextSelectionHandleControls) {
      return widget.toolbarOptions.cut && !widget.readOnly && !widget.obscureText;
    }
    return !widget.readOnly
        && !widget.obscureText
        && !textEditingValue.selection.isCollapsed;
  }

  @override
  bool get copyEnabled {
    if (widget.selectionControls is! TextSelectionHandleControls) {
      return widget.toolbarOptions.copy && !widget.obscureText;
    }
    return !widget.obscureText
        && !textEditingValue.selection.isCollapsed;
  }

  @override
  bool get pasteEnabled {
    if (widget.selectionControls is! TextSelectionHandleControls) {
      return widget.toolbarOptions.paste && !widget.readOnly;
    }
    return !widget.readOnly
        && (clipboardStatus.value == ClipboardStatus.pasteable);
  }

  @override
  bool get selectAllEnabled {
    if (widget.selectionControls is! TextSelectionHandleControls) {
      return widget.toolbarOptions.selectAll && (!widget.readOnly || !widget.obscureText) && widget.enableInteractiveSelection;
    }

    if (!widget.enableInteractiveSelection
        || (widget.readOnly
            && widget.obscureText)) {
      return false;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return false;
      case TargetPlatform.iOS:
        return textEditingValue.text.isNotEmpty
            && textEditingValue.selection.isCollapsed;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return textEditingValue.text.isNotEmpty
           && !(textEditingValue.selection.start == 0
               && textEditingValue.selection.end == textEditingValue.text.length);
    }
  }

  @override
  bool get lookUpEnabled {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    return !widget.obscureText
        && !textEditingValue.selection.isCollapsed
        && textEditingValue.selection.textInside(textEditingValue.text).trim() != '';
  }

  @override
  bool get searchWebEnabled {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }

    return !widget.obscureText
        && !textEditingValue.selection.isCollapsed
        && textEditingValue.selection.textInside(textEditingValue.text).trim() != '';
  }

  @override
  bool get shareEnabled {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return !widget.obscureText
            && !textEditingValue.selection.isCollapsed
            && textEditingValue.selection.textInside(textEditingValue.text).trim() != '';
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return false;
    }
  }

  @override
  bool get liveTextInputEnabled {
    return _liveTextInputStatus?.value == LiveTextInputStatus.enabled &&
        !widget.obscureText &&
        !widget.readOnly &&
        textEditingValue.selection.isCollapsed;
  }

  void _onChangedClipboardStatus() {
    setState(() {
      // Inform the widget that the value of clipboardStatus has changed.
    });
  }

  void _onChangedLiveTextInputStatus() {
    setState(() {
      // Inform the widget that the value of liveTextInputStatus has changed.
    });
  }

  TextEditingValue get _textEditingValueforTextLayoutMetrics {
    final Widget? editableWidget =_editableKey.currentContext?.widget;
    if (editableWidget is! _Editable) {
      throw StateError('_Editable must be mounted.');
    }
    return editableWidget.value;
  }

  /// Copy current selection to [Clipboard].
  @override
  void copySelection(SelectionChangedCause cause) {
    final TextSelection selection = textEditingValue.selection;
    if (selection.isCollapsed || widget.obscureText) {
      return;
    }
    final String text = textEditingValue.text;
    Clipboard.setData(ClipboardData(text: selection.textInside(text)));
    if (cause == SelectionChangedCause.toolbar) {
      bringIntoView(textEditingValue.selection.extent);
      hideToolbar(false);

      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          break;
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
          // Collapse the selection and hide the toolbar and handles.
          userUpdateTextEditingValue(
            TextEditingValue(
              text: textEditingValue.text,
              selection: TextSelection.collapsed(offset: textEditingValue.selection.end),
            ),
            SelectionChangedCause.toolbar,
          );
      }
    }
    clipboardStatus.update();
  }

  /// Cut current selection to [Clipboard].
  @override
  void cutSelection(SelectionChangedCause cause) {
    if (widget.readOnly || widget.obscureText) {
      return;
    }
    final TextSelection selection = textEditingValue.selection;
    final String text = textEditingValue.text;
    if (selection.isCollapsed) {
      return;
    }
    Clipboard.setData(ClipboardData(text: selection.textInside(text)));
    _replaceText(ReplaceTextIntent(textEditingValue, '', selection, cause));
    if (cause == SelectionChangedCause.toolbar) {
      // Schedule a call to bringIntoView() after renderEditable updates.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          bringIntoView(textEditingValue.selection.extent);
        }
      }, debugLabel: 'EditableText.bringSelectionIntoView');
      hideToolbar();
    }
    clipboardStatus.update();
  }

  bool get _allowPaste {
    return !widget.readOnly && textEditingValue.selection.isValid;
  }

  /// Paste text from [Clipboard].
  @override
  Future<void> pasteText(SelectionChangedCause cause) async {
    if (!_allowPaste) {
      return;
    }
    // Snapshot the input before using `await`.
    // See https://github.com/flutter/flutter/issues/11427
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null) {
      return;
    }
    _pasteText(cause, data.text!);
  }

  void _pasteText(SelectionChangedCause cause, String text) {
    if (!_allowPaste) {
      return;
    }

    // After the paste, the cursor should be collapsed and located after the
    // pasted content.
    final TextSelection selection = textEditingValue.selection;
    final int lastSelectionIndex = math.max(selection.baseOffset, selection.extentOffset);
    final TextEditingValue collapsedTextEditingValue = textEditingValue.copyWith(
      selection: TextSelection.collapsed(offset: lastSelectionIndex),
    );

    userUpdateTextEditingValue(
      collapsedTextEditingValue.replaced(selection, text),
      cause,
    );
    if (cause == SelectionChangedCause.toolbar) {
      // Schedule a call to bringIntoView() after renderEditable updates.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          bringIntoView(textEditingValue.selection.extent);
        }
      }, debugLabel: 'EditableText.bringSelectionIntoView');
      hideToolbar();
    }
  }

  /// Select the entire text value.
  @override
  void selectAll(SelectionChangedCause cause) {
    if (widget.readOnly && widget.obscureText) {
      // If we can't modify it, and we can't copy it, there's no point in
      // selecting it.
      return;
    }
    userUpdateTextEditingValue(
      textEditingValue.copyWith(
        selection: TextSelection(baseOffset: 0, extentOffset: textEditingValue.text.length),
      ),
      cause,
    );

    if (cause == SelectionChangedCause.toolbar) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.iOS:
        case TargetPlatform.fuchsia:
          break;
        case TargetPlatform.macOS:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          hideToolbar();
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          bringIntoView(textEditingValue.selection.extent);
        case TargetPlatform.macOS:
        case TargetPlatform.iOS:
          break;
      }
    }
  }

  /// Look up the current selection,
  /// as in the "Look Up" edit menu button on iOS.
  ///
  /// Currently this is only implemented for iOS.
  ///
  /// Throws an error if the selection is empty or collapsed.
  Future<void> lookUpSelection(SelectionChangedCause cause) async {
    assert(!widget.obscureText);

    final String text = textEditingValue.selection.textInside(textEditingValue.text);
    if (widget.obscureText || text.isEmpty) {
      return;
    }
    await SystemChannels.platform.invokeMethod(
      'LookUp.invoke',
      text,
    );
  }

  /// Launch a web search on the current selection,
  /// as in the "Search Web" edit menu button on iOS.
  ///
  /// Currently this is only implemented for iOS.
  ///
  /// When 'obscureText' is true or the selection is empty,
  /// this function will not do anything
  Future<void> searchWebForSelection(SelectionChangedCause cause) async {
    assert(!widget.obscureText);
    if (widget.obscureText) {
      return;
    }

    final String text = textEditingValue.selection.textInside(textEditingValue.text);
    if (text.isNotEmpty) {
      await SystemChannels.platform.invokeMethod(
        'SearchWeb.invoke',
        text,
      );
    }
  }

  /// Launch the share interface for the current selection,
  /// as in the "Share..." edit menu button on iOS.
  ///
  /// Currently this is only implemented for iOS and Android.
  ///
  /// When 'obscureText' is true or the selection is empty,
  /// this function will not do anything
  Future<void> shareSelection(SelectionChangedCause cause) async {
    assert(!widget.obscureText);
    if (widget.obscureText) {
      return;
    }

    final String text = textEditingValue.selection.textInside(textEditingValue.text);
    if (text.isNotEmpty) {
      await SystemChannels.platform.invokeMethod(
        'Share.invoke',
        text,
      );
    }
  }

  void _startLiveTextInput(SelectionChangedCause cause) {
    if (!liveTextInputEnabled) {
      return;
    }
    if (_hasInputConnection) {
      LiveText.startLiveTextInput();
    }
    if (cause == SelectionChangedCause.toolbar) {
      hideToolbar();
    }
  }

  /// Finds specified [SuggestionSpan] that matches the provided index using
  /// binary search.
  ///
  /// See also:
  ///
  ///  * [SpellCheckSuggestionsToolbar], the Material style spell check
  ///    suggestions toolbar that uses this method to render the correct
  ///    suggestions in the toolbar for a misspelled word.
  SuggestionSpan? findSuggestionSpanAtCursorIndex(int cursorIndex) {
    if (!_spellCheckResultsReceived
        || spellCheckResults!.suggestionSpans.last.range.end < cursorIndex) {
      // No spell check results have been received or the cursor index is out
      // of range that suggestionSpans covers.
      return null;
    }

    final List<SuggestionSpan> suggestionSpans = spellCheckResults!.suggestionSpans;
    int leftIndex = 0;
    int rightIndex = suggestionSpans.length - 1;
    int midIndex = 0;

    while (leftIndex <= rightIndex) {
      midIndex = ((leftIndex + rightIndex) / 2).floor();
      final int currentSpanStart = suggestionSpans[midIndex].range.start;
      final int currentSpanEnd = suggestionSpans[midIndex].range.end;

      if (cursorIndex <= currentSpanEnd && cursorIndex >= currentSpanStart) {
        return suggestionSpans[midIndex];
      }
      else if (cursorIndex <= currentSpanStart) {
        rightIndex = midIndex - 1;
      }
      else {
        leftIndex = midIndex + 1;
      }
    }
    return null;
  }

  /// Infers the [SpellCheckConfiguration] used to perform spell check.
  ///
  /// If spell check is enabled, this will try to infer a value for
  /// the [SpellCheckService] if left unspecified.
  static SpellCheckConfiguration _inferSpellCheckConfiguration(SpellCheckConfiguration? configuration) {
    final SpellCheckService? spellCheckService = configuration?.spellCheckService;
    final bool spellCheckAutomaticallyDisabled = configuration == null || configuration == const SpellCheckConfiguration.disabled();
    final bool spellCheckServiceIsConfigured = spellCheckService != null || spellCheckService == null && WidgetsBinding.instance.platformDispatcher.nativeSpellCheckServiceDefined;
    if (spellCheckAutomaticallyDisabled || !spellCheckServiceIsConfigured) {
      // Only enable spell check if a non-disabled configuration is provided
      // and if that configuration does not specify a spell check service,
      // a native spell checker must be supported.
      assert(() {
        if (!spellCheckAutomaticallyDisabled && !spellCheckServiceIsConfigured) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: FlutterError(
                'Spell check was enabled with spellCheckConfiguration, but the '
                'current platform does not have a supported spell check '
                'service, and none was provided. Consider disabling spell '
                'check for this platform or passing a SpellCheckConfiguration '
                'with a specified spell check service.',
              ),
              library: 'widget library',
              stack: StackTrace.current,
            ),
          );
        }
        return true;
      }());
      return const SpellCheckConfiguration.disabled();
    }

    return configuration.copyWith(spellCheckService: spellCheckService ?? DefaultSpellCheckService());
  }

  /// Returns the [ContextMenuButtonItem]s for the given [ToolbarOptions].
  @Deprecated(
    'Use `contextMenuBuilder` instead of `toolbarOptions`. '
    'This feature was deprecated after v3.3.0-0.5.pre.',
  )
  List<ContextMenuButtonItem>? buttonItemsForToolbarOptions([TargetPlatform? targetPlatform]) {
    final ToolbarOptions toolbarOptions = widget.toolbarOptions;
    if (toolbarOptions == ToolbarOptions.empty) {
      return null;
    }
    return <ContextMenuButtonItem>[
      if (toolbarOptions.cut && cutEnabled)
        ContextMenuButtonItem(
          onPressed: () {
            cutSelection(SelectionChangedCause.toolbar);
          },
          type: ContextMenuButtonType.cut,
        ),
      if (toolbarOptions.copy && copyEnabled)
        ContextMenuButtonItem(
          onPressed: () {
            copySelection(SelectionChangedCause.toolbar);
          },
          type: ContextMenuButtonType.copy,
        ),
      if (toolbarOptions.paste && pasteEnabled)
        ContextMenuButtonItem(
          onPressed: () {
            pasteText(SelectionChangedCause.toolbar);
          },
          type: ContextMenuButtonType.paste,
        ),
      if (toolbarOptions.selectAll && selectAllEnabled)
        ContextMenuButtonItem(
          onPressed: () {
            selectAll(SelectionChangedCause.toolbar);
          },
          type: ContextMenuButtonType.selectAll,
        ),
    ];
  }

  /// Gets the line heights at the start and end of the selection for the given
  /// [EditableTextStateDefault].
  _GlyphHeights _getGlyphHeights() {
    final TextSelection selection = textEditingValue.selection;

    // Only calculate handle rects if the text in the previous frame
    // is the same as the text in the current frame. This is done because
    // widget.renderObject contains the renderEditable from the previous frame.
    // If the text changed between the current and previous frames then
    // widget.renderObject.getRectForComposingRange might fail. In cases where
    // the current frame is different from the previous we fall back to
    // renderObject.preferredLineHeight.
    final InlineSpan span = renderEditable.text!;
    final String prevText = span.toPlainText();
    final String currText = textEditingValue.text;
    if (prevText != currText || !selection.isValid || selection.isCollapsed) {
      return _GlyphHeights(
        start: renderEditable.preferredLineHeight,
        end: renderEditable.preferredLineHeight,
      );
    }

    final String selectedGraphemes = selection.textInside(currText);
    final int firstSelectedGraphemeExtent = selectedGraphemes.characters.first.length;
    final Rect? startCharacterRect = renderEditable.getRectForComposingRange(TextRange(
      start: selection.start,
      end: selection.start + firstSelectedGraphemeExtent,
    ));
    final int lastSelectedGraphemeExtent = selectedGraphemes.characters.last.length;
    final Rect? endCharacterRect = renderEditable.getRectForComposingRange(TextRange(
      start: selection.end - lastSelectedGraphemeExtent,
      end: selection.end,
    ));
    return _GlyphHeights(
      start: startCharacterRect?.height ?? renderEditable.preferredLineHeight,
      end: endCharacterRect?.height ?? renderEditable.preferredLineHeight,
    );
  }

  /// {@template flutter.widgets.EditableText.getAnchors}
  /// Returns the anchor points for the default context menu.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [contextMenuButtonItems], which provides the [ContextMenuButtonItem]s
  ///    for the default context menu buttons.
  TextSelectionToolbarAnchors get contextMenuAnchors {
    if (renderEditable.lastSecondaryTapDownPosition != null) {
      return TextSelectionToolbarAnchors(
        primaryAnchor: renderEditable.lastSecondaryTapDownPosition!,
      );
    }

    final _GlyphHeights glyphHeights = _getGlyphHeights();
    final TextSelection selection = textEditingValue.selection;
    final List<TextSelectionPoint> points =
        renderEditable.getEndpointsForSelection(selection);
    return TextSelectionToolbarAnchors.fromSelection(
      renderBox: renderEditable,
      startGlyphHeight: glyphHeights.start,
      endGlyphHeight: glyphHeights.end,
      selectionEndpoints: points,
    );
  }

  /// Returns the [ContextMenuButtonItem]s representing the buttons in this
  /// platform's default selection menu for [EditableText].
  ///
  /// See also:
  ///
  /// * [EditableText.getEditableButtonItems], which performs a similar role,
  ///   but for any editable field, not just specifically EditableText.
  /// * [SelectableRegionState.contextMenuButtonItems], which performs a similar
  ///   role but for content that is selectable but not editable.
  /// * [contextMenuAnchors], which provides the anchor points for the default
  ///   context menu.
  /// * [AdaptiveTextSelectionToolbar], which builds the toolbar itself, and can
  ///   take a list of [ContextMenuButtonItem]s with
  ///   [AdaptiveTextSelectionToolbar.buttonItems].
  /// * [AdaptiveTextSelectionToolbar.getAdaptiveButtons], which builds the
  ///   button Widgets for the current platform given [ContextMenuButtonItem]s.
  List<ContextMenuButtonItem> get contextMenuButtonItems {
    return buttonItemsForToolbarOptions() ?? EditableText.getEditableButtonItems(
      clipboardStatus: clipboardStatus.value,
      onCopy: copyEnabled
          ? () => copySelection(SelectionChangedCause.toolbar)
          : null,
      onCut: cutEnabled
          ? () => cutSelection(SelectionChangedCause.toolbar)
          : null,
      onPaste: pasteEnabled
          ? () => pasteText(SelectionChangedCause.toolbar)
          : null,
      onSelectAll: selectAllEnabled
          ? () => selectAll(SelectionChangedCause.toolbar)
          : null,
      onLookUp: lookUpEnabled
          ? () => lookUpSelection(SelectionChangedCause.toolbar)
          : null,
      onSearchWeb: searchWebEnabled
          ? () => searchWebForSelection(SelectionChangedCause.toolbar)
          : null,
      onShare: shareEnabled
          ? () => shareSelection(SelectionChangedCause.toolbar)
          : null,
      onLiveTextInput: liveTextInputEnabled
          ? () => _startLiveTextInput(SelectionChangedCause.toolbar)
          : null,
    )..addAll(_textProcessingActionButtonItems);
  }

  List<ContextMenuButtonItem> get _textProcessingActionButtonItems {
    final List<ContextMenuButtonItem> buttonItems = <ContextMenuButtonItem>[];
    final TextSelection selection = textEditingValue.selection;
    if (widget.obscureText || !selection.isValid || selection.isCollapsed) {
      return buttonItems;
    }

    for (final ProcessTextAction action in _processTextActions) {
      buttonItems.add(ContextMenuButtonItem(
        label: action.label,
        onPressed: () async {
          final String selectedText = selection.textInside(textEditingValue.text);
          if (selectedText.isNotEmpty) {
            final String? processedText = await _processTextService.processTextAction(action.id, selectedText, widget.readOnly);
            // If an activity does not return a modified version, just hide the toolbar.
            // Otherwise use the result to replace the selected text.
            if (processedText != null && _allowPaste) {
              _pasteText(SelectionChangedCause.toolbar, processedText);
            } else {
              hideToolbar();
            }
          }
        },
      ));
    }
    return buttonItems;
  }

  // State lifecycle:

  @override
  void initState() {
    super.initState();
    _liveTextInputStatus?.addListener(_onChangedLiveTextInputStatus);
    clipboardStatus.addListener(_onChangedClipboardStatus);
    widget.controller.addListener(_didChangeTextEditingValue);
    widget.focusNode.addListener(_handleFocusChanged);
    _cursorVisibilityNotifier.value = widget.showCursor;
    _spellCheckConfiguration = _inferSpellCheckConfiguration(widget.spellCheckConfiguration);
    _initProcessTextActions();
  }

  /// Query the engine to initialize the list of text processing actions to show
  /// in the text selection toolbar.
  Future<void> _initProcessTextActions() async {
    _processTextActions.clear();
    _processTextActions.addAll(await _processTextService.queryTextActions());
  }

  // Whether `TickerMode.of(context)` is true and animations (like blinking the
  // cursor) are supposed to run.
  bool _tickersEnabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _style = MediaQuery.boldTextOf(context)
        ? widget.style.merge(const TextStyle(fontWeight: FontWeight.bold))
        : widget.style;

    final AutofillGroupState? newAutofillGroup = AutofillGroup.maybeOf(context);
    if (currentAutofillScope != newAutofillGroup) {
      _currentAutofillScope?.unregister(autofillId);
      _currentAutofillScope = newAutofillGroup;
      _currentAutofillScope?.register(_effectiveAutofillClient);
    }

    if (!_didAutoFocus && widget.autofocus) {
      _didAutoFocus = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && renderEditable.hasSize) {
          _flagInternalFocus();
          FocusScope.of(context).autofocus(widget.focusNode);
        }
      }, debugLabel: 'EditableText.autofocus');
    }

    // Restart or stop the blinking cursor when TickerMode changes.
    final bool newTickerEnabled = TickerMode.of(context);
    if (_tickersEnabled != newTickerEnabled) {
      _tickersEnabled = newTickerEnabled;
      if (_showBlinkingCursor) {
        _startCursorBlink();
      } else if (!_tickersEnabled && _cursorTimer != null) {
        _stopCursorBlink();
      }
    }

    if (defaultTargetPlatform != TargetPlatform.iOS && defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    // Hide the text selection toolbar on mobile when orientation changes.
    final Orientation orientation = MediaQuery.orientationOf(context);
    if (_lastOrientation == null) {
      _lastOrientation = orientation;
      return;
    }
    if (orientation != _lastOrientation) {
      _lastOrientation = orientation;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        hideToolbar(false);
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        hideToolbar();
      }
    }

    if (_listeningToScrollNotificationObserver) {
      // Only update subscription when we have previously subscribed to the
      // scroll notification observer. We only subscribe to the scroll
      // notification observer when the context menu is shown on platforms that
      // support _platformSupportsFadeOnScroll.
      _scrollNotificationObserver?.removeListener(_handleContextMenuOnParentScroll);
      _scrollNotificationObserver = ScrollNotificationObserver.maybeOf(context);
      _scrollNotificationObserver?.addListener(_handleContextMenuOnParentScroll);
    }
  }

  @override
  void didUpdateWidget(EditableTextDefault oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_didChangeTextEditingValue);
      widget.controller.addListener(_didChangeTextEditingValue);
      _updateRemoteEditingValueIfNeeded();
    }

    if (_selectionOverlay != null
        && (widget.contextMenuBuilder != oldWidget.contextMenuBuilder ||
            widget.selectionControls != oldWidget.selectionControls ||
            widget.onSelectionHandleTapped != oldWidget.onSelectionHandleTapped ||
            widget.dragStartBehavior != oldWidget.dragStartBehavior ||
            widget.magnifierConfiguration != oldWidget.magnifierConfiguration)) {
      final bool shouldShowToolbar = _selectionOverlay!.toolbarIsVisible;
      final bool shouldShowHandles = _selectionOverlay!.handlesVisible;
      _selectionOverlay!.dispose();
      _selectionOverlay = _createSelectionOverlay();
      if (shouldShowToolbar || shouldShowHandles) {
        SchedulerBinding.instance.addPostFrameCallback((Duration _) {
          if (shouldShowToolbar) {
            _selectionOverlay!.showToolbar();
          }
          if (shouldShowHandles) {
            _selectionOverlay!.showHandles();
          }
        });
      }
    } else if (widget.controller.selection != oldWidget.controller.selection) {
      _selectionOverlay?.update(_value);
    }
    _selectionOverlay?.handlesVisible = widget.showSelectionHandles;

    if (widget.autofillClient != oldWidget.autofillClient) {
      _currentAutofillScope?.unregister(oldWidget.autofillClient?.autofillId ?? autofillId);
      _currentAutofillScope?.register(_effectiveAutofillClient);
    }

    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
      updateKeepAlive();
    }

    if (!_shouldCreateInputConnection) {
      _closeInputConnectionIfNeeded();
    } else if (oldWidget.readOnly && _hasFocus) {
      // _openInputConnection must be called after layout information is available.
      // See https://github.com/flutter/flutter/issues/126312
      SchedulerBinding.instance.addPostFrameCallback((Duration _) {
        _openInputConnection();
      }, debugLabel: 'EditableText.openInputConnection');
    }

    if (kIsWeb && _hasInputConnection) {
      if (oldWidget.readOnly != widget.readOnly) {
        _textInputConnection!.updateConfig(_effectiveAutofillClient.textInputConfiguration);
      }
    }

    if (_hasInputConnection) {
      if (oldWidget.obscureText != widget.obscureText) {
        _textInputConnection!.updateConfig(_effectiveAutofillClient.textInputConfiguration);
      }
    }

    if (widget.style != oldWidget.style) {
      // The _textInputConnection will pick up the new style when it attaches in
      // _openInputConnection.
      _style = MediaQuery.boldTextOf(context)
          ? widget.style.merge(const TextStyle(fontWeight: FontWeight.bold))
          : widget.style;
      if (_hasInputConnection) {
        _textInputConnection!.setStyle(
          fontFamily: _style.fontFamily,
          fontSize: _style.fontSize,
          fontWeight: _style.fontWeight,
          textDirection: _textDirection,
          textAlign: widget.textAlign,
        );
      }
    }

    if (widget.showCursor != oldWidget.showCursor) {
      _startOrStopCursorTimerIfNeeded();
    }
    final bool canPaste = widget.selectionControls is TextSelectionHandleControls
        ? pasteEnabled
        : widget.selectionControls?.canPaste(this) ?? false;
    if (widget.selectionEnabled && pasteEnabled && canPaste) {
      clipboardStatus.update();
    }
  }

  void _disposeScrollNotificationObserver() {
    _listeningToScrollNotificationObserver = false;
    if (_scrollNotificationObserver != null) {
      _scrollNotificationObserver!.removeListener(_handleContextMenuOnParentScroll);
      _scrollNotificationObserver = null;
    }
  }

  @override
  void dispose() {
    _internalScrollController?.dispose();
    _currentAutofillScope?.unregister(autofillId);
    widget.controller.removeListener(_didChangeTextEditingValue);
    _floatingCursorResetController?.dispose();
    _floatingCursorResetController = null;
    _closeInputConnectionIfNeeded();
    assert(!_hasInputConnection);
    _cursorTimer?.cancel();
    _cursorTimer = null;
    _backingCursorBlinkOpacityController?.dispose();
    _backingCursorBlinkOpacityController = null;
    _selectionOverlay?.dispose();
    _selectionOverlay = null;
    widget.focusNode.removeListener(_handleFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    _liveTextInputStatus?.removeListener(_onChangedLiveTextInputStatus);
    _liveTextInputStatus?.dispose();
    clipboardStatus.removeListener(_onChangedClipboardStatus);
    clipboardStatus.dispose();
    _cursorVisibilityNotifier.dispose();
    FocusManager.instance.removeListener(_unflagInternalFocus);
    _disposeScrollNotificationObserver();
    super.dispose();
    assert(_batchEditDepth <= 0, 'unfinished batch edits: $_batchEditDepth');
  }

  // TextInputClient implementation:

  /// The last known [TextEditingValue] of the platform text input plugin.
  ///
  /// This value is updated when the platform text input plugin sends a new
  /// update via [updateEditingValue], or when [EditableTextDefault] calls
  /// [TextInputConnection.setEditingState] to overwrite the platform text input
  /// plugin's [TextEditingValue].
  ///
  /// Used in [_updateRemoteEditingValueIfNeeded] to determine whether the
  /// remote value is outdated and needs updating.
  TextEditingValue? _lastKnownRemoteTextEditingValue;

  @override
  TextEditingValue get currentTextEditingValue => _value;

  @override
  void updateEditingValue(TextEditingValue value) {
    // This method handles text editing state updates from the platform text
    // input plugin. The [EditableTextDefault] may not have the focus or an open input
    // connection, as autofill can update a disconnected [EditableTextDefault].

    // Since we still have to support keyboard select, this is the best place
    // to disable text updating.
    if (!_shouldCreateInputConnection) {
      return;
    }

    if (_checkNeedsAdjustAffinity(value)) {
      value = value.copyWith(selection: value.selection.copyWith(affinity: _value.selection.affinity));
    }

    if (widget.readOnly) {
      // In the read-only case, we only care about selection changes, and reject
      // everything else.
      value = _value.copyWith(selection: value.selection);
    }
    _lastKnownRemoteTextEditingValue = value;

    if (value == _value) {
      // This is possible, for example, when the numeric keyboard is input,
      // the engine will notify twice for the same value.
      // Track at https://github.com/flutter/flutter/issues/65811
      return;
    }

    if (value.text == _value.text && value.composing == _value.composing) {
      // `selection` is the only change.
      SelectionChangedCause cause;
      if (_textInputConnection?.scribbleInProgress ?? false) {
        cause = SelectionChangedCause.scribble;
      } else if (_pointOffsetOrigin != null) {
        // For floating cursor selection when force pressing the space bar.
        cause = SelectionChangedCause.forcePress;
      } else {
        cause = SelectionChangedCause.keyboard;
      }
      _handleSelectionChanged(value.selection, cause);
    } else {
      if (value.text != _value.text) {
        // Hide the toolbar if the text was changed, but only hide the toolbar
        // overlay; the selection handle's visibility will be handled
        // by `_handleSelectionChanged`. https://github.com/flutter/flutter/issues/108673
        hideToolbar(false);
      }
      _currentPromptRectRange = null;

      final bool revealObscuredInput = _hasInputConnection
                                    && widget.obscureText
                                    && WidgetsBinding.instance.platformDispatcher.brieflyShowPassword
                                    && value.text.length == _value.text.length + 1;

      _obscureShowCharTicksPending = revealObscuredInput ? _kObscureShowLatestCharCursorTicks : 0;
      _obscureLatestCharIndex = revealObscuredInput ? _value.selection.baseOffset : null;
      _formatAndSetValue(value, SelectionChangedCause.keyboard);
    }

    if (_showBlinkingCursor && _cursorTimer != null) {
      // To keep the cursor from blinking while typing, restart the timer here.
      _stopCursorBlink(resetCharTicks: false);
      _startCursorBlink();
    }

    // Wherever the value is changed by the user, schedule a showCaretOnScreen
    // to make sure the user can see the changes they just made. Programmatic
    // changes to `textEditingValue` do not trigger the behavior even if the
    // text field is focused.
    _scheduleShowCaretOnScreen(withAnimation: true);
  }

  bool _checkNeedsAdjustAffinity(TextEditingValue value) {
    // Trust the engine affinity if the text changes or selection changes.
    return value.text == _value.text &&
      value.selection.isCollapsed == _value.selection.isCollapsed &&
      value.selection.start == _value.selection.start &&
      value.selection.affinity != _value.selection.affinity;
  }

  @override
  void performAction(TextInputAction action) {
    switch (action) {
      case TextInputAction.newline:
        // If this is a multiline EditableText, do nothing for a "newline"
        // action; The newline is already inserted. Otherwise, finalize
        // editing.
        if (!_isMultiline) {
          _finalizeEditing(action, shouldUnfocus: true);
        }
      case TextInputAction.done:
      case TextInputAction.go:
      case TextInputAction.next:
      case TextInputAction.previous:
      case TextInputAction.search:
      case TextInputAction.send:
        _finalizeEditing(action, shouldUnfocus: true);
      case TextInputAction.continueAction:
      case TextInputAction.emergencyCall:
      case TextInputAction.join:
      case TextInputAction.none:
      case TextInputAction.route:
      case TextInputAction.unspecified:
        // Finalize editing, but don't give up focus because this keyboard
        // action does not imply the user is done inputting information.
        _finalizeEditing(action, shouldUnfocus: false);
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    widget.onAppPrivateCommand?.call(action, data);
  }

  @override
  void insertContent(KeyboardInsertedContent content) {
    assert(widget.contentInsertionConfiguration?.allowedMimeTypes.contains(content.mimeType) ?? false);
    widget.contentInsertionConfiguration?.onContentInserted.call(content);
  }

  // The original position of the caret on FloatingCursorDragState.start.
  Offset? _startCaretCenter;

  // The most recent text position as determined by the location of the floating
  // cursor.
  TextPosition? _lastTextPosition;

  // The offset of the floating cursor as determined from the start call.
  Offset? _pointOffsetOrigin;

  // The most recent position of the floating cursor.
  Offset? _lastBoundedOffset;

  // Because the center of the cursor is preferredLineHeight / 2 below the touch
  // origin, but the touch origin is used to determine which line the cursor is
  // on, we need this offset to correctly render and move the cursor.
  Offset get _floatingCursorOffset => Offset(0, renderEditable.preferredLineHeight / 2);

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    _floatingCursorResetController ??= AnimationController(
      vsync: this,
    )..addListener(_onFloatingCursorResetTick);
    switch (point.state) {
      case FloatingCursorDragState.Start:
        if (_floatingCursorResetController!.isAnimating) {
          _floatingCursorResetController!.stop();
          _onFloatingCursorResetTick();
        }
        // Stop cursor blinking and making it visible.
        _stopCursorBlink(resetCharTicks: false);
        _cursorBlinkOpacityController.value = 1.0;
        // We want to send in points that are centered around a (0,0) origin, so
        // we cache the position.
        _pointOffsetOrigin = point.offset;

        final Offset startCaretCenter;
        final TextPosition currentTextPosition;
        final bool shouldResetOrigin;
        // Only non-null when starting a floating cursor via long press.
        if (point.startLocation != null) {
          shouldResetOrigin = false;
          (startCaretCenter, currentTextPosition) = point.startLocation!;
        } else {
          shouldResetOrigin = true;
          currentTextPosition = TextPosition(offset: renderEditable.selection!.baseOffset, affinity: renderEditable.selection!.affinity);
          startCaretCenter = renderEditable.getLocalRectForCaret(currentTextPosition).center;
        }

        _startCaretCenter = startCaretCenter;
        _lastBoundedOffset = renderEditable.calculateBoundedFloatingCursorOffset(_startCaretCenter! - _floatingCursorOffset, shouldResetOrigin: shouldResetOrigin);
        _lastTextPosition = currentTextPosition;
        renderEditable.setFloatingCursor(point.state, _lastBoundedOffset!, _lastTextPosition!);
      case FloatingCursorDragState.Update:
        final Offset centeredPoint = point.offset! - _pointOffsetOrigin!;
        final Offset rawCursorOffset = _startCaretCenter! + centeredPoint - _floatingCursorOffset;

        _lastBoundedOffset = renderEditable.calculateBoundedFloatingCursorOffset(rawCursorOffset);
        _lastTextPosition = renderEditable.getPositionForPoint(renderEditable.localToGlobal(_lastBoundedOffset! + _floatingCursorOffset));
        renderEditable.setFloatingCursor(point.state, _lastBoundedOffset!, _lastTextPosition!);
      case FloatingCursorDragState.End:
        // Resume cursor blinking.
        _startCursorBlink();
        // We skip animation if no update has happened.
        if (_lastTextPosition != null && _lastBoundedOffset != null) {
          _floatingCursorResetController!.value = 0.0;
          _floatingCursorResetController!.animateTo(1.0, duration: _floatingCursorResetTime, curve: Curves.decelerate);
        }
    }
  }

  void _onFloatingCursorResetTick() {
    final Offset finalPosition = renderEditable.getLocalRectForCaret(_lastTextPosition!).centerLeft - _floatingCursorOffset;
    if (_floatingCursorResetController!.isCompleted) {
      renderEditable.setFloatingCursor(FloatingCursorDragState.End, finalPosition, _lastTextPosition!);
      // During a floating cursor's move gesture (1 finger), a cursor is
      // animated only visually, without actually updating the selection.
      // Only after move gesture is complete, this function will be called
      // to actually update the selection to the new cursor location with
      // zero selection length.

      // However, During a floating cursor's selection gesture (2 fingers), the
      // selection is constantly updated by the engine throughout the gesture.
      // Thus when the gesture is complete, we should not update the selection
      // to the cursor location with zero selection length, because that would
      // overwrite the selection made by floating cursor selection.

      // Here we use `isCollapsed` to distinguish between floating cursor's
      // move gesture (1 finger) vs selection gesture (2 fingers), as
      // the engine does not provide information other than notifying a
      // new selection during with selection gesture (2 fingers).
      if (renderEditable.selection!.isCollapsed) {
        // The cause is technically the force cursor, but the cause is listed as tap as the desired functionality is the same.
        _handleSelectionChanged(TextSelection.fromPosition(_lastTextPosition!), SelectionChangedCause.forcePress);
      }
      _startCaretCenter = null;
      _lastTextPosition = null;
      _pointOffsetOrigin = null;
      _lastBoundedOffset = null;
    } else {
      final double lerpValue = _floatingCursorResetController!.value;
      final double lerpX = ui.lerpDouble(_lastBoundedOffset!.dx, finalPosition.dx, lerpValue)!;
      final double lerpY = ui.lerpDouble(_lastBoundedOffset!.dy, finalPosition.dy, lerpValue)!;

      renderEditable.setFloatingCursor(FloatingCursorDragState.Update, Offset(lerpX, lerpY), _lastTextPosition!, resetLerpValue: lerpValue);
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  void _finalizeEditing(TextInputAction action, {required bool shouldUnfocus}) {
    // Take any actions necessary now that the user has completed editing.
    if (widget.onEditingComplete != null) {
      try {
        widget.onEditingComplete!();
      } catch (exception, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'widgets',
          context: ErrorDescription('while calling onEditingComplete for $action'),
        ));
      }
    } else {
      // Default behavior if the developer did not provide an
      // onEditingComplete callback: Finalize editing and remove focus, or move
      // it to the next/previous field, depending on the action.
      widget.controller.clearComposing();
      if (shouldUnfocus) {
        switch (action) {
          case TextInputAction.none:
          case TextInputAction.unspecified:
          case TextInputAction.done:
          case TextInputAction.go:
          case TextInputAction.search:
          case TextInputAction.send:
          case TextInputAction.continueAction:
          case TextInputAction.join:
          case TextInputAction.route:
          case TextInputAction.emergencyCall:
          case TextInputAction.newline:
            widget.focusNode.unfocus();
          case TextInputAction.next:
            widget.focusNode.nextFocus();
          case TextInputAction.previous:
            widget.focusNode.previousFocus();
        }
      }
    }

    final ValueChanged<String>? onSubmitted = widget.onSubmitted;
    if (onSubmitted == null) {
      return;
    }

    // Invoke optional callback with the user's submitted content.
    try {
      onSubmitted(_value.text);
    } catch (exception, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: 'widgets',
        context: ErrorDescription('while calling onSubmitted for $action'),
      ));
    }

    // If `shouldUnfocus` is true, the text field should no longer be focused
    // after the microtask queue is drained. But in case the developer cancelled
    // the focus change in the `onSubmitted` callback by focusing this input
    // field again, reset the soft keyboard.
    // See https://github.com/flutter/flutter/issues/84240.
    //
    // `_restartConnectionIfNeeded` creates a new TextInputConnection to replace
    // the current one. This on iOS switches to a new input view and on Android
    // restarts the input method, and in both cases the soft keyboard will be
    // reset.
    if (shouldUnfocus) {
      _scheduleRestartConnection();
    }
  }

  int _batchEditDepth = 0;

  /// Begins a new batch edit, within which new updates made to the text editing
  /// value will not be sent to the platform text input plugin.
  ///
  /// Batch edits nest. When the outermost batch edit finishes, [endBatchEdit]
  /// will attempt to send [currentTextEditingValue] to the text input plugin if
  /// it detected a change.
  void beginBatchEdit() {
    _batchEditDepth += 1;
  }

  /// Ends the current batch edit started by the last call to [beginBatchEdit],
  /// and send [currentTextEditingValue] to the text input plugin if needed.
  ///
  /// Throws an error in debug mode if this [EditableTextDefault] is not in a batch
  /// edit.
  void endBatchEdit() {
    _batchEditDepth -= 1;
    assert(
      _batchEditDepth >= 0,
      'Unbalanced call to endBatchEdit: beginBatchEdit must be called first.',
    );
    _updateRemoteEditingValueIfNeeded();
  }

  void _updateRemoteEditingValueIfNeeded() {
    if (_batchEditDepth > 0 || !_hasInputConnection) {
      return;
    }
    final TextEditingValue localValue = _value;
    if (localValue == _lastKnownRemoteTextEditingValue) {
      return;
    }
    _textInputConnection!.setEditingState(localValue);
    _lastKnownRemoteTextEditingValue = localValue;
  }

  TextEditingValue get _value => widget.controller.value;
  set _value(TextEditingValue value) {
    widget.controller.value = value;
  }

  bool get _hasFocus => widget.focusNode.hasFocus;
  bool get _isMultiline => widget.maxLines != 1;

  // Finds the closest scroll offset to the current scroll offset that fully
  // reveals the given caret rect. If the given rect's main axis extent is too
  // large to be fully revealed in `renderEditable`, it will be centered along
  // the main axis.
  //
  // If this is a multiline EditableText (which means the Editable can only
  // scroll vertically), the given rect's height will first be extended to match
  // `renderEditable.preferredLineHeight`, before the target scroll offset is
  // calculated.
  RevealedOffset _getOffsetToRevealCaret(Rect rect) {
    if (!_scrollController.position.allowImplicitScrolling) {
      return RevealedOffset(offset: _scrollController.offset, rect: rect);
    }

    final Size editableSize = renderEditable.size;
    final double additionalOffset;
    final Offset unitOffset;

    if (!_isMultiline) {
      additionalOffset = rect.width >= editableSize.width
        // Center `rect` if it's oversized.
        ? editableSize.width / 2 - rect.center.dx
        // Valid additional offsets range from (rect.right - size.width)
        // to (rect.left). Pick the closest one if out of range.
        : clampDouble(0.0, rect.right - editableSize.width, rect.left);
      unitOffset = const Offset(1, 0);
    } else {
      // The caret is vertically centered within the line. Expand the caret's
      // height so that it spans the line because we're going to ensure that the
      // entire expanded caret is scrolled into view.
      final Rect expandedRect = Rect.fromCenter(
        center: rect.center,
        width: rect.width,
        height: math.max(rect.height, renderEditable.preferredLineHeight),
      );

      additionalOffset = expandedRect.height >= editableSize.height
        ? editableSize.height / 2 - expandedRect.center.dy
        : clampDouble(0.0, expandedRect.bottom - editableSize.height, expandedRect.top);
      unitOffset = const Offset(0, 1);
    }

    // No overscrolling when encountering tall fonts/scripts that extend past
    // the ascent.
    final double targetOffset = clampDouble(
      additionalOffset + _scrollController.offset,
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    final double offsetDelta = _scrollController.offset - targetOffset;
    return RevealedOffset(rect: rect.shift(unitOffset * offsetDelta), offset: targetOffset);
  }

  /// Whether to send the autofill information to the autofill service. True by
  /// default.
  bool get _needsAutofill => _effectiveAutofillClient.textInputConfiguration.autofillConfiguration.enabled;

  // Must be called after layout.
  // See https://github.com/flutter/flutter/issues/126312
  void _openInputConnection() {
    if (!_shouldCreateInputConnection) {
      return;
    }
    if (!_hasInputConnection) {
      final TextEditingValue localValue = _value;

      // When _needsAutofill == true && currentAutofillScope == null, autofill
      // is allowed but saving the user input from the text field is
      // discouraged.
      //
      // In case the autofillScope changes from a non-null value to null, or
      // _needsAutofill changes to false from true, the platform needs to be
      // notified to exclude this field from the autofill context. So we need to
      // provide the autofillId.
      _textInputConnection = _needsAutofill && currentAutofillScope != null
        ? currentAutofillScope!.attach(this, _effectiveAutofillClient.textInputConfiguration)
        : TextInput.attach(this, _effectiveAutofillClient.textInputConfiguration);
      _updateSizeAndTransform();
      _schedulePeriodicPostFrameCallbacks();
      _textInputConnection!
        ..setStyle(
          fontFamily: _style.fontFamily,
          fontSize: _style.fontSize,
          fontWeight: _style.fontWeight,
          textDirection: _textDirection,
          textAlign: widget.textAlign,
        )
        ..setEditingState(localValue)
        ..show();
      if (_needsAutofill) {
        // Request autofill AFTER the size and the transform have been sent to
        // the platform text input plugin.
        _textInputConnection!.requestAutofill();
      }
      _lastKnownRemoteTextEditingValue = localValue;
    } else {
      _textInputConnection!.show();
    }
  }

  void _closeInputConnectionIfNeeded() {
    if (_hasInputConnection) {
      _textInputConnection!.close();
      _textInputConnection = null;
      _lastKnownRemoteTextEditingValue = null;
      _scribbleCacheKey = null;
      removeTextPlaceholder();
    }
  }

  void _openOrCloseInputConnectionIfNeeded() {
    if (_hasFocus && widget.focusNode.consumeKeyboardToken()) {
      _openInputConnection();
    } else if (!_hasFocus) {
      _closeInputConnectionIfNeeded();
      widget.controller.clearComposing();
    }
  }

  bool _restartConnectionScheduled = false;
  void _scheduleRestartConnection() {
    if (_restartConnectionScheduled) {
      return;
    }
    _restartConnectionScheduled = true;
    scheduleMicrotask(_restartConnectionIfNeeded);
  }
  // Discards the current [TextInputConnection] and establishes a new one.
  //
  // This method is rarely needed. This is currently used to reset the input
  // type when the "submit" text input action is triggered and the developer
  // puts the focus back to this input field..
  void _restartConnectionIfNeeded() {
    _restartConnectionScheduled = false;
    if (!_hasInputConnection || !_shouldCreateInputConnection) {
      return;
    }
    _textInputConnection!.close();
    _textInputConnection = null;
    _lastKnownRemoteTextEditingValue = null;

    final AutofillScope? currentAutofillScope = _needsAutofill ? this.currentAutofillScope : null;
    final TextInputConnection newConnection = currentAutofillScope?.attach(this, textInputConfiguration)
      ?? TextInput.attach(this, _effectiveAutofillClient.textInputConfiguration);
    _textInputConnection = newConnection;

    newConnection
      ..show()
      ..setStyle(
        fontFamily: _style.fontFamily,
        fontSize: _style.fontSize,
        fontWeight: _style.fontWeight,
        textDirection: _textDirection,
        textAlign: widget.textAlign,
      )
      ..setEditingState(_value);
    _lastKnownRemoteTextEditingValue = _value;
  }


  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {
    if (_hasFocus && _hasInputConnection) {
      oldControl?.hide();
      newControl?.show();
    }
  }

  @override
  void connectionClosed() {
    if (_hasInputConnection) {
      _textInputConnection!.connectionClosedReceived();
      _textInputConnection = null;
      _lastKnownRemoteTextEditingValue = null;
      widget.focusNode.unfocus();
    }
  }

  // Indicates that a call to _handleFocusChanged originated within
  // EditableTextDefault, allowing it to distinguish between internal and external
  // focus changes.
  bool _nextFocusChangeIsInternal = false;

  // Sets _nextFocusChangeIsInternal to true only until any subsequent focus
  // change happens.
  void _flagInternalFocus() {
    _nextFocusChangeIsInternal = true;
    FocusManager.instance.addListener(_unflagInternalFocus);
  }

  void _unflagInternalFocus() {
    _nextFocusChangeIsInternal = false;
    FocusManager.instance.removeListener(_unflagInternalFocus);
  }

  /// Express interest in interacting with the keyboard.
  ///
  /// If this control is already attached to the keyboard, this function will
  /// request that the keyboard become visible. Otherwise, this function will
  /// ask the focus system that it become focused. If successful in acquiring
  /// focus, the control will then attach to the keyboard and request that the
  /// keyboard become visible.
  void requestKeyboard() {
    if (_hasFocus) {
      _openInputConnection();
    } else {
      _flagInternalFocus();
      widget.focusNode.requestFocus(); // This eventually calls _openInputConnection also, see _handleFocusChanged.
    }
  }

  void _updateOrDisposeSelectionOverlayIfNeeded() {
    if (_selectionOverlay != null) {
      if (_hasFocus) {
        _selectionOverlay!.update(_value);
      } else {
        _selectionOverlay!.dispose();
        _selectionOverlay = null;
      }
    }
  }

  final bool _platformSupportsFadeOnScroll = switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };

  bool _isInternalScrollableNotification(BuildContext? notificationContext) {
    final ScrollableState? scrollableState = notificationContext?.findAncestorStateOfType<ScrollableState>();
    return _scrollableKey.currentContext == scrollableState?.context;
  }

  bool _scrollableNotificationIsFromSameSubtree(BuildContext? notificationContext) {
    if (notificationContext == null) {
      return false;
    }
    BuildContext? currentContext = context;
    // The notification context of a ScrollNotification points to the RawGestureDetector
    // of the Scrollable. We get the ScrollableState associated with this notification
    // by looking up the tree.
    final ScrollableState? notificationScrollableState = notificationContext.findAncestorStateOfType<ScrollableState>();
    if (notificationScrollableState == null) {
      return false;
    }
    while (currentContext != null) {
      final ScrollableState? scrollableState = currentContext.findAncestorStateOfType<ScrollableState>();
      if (scrollableState == notificationScrollableState) {
        return true;
      }
      currentContext = scrollableState?.context;
    }
    return false;
  }

  void _handleContextMenuOnParentScroll(ScrollNotification notification) {
    // Do some preliminary checks to avoid expensive subtree traversal.
    if (notification is! ScrollStartNotification
       && notification is! ScrollEndNotification) {
      return;
    }
    if (notification is ScrollStartNotification
       && _dataWhenToolbarShowScheduled != null) {
      return;
    }
    if (notification is ScrollEndNotification
       && _dataWhenToolbarShowScheduled == null) {
      return;
    }
    if (notification is ScrollEndNotification
       && _dataWhenToolbarShowScheduled!.value != _value) {
      _dataWhenToolbarShowScheduled = null;
      _disposeScrollNotificationObserver();
      return;
    }
    if (_isInternalScrollableNotification(notification.context)) {
      return;
    }
    if (!_scrollableNotificationIsFromSameSubtree(notification.context)) {
      return;
    }
    _handleContextMenuOnScroll(notification);
  }

  Rect _calculateDeviceRect() {
    final Size screenSize = MediaQuery.sizeOf(context);
    final ui.FlutterView view = View.of(context);
    final double obscuredVertical = (view.padding.top + view.padding.bottom + view.viewInsets.bottom) / view.devicePixelRatio;
    final double obscuredHorizontal = (view.padding.left + view.padding.right) / view.devicePixelRatio;
    final Size visibleScreenSize = Size(screenSize.width - obscuredHorizontal, screenSize.height - obscuredVertical);
    return Rect.fromLTWH(view.padding.left / view.devicePixelRatio, view.padding.top / view.devicePixelRatio, visibleScreenSize.width, visibleScreenSize.height);
  }

  bool _showToolbarOnScreenScheduled = false;
  void _handleContextMenuOnScroll(ScrollNotification notification) {
    if (_webContextMenuEnabled) {
      return;
    }
    if (!_platformSupportsFadeOnScroll) {
      _selectionOverlay?.updateForScroll();
      return;
    }
    // When the scroll begins and the toolbar is visible, hide it
    // until scrolling ends.
    //
    // The selection and renderEditable need to be visible within the current
    // viewport for the toolbar to show when scrolling ends. If they are not
    // then the toolbar is shown when they are scrolled back into view, unless
    // invalidated by a change in TextEditingValue.
    if (notification is ScrollStartNotification) {
      if (_dataWhenToolbarShowScheduled != null) {
        return;
      }
      final bool toolbarIsVisible = _selectionOverlay != null
                                  && _selectionOverlay!.toolbarIsVisible
                                  && !_selectionOverlay!.spellCheckToolbarIsVisible;
      if (!toolbarIsVisible) {
        return;
      }
      final List<TextBox> selectionBoxes = renderEditable.getBoxesForSelection(_value.selection);
      final Rect selectionBounds = _value.selection.isCollapsed || selectionBoxes.isEmpty
                                      ? renderEditable.getLocalRectForCaret(_value.selection.extent)
                                      : selectionBoxes
                                          .map((TextBox box) => box.toRect())
                                          .reduce((Rect result, Rect rect) => result.expandToInclude(rect));
      _dataWhenToolbarShowScheduled = (value: _value, selectionBounds: selectionBounds);
      _selectionOverlay?.hideToolbar();
    } else if (notification is ScrollEndNotification) {
      if (_dataWhenToolbarShowScheduled == null) {
        return;
      }
      if (_dataWhenToolbarShowScheduled!.value != _value) {
        // Value has changed so we should invalidate any toolbar scheduling.
        _dataWhenToolbarShowScheduled = null;
        _disposeScrollNotificationObserver();
        return;
      }

      if (_showToolbarOnScreenScheduled) {
        return;
      }
      _showToolbarOnScreenScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((Duration _) {
        _showToolbarOnScreenScheduled = false;
        if (!mounted) {
          return;
        }
        final Rect deviceRect = _calculateDeviceRect();
        final bool selectionVisibleInEditable = renderEditable.selectionStartInViewport.value || renderEditable.selectionEndInViewport.value;
        final Rect selectionBounds = MatrixUtils.transformRect(renderEditable.getTransformTo(null), _dataWhenToolbarShowScheduled!.selectionBounds);
        final bool selectionOverlapsWithDeviceRect = !selectionBounds.hasNaN && deviceRect.overlaps(selectionBounds);

        if (selectionVisibleInEditable
          && selectionOverlapsWithDeviceRect
          && _selectionInViewport(_dataWhenToolbarShowScheduled!.selectionBounds)) {
          showToolbar();
          _dataWhenToolbarShowScheduled = null;
        }
      }, debugLabel: 'EditableText.scheduleToolbar');
    }
  }

  bool _selectionInViewport(Rect selectionBounds) {
    RenderAbstractViewport? closestViewport = RenderAbstractViewport.maybeOf(renderEditable);
    while (closestViewport != null) {
      final Rect selectionBoundsLocalToViewport = MatrixUtils.transformRect(renderEditable.getTransformTo(closestViewport), selectionBounds);
      if (selectionBoundsLocalToViewport.hasNaN
         || closestViewport.paintBounds.hasNaN
         || !closestViewport.paintBounds.overlaps(selectionBoundsLocalToViewport)) {
        return false;
      }
      closestViewport = RenderAbstractViewport.maybeOf(closestViewport.parent);
    }
    return true;
  }

  TextSelectionOverlay _createSelectionOverlay() {
    final EditableTextContextMenuBuilder? contextMenuBuilder = widget.contextMenuBuilder;
    final TextSelectionOverlay selectionOverlay = TextSelectionOverlay(
      clipboardStatus: clipboardStatus,
      context: context,
      value: _value,
      debugRequiredFor: widget,
      toolbarLayerLink: _toolbarLayerLink,
      startHandleLayerLink: _startHandleLayerLink,
      endHandleLayerLink: _endHandleLayerLink,
      renderObject: renderEditable,
      selectionControls: widget.selectionControls,
      selectionDelegate: this,
      dragStartBehavior: widget.dragStartBehavior,
      onSelectionHandleTapped: widget.onSelectionHandleTapped,
      contextMenuBuilder: contextMenuBuilder == null || _webContextMenuEnabled
        ? null
        : (BuildContext context) {
          return contextMenuBuilder(
            context,
            this,
          );
        },
      magnifierConfiguration: widget.magnifierConfiguration,
    );

    return selectionOverlay;
  }

  @pragma('vm:notify-debugger-on-exception')
  void _handleSelectionChanged(TextSelection selection, SelectionChangedCause? cause) {
    // We return early if the selection is not valid. This can happen when the
    // text of [EditableText] is updated at the same time as the selection is
    // changed by a gesture event.
    if (!widget.controller.selection.isWithinTextBounds(widget.controller.text)) {
      return;
    }

    widget.controller.selection = selection;

    // This will show the keyboard for all selection changes on the
    // EditableText except for those triggered by a keyboard input.
    // Typically EditableText shouldn't take user keyboard input if
    // it's not focused already. If the EditableText is being
    // autofilled it shouldn't request focus.
    switch (cause) {
      case null:
      case SelectionChangedCause.doubleTap:
      case SelectionChangedCause.drag:
      case SelectionChangedCause.forcePress:
      case SelectionChangedCause.longPress:
      case SelectionChangedCause.scribble:
      case SelectionChangedCause.tap:
      case SelectionChangedCause.toolbar:
        requestKeyboard();
      case SelectionChangedCause.keyboard:
        if (_hasFocus) {
          requestKeyboard();
        }
    }
    if (widget.selectionControls == null && widget.contextMenuBuilder == null) {
      _selectionOverlay?.dispose();
      _selectionOverlay = null;
    } else {
      if (_selectionOverlay == null) {
        _selectionOverlay = _createSelectionOverlay();
      } else {
        _selectionOverlay!.update(_value);
      }
      _selectionOverlay!.handlesVisible = widget.showSelectionHandles;
      _selectionOverlay!.showHandles();
    }
    // TODO(chunhtai): we should make sure selection actually changed before
    // we call the onSelectionChanged.
    // https://github.com/flutter/flutter/issues/76349.
    try {
      widget.onSelectionChanged?.call(selection, cause);
    } catch (exception, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: 'widgets',
        context: ErrorDescription('while calling onSelectionChanged for $cause'),
      ));
    }

    // To keep the cursor from blinking while it moves, restart the timer here.
    if (_showBlinkingCursor && _cursorTimer != null) {
      _stopCursorBlink(resetCharTicks: false);
      _startCursorBlink();
    }
  }

  // Animation configuration for scrolling the caret back on screen.
  static const Duration _caretAnimationDuration = Duration(milliseconds: 100);
  static const Curve _caretAnimationCurve = Curves.fastOutSlowIn;

  bool _showCaretOnScreenScheduled = false;

  void _scheduleShowCaretOnScreen({required bool withAnimation}) {
    if (_showCaretOnScreenScheduled) {
      return;
    }
    _showCaretOnScreenScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      _showCaretOnScreenScheduled = false;
      // Since we are in a post frame callback, check currentContext in case
      // RenderEditable has been disposed (in which case it will be null).
      final RenderEditable? renderEditable =
          _editableKey.currentContext?.findRenderObject() as RenderEditable?;
      if (renderEditable == null
          || !(renderEditable.selection?.isValid ?? false)
          || !_scrollController.hasClients) {
        return;
      }

      final double lineHeight = renderEditable.preferredLineHeight;

      // Enlarge the target rect by scrollPadding to ensure that caret is not
      // positioned directly at the edge after scrolling.
      double bottomSpacing = widget.scrollPadding.bottom;
      if (_selectionOverlay?.selectionControls != null) {
        final double handleHeight = _selectionOverlay!.selectionControls!
          .getHandleSize(lineHeight).height;
        final double interactiveHandleHeight = math.max(
          handleHeight,
          kMinInteractiveDimension,
        );
        final Offset anchor = _selectionOverlay!.selectionControls!
          .getHandleAnchor(
            TextSelectionHandleType.collapsed,
            lineHeight,
          );
        final double handleCenter = handleHeight / 2 - anchor.dy;
        bottomSpacing = math.max(
          handleCenter + interactiveHandleHeight / 2,
          bottomSpacing,
        );
      }

      final EdgeInsets caretPadding = widget.scrollPadding
        .copyWith(bottom: bottomSpacing);

      final Rect caretRect = renderEditable.getLocalRectForCaret(renderEditable.selection!.extent);
      final RevealedOffset targetOffset = _getOffsetToRevealCaret(caretRect);

      final Rect rectToReveal;
      final TextSelection selection = textEditingValue.selection;
      if (selection.isCollapsed) {
        rectToReveal = targetOffset.rect;
      } else {
        final List<TextBox> selectionBoxes = renderEditable.getBoxesForSelection(selection);
        // selectionBoxes may be empty if, for example, the selection does not
        // encompass a full character, like if it only contained part of an
        // extended grapheme cluster.
        if (selectionBoxes.isEmpty) {
          rectToReveal = targetOffset.rect;
        } else {
          rectToReveal = selection.baseOffset < selection.extentOffset ?
            selectionBoxes.last.toRect() : selectionBoxes.first.toRect();
        }
      }

      if (withAnimation) {
        _scrollController.animateTo(
          targetOffset.offset,
          duration: _caretAnimationDuration,
          curve: _caretAnimationCurve,
        );
        renderEditable.showOnScreen(
          rect: caretPadding.inflateRect(rectToReveal),
          duration: _caretAnimationDuration,
          curve: _caretAnimationCurve,
        );
      } else {
        _scrollController.jumpTo(targetOffset.offset);
        renderEditable.showOnScreen(
          rect: caretPadding.inflateRect(rectToReveal),
        );
      }
    }, debugLabel: 'EditableText.showCaret');
  }

  late double _lastBottomViewInset;

  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }
    final ui.FlutterView view = View.of(context);
    if (_lastBottomViewInset != view.viewInsets.bottom) {
      SchedulerBinding.instance.addPostFrameCallback((Duration _) {
        _selectionOverlay?.updateForScroll();
      }, debugLabel: 'EditableText.updateForScroll');
      if (_lastBottomViewInset < view.viewInsets.bottom) {
        // Because the metrics change signal from engine will come here every frame
        // (on both iOS and Android). So we don't need to show caret with animation.
        _scheduleShowCaretOnScreen(withAnimation: false);
      }
    }
    _lastBottomViewInset = view.viewInsets.bottom;
  }

  Future<void> _performSpellCheck(final String text) async {
    try {
      final Locale? localeForSpellChecking = widget.locale ?? Localizations.maybeLocaleOf(context);

      assert(
        localeForSpellChecking != null,
        'Locale must be specified in widget or Localization widget must be in scope',
      );

      final List<SuggestionSpan>? suggestions = await
        _spellCheckConfiguration
          .spellCheckService!
            .fetchSpellCheckSuggestions(localeForSpellChecking!, text);

      if (suggestions == null) {
        // The request to fetch spell check suggestions was canceled due to ongoing request.
        return;
      }

      spellCheckResults = SpellCheckResults(text, suggestions);
      renderEditable.text = buildTextSpan();
    } catch (exception, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: 'widgets',
        context: ErrorDescription('while performing spell check'),
      ));
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  void _formatAndSetValue(TextEditingValue value, SelectionChangedCause? cause, {bool userInteraction = false}) {
    final TextEditingValue oldValue = _value;
    final bool textChanged = oldValue.text != value.text;
    final bool textCommitted = !oldValue.composing.isCollapsed && value.composing.isCollapsed;
    final bool selectionChanged = oldValue.selection != value.selection;

    if (textChanged || textCommitted) {
      // Only apply input formatters if the text has changed (including uncommitted
      // text in the composing region), or when the user committed the composing
      // text.
      // Gboard is very persistent in restoring the composing region. Applying
      // input formatters on composing-region-only changes (except clearing the
      // current composing region) is very infinite-loop-prone: the formatters
      // will keep trying to modify the composing region while Gboard will keep
      // trying to restore the original composing region.
      try {
        value = widget.inputFormatters?.fold<TextEditingValue>(
          value,
          (TextEditingValue newValue, TextInputFormatter formatter) => formatter.formatEditUpdate(_value, newValue),
        ) ?? value;

        if (spellCheckEnabled && value.text.isNotEmpty && _value.text != value.text) {
          _performSpellCheck(value.text);
        }
      } catch (exception, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'widgets',
          context: ErrorDescription('while applying input formatters'),
        ));
      }
    }

    final TextSelection oldTextSelection = textEditingValue.selection;

    // Put all optional user callback invocations in a batch edit to prevent
    // sending multiple `TextInput.updateEditingValue` messages.
    beginBatchEdit();
    _value = value;
    // Changes made by the keyboard can sometimes be "out of band" for listening
    // components, so always send those events, even if we didn't think it
    // changed. Also, the user long pressing should always send a selection change
    // as well.
    if (selectionChanged ||
        (userInteraction &&
        (cause == SelectionChangedCause.longPress ||
         cause == SelectionChangedCause.keyboard))) {
      _handleSelectionChanged(_value.selection, cause);
      _bringIntoViewBySelectionState(oldTextSelection, value.selection, cause);
    }
    final String currentText = _value.text;
    if (oldValue.text != currentText) {
      try {
        widget.onChanged?.call(currentText);
      } catch (exception, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'widgets',
          context: ErrorDescription('while calling onChanged'),
        ));
      }
    }
    endBatchEdit();
  }

  void _bringIntoViewBySelectionState(TextSelection oldSelection, TextSelection newSelection, SelectionChangedCause? cause) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        if (cause == SelectionChangedCause.longPress ||
            cause == SelectionChangedCause.drag) {
          bringIntoView(newSelection.extent);
        }
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
      case TargetPlatform.android:
        if (cause == SelectionChangedCause.drag) {
          if (oldSelection.baseOffset != newSelection.baseOffset) {
            bringIntoView(newSelection.base);
          } else if (oldSelection.extentOffset != newSelection.extentOffset) {
            bringIntoView(newSelection.extent);
          }
        }
    }
  }

  void _onCursorColorTick() {
    final double effectiveOpacity = math.min(widget.cursorColor.alpha / 255.0, _cursorBlinkOpacityController.value);
    renderEditable.cursorColor = widget.cursorColor.withOpacity(effectiveOpacity);
    _cursorVisibilityNotifier.value = widget.showCursor && (EditableText.debugDeterministicCursor || _cursorBlinkOpacityController.value > 0);
  }

  bool get _showBlinkingCursor => _hasFocus && _value.selection.isCollapsed && widget.showCursor && _tickersEnabled && !renderEditable.floatingCursorOn;

  /// Whether the blinking cursor is actually visible at this precise moment
  /// (it's hidden half the time, since it blinks).
  @visibleForTesting
  bool get cursorCurrentlyVisible => _cursorBlinkOpacityController.value > 0;

  /// The cursor blink interval (the amount of time the cursor is in the "on"
  /// state or the "off" state). A complete cursor blink period is twice this
  /// value (half on, half off).
  @visibleForTesting
  Duration get cursorBlinkInterval => _kCursorBlinkHalfPeriod;

  /// The current status of the text selection handles.
  @visibleForTesting
  TextSelectionOverlay? get selectionOverlay => _selectionOverlay;

  int _obscureShowCharTicksPending = 0;
  int? _obscureLatestCharIndex;

  void _startCursorBlink() {
    assert(!(_cursorTimer?.isActive ?? false) || !(_backingCursorBlinkOpacityController?.isAnimating ?? false));
    if (!widget.showCursor) {
      return;
    }
    if (!_tickersEnabled) {
      return;
    }
    _cursorTimer?.cancel();
    _cursorBlinkOpacityController.value = 1.0;
    if (EditableText.debugDeterministicCursor) {
      return;
    }
    if (widget.cursorOpacityAnimates) {
      _cursorBlinkOpacityController.animateWith(_iosBlinkCursorSimulation).whenComplete(_onCursorTick);
    } else {
      _cursorTimer = Timer.periodic(_kCursorBlinkHalfPeriod, (Timer timer) { _onCursorTick(); });
    }
  }

  void _onCursorTick() {
    if (_obscureShowCharTicksPending > 0) {
      _obscureShowCharTicksPending = WidgetsBinding.instance.platformDispatcher.brieflyShowPassword
        ? _obscureShowCharTicksPending - 1
        : 0;
      if (_obscureShowCharTicksPending == 0) {
        setState(() { });
      }
    }

    if (widget.cursorOpacityAnimates) {
      _cursorTimer?.cancel();
      // Schedule this as an async task to avoid blocking tester.pumpAndSettle
      // indefinitely.
      _cursorTimer = Timer(Duration.zero, () => _cursorBlinkOpacityController.animateWith(_iosBlinkCursorSimulation).whenComplete(_onCursorTick));
    } else {
      if (!(_cursorTimer?.isActive ?? false) && _tickersEnabled) {
        _cursorTimer = Timer.periodic(_kCursorBlinkHalfPeriod, (Timer timer) { _onCursorTick(); });
      }
      _cursorBlinkOpacityController.value = _cursorBlinkOpacityController.value == 0 ? 1 : 0;
    }
  }

  void _stopCursorBlink({ bool resetCharTicks = true }) {
    // If the cursor is animating, stop the animation, and we always
    // want the cursor to be visible when the floating cursor is enabled.
    _cursorBlinkOpacityController.value = renderEditable.floatingCursorOn ? 1.0 : 0.0;
    _cursorTimer?.cancel();
    _cursorTimer = null;
    if (resetCharTicks) {
      _obscureShowCharTicksPending = 0;
    }
  }

  void _startOrStopCursorTimerIfNeeded() {
    if (!_showBlinkingCursor) {
      _stopCursorBlink();
    } else if (_cursorTimer == null) {
      _startCursorBlink();
    }
  }

  void _didChangeTextEditingValue() {
    if (_hasFocus && !_value.selection.isValid) {
      // If this field is focused and the selection is invalid, place the cursor at
      // the end. Does not rely on _handleFocusChanged because it makes selection
      // handles visible on Android.
      // Unregister as a listener to the text controller while making the change.
      widget.controller.removeListener(_didChangeTextEditingValue);
      widget.controller.selection = _adjustedSelectionWhenFocused()!;
      widget.controller.addListener(_didChangeTextEditingValue);
    }
    _updateRemoteEditingValueIfNeeded();
    _startOrStopCursorTimerIfNeeded();
    _updateOrDisposeSelectionOverlayIfNeeded();
    // TODO(abarth): Teach RenderEditable about ValueNotifier<TextEditingValue>
    // to avoid this setState().
    setState(() { /* We use widget.controller.value in build(). */ });
    _verticalSelectionUpdateAction.stopCurrentVerticalRunIfSelectionChanges();
  }

  void _handleFocusChanged() {
    _openOrCloseInputConnectionIfNeeded();
    _startOrStopCursorTimerIfNeeded();
    _updateOrDisposeSelectionOverlayIfNeeded();
    if (_hasFocus) {
      // Listen for changing viewInsets, which indicates keyboard showing up.
      WidgetsBinding.instance.addObserver(this);
      _lastBottomViewInset = View.of(context).viewInsets.bottom;
      if (!widget.readOnly) {
        _scheduleShowCaretOnScreen(withAnimation: true);
      }
      final TextSelection? updatedSelection = _adjustedSelectionWhenFocused();
      if (updatedSelection != null) {
        _handleSelectionChanged(updatedSelection, null);
      }
    } else {
      WidgetsBinding.instance.removeObserver(this);
      setState(() { _currentPromptRectRange = null; });
    }
    updateKeepAlive();
  }

  TextSelection? _adjustedSelectionWhenFocused() {
    TextSelection? selection;
    final bool shouldSelectAll = widget.selectionEnabled && kIsWeb
        && !_isMultiline && !_nextFocusChangeIsInternal;
    if (shouldSelectAll) {
      // On native web, single line <input> tags select all when receiving
      // focus.
      selection = TextSelection(
        baseOffset: 0,
        extentOffset: _value.text.length,
      );
    } else if (!_value.selection.isValid) {
      // Place cursor at the end if the selection is invalid when we receive focus.
      selection = TextSelection.collapsed(offset: _value.text.length);
    }
    return selection;
  }

  void _compositeCallback(Layer layer) {
    // The callback can be invoked when the layer is detached.
    // The input connection can be closed by the platform in which case this
    // widget doesn't rebuild.
    if (!renderEditable.attached || !_hasInputConnection) {
      return;
    }
    assert(mounted);
    assert((context as Element).debugIsActive);
    _updateSizeAndTransform();
  }

  // Must be called after layout.
  // See https://github.com/flutter/flutter/issues/126312
  void _updateSizeAndTransform() {
    final Size size = renderEditable.size;
    final Matrix4 transform = renderEditable.getTransformTo(null);
    _textInputConnection!.setEditableSizeAndTransform(size, transform);
  }

  void _schedulePeriodicPostFrameCallbacks([Duration? duration]) {
    if (!_hasInputConnection) {
      return;
    }
    _updateSelectionRects();
    _updateComposingRectIfNeeded();
    _updateCaretRectIfNeeded();
    SchedulerBinding.instance.addPostFrameCallback(
      _schedulePeriodicPostFrameCallbacks,
      debugLabel: 'EditableText.postFrameCallbacks'
    );
  }
  _ScribbleCacheKey? _scribbleCacheKey;

  void _updateSelectionRects({bool force = false}) {
    if (!widget.scribbleEnabled || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final ScrollDirection scrollDirection = _scrollController.position.userScrollDirection;
    if (scrollDirection != ScrollDirection.idle) {
      return;
    }

    final InlineSpan inlineSpan = renderEditable.text!;
    final TextScaler effectiveTextScaler = switch ((widget.textScaler, widget.textScaleFactor)) {
      (final TextScaler textScaler, _)     => textScaler,
      (null, final double textScaleFactor) => TextScaler.linear(textScaleFactor),
      (null, null)                         => MediaQuery.textScalerOf(context),
    };

    final _ScribbleCacheKey newCacheKey = _ScribbleCacheKey(
      inlineSpan: inlineSpan,
      textAlign: widget.textAlign,
      textDirection: _textDirection,
      textScaler: effectiveTextScaler,
      textHeightBehavior: widget.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
      locale: widget.locale,
      structStyle: widget.strutStyle,
      placeholder: _placeholderLocation,
      size: renderEditable.size,
    );

    final RenderComparison comparison = force
      ? RenderComparison.layout
      : _scribbleCacheKey?.compare(newCacheKey) ?? RenderComparison.layout;
    if (comparison.index < RenderComparison.layout.index) {
      return;
    }
    _scribbleCacheKey = newCacheKey;

    final List<SelectionRect> rects = <SelectionRect>[];
    int graphemeStart = 0;
    // Can't use _value.text here: the controller value could change between
    // frames.
    final String plainText = inlineSpan.toPlainText(includeSemanticsLabels: false);
    final CharacterRange characterRange = CharacterRange(plainText);
    while (characterRange.moveNext()) {
      final int graphemeEnd = graphemeStart + characterRange.current.length;
      final List<TextBox> boxes = renderEditable.getBoxesForSelection(
        TextSelection(baseOffset: graphemeStart, extentOffset: graphemeEnd),
      );

      final TextBox? box = boxes.isEmpty ? null : boxes.first;
      if (box != null) {
        final Rect paintBounds = renderEditable.paintBounds;
        // Stop early when characters are already below the bottom edge of the
        // RenderEditable, regardless of its clipBehavior.
        if (paintBounds.bottom <= box.top) {
          break;
        }
        // Include any TextBox which intersects with the RenderEditable.
        if (paintBounds.left <= box.right &&
            box.left <= paintBounds.right &&
            paintBounds.top <= box.bottom) {
          // At least some part of the letter is visible within the text field.
          rects.add(SelectionRect(position: graphemeStart, bounds: box.toRect(), direction: box.direction));
        }
      }
      graphemeStart = graphemeEnd;
    }
    _textInputConnection!.setSelectionRects(rects);
  }

  // Sends the current composing rect to the embedder's text input plugin.
  //
  // In cases where the composing rect hasn't been updated in the embedder due
  // to the lag of asynchronous messages over the channel, the position of the
  // current caret rect is used instead.
  //
  // See: [_updateCaretRectIfNeeded]
  void _updateComposingRectIfNeeded() {
    final TextRange composingRange = _value.composing;
    assert(mounted);
    Rect? composingRect = renderEditable.getRectForComposingRange(composingRange);
    // Send the caret location instead if there's no marked text yet.
    if (composingRect == null) {
      assert(!composingRange.isValid || composingRange.isCollapsed);
      final int offset = composingRange.isValid ? composingRange.start : 0;
      composingRect = renderEditable.getLocalRectForCaret(TextPosition(offset: offset));
    }
    _textInputConnection!.setComposingRect(composingRect);
  }

  // Sends the current caret rect to the embedder's text input plugin.
  //
  // The position of the caret rect is updated periodically such that if the
  // user initiates composing input, the current cursor rect can be used for
  // the first character until the composing rect can be sent.
  //
  // On selection changes, the start of the selection is used. This ensures
  // that regardless of the direction the selection was created, the cursor is
  // set to the position where next text input occurs. This position is used to
  // position the IME's candidate selection menu.
  //
  // See: [_updateComposingRectIfNeeded]
  void _updateCaretRectIfNeeded() {
    final TextSelection? selection = renderEditable.selection;
    if (selection == null || !selection.isValid) {
      return;
    }
    final TextPosition currentTextPosition = TextPosition(offset: selection.start);
    final Rect caretRect = renderEditable.getLocalRectForCaret(currentTextPosition);
    _textInputConnection!.setCaretRect(caretRect);
  }

  TextDirection get _textDirection => widget.textDirection ?? Directionality.of(context);

  /// The renderer for this widget's descendant.
  ///
  /// This property is typically used to notify the renderer of input gestures
  /// when [RenderEditable.ignorePointer] is true.
  late final RenderEditable renderEditable = _editableKey.currentContext!.findRenderObject()! as RenderEditable;

  @override
  TextEditingValue get textEditingValue => _value;

  double get _devicePixelRatio => MediaQuery.devicePixelRatioOf(context);

  @override
  void userUpdateTextEditingValue(TextEditingValue value, SelectionChangedCause? cause) {
    // Compare the current TextEditingValue with the pre-format new
    // TextEditingValue value, in case the formatter would reject the change.
    final bool shouldShowCaret = widget.readOnly
      ? _value.selection != value.selection
      : _value != value;
    if (shouldShowCaret) {
      _scheduleShowCaretOnScreen(withAnimation: true);
    }

    // Even if the value doesn't change, it may be necessary to focus and build
    // the selection overlay. For example, this happens when right clicking an
    // unfocused field that previously had a selection in the same spot.
    if (value == textEditingValue) {
      if (!widget.focusNode.hasFocus) {
        _flagInternalFocus();
        widget.focusNode.requestFocus();
        _selectionOverlay ??= _createSelectionOverlay();
      }
      return;
    }

    _formatAndSetValue(value, cause, userInteraction: true);
  }

  @override
  void bringIntoView(TextPosition position) {
    final Rect localRect = renderEditable.getLocalRectForCaret(position);
    final RevealedOffset targetOffset = _getOffsetToRevealCaret(localRect);

    _scrollController.jumpTo(targetOffset.offset);
    renderEditable.showOnScreen(rect: targetOffset.rect);
  }

  /// Shows the selection toolbar at the location of the current cursor.
  ///
  /// Returns `false` if a toolbar couldn't be shown, such as when the toolbar
  /// is already shown, or when no text selection currently exists.
  @override
  bool showToolbar() {
    // Web is using native dom elements to enable clipboard functionality of the
    // context menu: copy, paste, select, cut. It might also provide additional
    // functionality depending on the browser (such as translate). Due to this,
    // we should not show a Flutter toolbar for the editable text elements
    // unless the browser's context menu is explicitly disabled.
    if (_webContextMenuEnabled) {
      return false;
    }

    if (_selectionOverlay == null) {
      return false;
    }
    _liveTextInputStatus?.update();
    clipboardStatus.update();
    _selectionOverlay!.showToolbar();
    // Listen to parent scroll events when the toolbar is visible so it can be
    // hidden during a scroll on supported platforms.
    if (_platformSupportsFadeOnScroll) {
      _listeningToScrollNotificationObserver = true;
      _scrollNotificationObserver?.removeListener(_handleContextMenuOnParentScroll);
      _scrollNotificationObserver = ScrollNotificationObserver.maybeOf(context);
      _scrollNotificationObserver?.addListener(_handleContextMenuOnParentScroll);
    }
    return true;
  }

  @override
  void hideToolbar([bool hideHandles = true]) {
    // Stop listening to parent scroll events when toolbar is hidden.
    _disposeScrollNotificationObserver();
    if (hideHandles) {
      // Hide the handles and the toolbar.
      _selectionOverlay?.hide();
    } else if (_selectionOverlay?.toolbarIsVisible ?? false) {
      // Hide only the toolbar but not the handles.
      _selectionOverlay?.hideToolbar();
    }
  }

  /// Toggles the visibility of the toolbar.
  void toggleToolbar([bool hideHandles = true]) {
    final TextSelectionOverlay selectionOverlay = _selectionOverlay ??= _createSelectionOverlay();
    if (selectionOverlay.toolbarIsVisible) {
      hideToolbar(hideHandles);
    } else {
      showToolbar();
    }
  }

  /// Shows toolbar with spell check suggestions of misspelled words that are
  /// available for click-and-replace.
  bool showSpellCheckSuggestionsToolbar() {
    // Spell check suggestions toolbars are intended to be shown on non-web
    // platforms. Additionally, the Cupertino style toolbar can't be drawn on
    // the web with the HTML renderer due to
    // https://github.com/flutter/flutter/issues/123560.
    if (!spellCheckEnabled
        || _webContextMenuEnabled
        || widget.readOnly
        || _selectionOverlay == null
        || !_spellCheckResultsReceived
        || findSuggestionSpanAtCursorIndex(textEditingValue.selection.extentOffset) == null) {
      // Only attempt to show the spell check suggestions toolbar if there
      // is a toolbar specified and spell check suggestions available to show.
      return false;
    }

    assert(
      _spellCheckConfiguration.spellCheckSuggestionsToolbarBuilder != null,
      'spellCheckSuggestionsToolbarBuilder must be defined in '
      'SpellCheckConfiguration to show a toolbar with spell check '
      'suggestions',
    );

    _selectionOverlay!
      .showSpellCheckSuggestionsToolbar(
        (BuildContext context) {
          return _spellCheckConfiguration
            .spellCheckSuggestionsToolbarBuilder!(
              context,
              this,
          );
        },
    );
    return true;
  }

  /// Shows the magnifier at the position given by `positionToShow`,
  /// if there is no magnifier visible.
  ///
  /// Updates the magnifier to the position given by `positionToShow`,
  /// if there is a magnifier visible.
  ///
  /// Does nothing if a magnifier couldn't be shown, such as when the selection
  /// overlay does not currently exist.
  void showMagnifier(Offset positionToShow) {
    if (_selectionOverlay == null) {
      return;
    }

    if (_selectionOverlay!.magnifierIsVisible) {
      _selectionOverlay!.updateMagnifier(positionToShow);
    } else {
      _selectionOverlay!.showMagnifier(positionToShow);
    }
  }

  /// Hides the magnifier if it is visible.
  void hideMagnifier() {
    if (_selectionOverlay == null) {
      return;
    }

    if (_selectionOverlay!.magnifierIsVisible) {
      _selectionOverlay!.hideMagnifier();
    }
  }

  // Tracks the location a [_ScribblePlaceholder] should be rendered in the
  // text.
  //
  // A value of -1 indicates there should be no placeholder, otherwise the
  // value should be between 0 and the length of the text, inclusive.
  int _placeholderLocation = -1;

  @override
  void insertTextPlaceholder(Size size) {
    if (!widget.scribbleEnabled) {
      return;
    }

    if (!widget.controller.selection.isValid) {
      return;
    }

    setState(() {
      _placeholderLocation = _value.text.length - widget.controller.selection.end;
    });
  }

  @override
  void removeTextPlaceholder() {
    if (!widget.scribbleEnabled || _placeholderLocation == -1) {
      return;
    }

    setState(() {
      _placeholderLocation = -1;
    });
  }

  @override
  void performSelector(String selectorName) {
    final Intent? intent = intentForMacOSSelector(selectorName);

    if (intent != null) {
      final BuildContext? primaryContext = primaryFocus?.context;
      if (primaryContext != null) {
        Actions.invoke(primaryContext, intent);
      }
    }
  }

  @override
  String get autofillId => 'EditableText-$hashCode';

  @override
  TextInputConfiguration get textInputConfiguration {
    final List<String>? autofillHints = widget.autofillHints?.toList(growable: false);
    final AutofillConfiguration autofillConfiguration = autofillHints != null
      ? AutofillConfiguration(
          uniqueIdentifier: autofillId,
          autofillHints: autofillHints,
          currentEditingValue: currentTextEditingValue,
        )
      : AutofillConfiguration.disabled;

    return TextInputConfiguration(
      inputType: widget.keyboardType,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      autocorrect: widget.autocorrect,
      smartDashesType: widget.smartDashesType,
      smartQuotesType: widget.smartQuotesType,
      enableSuggestions: widget.enableSuggestions,
      enableInteractiveSelection: widget.userSelectionEnabled,
      inputAction: widget.textInputAction ?? (widget.keyboardType == TextInputType.multiline
        ? TextInputAction.newline
        : TextInputAction.done
      ),
      textCapitalization: widget.textCapitalization,
      keyboardAppearance: widget.keyboardAppearance,
      autofillConfiguration: autofillConfiguration,
      enableIMEPersonalizedLearning: widget.enableIMEPersonalizedLearning,
      allowedMimeTypes: widget.contentInsertionConfiguration == null
        ? const <String>[]
        : widget.contentInsertionConfiguration!.allowedMimeTypes,
    );
  }

  @override
  void autofill(TextEditingValue value) => updateEditingValue(value);

  // null if no promptRect should be shown.
  TextRange? _currentPromptRectRange;

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    setState(() {
      _currentPromptRectRange = TextRange(start: start, end: end);
    });
  }

  VoidCallback? _semanticsOnCopy(TextSelectionControls? controls) {
    return widget.selectionEnabled
        && _hasFocus
        && (widget.selectionControls is TextSelectionHandleControls
            ? copyEnabled
            : copyEnabled && (widget.selectionControls?.canCopy(this) ?? false))
      ? () {
        controls?.handleCopy(this);
        copySelection(SelectionChangedCause.toolbar);
      }
      : null;
  }

  VoidCallback? _semanticsOnCut(TextSelectionControls? controls) {
    return widget.selectionEnabled
        && _hasFocus
        && (widget.selectionControls is TextSelectionHandleControls
            ? cutEnabled
            : cutEnabled && (widget.selectionControls?.canCut(this) ?? false))
      ? () {
        controls?.handleCut(this);
        cutSelection(SelectionChangedCause.toolbar);
      }
      : null;
  }

  VoidCallback? _semanticsOnPaste(TextSelectionControls? controls) {
    return widget.selectionEnabled
        && _hasFocus
        && (widget.selectionControls is TextSelectionHandleControls
            ? pasteEnabled
            : pasteEnabled && (widget.selectionControls?.canPaste(this) ?? false))
        && (clipboardStatus.value == ClipboardStatus.pasteable)
      ? () {
        controls?.handlePaste(this);
        pasteText(SelectionChangedCause.toolbar);
      }
      : null;
  }

  // Returns the closest boundary location to `extent` but not including `extent`
  // itself (unless already at the start/end of the text), in the direction
  // specified by `forward`.
  TextPosition _moveBeyondTextBoundary(TextPosition extent, bool forward, TextBoundary textBoundary) {
    assert(extent.offset >= 0);
    final int newOffset = forward
      ? textBoundary.getTrailingTextBoundaryAt(extent.offset) ?? _value.text.length
      // if x is a boundary defined by `textBoundary`, most textBoundaries (except
      // LineBreaker) guarantees `x == textBoundary.getLeadingTextBoundaryAt(x)`.
      // Use x - 1 here to make sure we don't get stuck at the fixed point x.
      : textBoundary.getLeadingTextBoundaryAt(extent.offset - 1) ?? 0;
    return TextPosition(offset: newOffset);
  }

  // Returns the closest boundary location to `extent`, including `extent`
  // itself, in the direction specified by `forward`.
  //
  // This method returns a fixed point of itself: applying `_toTextBoundary`
  // again on the returned TextPosition gives the same TextPosition. It's used
  // exclusively for handling line boundaries, since performing "move to line
  // start" more than once usually doesn't move you to the previous line.
  TextPosition _moveToTextBoundary(TextPosition extent, bool forward, TextBoundary textBoundary) {
    assert(extent.offset >= 0);
    final int caretOffset;
    switch (extent.affinity) {
      case TextAffinity.upstream:
        if (extent.offset < 1 && !forward) {
          assert (extent.offset == 0);
          return const TextPosition(offset: 0);
        }
        // When the text affinity is upstream, the caret is associated with the
        // grapheme before the code unit at `extent.offset`.
        // TODO(LongCatIsLooong): don't assume extent.offset is at a grapheme
        // boundary, and do this instead:
        // final int graphemeStart = CharacterRange.at(string, extent.offset).stringBeforeLength - 1;
        caretOffset = math.max(0, extent.offset - 1);
      case TextAffinity.downstream:
        caretOffset = extent.offset;
    }
    // The line boundary range does not include some control characters
    // (most notably, Line Feed), in which case there's
    // `x ∉ getTextBoundaryAt(x)`. In case `caretOffset` points to one such
    // control character, we define that these control characters themselves are
    // still part of the previous line, but also exclude them from the
    // line boundary range since they're non-printing. IOW, no additional
    // processing needed since the LineBoundary class does exactly that.
    return forward
      ? TextPosition(offset: textBoundary.getTrailingTextBoundaryAt(caretOffset) ?? _value.text.length, affinity: TextAffinity.upstream)
      : TextPosition(offset: textBoundary.getLeadingTextBoundaryAt(caretOffset) ?? 0);
  }

  // --------------------------- Text Editing Actions ---------------------------

  TextBoundary _characterBoundary() => widget.obscureText ? _CodePointBoundary(_value.text) : CharacterBoundary(_value.text);
  TextBoundary _nextWordBoundary() => widget.obscureText ? _documentBoundary() : renderEditable.wordBoundaries.moveByWordBoundary;
  TextBoundary _linebreak() => widget.obscureText ? _documentBoundary() : LineBoundary(renderEditable);
  TextBoundary _paragraphBoundary() => ParagraphBoundary(_value.text);
  TextBoundary _documentBoundary() => DocumentBoundary(_value.text);

  Action<T> _makeOverridable<T extends Intent>(Action<T> defaultAction) {
    return Action<T>.overridable(context: context, defaultAction: defaultAction);
  }

  /// Transpose the characters immediately before and after the current
  /// collapsed selection.
  ///
  /// When the cursor is at the end of the text, transposes the last two
  /// characters, if they exist.
  ///
  /// When the cursor is at the start of the text, does nothing.
  void _transposeCharacters(TransposeCharactersIntent intent) {
    if (_value.text.characters.length <= 1
        || !_value.selection.isCollapsed
        || _value.selection.baseOffset == 0) {
      return;
    }

    final String text = _value.text;
    final TextSelection selection = _value.selection;
    final bool atEnd = selection.baseOffset == text.length;
    final CharacterRange transposing = CharacterRange.at(text, selection.baseOffset);
    if (atEnd) {
      transposing.moveBack(2);
    } else {
      transposing..moveBack()..expandNext();
    }
    assert(transposing.currentCharacters.length == 2);

    userUpdateTextEditingValue(
      TextEditingValue(
        text: transposing.stringBefore
            + transposing.currentCharacters.last
            + transposing.currentCharacters.first
            + transposing.stringAfter,
        selection: TextSelection.collapsed(
          offset: transposing.stringBeforeLength + transposing.current.length,
        ),
      ),
      SelectionChangedCause.keyboard,
    );
  }
  late final Action<TransposeCharactersIntent> _transposeCharactersAction = CallbackAction<TransposeCharactersIntent>(onInvoke: _transposeCharacters);

  void _replaceText(ReplaceTextIntent intent) {
    final TextEditingValue oldValue = _value;
    final TextEditingValue newValue = intent.currentTextEditingValue.replaced(
      intent.replacementRange,
      intent.replacementText,
    );
    userUpdateTextEditingValue(newValue, intent.cause);

    // If there's no change in text and selection (e.g. when selecting and
    // pasting identical text), the widget won't be rebuilt on value update.
    // Handle this by calling _didChangeTextEditingValue() so caret and scroll
    // updates can happen.
    if (newValue == oldValue) {
      _didChangeTextEditingValue();
    }
  }
  late final Action<ReplaceTextIntent> _replaceTextAction = CallbackAction<ReplaceTextIntent>(onInvoke: _replaceText);

  // Scrolls either to the beginning or end of the document depending on the
  // intent's `forward` parameter.
  void _scrollToDocumentBoundary(ScrollToDocumentBoundaryIntent intent) {
    if (intent.forward) {
      bringIntoView(TextPosition(offset: _value.text.length));
    } else {
      bringIntoView(const TextPosition(offset: 0));
    }
  }

  /// Handles [ScrollIntent] by scrolling the [Scrollable] inside of
  /// [EditableText].
  void _scroll(ScrollIntent intent) {
    if (intent.type != ScrollIncrementType.page) {
      return;
    }

    final ScrollPosition position = _scrollController.position;
    if (widget.maxLines == 1) {
      _scrollController.jumpTo(position.maxScrollExtent);
      return;
    }

    // If the field isn't scrollable, do nothing. For example, when the lines of
    // text is less than maxLines, the field has nothing to scroll.
    if (position.maxScrollExtent == 0.0 && position.minScrollExtent == 0.0) {
      return;
    }

    final ScrollableState? state = _scrollableKey.currentState as ScrollableState?;
    final double increment = ScrollAction.getDirectionalIncrement(state!, intent);
    final double destination = clampDouble(
      position.pixels + increment,
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (destination == position.pixels) {
      return;
    }
    _scrollController.jumpTo(destination);
  }

  /// Extend the selection down by page if the `forward` parameter is true, or
  /// up by page otherwise.
  void _extendSelectionByPage(ExtendSelectionByPageIntent intent) {
    if (widget.maxLines == 1) {
      return;
    }

    final TextSelection nextSelection;
    final Rect extentRect = renderEditable.getLocalRectForCaret(
      _value.selection.extent,
    );
    final ScrollableState? state = _scrollableKey.currentState as ScrollableState?;
    final double increment = ScrollAction.getDirectionalIncrement(
      state!,
      ScrollIntent(
        direction: intent.forward ? AxisDirection.down : AxisDirection.up,
        type: ScrollIncrementType.page,
      ),
    );
    final ScrollPosition position = _scrollController.position;
    if (intent.forward) {
      if (_value.selection.extentOffset >= _value.text.length) {
        return;
      }
      final Offset nextExtentOffset =
          Offset(extentRect.left, extentRect.top + increment);
      final double height = position.maxScrollExtent + renderEditable.size.height;
      final TextPosition nextExtent = nextExtentOffset.dy + position.pixels >= height
          ? TextPosition(offset: _value.text.length)
          : renderEditable.getPositionForPoint(
              renderEditable.localToGlobal(nextExtentOffset),
            );
      nextSelection = _value.selection.copyWith(
        extentOffset: nextExtent.offset,
      );
    } else {
      if (_value.selection.extentOffset <= 0) {
        return;
      }
      final Offset nextExtentOffset =
          Offset(extentRect.left, extentRect.top + increment);
      final TextPosition nextExtent = nextExtentOffset.dy + position.pixels <= 0
          ? const TextPosition(offset: 0)
          : renderEditable.getPositionForPoint(
              renderEditable.localToGlobal(nextExtentOffset),
            );
      nextSelection = _value.selection.copyWith(
        extentOffset: nextExtent.offset,
      );
    }

    bringIntoView(nextSelection.extent);
    userUpdateTextEditingValue(
      _value.copyWith(selection: nextSelection),
      SelectionChangedCause.keyboard,
    );
  }

  void _updateSelection(UpdateSelectionIntent intent) {
    assert(
      intent.newSelection.start <= intent.currentTextEditingValue.text.length,
      'invalid selection: ${intent.newSelection}: it must not exceed the current text length ${intent.currentTextEditingValue.text.length}',
    );
    assert(
      intent.newSelection.end <= intent.currentTextEditingValue.text.length,
      'invalid selection: ${intent.newSelection}: it must not exceed the current text length ${intent.currentTextEditingValue.text.length}',
    );

    bringIntoView(intent.newSelection.extent);
    userUpdateTextEditingValue(
      intent.currentTextEditingValue.copyWith(selection: intent.newSelection),
      intent.cause,
    );
  }
  late final Action<UpdateSelectionIntent> _updateSelectionAction = CallbackAction<UpdateSelectionIntent>(onInvoke: _updateSelection);

  late final _UpdateTextSelectionVerticallyAction<DirectionalCaretMovementIntent> _verticalSelectionUpdateAction =
      _UpdateTextSelectionVerticallyAction<DirectionalCaretMovementIntent>(this);

  Object? _hideToolbarIfVisible(DismissIntent intent) {
    if (_selectionOverlay?.toolbarIsVisible ?? false) {
      hideToolbar(false);
      return null;
    }
    return Actions.invoke(context, intent);
  }


  /// The default behavior used if [onTapOutside] is null.
  ///
  /// The `event` argument is the [PointerDownEvent] that caused the notification.
  void _defaultOnTapOutside(PointerDownEvent event) {
    /// The focus dropping behavior is only present on desktop platforms
    /// and mobile browsers.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
      // On mobile platforms, we don't unfocus on touch events unless they're
      // in the web browser, but we do unfocus for all other kinds of events.
        switch (event.kind) {
          case ui.PointerDeviceKind.touch:
            if (kIsWeb) {
              widget.focusNode.unfocus();
            }
          case ui.PointerDeviceKind.mouse:
          case ui.PointerDeviceKind.stylus:
          case ui.PointerDeviceKind.invertedStylus:
          case ui.PointerDeviceKind.unknown:
            widget.focusNode.unfocus();
          case ui.PointerDeviceKind.trackpad:
            throw UnimplementedError('Unexpected pointer down event for trackpad');
        }
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        widget.focusNode.unfocus();
    }
  }

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    DoNothingAndStopPropagationTextIntent: DoNothingAction(consumesKey: false),
    ReplaceTextIntent: _replaceTextAction,
    UpdateSelectionIntent: _updateSelectionAction,
    DirectionalFocusIntent: DirectionalFocusAction.forTextField(),
    DismissIntent: CallbackAction<DismissIntent>(onInvoke: _hideToolbarIfVisible),

    // Delete
    DeleteCharacterIntent: _makeOverridable(_DeleteTextAction<DeleteCharacterIntent>(this, _characterBoundary, _moveBeyondTextBoundary)),
    DeleteToNextWordBoundaryIntent: _makeOverridable(_DeleteTextAction<DeleteToNextWordBoundaryIntent>(this, _nextWordBoundary, _moveBeyondTextBoundary)),
    DeleteToLineBreakIntent: _makeOverridable(_DeleteTextAction<DeleteToLineBreakIntent>(this, _linebreak, _moveToTextBoundary)),

    // Extend/Move Selection
    ExtendSelectionByCharacterIntent: _makeOverridable(_UpdateTextSelectionAction<ExtendSelectionByCharacterIntent>(this, _characterBoundary, _moveBeyondTextBoundary, ignoreNonCollapsedSelection: false)),
    ExtendSelectionByPageIntent: _makeOverridable(CallbackAction<ExtendSelectionByPageIntent>(onInvoke: _extendSelectionByPage)),
    ExtendSelectionToNextWordBoundaryIntent: _makeOverridable(_UpdateTextSelectionAction<ExtendSelectionToNextWordBoundaryIntent>(this, _nextWordBoundary, _moveBeyondTextBoundary, ignoreNonCollapsedSelection: true)),
    ExtendSelectionToNextParagraphBoundaryIntent : _makeOverridable(_UpdateTextSelectionAction<ExtendSelectionToNextParagraphBoundaryIntent>(this, _paragraphBoundary, _moveBeyondTextBoundary, ignoreNonCollapsedSelection: true)),
    ExtendSelectionToLineBreakIntent: _makeOverridable(_UpdateTextSelectionAction<ExtendSelectionToLineBreakIntent>(this, _linebreak, _moveToTextBoundary, ignoreNonCollapsedSelection: true)),
    ExtendSelectionVerticallyToAdjacentLineIntent: _makeOverridable(_verticalSelectionUpdateAction),
    ExtendSelectionVerticallyToAdjacentPageIntent: _makeOverridable(_verticalSelectionUpdateAction),
    ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent: _makeOverridable(_UpdateTextSelectionAction<ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent>(this, _paragraphBoundary, _moveBeyondTextBoundary, ignoreNonCollapsedSelection: true)),
    ExtendSelectionToDocumentBoundaryIntent: _makeOverridable(_UpdateTextSelectionAction<ExtendSelectionToDocumentBoundaryIntent>(this, _documentBoundary, _moveBeyondTextBoundary, ignoreNonCollapsedSelection: true)),
    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent: _makeOverridable(_UpdateTextSelectionAction<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent>(this, _nextWordBoundary, _moveBeyondTextBoundary, ignoreNonCollapsedSelection: true)),
    ScrollToDocumentBoundaryIntent: _makeOverridable(CallbackAction<ScrollToDocumentBoundaryIntent>(onInvoke: _scrollToDocumentBoundary)),
    ScrollIntent: CallbackAction<ScrollIntent>(onInvoke: _scroll),

    // Expand Selection
    ExpandSelectionToLineBreakIntent: _makeOverridable(_UpdateTextSelectionAction<ExpandSelectionToLineBreakIntent>(this, _linebreak, _moveToTextBoundary, ignoreNonCollapsedSelection: true, isExpand: true)),
    ExpandSelectionToDocumentBoundaryIntent: _makeOverridable(_UpdateTextSelectionAction<ExpandSelectionToDocumentBoundaryIntent>(this, _documentBoundary, _moveToTextBoundary, ignoreNonCollapsedSelection: true, isExpand: true, extentAtIndex: true)),

    // Copy Paste
    SelectAllTextIntent: _makeOverridable(_SelectAllAction(this)),
    CopySelectionTextIntent: _makeOverridable(_CopySelectionAction(this)),
    PasteTextIntent: _makeOverridable(CallbackAction<PasteTextIntent>(onInvoke: (PasteTextIntent intent) => pasteText(intent.cause))),

    TransposeCharactersIntent: _makeOverridable(_transposeCharactersAction),
  };

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMediaQuery(context));
    super.build(context); // See AutomaticKeepAliveClientMixin.

    final TextSelectionControls? controls = widget.selectionControls;
    final TextScaler effectiveTextScaler = switch ((widget.textScaler, widget.textScaleFactor)) {
      (final TextScaler textScaler, _)     => textScaler,
      (null, final double textScaleFactor) => TextScaler.linear(textScaleFactor),
      (null, null)                         => MediaQuery.textScalerOf(context),
    };

    return _CompositionCallback(
      compositeCallback: _compositeCallback,
      enabled: _hasInputConnection,
      child: TextFieldTapRegion(
        onTapOutside: _hasFocus ? widget.onTapOutside ?? _defaultOnTapOutside : null,
        debugLabel: kReleaseMode ? null : 'EditableText',
        child: MouseRegion(
          cursor: widget.mouseCursor ?? SystemMouseCursors.text,
          child: Actions(
            actions: _actions,
            child: UndoHistory<TextEditingValue>(
              value: widget.controller,
              onTriggered: (TextEditingValue value) {
                userUpdateTextEditingValue(value, SelectionChangedCause.keyboard);
              },
              shouldChangeUndoStack: (TextEditingValue? oldValue, TextEditingValue newValue) {
                if (!newValue.selection.isValid) {
                  return false;
                }

                if (oldValue == null) {
                  return true;
                }

                switch (defaultTargetPlatform) {
                  case TargetPlatform.iOS:
                  case TargetPlatform.macOS:
                  case TargetPlatform.fuchsia:
                  case TargetPlatform.linux:
                  case TargetPlatform.windows:
                    // Composing text is not counted in history coalescing.
                    if (!widget.controller.value.composing.isCollapsed) {
                      return false;
                    }
                  case TargetPlatform.android:
                    // Gboard on Android puts non-CJK words in composing regions. Coalesce
                    // composing text in order to allow the saving of partial words in that
                    // case.
                    break;
                }

                return oldValue.text != newValue.text || oldValue.composing != newValue.composing;
              },
              undoStackModifier: (TextEditingValue value) {
                // On Android we should discard the composing region when pushing
                // a new entry to the undo stack. This prevents the TextInputPlugin
                // from restarting the input on every undo/redo when the composing
                // region is changed by the framework.
                return defaultTargetPlatform == TargetPlatform.android ? value.copyWith(composing: TextRange.empty) : value;
              },
              focusNode: widget.focusNode,
              controller: widget.undoController,
              child: Focus(
                focusNode: widget.focusNode,
                includeSemantics: false,
                debugLabel: kReleaseMode ? null : 'EditableText',
                child: NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification notification) {
                    _handleContextMenuOnScroll(notification);
                    _scribbleCacheKey = null;
                    return false;
                  },
                  child: Scrollable(
                    key: _scrollableKey,
                    excludeFromSemantics: true,
                    axisDirection: _isMultiline ? AxisDirection.down : AxisDirection.right,
                    controller: _scrollController,
                    physics: widget.scrollPhysics,
                    dragStartBehavior: widget.dragStartBehavior,
                    restorationId: widget.restorationId,
                    // If a ScrollBehavior is not provided, only apply scrollbars when
                    // multiline. The overscroll indicator should not be applied in
                    // either case, glowing or stretching.
                    scrollBehavior: widget.scrollBehavior ?? ScrollConfiguration.of(context).copyWith(
                      scrollbars: _isMultiline,
                      overscroll: false,
                    ),
                    viewportBuilder: (BuildContext context, ViewportOffset offset) {
                      return CompositedTransformTarget(
                        link: _toolbarLayerLink,
                        child: Semantics(
                          onCopy: _semanticsOnCopy(controls),
                          onCut: _semanticsOnCut(controls),
                          onPaste: _semanticsOnPaste(controls),
                          child: _ScribbleFocusable(
                            focusNode: widget.focusNode,
                            editableKey: _editableKey,
                            enabled: widget.scribbleEnabled,
                            updateSelectionRects: () {
                              _openInputConnection();
                              _updateSelectionRects(force: true);
                            },
                            child: SizeChangedLayoutNotifier(
                              child: _Editable(
                                key: _editableKey,
                                startHandleLayerLink: _startHandleLayerLink,
                                endHandleLayerLink: _endHandleLayerLink,
                                inlineSpan: buildTextSpan(),
                                value: _value,
                                cursorColor: _cursorColor,
                                backgroundCursorColor: widget.backgroundCursorColor,
                                showCursor: _cursorVisibilityNotifier,
                                forceLine: widget.forceLine,
                                readOnly: widget.readOnly,
                                hasFocus: _hasFocus,
                                maxLines: widget.maxLines,
                                minLines: widget.minLines,
                                expands: widget.expands,
                                strutStyle: widget.strutStyle,
                                selectionColor: _selectionOverlay?.spellCheckToolbarIsVisible ?? false
                                    ? _spellCheckConfiguration.misspelledSelectionColor ?? widget.selectionColor
                                    : widget.selectionColor,
                                textScaler: effectiveTextScaler,
                                textAlign: widget.textAlign,
                                textDirection: _textDirection,
                                locale: widget.locale,
                                textHeightBehavior: widget.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
                                textWidthBasis: widget.textWidthBasis,
                                obscuringCharacter: widget.obscuringCharacter,
                                obscureText: widget.obscureText,
                                offset: offset,
                                rendererIgnoresPointer: widget.rendererIgnoresPointer,
                                cursorWidth: widget.cursorWidth,
                                cursorHeight: widget.cursorHeight,
                                cursorRadius: widget.cursorRadius,
                                cursorOffset: widget.cursorOffset ?? Offset.zero,
                                selectionHeightStyle: widget.selectionHeightStyle,
                                selectionWidthStyle: widget.selectionWidthStyle,
                                paintCursorAboveText: widget.paintCursorAboveText,
                                enableInteractiveSelection: widget.userSelectionEnabled,
                                textSelectionDelegate: this,
                                devicePixelRatio: _devicePixelRatio,
                                promptRectRange: _currentPromptRectRange,
                                promptRectColor: widget.autocorrectionTextRectColor,
                                clipBehavior: widget.clipBehavior,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds [TextSpan] from current editing value.
  ///
  /// By default makes text in composing range appear as underlined.
  /// Descendants can override this method to customize appearance of text.
  TextSpan buildTextSpan() {

    if (widget.obscureText) {
      String text = _value.text;
      text = widget.obscuringCharacter * text.length;
      // Reveal the latest character in an obscured field only on mobile.
      // Newer versions of iOS (iOS 15+) no longer reveal the most recently
      // entered character.
      const Set<TargetPlatform> mobilePlatforms = <TargetPlatform> {
        TargetPlatform.android, TargetPlatform.fuchsia,
      };
      final bool brieflyShowPassword = WidgetsBinding.instance.platformDispatcher.brieflyShowPassword
                                    && mobilePlatforms.contains(defaultTargetPlatform);
      if (brieflyShowPassword) {
        final int? o = _obscureShowCharTicksPending > 0 ? _obscureLatestCharIndex : null;
        if (o != null && o >= 0 && o < text.length) {
          text = text.replaceRange(o, o + 1, _value.text.substring(o, o + 1));
        }
      }
      return TextSpan(style: _style, text: text);
    }
    if (_placeholderLocation >= 0 && _placeholderLocation <= _value.text.length) {
      final List<_ScribblePlaceholder> placeholders = <_ScribblePlaceholder>[];
      final int placeholderLocation = _value.text.length - _placeholderLocation;
      if (_isMultiline) {
        // The zero size placeholder here allows the line to break and keep the caret on the first line.
        placeholders.add(const _ScribblePlaceholder(child: SizedBox.shrink(), size: Size.zero));
        placeholders.add(_ScribblePlaceholder(child: const SizedBox.shrink(), size: Size(renderEditable.size.width, 0.0)));
      } else {
        placeholders.add(const _ScribblePlaceholder(child: SizedBox.shrink(), size: Size(100.0, 0.0)));
      }
      return TextSpan(style: _style, children: <InlineSpan>[
          TextSpan(text: _value.text.substring(0, placeholderLocation)),
          ...placeholders,
          TextSpan(text: _value.text.substring(placeholderLocation)),
        ],
      );
    }
    final bool withComposing = !widget.readOnly && _hasFocus;
    if (_spellCheckResultsReceived) {
      // If the composing range is out of range for the current text, ignore it to
      // preserve the tree integrity, otherwise in release mode a RangeError will
      // be thrown and this EditableText will be built with a broken subtree.
      assert(!_value.composing.isValid || !withComposing || _value.isComposingRangeValid);

      final bool composingRegionOutOfRange = !_value.isComposingRangeValid || !withComposing;

      return buildTextSpanWithSpellCheckSuggestions(
        _value,
        composingRegionOutOfRange,
        _style,
        _spellCheckConfiguration.misspelledTextStyle!,
        spellCheckResults!,
      );
    }

    // Read only mode should not paint text composing.
    return widget.controller.buildTextSpan(
      context: context,
      style: _style,
      withComposing: withComposing,
    );
  }
}

class _Editable extends MultiChildRenderObjectWidget {
  _Editable({
    super.key,
    required this.inlineSpan,
    required this.value,
    required this.startHandleLayerLink,
    required this.endHandleLayerLink,
    this.cursorColor,
    this.backgroundCursorColor,
    required this.showCursor,
    required this.forceLine,
    required this.readOnly,
    this.textHeightBehavior,
    required this.textWidthBasis,
    required this.hasFocus,
    required this.maxLines,
    this.minLines,
    required this.expands,
    this.strutStyle,
    this.selectionColor,
    required this.textScaler,
    required this.textAlign,
    required this.textDirection,
    this.locale,
    required this.obscuringCharacter,
    required this.obscureText,
    required this.offset,
    this.rendererIgnoresPointer = false,
    required this.cursorWidth,
    this.cursorHeight,
    this.cursorRadius,
    required this.cursorOffset,
    required this.paintCursorAboveText,
    this.selectionHeightStyle = ui.BoxHeightStyle.tight,
    this.selectionWidthStyle = ui.BoxWidthStyle.tight,
    this.enableInteractiveSelection = true,
    required this.textSelectionDelegate,
    required this.devicePixelRatio,
    this.promptRectRange,
    this.promptRectColor,
    required this.clipBehavior,
  }) : super(children: WidgetSpan.extractFromInlineSpan(inlineSpan, textScaler));

  final InlineSpan inlineSpan;
  final TextEditingValue value;
  final Color? cursorColor;
  final LayerLink startHandleLayerLink;
  final LayerLink endHandleLayerLink;
  final Color? backgroundCursorColor;
  final ValueNotifier<bool> showCursor;
  final bool forceLine;
  final bool readOnly;
  final bool hasFocus;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final StrutStyle? strutStyle;
  final Color? selectionColor;
  final TextScaler textScaler;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final Locale? locale;
  final String obscuringCharacter;
  final bool obscureText;
  final TextHeightBehavior? textHeightBehavior;
  final TextWidthBasis textWidthBasis;
  final ViewportOffset offset;
  final bool rendererIgnoresPointer;
  final double cursorWidth;
  final double? cursorHeight;
  final Radius? cursorRadius;
  final Offset cursorOffset;
  final bool paintCursorAboveText;
  final ui.BoxHeightStyle selectionHeightStyle;
  final ui.BoxWidthStyle selectionWidthStyle;
  final bool enableInteractiveSelection;
  final TextSelectionDelegate textSelectionDelegate;
  final double devicePixelRatio;
  final TextRange? promptRectRange;
  final Color? promptRectColor;
  final Clip clipBehavior;

  @override
  RenderEditable createRenderObject(BuildContext context) {
    return RenderEditable(
      text: inlineSpan,
      cursorColor: cursorColor,
      startHandleLayerLink: startHandleLayerLink,
      endHandleLayerLink: endHandleLayerLink,
      backgroundCursorColor: backgroundCursorColor,
      showCursor: showCursor,
      forceLine: forceLine,
      readOnly: readOnly,
      hasFocus: hasFocus,
      maxLines: maxLines,
      minLines: minLines,
      expands: expands,
      strutStyle: strutStyle,
      selectionColor: selectionColor,
      textScaler: textScaler,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale ?? Localizations.maybeLocaleOf(context),
      selection: value.selection,
      offset: offset,
      ignorePointer: rendererIgnoresPointer,
      obscuringCharacter: obscuringCharacter,
      obscureText: obscureText,
      textHeightBehavior: textHeightBehavior,
      textWidthBasis: textWidthBasis,
      cursorWidth: cursorWidth,
      cursorHeight: cursorHeight,
      cursorRadius: cursorRadius,
      cursorOffset: cursorOffset,
      paintCursorAboveText: paintCursorAboveText,
      selectionHeightStyle: selectionHeightStyle,
      selectionWidthStyle: selectionWidthStyle,
      enableInteractiveSelection: enableInteractiveSelection,
      textSelectionDelegate: textSelectionDelegate,
      devicePixelRatio: devicePixelRatio,
      promptRectRange: promptRectRange,
      promptRectColor: promptRectColor,
      clipBehavior: clipBehavior,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderEditable renderObject) {
    renderObject
      ..text = inlineSpan
      ..cursorColor = cursorColor
      ..startHandleLayerLink = startHandleLayerLink
      ..endHandleLayerLink = endHandleLayerLink
      ..backgroundCursorColor = backgroundCursorColor
      ..showCursor = showCursor
      ..forceLine = forceLine
      ..readOnly = readOnly
      ..hasFocus = hasFocus
      ..maxLines = maxLines
      ..minLines = minLines
      ..expands = expands
      ..strutStyle = strutStyle
      ..selectionColor = selectionColor
      ..textScaler = textScaler
      ..textAlign = textAlign
      ..textDirection = textDirection
      ..locale = locale ?? Localizations.maybeLocaleOf(context)
      ..selection = value.selection
      ..offset = offset
      ..ignorePointer = rendererIgnoresPointer
      ..textHeightBehavior = textHeightBehavior
      ..textWidthBasis = textWidthBasis
      ..obscuringCharacter = obscuringCharacter
      ..obscureText = obscureText
      ..cursorWidth = cursorWidth
      ..cursorHeight = cursorHeight
      ..cursorRadius = cursorRadius
      ..cursorOffset = cursorOffset
      ..selectionHeightStyle = selectionHeightStyle
      ..selectionWidthStyle = selectionWidthStyle
      ..enableInteractiveSelection = enableInteractiveSelection
      ..textSelectionDelegate = textSelectionDelegate
      ..devicePixelRatio = devicePixelRatio
      ..paintCursorAboveText = paintCursorAboveText
      ..promptRectColor = promptRectColor
      ..clipBehavior = clipBehavior
      ..setPromptRectRange(promptRectRange);
  }
}

@immutable
class _ScribbleCacheKey  {
  const _ScribbleCacheKey({
    required this.inlineSpan,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.textHeightBehavior,
    required this.locale,
    required this.structStyle,
    required this.placeholder,
    required this.size,
  });

  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final TextHeightBehavior? textHeightBehavior;
  final Locale? locale;
  final StrutStyle structStyle;
  final int placeholder;
  final Size size;
  final InlineSpan inlineSpan;

  RenderComparison compare(_ScribbleCacheKey other) {
    if (identical(other, this)) {
      return RenderComparison.identical;
    }
    final bool needsLayout = textAlign != other.textAlign
                          || textDirection != other.textDirection
                          || textScaler != other.textScaler
                          || (textHeightBehavior ?? const TextHeightBehavior()) != (other.textHeightBehavior ?? const TextHeightBehavior())
                          || locale != other.locale
                          || structStyle != other.structStyle
                          || placeholder != other.placeholder
                          || size != other.size;
    return needsLayout ? RenderComparison.layout : inlineSpan.compareTo(other.inlineSpan);
  }
}

class _ScribbleFocusable extends StatefulWidget {
  const _ScribbleFocusable({
    required this.child,
    required this.focusNode,
    required this.editableKey,
    required this.updateSelectionRects,
    required this.enabled,
  });

  final Widget child;
  final FocusNode focusNode;
  final GlobalKey editableKey;
  final VoidCallback updateSelectionRects;
  final bool enabled;

  @override
  _ScribbleFocusableState createState() => _ScribbleFocusableState();
}

class _ScribbleFocusableState extends State<_ScribbleFocusable> implements ScribbleClient {
  _ScribbleFocusableState(): _elementIdentifier = (_nextElementIdentifier++).toString();

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      TextInput.registerScribbleElement(elementIdentifier, this);
    }
  }

  @override
  void didUpdateWidget(_ScribbleFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled) {
      TextInput.registerScribbleElement(elementIdentifier, this);
    }

    if (oldWidget.enabled && !widget.enabled) {
      TextInput.unregisterScribbleElement(elementIdentifier);
    }
  }

  @override
  void dispose() {
    TextInput.unregisterScribbleElement(elementIdentifier);
    super.dispose();
  }

  RenderEditable? get renderEditable => widget.editableKey.currentContext?.findRenderObject() as RenderEditable?;

  static int _nextElementIdentifier = 1;
  final String _elementIdentifier;

  @override
  String get elementIdentifier => _elementIdentifier;

  @override
  void onScribbleFocus(Offset offset) {
    widget.focusNode.requestFocus();
    renderEditable?.selectPositionAt(from: offset, cause: SelectionChangedCause.scribble);
    widget.updateSelectionRects();
  }

  @override
  bool isInScribbleRect(Rect rect) {
    final Rect calculatedBounds = bounds;
    if (renderEditable?.readOnly ?? false) {
      return false;
    }
    if (calculatedBounds == Rect.zero) {
      return false;
    }
    if (!calculatedBounds.overlaps(rect)) {
      return false;
    }
    final Rect intersection = calculatedBounds.intersect(rect);
    final HitTestResult result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, intersection.center, View.of(context).viewId);
    return result.path.any((HitTestEntry entry) => entry.target == renderEditable);
  }

  @override
  Rect get bounds {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !mounted || !box.attached) {
      return Rect.zero;
    }
    final Matrix4 transform = box.getTransformTo(null);
    return MatrixUtils.transformRect(transform, Rect.fromLTWH(0, 0, box.size.width, box.size.height));
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _ScribblePlaceholder extends WidgetSpan {
  const _ScribblePlaceholder({
    required super.child,
    required this.size,
  });

  /// The size of the span, used in place of adding a placeholder size to the [TextPainter].
  final Size size;

  @override
  void build(ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    assert(debugAssertIsValid());
    final bool hasStyle = style != null;
    if (hasStyle) {
      builder.pushStyle(style!.getTextStyle(textScaler: textScaler));
    }
    builder.addPlaceholder(size.width, size.height, alignment);
    if (hasStyle) {
      builder.pop();
    }
  }
}

/// A text boundary that uses code points as logical boundaries.
///
/// A code point represents a single character. This may be smaller than what is
/// represented by a user-perceived character, or grapheme. For example, a
/// single grapheme (in this case a Unicode extended grapheme cluster) like
/// "👨‍👩‍👦" consists of five code points: the man emoji, a zero
/// width joiner, the woman emoji, another zero width joiner, and the boy emoji.
/// The [String] has a length of eight because each emoji consists of two code
/// units.
///
/// Code units are the units by which Dart's String class is measured, which is
/// encoded in UTF-16.
///
/// See also:
///
///  * [String.runes], which deals with code points like this class.
///  * [String.characters], which deals with graphemes.
///  * [CharacterBoundary], which is a [TextBoundary] like this class, but whose
///    boundaries are graphemes instead of code points.
class _CodePointBoundary extends TextBoundary {
  const _CodePointBoundary(this._text);

  final String _text;

  // Returns true if the given position falls in the center of a surrogate pair.
  bool _breaksSurrogatePair(int position) {
    assert(position > 0 && position < _text.length && _text.length > 1);
    return TextPainter.isHighSurrogate(_text.codeUnitAt(position - 1))
        && TextPainter.isLowSurrogate(_text.codeUnitAt(position));
  }

  @override
  int? getLeadingTextBoundaryAt(int position) {
    if (_text.isEmpty || position < 0) {
      return null;
    }
    if (position == 0) {
      return 0;
    }
    if (position >= _text.length) {
      return _text.length;
    }
    if (_text.length <= 1) {
      return position;
    }

    return _breaksSurrogatePair(position)
        ? position - 1
        : position;
  }

  @override
  int? getTrailingTextBoundaryAt(int position) {
    if (_text.isEmpty || position >= _text.length) {
      return null;
    }
    if (position < 0) {
      return 0;
    }
    if (position == _text.length - 1) {
      return _text.length;
    }
    if (_text.length <= 1) {
      return position;
    }

    return _breaksSurrogatePair(position + 1)
        ? position + 2
        : position + 1;
  }
}

// -------------------------------  Text Actions -------------------------------
class _DeleteTextAction<T extends DirectionalTextEditingIntent> extends ContextAction<T> {
  _DeleteTextAction(this.state, this.getTextBoundary, this._applyTextBoundary);

  final EditableTextStateDefault state;
  final TextBoundary Function() getTextBoundary;
  final _ApplyTextBoundary _applyTextBoundary;

  @override
  Object? invoke(T intent, [BuildContext? context]) {
    final TextSelection selection = state._value.selection;
    if (!selection.isValid) {
      return null;
    }
    assert(selection.isValid);
    // Expands the selection to ensure the range covers full graphemes.
    final TextBoundary atomicBoundary = state._characterBoundary();
    if (!selection.isCollapsed) {
      // Expands the selection to ensure the range covers full graphemes.
      final TextRange range = TextRange(
        start: atomicBoundary.getLeadingTextBoundaryAt(selection.start) ?? state._value.text.length,
        end: atomicBoundary.getTrailingTextBoundaryAt(selection.end - 1) ?? 0,
      );
      return Actions.invoke(
        context!,
        ReplaceTextIntent(state._value, '', range, SelectionChangedCause.keyboard),
      );
    }

    final int target = _applyTextBoundary(selection.base, intent.forward, getTextBoundary()).offset;

    final TextRange rangeToDelete = TextSelection(
      baseOffset: intent.forward
        ? atomicBoundary.getLeadingTextBoundaryAt(selection.baseOffset) ?? state._value.text.length
        : atomicBoundary.getTrailingTextBoundaryAt(selection.baseOffset - 1) ?? 0,
      extentOffset: target,
    );
    return Actions.invoke(
      context!,
      ReplaceTextIntent(state._value, '', rangeToDelete, SelectionChangedCause.keyboard),
    );
  }

  @override
  bool get isActionEnabled => !state.widget.readOnly && state._value.selection.isValid;
}

class _UpdateTextSelectionAction<T extends DirectionalCaretMovementIntent> extends ContextAction<T> {
  _UpdateTextSelectionAction(
    this.state,
    this.getTextBoundary,
    this.applyTextBoundary, {
    required this.ignoreNonCollapsedSelection,
    this.isExpand = false,
    this.extentAtIndex = false,
  });

  final EditableTextStateDefault state;
  final bool ignoreNonCollapsedSelection;
  final bool isExpand;
  final bool extentAtIndex;
  final TextBoundary Function() getTextBoundary;
  final _ApplyTextBoundary applyTextBoundary;

  static const int NEWLINE_CODE_UNIT = 10;

  // Returns true iff the given position is at a wordwrap boundary in the
  // upstream position.
  bool _isAtWordwrapUpstream(TextPosition position) {
    final TextPosition end = TextPosition(
      offset: state.renderEditable.getLineAtOffset(position).end,
      affinity: TextAffinity.upstream,
    );
    return end == position && end.offset != state.textEditingValue.text.length
        && state.textEditingValue.text.codeUnitAt(position.offset) != NEWLINE_CODE_UNIT;
  }

  // Returns true if the given position at a wordwrap boundary in the
  // downstream position.
  bool _isAtWordwrapDownstream(TextPosition position) {
    final TextPosition start = TextPosition(
      offset: state.renderEditable.getLineAtOffset(position).start,
    );
    return start == position && start.offset != 0
        && state.textEditingValue.text.codeUnitAt(position.offset - 1) != NEWLINE_CODE_UNIT;
  }

  @override
  Object? invoke(T intent, [BuildContext? context]) {
    final TextSelection selection = state._value.selection;
    assert(selection.isValid);

    final bool collapseSelection = intent.collapseSelection || !state.widget.selectionEnabled;
    if (!selection.isCollapsed && !ignoreNonCollapsedSelection && collapseSelection) {
      return Actions.invoke(context!, UpdateSelectionIntent(
        state._value,
        TextSelection.collapsed(offset: intent.forward ? selection.end : selection.start),
        SelectionChangedCause.keyboard,
      ));
    }

    TextPosition extent = selection.extent;
    // If continuesAtWrap is true extent and is at the relevant wordwrap, then
    // move it just to the other side of the wordwrap.
    if (intent.continuesAtWrap) {
      if (intent.forward && _isAtWordwrapUpstream(extent)) {
        extent = TextPosition(
          offset: extent.offset,
        );
      } else if (!intent.forward && _isAtWordwrapDownstream(extent)) {
        extent = TextPosition(
          offset: extent.offset,
          affinity: TextAffinity.upstream,
        );
      }
    }

    final bool shouldTargetBase = isExpand && (intent.forward ? selection.baseOffset > selection.extentOffset : selection.baseOffset < selection.extentOffset);
    final TextPosition newExtent = applyTextBoundary(shouldTargetBase ? selection.base : extent, intent.forward, getTextBoundary());
    final TextSelection newSelection = collapseSelection || (!isExpand && newExtent.offset == selection.baseOffset)
      ? TextSelection.fromPosition(newExtent)
      : isExpand ? selection.expandTo(newExtent, extentAtIndex || selection.isCollapsed) : selection.extendTo(newExtent);

    final bool shouldCollapseToBase = intent.collapseAtReversal
      && (selection.baseOffset - selection.extentOffset) * (selection.baseOffset - newSelection.extentOffset) < 0;
    final TextSelection newRange = shouldCollapseToBase ? TextSelection.fromPosition(selection.base) : newSelection;
    return Actions.invoke(context!, UpdateSelectionIntent(state._value, newRange, SelectionChangedCause.keyboard));
  }

  @override
  bool get isActionEnabled => state._value.selection.isValid;
}

class _UpdateTextSelectionVerticallyAction<T extends DirectionalCaretMovementIntent> extends ContextAction<T> {
  _UpdateTextSelectionVerticallyAction(this.state);

  final EditableTextStateDefault state;

  VerticalCaretMovementRun? _verticalMovementRun;
  TextSelection? _runSelection;

  void stopCurrentVerticalRunIfSelectionChanges() {
    final TextSelection? runSelection = _runSelection;
    if (runSelection == null) {
      assert(_verticalMovementRun == null);
      return;
    }
    _runSelection = state._value.selection;
    final TextSelection currentSelection = state.widget.controller.selection;
    final bool continueCurrentRun = currentSelection.isValid && currentSelection.isCollapsed
                                    && currentSelection.baseOffset == runSelection.baseOffset
                                    && currentSelection.extentOffset == runSelection.extentOffset;
    if (!continueCurrentRun) {
      _verticalMovementRun = null;
      _runSelection = null;
    }
  }

  @override
  void invoke(T intent, [BuildContext? context]) {
    assert(state._value.selection.isValid);

    final bool collapseSelection = intent.collapseSelection || !state.widget.selectionEnabled;
    final TextEditingValue value = state._textEditingValueforTextLayoutMetrics;
    if (!value.selection.isValid) {
      return;
    }

    if (_verticalMovementRun?.isValid == false) {
      _verticalMovementRun = null;
      _runSelection = null;
    }

    final VerticalCaretMovementRun currentRun = _verticalMovementRun
      ?? state.renderEditable.startVerticalCaretMovement(state.renderEditable.selection!.extent);

    final bool shouldMove = intent is ExtendSelectionVerticallyToAdjacentPageIntent
      ? currentRun.moveByOffset((intent.forward ? 1.0 : -1.0) * state.renderEditable.size.height)
      : intent.forward ? currentRun.moveNext() : currentRun.movePrevious();
    final TextPosition newExtent = shouldMove
      ? currentRun.current
      : intent.forward ? TextPosition(offset: value.text.length) : const TextPosition(offset: 0);
    final TextSelection newSelection = collapseSelection
      ? TextSelection.fromPosition(newExtent)
      : value.selection.extendTo(newExtent);

    Actions.invoke(
      context!,
      UpdateSelectionIntent(value, newSelection, SelectionChangedCause.keyboard),
    );
    if (state._value.selection == newSelection) {
      _verticalMovementRun = currentRun;
      _runSelection = newSelection;
    }
  }

  @override
  bool get isActionEnabled => state._value.selection.isValid;
}

class _SelectAllAction extends ContextAction<SelectAllTextIntent> {
  _SelectAllAction(this.state);

  final EditableTextStateDefault state;

  @override
  Object? invoke(SelectAllTextIntent intent, [BuildContext? context]) {
    return Actions.invoke(
      context!,
      UpdateSelectionIntent(
        state._value,
        TextSelection(baseOffset: 0, extentOffset: state._value.text.length),
        intent.cause,
      ),
    );
  }

  @override
  bool get isActionEnabled => state.widget.selectionEnabled;
}

class _CopySelectionAction extends ContextAction<CopySelectionTextIntent> {
  _CopySelectionAction(this.state);

  final EditableTextStateDefault state;

  @override
  void invoke(CopySelectionTextIntent intent, [BuildContext? context]) {
    if (intent.collapseSelection) {
      state.cutSelection(intent.cause);
    } else {
      state.copySelection(intent.cause);
    }
  }

  @override
  bool get isActionEnabled => state._value.selection.isValid && !state._value.selection.isCollapsed;
}

/// The start and end glyph heights of some range of text.
@immutable
class _GlyphHeights {
  const _GlyphHeights({
    required this.start,
    required this.end,
  });

  /// The glyph height of the first line.
  final double start;

  /// The glyph height of the last line.
  final double end;
}

/// A [ClipboardStatusNotifier] whose [value] is hardcoded to
/// [ClipboardStatus.pasteable].
///
/// Useful to avoid showing a permission dialog on web, which happens when
/// [Clipboard.hasStrings] is called.
class _WebClipboardStatusNotifier extends ClipboardStatusNotifier {
  @override
  ClipboardStatus value = ClipboardStatus.pasteable;

  @override
  Future<void> update() {
    return Future<void>.value();
  }
}
