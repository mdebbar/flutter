// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui hide TextStyle;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'actions.dart';
import 'automatic_keep_alive.dart';
import 'basic.dart';
import 'context_menu_button_item.dart';
import 'default_selection_style.dart';
import 'editable_text_default.dart';
import 'focus_manager.dart';
import 'framework.dart';
import 'magnifier.dart';
import 'media_query.dart';
import 'scroll_configuration.dart';
import 'scroll_controller.dart';
import 'scroll_notification_observer.dart';
import 'scroll_physics.dart';
import 'scrollable.dart';
import 'shortcuts.dart';
import 'spell_check.dart';
import 'tap_region.dart';
import 'text_editing_intents.dart';
import 'text_selection.dart';
import 'undo_history.dart';

export 'package:flutter/services.dart' show KeyboardInsertedContent, SelectionChangedCause, SmartDashesType, SmartQuotesType, TextEditingValue, TextInputType, TextSelection;

// Examples can assume:
// late BuildContext context;
// late WidgetTester tester;

/// Signature for the callback that reports when the user changes the selection
/// (including the cursor location).
typedef SelectionChangedCallback = void Function(TextSelection selection, SelectionChangedCause? cause);

/// Signature for the callback that reports the app private command results.
typedef AppPrivateCommandCallback = void Function(String action, Map<String, dynamic> data);

/// Signature for a widget builder that builds a context menu for the given
/// [EditableTextState].
///
/// See also:
///
///  * [SelectableRegionContextMenuBuilder], which performs the same role for
///    [SelectableRegion].
typedef EditableTextContextMenuBuilder = Widget Function(
  BuildContext context,
  EditableTextState editableTextState,
);

/// The default mime types to be used when allowedMimeTypes is not provided.
///
/// The default value supports inserting images of any supported format.
const List<String> kDefaultContentInsertionMimeTypes = <String>[
  'image/png',
  'image/bmp',
  'image/jpg',
  'image/tiff',
  'image/gif',
  'image/jpeg',
  'image/webp'
];

/// A controller for an editable text field.
///
/// Whenever the user modifies a text field with an associated
/// [TextEditingController], the text field updates [value] and the controller
/// notifies its listeners. Listeners can then read the [text] and [selection]
/// properties to learn what the user has typed or how the selection has been
/// updated.
///
/// Similarly, if you modify the [text] or [selection] properties, the text
/// field will be notified and will update itself appropriately.
///
/// A [TextEditingController] can also be used to provide an initial value for a
/// text field. If you build a text field with a controller that already has
/// [text], the text field will use that text as its initial value.
///
/// The [value] (as well as [text] and [selection]) of this controller can be
/// updated from within a listener added to this controller. Be aware of
/// infinite loops since the listener will also be notified of the changes made
/// from within itself. Modifying the composing region from within a listener
/// can also have a bad interaction with some input methods. Gboard, for
/// example, will try to restore the composing region of the text if it was
/// modified programmatically, creating an infinite loop of communications
/// between the framework and the input method. Consider using
/// [TextInputFormatter]s instead for as-you-type text modification.
///
/// If both the [text] or [selection] properties need to be changed, set the
/// controller's [value] instead.
///
/// Remember to [dispose] of the [TextEditingController] when it is no longer
/// needed. This will ensure we discard any resources used by the object.
/// {@tool dartpad}
/// This example creates a [TextField] with a [TextEditingController] whose
/// change listener forces the entered text to be lower case and keeps the
/// cursor at the end of the input.
///
/// ** See code in examples/api/lib/widgets/editable_text/text_editing_controller.0.dart **
/// {@end-tool}
///
/// See also:
///
///  * [TextField], which is a Material Design text field that can be controlled
///    with a [TextEditingController].
///  * [EditableText], which is a raw region of editable text that can be
///    controlled with a [TextEditingController].
///  * Learn how to use a [TextEditingController] in one of our [cookbook recipes](https://flutter.dev/docs/cookbook/forms/text-field-changes#2-use-a-texteditingcontroller).
class TextEditingController extends ValueNotifier<TextEditingValue> {
  /// Creates a controller for an editable text field.
  ///
  /// This constructor treats a null [text] argument as if it were the empty
  /// string.
  TextEditingController({ String? text })
    : super(text == null ? TextEditingValue.empty : TextEditingValue(text: text));

  /// Creates a controller for an editable text field from an initial [TextEditingValue].
  ///
  /// This constructor treats a null [value] argument as if it were
  /// [TextEditingValue.empty].
  TextEditingController.fromValue(TextEditingValue? value)
    : assert(
        value == null || !value.composing.isValid || value.isComposingRangeValid,
        'New TextEditingValue $value has an invalid non-empty composing range '
        '${value.composing}. It is recommended to use a valid composing range, '
        'even for readonly text fields.',
      ),
      super(value ?? TextEditingValue.empty);

  /// The current string the user is editing.
  String get text => value.text;
  /// Setting this will notify all the listeners of this [TextEditingController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this value should only be set between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  ///
  /// This property can be set from a listener added to this
  /// [TextEditingController]; **however, one should not also set [selection]
  /// in a separate statement. To change both the [text] and the [selection]
  /// change the controller's [value].**
  set text(String newText) {
    value = value.copyWith(
      text: newText,
      selection: const TextSelection.collapsed(offset: -1),
      composing: TextRange.empty,
    );
  }

  @override
  set value(TextEditingValue newValue) {
    assert(
      !newValue.composing.isValid || newValue.isComposingRangeValid,
      'New TextEditingValue $newValue has an invalid non-empty composing range '
      '${newValue.composing}. It is recommended to use a valid composing range, '
      'even for readonly text fields.',
    );
    super.value = newValue;
  }

  /// Builds [TextSpan] from current editing value.
  ///
  /// By default makes text in composing range appear as underlined. Descendants
  /// can override this method to customize appearance of text.
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style , required bool withComposing}) {
    assert(!value.composing.isValid || !withComposing || value.isComposingRangeValid);
    // If the composing range is out of range for the current text, ignore it to
    // preserve the tree integrity, otherwise in release mode a RangeError will
    // be thrown and this EditableText will be built with a broken subtree.
    final bool composingRegionOutOfRange = !value.isComposingRangeValid || !withComposing;

    if (composingRegionOutOfRange) {
      return TextSpan(style: style, text: text);
    }

    final TextStyle composingStyle = style?.merge(const TextStyle(decoration: TextDecoration.underline))
        ?? const TextStyle(decoration: TextDecoration.underline);
    return TextSpan(
      style: style,
      children: <TextSpan>[
        TextSpan(text: value.composing.textBefore(value.text)),
        TextSpan(
          style: composingStyle,
          text: value.composing.textInside(value.text),
        ),
        TextSpan(text: value.composing.textAfter(value.text)),
      ],
    );
  }

  /// The currently selected [text].
  ///
  /// If the selection is collapsed, then this property gives the offset of the
  /// cursor within the text.
  TextSelection get selection => value.selection;
  /// Setting this will notify all the listeners of this [TextEditingController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this value should only be set between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  ///
  /// This property can be set from a listener added to this
  /// [TextEditingController]; however, one should not also set [text]
  /// in a separate statement. To change both the [text] and the [selection]
  /// change the controller's [value].
  ///
  /// If the new selection is outside the composing range, the composing range is
  /// cleared.
  set selection(TextSelection newSelection) {
    if (!newSelection.isWithinTextBounds(text)) {
      throw FlutterError('invalid text selection: $newSelection');
    }
    final TextRange newComposing = _isSelectionWithinComposingRange(newSelection) ? value.composing : TextRange.empty;
    value = value.copyWith(selection: newSelection, composing: newComposing);
  }

  /// Set the [value] to empty.
  ///
  /// After calling this function, [text] will be the empty string and the
  /// selection will be collapsed at zero offset.
  ///
  /// Calling this will notify all the listeners of this [TextEditingController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  void clear() {
    value = const TextEditingValue(selection: TextSelection.collapsed(offset: 0));
  }

  /// Set the composing region to an empty range.
  ///
  /// The composing region is the range of text that is still being composed.
  /// Calling this function indicates that the user is done composing that
  /// region.
  ///
  /// Calling this will notify all the listeners of this [TextEditingController]
  /// that they need to update (it calls [notifyListeners]). For this reason,
  /// this method should only be called between frames, e.g. in response to user
  /// actions, not during the build, layout, or paint phases.
  void clearComposing() {
    value = value.copyWith(composing: TextRange.empty);
  }

  /// Check that the [selection] is inside of the composing range.
  bool _isSelectionWithinComposingRange(TextSelection selection) {
    return selection.start >= value.composing.start && selection.end <= value.composing.end;
  }
}

/// Toolbar configuration for [EditableText].
///
/// Toolbar is a context menu that will show up when user right click or long
/// press the [EditableText]. It includes several options: cut, copy, paste,
/// and select all.
///
/// [EditableText] and its derived widgets have their own default [ToolbarOptions].
/// Create a custom [ToolbarOptions] if you want explicit control over the toolbar
/// option.
@Deprecated(
  'Use `contextMenuBuilder` instead. '
  'This feature was deprecated after v3.3.0-0.5.pre.',
)
class ToolbarOptions {
  /// Create a toolbar configuration with given options.
  ///
  /// All options default to false if they are not explicitly set.
  @Deprecated(
    'Use `contextMenuBuilder` instead. '
    'This feature was deprecated after v3.3.0-0.5.pre.',
  )
  const ToolbarOptions({
    this.copy = false,
    this.cut = false,
    this.paste = false,
    this.selectAll = false,
  });

  /// An instance of [ToolbarOptions] with no options enabled.
  static const ToolbarOptions empty = ToolbarOptions();

  /// Whether to show copy option in toolbar.
  ///
  /// Defaults to false.
  final bool copy;

  /// Whether to show cut option in toolbar.
  ///
  /// If [EditableText.readOnly] is set to true, cut will be disabled regardless.
  ///
  /// Defaults to false.
  final bool cut;

  /// Whether to show paste option in toolbar.
  ///
  /// If [EditableText.readOnly] is set to true, paste will be disabled regardless.
  ///
  /// Defaults to false.
  final bool paste;

  /// Whether to show select all option in toolbar.
  ///
  /// Defaults to false.
  final bool selectAll;
}

/// Configures the ability to insert media content through the soft keyboard.
///
/// The configuration provides a handler for any rich content inserted through
/// the system input method, and also provides the ability to limit the mime
/// types of the inserted content.
///
/// See also:
///
/// * [EditableText.contentInsertionConfiguration]
class ContentInsertionConfiguration {
  /// Creates a content insertion configuration with the specified options.
  ///
  /// A handler for inserted content, in the form of [onContentInserted], must
  /// be supplied.
  ///
  /// The allowable mime types of inserted content may also
  /// be provided via [allowedMimeTypes], which cannot be an empty list.
  ContentInsertionConfiguration({
    required this.onContentInserted,
    this.allowedMimeTypes = kDefaultContentInsertionMimeTypes,
  }) : assert(allowedMimeTypes.isNotEmpty);

  /// Called when a user inserts content through the virtual / on-screen keyboard,
  /// currently only used on Android.
  ///
  /// [KeyboardInsertedContent] holds the data representing the inserted content.
  ///
  /// {@tool dartpad}
  ///
  /// This example shows how to access the data for inserted content in your
  /// `TextField`.
  ///
  /// ** See code in examples/api/lib/widgets/editable_text/editable_text.on_content_inserted.0.dart **
  /// {@end-tool}
  ///
  /// See also:
  ///
  ///  * <https://developer.android.com/guide/topics/text/image-keyboard>
  final ValueChanged<KeyboardInsertedContent> onContentInserted;

  /// {@template flutter.widgets.contentInsertionConfiguration.allowedMimeTypes}
  /// Used when a user inserts image-based content through the device keyboard,
  /// currently only used on Android.
  ///
  /// The passed list of strings will determine which MIME types are allowed to
  /// be inserted via the device keyboard.
  ///
  /// The default mime types are given by [kDefaultContentInsertionMimeTypes].
  /// These are all the mime types that are able to be handled and inserted
  /// from keyboards.
  ///
  /// This field cannot be an empty list.
  ///
  /// {@tool dartpad}
  /// This example shows how to limit image insertion to specific file types.
  ///
  /// ** See code in examples/api/lib/widgets/editable_text/editable_text.on_content_inserted.0.dart **
  /// {@end-tool}
  ///
  /// See also:
  ///
  ///  * <https://developer.android.com/guide/topics/text/image-keyboard>
  /// {@endtemplate}
  final List<String> allowedMimeTypes;
}

/// The signature of functions that are replacing [EditableText.build].
///
/// See also:
///
/// * [EditableText], which provides basic text editing functionality.
/// * [EditableTextCustomizer], which customizes [EditableText] widgets.
typedef EditableTextBuilder = Widget Function(BuildContext, EditableText);

/// Customizes [EditableText] widgets within a widget subtree.
class EditableTextCustomizer extends InheritedWidget {
  /// Constructs a customization for the [EditableText] widget within this
  /// widget tree.
  const EditableTextCustomizer({
    super.key,
    required this.buildEditableText,
    required super.child,
  });

  /// The builder method that will be called by [EditableText] widgets.
  final EditableTextBuilder buildEditableText;

  static EditableTextBuilder _of(BuildContext context) {
    final EditableTextCustomizer? editableTextCustomizer = context.dependOnInheritedWidgetOfExactType<EditableTextCustomizer>();
    return editableTextCustomizer?.buildEditableText ?? EditableTextStateDefault.buildEditableText;
  }

  @override
  bool updateShouldNotify(EditableTextCustomizer oldWidget) => buildEditableText != oldWidget.buildEditableText;
}

/// ```
/// class MyWidget extends StatelessWidget {
///   const MyWidget({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     return EditableTextCustomizer(
///       buildEditableText: (context, editableText) {
///         return WebEditableText(editableText);
///       },
///       child: MaterialApp(
///         home: Column(
///           children: [
///             TextField(...),
///           ],
///         ),
///       ),
///     );
///   }
/// }
/// ```

/// A basic text input field.
///
/// This widget interacts with the [TextInput] service to let the user edit the
/// text it contains. It also provides scrolling, selection, and cursor
/// movement.
///
/// The [EditableText] widget is a low-level widget that is intended as a
/// building block for custom widget sets. For a complete user experience,
/// consider using a [TextField] or [CupertinoTextField].
///
/// ## Handling User Input
///
/// Currently the user may change the text this widget contains via keyboard or
/// the text selection menu. When the user inserted or deleted text, you will be
/// notified of the change and get a chance to modify the new text value:
///
/// * The [inputFormatters] will be first applied to the user input.
///
/// * The [controller]'s [TextEditingController.value] will be updated with the
///   formatted result, and the [controller]'s listeners will be notified.
///
/// * The [onChanged] callback, if specified, will be called last.
///
/// ## Input Actions
///
/// A [TextInputAction] can be provided to customize the appearance of the
/// action button on the soft keyboard for Android and iOS. The default action
/// is [TextInputAction.done].
///
/// Many [TextInputAction]s are common between Android and iOS. However, if a
/// [textInputAction] is provided that is not supported by the current
/// platform in debug mode, an error will be thrown when the corresponding
/// EditableText receives focus. For example, providing iOS's "emergencyCall"
/// action when running on an Android device will result in an error when in
/// debug mode. In release mode, incompatible [TextInputAction]s are replaced
/// either with "unspecified" on Android, or "default" on iOS. Appropriate
/// [textInputAction]s can be chosen by checking the current platform and then
/// selecting the appropriate action.
///
/// {@template flutter.widgets.EditableText.lifeCycle}
/// ## Lifecycle
///
/// Upon completion of editing, like pressing the "done" button on the keyboard,
/// two actions take place:
///
///   1st: Editing is finalized. The default behavior of this step includes
///   an invocation of [onChanged]. That default behavior can be overridden.
///   See [onEditingComplete] for details.
///
///   2nd: [onSubmitted] is invoked with the user's input value.
///
/// [onSubmitted] can be used to manually move focus to another input widget
/// when a user finishes with the currently focused input widget.
///
/// When the widget has focus, it will prevent itself from disposing via
/// [AutomaticKeepAliveClientMixin.wantKeepAlive] in order to avoid losing the
/// selection. Removing the focus will allow it to be disposed.
/// {@endtemplate}
///
/// Rather than using this widget directly, consider using [TextField], which
/// is a full-featured, material-design text input field with placeholder text,
/// labels, and [Form] integration.
///
/// ## Text Editing [Intent]s and Their Default [Action]s
///
/// This widget provides default [Action]s for handling common text editing
/// [Intent]s such as deleting, copying and pasting in the text field. These
/// [Action]s can be directly invoked using [Actions.invoke] or the
/// [Actions.maybeInvoke] method. The default text editing keyboard [Shortcuts]
/// also use these [Intent]s and [Action]s to perform the text editing
/// operations they are bound to.
///
/// The default handling of a specific [Intent] can be overridden by placing an
/// [Actions] widget above this widget. See the [Action] class and the
/// [Action.overridable] constructor for more information on how a pre-defined
/// overridable [Action] can be overridden.
///
/// ### Intents for Deleting Text and Their Default Behavior
///
/// | **Intent Class**                 | **Default Behavior when there's selected text**      | **Default Behavior when there is a [caret](https://en.wikipedia.org/wiki/Caret_navigation) (The selection is [TextSelection.collapsed])**  |
/// | :------------------------------- | :--------------------------------------------------- | :----------------------------------------------------------------------- |
/// | [DeleteCharacterIntent]          | Deletes the selected text                            | Deletes the user-perceived character before or after the caret location. |
/// | [DeleteToNextWordBoundaryIntent] | Deletes the selected text and the word before/after the selection's [TextSelection.extent] position | Deletes from the caret location to the previous or the next word boundary |
/// | [DeleteToLineBreakIntent]        | Deletes the selected text, and deletes to the start/end of the line from the selection's [TextSelection.extent] position | Deletes from the caret location to the logical start or end of the current line |
///
/// ### Intents for Moving the [Caret](https://en.wikipedia.org/wiki/Caret_navigation)
///
/// | **Intent Class**                                                                     | **Default Behavior when there's selected text**                  | **Default Behavior when there is a caret ([TextSelection.collapsed])**  |
/// | :----------------------------------------------------------------------------------- | :--------------------------------------------------------------- | :---------------------------------------------------------------------- |
/// | [ExtendSelectionByCharacterIntent](`collapseSelection: true`)                        | Collapses the selection to the logical start/end of the selection | Moves the caret past the user-perceived character before or after the current caret location. |
/// | [ExtendSelectionToNextWordBoundaryIntent](`collapseSelection: true`)                 | Collapses the selection to the word boundary before/after the selection's [TextSelection.extent] position | Moves the caret to the previous/next word boundary. |
/// | [ExtendSelectionToNextWordBoundaryOrCaretLocationIntent](`collapseSelection: true`)  | Collapses the selection to the word boundary before/after the selection's [TextSelection.extent] position, or [TextSelection.base], whichever is closest in the given direction | Moves the caret to the previous/next word boundary. |
/// | [ExtendSelectionToLineBreakIntent](`collapseSelection: true`)                        | Collapses the selection to the start/end of the line at the selection's [TextSelection.extent] position | Moves the caret to the start/end of the current line .|
/// | [ExtendSelectionVerticallyToAdjacentLineIntent](`collapseSelection: true`)           | Collapses the selection to the position closest to the selection's [TextSelection.extent], on the previous/next adjacent line | Moves the caret to the closest position on the previous/next adjacent line. |
/// | [ExtendSelectionVerticallyToAdjacentPageIntent](`collapseSelection: true`)           | Collapses the selection to the position closest to the selection's [TextSelection.extent], on the previous/next adjacent page | Moves the caret to the closest position on the previous/next adjacent page. |
/// | [ExtendSelectionToDocumentBoundaryIntent](`collapseSelection: true`)                 | Collapses the selection to the start/end of the document | Moves the caret to the start/end of the document. |
///
/// #### Intents for Extending the Selection
///
/// | **Intent Class**                                                                     | **Default Behavior when there's selected text**                  | **Default Behavior when there is a caret ([TextSelection.collapsed])**  |
/// | :----------------------------------------------------------------------------------- | :--------------------------------------------------------------- | :---------------------------------------------------------------------- |
/// | [ExtendSelectionByCharacterIntent](`collapseSelection: false`)                       | Moves the selection's [TextSelection.extent] past the user-perceived character before/after it |
/// | [ExtendSelectionToNextWordBoundaryIntent](`collapseSelection: false`)                | Moves the selection's [TextSelection.extent] to the previous/next word boundary |
/// | [ExtendSelectionToNextWordBoundaryOrCaretLocationIntent](`collapseSelection: false`) | Moves the selection's [TextSelection.extent] to the previous/next word boundary, or [TextSelection.base] whichever is closest in the given direction | Moves the selection's [TextSelection.extent] to the previous/next word boundary. |
/// | [ExtendSelectionToLineBreakIntent](`collapseSelection: false`)                       | Moves the selection's [TextSelection.extent] to the start/end of the line |
/// | [ExtendSelectionVerticallyToAdjacentLineIntent](`collapseSelection: false`)          | Moves the selection's [TextSelection.extent] to the closest position on the previous/next adjacent line |
/// | [ExtendSelectionVerticallyToAdjacentPageIntent](`collapseSelection: false`)          | Moves the selection's [TextSelection.extent] to the closest position on the previous/next adjacent page |
/// | [ExtendSelectionToDocumentBoundaryIntent](`collapseSelection: false`)                | Moves the selection's [TextSelection.extent] to the start/end of the document |
/// | [SelectAllTextIntent]  | Selects the entire document |
///
/// ### Other Intents
///
/// | **Intent Class**                        | **Default Behavior**                                 |
/// | :-------------------------------------- | :--------------------------------------------------- |
/// | [DoNothingAndStopPropagationTextIntent] | Does nothing in the input field, and prevents the key event from further propagating in the widget tree. |
/// | [ReplaceTextIntent]                     | Replaces the current [TextEditingValue] in the input field's [TextEditingController], and triggers all related user callbacks and [TextInputFormatter]s. |
/// | [UpdateSelectionIntent]                 | Updates the current selection in the input field's [TextEditingController], and triggers the [onSelectionChanged] callback. |
/// | [CopySelectionTextIntent]               | Copies or cuts the selected text into the clipboard |
/// | [PasteTextIntent]                       | Inserts the current text in the clipboard after the caret location, or replaces the selected text if the selection is not collapsed. |
///
/// ## Gesture Events Handling
///
/// When [rendererIgnoresPointer] is false (the default), this widget provides
/// rudimentary, platform-agnostic gesture handling for user actions such as
/// tapping, long-pressing, and scrolling.
///
/// To provide more complete gesture handling, including double-click to select
/// a word, drag selection, and platform-specific handling of gestures such as
/// long presses, consider setting [rendererIgnoresPointer] to true and using
/// [TextSelectionGestureDetectorBuilder].
///
/// {@template flutter.widgets.editableText.showCaretOnScreen}
/// ## Keep the caret visible when focused
///
/// When focused, this widget will make attempts to keep the text area and its
/// caret (even when [showCursor] is `false`) visible, on these occasions:
///
///  * When the user focuses this text field and it is not [readOnly].
///  * When the user changes the selection of the text field, or changes the
///    text when the text field is not [readOnly].
///  * When the virtual keyboard pops up.
/// {@endtemplate}
///
/// ## Scrolling Considerations
///
/// If this [EditableText] is not a descendant of [Scaffold] and is being used
/// within a [Scrollable] or nested [Scrollable]s, consider placing a
/// [ScrollNotificationObserver] above the root [Scrollable] that contains this
/// [EditableText] to ensure proper scroll coordination for [EditableText] and
/// its components like [TextSelectionOverlay].
///
/// {@template flutter.widgets.editableText.accessibility}
/// ## Troubleshooting Common Accessibility Issues
///
/// ### Customizing User Input Accessibility Announcements
///
/// To customize user input accessibility announcements triggered by text
/// changes, use [SemanticsService.announce] to make the desired
/// accessibility announcement.
///
/// On iOS, the on-screen keyboard may announce the most recent input
/// incorrectly when a [TextInputFormatter] inserts a thousands separator to
/// a currency value text field. The following example demonstrates how to
/// suppress the default accessibility announcements by always announcing
/// the content of the text field as a US currency value (the `\$` inserts
/// a dollar sign, the `$newText` interpolates the `newText` variable):
///
/// ```dart
/// onChanged: (String newText) {
///   if (newText.isNotEmpty) {
///     SemanticsService.announce('\$$newText', Directionality.of(context));
///   }
/// }
/// ```
///
/// {@endtemplate}
///
/// See also:
///
///  * [TextField], which is a full-featured, material-design text input field
///    with placeholder text, labels, and [Form] integration.
class EditableText extends StatelessWidget {
  /// Creates a basic text input control.
  ///
  /// The [maxLines] property can be set to null to remove the restriction on
  /// the number of lines. By default, it is one, meaning this is a single-line
  /// text field. [maxLines] must be null or greater than zero.
  ///
  /// If [keyboardType] is not set or is null, its value will be inferred from
  /// [autofillHints], if [autofillHints] is not empty. Otherwise it defaults to
  /// [TextInputType.text] if [maxLines] is exactly one, and
  /// [TextInputType.multiline] if [maxLines] is null or greater than one.
  ///
  /// The text cursor is not shown if [showCursor] is false or if [showCursor]
  /// is null (the default) and [readOnly] is true.
  EditableText({
    super.key,
    required this.controller,
    required this.focusNode,
    this.readOnly = false,
    this.obscuringCharacter = '•',
    this.obscureText = false,
    this.autocorrect = true,
    SmartDashesType? smartDashesType,
    SmartQuotesType? smartQuotesType,
    this.enableSuggestions = true,
    required this.style,
    StrutStyle? strutStyle,
    required this.cursorColor,
    required this.backgroundCursorColor,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.locale,
    @Deprecated(
      'Use textScaler instead. '
      'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
      'This feature was deprecated after v3.12.0-2.0.pre.',
    )
    this.textScaleFactor,
    this.textScaler,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.forceLine = true,
    this.textHeightBehavior,
    this.textWidthBasis = TextWidthBasis.parent,
    this.autofocus = false,
    bool? showCursor,
    this.showSelectionHandles = false,
    this.selectionColor,
    this.selectionControls,
    TextInputType? keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.onAppPrivateCommand,
    this.onSelectionChanged,
    this.onSelectionHandleTapped,
    this.onTapOutside,
    List<TextInputFormatter>? inputFormatters,
    this.mouseCursor,
    this.rendererIgnoresPointer = false,
    this.cursorWidth = 2.0,
    this.cursorHeight,
    this.cursorRadius,
    this.cursorOpacityAnimates = false,
    this.cursorOffset,
    this.paintCursorAboveText = false,
    this.selectionHeightStyle = ui.BoxHeightStyle.tight,
    this.selectionWidthStyle = ui.BoxWidthStyle.tight,
    this.scrollPadding = const EdgeInsets.all(20.0),
    this.keyboardAppearance = Brightness.light,
    this.dragStartBehavior = DragStartBehavior.start,
    bool? enableInteractiveSelection,
    this.scrollController,
    this.scrollPhysics,
    this.autocorrectionTextRectColor,
    @Deprecated(
      'Use `contextMenuBuilder` instead. '
      'This feature was deprecated after v3.3.0-0.5.pre.',
    )
    ToolbarOptions? toolbarOptions,
    this.autofillHints = const <String>[],
    this.autofillClient,
    this.clipBehavior = Clip.hardEdge,
    this.restorationId,
    this.scrollBehavior,
    this.scribbleEnabled = true,
    this.enableIMEPersonalizedLearning = true,
    this.contentInsertionConfiguration,
    this.contextMenuBuilder,
    this.spellCheckConfiguration,
    this.magnifierConfiguration = TextMagnifierConfiguration.disabled,
    this.undoController,
  }) : assert(obscuringCharacter.length == 1),
       smartDashesType = smartDashesType ?? (obscureText ? SmartDashesType.disabled : SmartDashesType.enabled),
       smartQuotesType = smartQuotesType ?? (obscureText ? SmartQuotesType.disabled : SmartQuotesType.enabled),
       assert(minLines == null || minLines > 0),
       assert(
         (maxLines == null) || (minLines == null) || (maxLines >= minLines),
         "minLines can't be greater than maxLines",
       ),
       assert(
         !expands || (maxLines == null && minLines == null),
         'minLines and maxLines must be null when expands is true.',
       ),
       assert(!obscureText || maxLines == 1, 'Obscured fields cannot be multiline.'),
       enableInteractiveSelection = enableInteractiveSelection ?? (!readOnly || !obscureText),
       toolbarOptions = selectionControls is TextSelectionHandleControls && toolbarOptions == null ? ToolbarOptions.empty : toolbarOptions ??
           (obscureText
               ? (readOnly
                   // No point in even offering "Select All" in a read-only obscured
                   // field.
                   ? ToolbarOptions.empty
                   // Writable, but obscured.
                   : const ToolbarOptions(
                       selectAll: true,
                       paste: true,
                     ))
               : (readOnly
                   // Read-only, not obscured.
                   ? const ToolbarOptions(
                       selectAll: true,
                       copy: true,
                     )
                   // Writable, not obscured.
                   : const ToolbarOptions(
                       copy: true,
                       cut: true,
                       selectAll: true,
                       paste: true,
                     ))),
       assert(
          spellCheckConfiguration == null ||
          spellCheckConfiguration == const SpellCheckConfiguration.disabled() ||
          spellCheckConfiguration.misspelledTextStyle != null,
          'spellCheckConfiguration must specify a misspelledTextStyle if spell check behavior is desired',
       ),
       _strutStyle = strutStyle,
       keyboardType = keyboardType ?? _inferKeyboardType(autofillHints: autofillHints, maxLines: maxLines),
       inputFormatters = maxLines == 1
           ? <TextInputFormatter>[
               FilteringTextInputFormatter.singleLineFormatter,
               ...inputFormatters ?? const Iterable<TextInputFormatter>.empty(),
             ]
           : inputFormatters,
       showCursor = showCursor ?? !readOnly;

  /// Controls the text being edited.
  final TextEditingController controller;

  /// Controls whether this widget has keyboard focus.
  final FocusNode focusNode;

  /// {@template flutter.widgets.editableText.obscuringCharacter}
  /// Character used for obscuring text if [obscureText] is true.
  ///
  /// Must be only a single character.
  ///
  /// Defaults to the character U+2022 BULLET (•).
  /// {@endtemplate}
  final String obscuringCharacter;

  /// {@template flutter.widgets.editableText.obscureText}
  /// Whether to hide the text being edited (e.g., for passwords).
  ///
  /// When this is set to true, all the characters in the text field are
  /// replaced by [obscuringCharacter], and the text in the field cannot be
  /// copied with copy or cut. If [readOnly] is also true, then the text cannot
  /// be selected.
  ///
  /// Defaults to false.
  /// {@endtemplate}
  final bool obscureText;

  /// {@macro dart.ui.textHeightBehavior}
  final TextHeightBehavior? textHeightBehavior;

  /// {@macro flutter.painting.textPainter.textWidthBasis}
  final TextWidthBasis textWidthBasis;

  /// {@template flutter.widgets.editableText.readOnly}
  /// Whether the text can be changed.
  ///
  /// When this is set to true, the text cannot be modified
  /// by any shortcut or keyboard operation. The text is still selectable.
  ///
  /// Defaults to false.
  /// {@endtemplate}
  final bool readOnly;

  /// Whether the text will take the full width regardless of the text width.
  ///
  /// When this is set to false, the width will be based on text width, which
  /// will also be affected by [textWidthBasis].
  ///
  /// Defaults to true.
  ///
  /// See also:
  ///
  ///  * [textWidthBasis], which controls the calculation of text width.
  final bool forceLine;

  /// Configuration of toolbar options.
  ///
  /// By default, all options are enabled. If [readOnly] is true, paste and cut
  /// will be disabled regardless. If [obscureText] is true, cut and copy will
  /// be disabled regardless. If [readOnly] and [obscureText] are both true,
  /// select all will also be disabled.
  final ToolbarOptions toolbarOptions;

  /// Whether to show selection handles.
  ///
  /// When a selection is active, there will be two handles at each side of
  /// boundary, or one handle if the selection is collapsed. The handles can be
  /// dragged to adjust the selection.
  ///
  /// See also:
  ///
  ///  * [showCursor], which controls the visibility of the cursor.
  final bool showSelectionHandles;

  /// {@template flutter.widgets.editableText.showCursor}
  /// Whether to show cursor.
  ///
  /// The cursor refers to the blinking caret when the [EditableText] is focused.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [showSelectionHandles], which controls the visibility of the selection handles.
  final bool showCursor;

  /// {@template flutter.widgets.editableText.autocorrect}
  /// Whether to enable autocorrection.
  ///
  /// Defaults to true.
  /// {@endtemplate}
  final bool autocorrect;

  /// {@macro flutter.services.TextInputConfiguration.smartDashesType}
  final SmartDashesType smartDashesType;

  /// {@macro flutter.services.TextInputConfiguration.smartQuotesType}
  final SmartQuotesType smartQuotesType;

  /// {@macro flutter.services.TextInputConfiguration.enableSuggestions}
  final bool enableSuggestions;

  /// The text style to use for the editable text.
  final TextStyle style;

  /// Controls the undo state of the current editable text.
  ///
  /// If null, this widget will create its own [UndoHistoryController].
  final UndoHistoryController? undoController;

  /// {@template flutter.widgets.editableText.strutStyle}
  /// The strut style used for the vertical layout.
  ///
  /// [StrutStyle] is used to establish a predictable vertical layout.
  /// Since fonts may vary depending on user input and due to font
  /// fallback, [StrutStyle.forceStrutHeight] is enabled by default
  /// to lock all lines to the height of the base [TextStyle], provided by
  /// [style]. This ensures the typed text fits within the allotted space.
  ///
  /// If null, the strut used will inherit values from the [style] and will
  /// have [StrutStyle.forceStrutHeight] set to true. When no [style] is
  /// passed, the theme's [TextStyle] will be used to generate [strutStyle]
  /// instead.
  ///
  /// To disable strut-based vertical alignment and allow dynamic vertical
  /// layout based on the glyphs typed, use [StrutStyle.disabled].
  ///
  /// Flutter's strut is based on [typesetting strut](https://en.wikipedia.org/wiki/Strut_(typesetting))
  /// and CSS's [line-height](https://www.w3.org/TR/CSS2/visudet.html#line-height).
  /// {@endtemplate}
  ///
  /// Within editable text and text fields, [StrutStyle] will not use its standalone
  /// default values, and will instead inherit omitted/null properties from the
  /// [TextStyle] instead. See [StrutStyle.inheritFromTextStyle].
  StrutStyle get strutStyle {
    if (_strutStyle == null) {
      return StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    }
    return _strutStyle.inheritFromTextStyle(style);
  }
  final StrutStyle? _strutStyle;

  /// {@template flutter.widgets.editableText.textAlign}
  /// How the text should be aligned horizontally.
  ///
  /// Defaults to [TextAlign.start].
  /// {@endtemplate}
  final TextAlign textAlign;

  /// {@template flutter.widgets.editableText.textDirection}
  /// The directionality of the text.
  ///
  /// This decides how [textAlign] values like [TextAlign.start] and
  /// [TextAlign.end] are interpreted.
  ///
  /// This is also used to disambiguate how to render bidirectional text. For
  /// example, if the text is an English phrase followed by a Hebrew phrase,
  /// in a [TextDirection.ltr] context the English phrase will be on the left
  /// and the Hebrew phrase to its right, while in a [TextDirection.rtl]
  /// context, the English phrase will be on the right and the Hebrew phrase on
  /// its left.
  ///
  /// Defaults to the ambient [Directionality], if any.
  /// {@endtemplate}
  final TextDirection? textDirection;

  /// {@template flutter.widgets.editableText.textCapitalization}
  /// Configures how the platform keyboard will select an uppercase or
  /// lowercase keyboard.
  ///
  /// Only supports text keyboards, other keyboard types will ignore this
  /// configuration. Capitalization is locale-aware.
  ///
  /// Defaults to [TextCapitalization.none].
  ///
  /// See also:
  ///
  ///  * [TextCapitalization], for a description of each capitalization behavior.
  ///
  /// {@endtemplate}
  final TextCapitalization textCapitalization;

  /// Used to select a font when the same Unicode character can
  /// be rendered differently, depending on the locale.
  ///
  /// It's rarely necessary to set this property. By default its value
  /// is inherited from the enclosing app with `Localizations.localeOf(context)`.
  ///
  /// See [RenderEditable.locale] for more information.
  final Locale? locale;

  /// {@template flutter.widgets.editableText.textScaleFactor}
  /// Deprecated. Will be removed in a future version of Flutter. Use
  /// [textScaler] instead.
  ///
  /// The number of font pixels for each logical pixel.
  ///
  /// For example, if the text scale factor is 1.5, text will be 50% larger than
  /// the specified font size.
  ///
  /// Defaults to the [MediaQueryData.textScaleFactor] obtained from the ambient
  /// [MediaQuery], or 1.0 if there is no [MediaQuery] in scope.
  /// {@endtemplate}
  @Deprecated(
    'Use textScaler instead. '
    'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
    'This feature was deprecated after v3.12.0-2.0.pre.',
  )
  final double? textScaleFactor;

  /// {@macro flutter.painting.textPainter.textScaler}
  final TextScaler? textScaler;

  /// The color to use when painting the cursor.
  final Color cursorColor;

  /// The color to use when painting the autocorrection Rect.
  ///
  /// For [CupertinoTextField]s, the value is set to the ambient
  /// [CupertinoThemeData.primaryColor] with 20% opacity. For [TextField]s, the
  /// value is null on non-iOS platforms and the same color used in [CupertinoTextField]
  /// on iOS.
  ///
  /// Currently the autocorrection Rect only appears on iOS.
  ///
  /// Defaults to null, which disables autocorrection Rect painting.
  final Color? autocorrectionTextRectColor;

  /// The color to use when painting the background cursor aligned with the text
  /// while rendering the floating cursor.
  ///
  /// Typically this would be set to [CupertinoColors.inactiveGray].
  ///
  /// See also:
  ///
  ///  * [FloatingCursorDragState], which explains the floating cursor feature
  ///    in detail.
  final Color backgroundCursorColor;

  /// {@template flutter.widgets.editableText.maxLines}
  /// The maximum number of lines to show at one time, wrapping if necessary.
  ///
  /// This affects the height of the field itself and does not limit the number
  /// of lines that can be entered into the field.
  ///
  /// If this is 1 (the default), the text will not wrap, but will scroll
  /// horizontally instead.
  ///
  /// If this is null, there is no limit to the number of lines, and the text
  /// container will start with enough vertical space for one line and
  /// automatically grow to accommodate additional lines as they are entered, up
  /// to the height of its constraints.
  ///
  /// If this is not null, the value must be greater than zero, and it will lock
  /// the input to the given number of lines and take up enough horizontal space
  /// to accommodate that number of lines. Setting [minLines] as well allows the
  /// input to grow and shrink between the indicated range.
  ///
  /// The full set of behaviors possible with [minLines] and [maxLines] are as
  /// follows. These examples apply equally to [TextField], [TextFormField],
  /// [CupertinoTextField], and [EditableText].
  ///
  /// Input that occupies a single line and scrolls horizontally as needed.
  /// ```dart
  /// const TextField()
  /// ```
  ///
  /// Input whose height grows from one line up to as many lines as needed for
  /// the text that was entered. If a height limit is imposed by its parent, it
  /// will scroll vertically when its height reaches that limit.
  /// ```dart
  /// const TextField(maxLines: null)
  /// ```
  ///
  /// The input's height is large enough for the given number of lines. If
  /// additional lines are entered the input scrolls vertically.
  /// ```dart
  /// const TextField(maxLines: 2)
  /// ```
  ///
  /// Input whose height grows with content between a min and max. An infinite
  /// max is possible with `maxLines: null`.
  /// ```dart
  /// const TextField(minLines: 2, maxLines: 4)
  /// ```
  ///
  /// See also:
  ///
  ///  * [minLines], which sets the minimum number of lines visible.
  /// {@endtemplate}
  ///  * [expands], which determines whether the field should fill the height of
  ///    its parent.
  final int? maxLines;

  /// {@template flutter.widgets.editableText.minLines}
  /// The minimum number of lines to occupy when the content spans fewer lines.
  ///
  /// This affects the height of the field itself and does not limit the number
  /// of lines that can be entered into the field.
  ///
  /// If this is null (default), text container starts with enough vertical space
  /// for one line and grows to accommodate additional lines as they are entered.
  ///
  /// This can be used in combination with [maxLines] for a varying set of behaviors.
  ///
  /// If the value is set, it must be greater than zero. If the value is greater
  /// than 1, [maxLines] should also be set to either null or greater than
  /// this value.
  ///
  /// When [maxLines] is set as well, the height will grow between the indicated
  /// range of lines. When [maxLines] is null, it will grow as high as needed,
  /// starting from [minLines].
  ///
  /// A few examples of behaviors possible with [minLines] and [maxLines] are as follows.
  /// These apply equally to [TextField], [TextFormField], [CupertinoTextField],
  /// and [EditableText].
  ///
  /// Input that always occupies at least 2 lines and has an infinite max.
  /// Expands vertically as needed.
  /// ```dart
  /// TextField(minLines: 2)
  /// ```
  ///
  /// Input whose height starts from 2 lines and grows up to 4 lines at which
  /// point the height limit is reached. If additional lines are entered it will
  /// scroll vertically.
  /// ```dart
  /// const TextField(minLines:2, maxLines: 4)
  /// ```
  ///
  /// Defaults to null.
  ///
  /// See also:
  ///
  ///  * [maxLines], which sets the maximum number of lines visible, and has
  ///    several examples of how minLines and maxLines interact to produce
  ///    various behaviors.
  /// {@endtemplate}
  ///  * [expands], which determines whether the field should fill the height of
  ///    its parent.
  final int? minLines;

  /// {@template flutter.widgets.editableText.expands}
  /// Whether this widget's height will be sized to fill its parent.
  ///
  /// If set to true and wrapped in a parent widget like [Expanded] or
  /// [SizedBox], the input will expand to fill the parent.
  ///
  /// [maxLines] and [minLines] must both be null when this is set to true,
  /// otherwise an error is thrown.
  ///
  /// Defaults to false.
  ///
  /// See the examples in [maxLines] for the complete picture of how [maxLines],
  /// [minLines], and [expands] interact to produce various behaviors.
  ///
  /// Input that matches the height of its parent:
  /// ```dart
  /// const Expanded(
  ///   child: TextField(maxLines: null, expands: true),
  /// )
  /// ```
  /// {@endtemplate}
  final bool expands;

  /// {@template flutter.widgets.editableText.autofocus}
  /// Whether this text field should focus itself if nothing else is already
  /// focused.
  ///
  /// If true, the keyboard will open as soon as this text field obtains focus.
  /// Otherwise, the keyboard is only shown after the user taps the text field.
  ///
  /// Defaults to false.
  /// {@endtemplate}
  // See https://github.com/flutter/flutter/issues/7035 for the rationale for this
  // keyboard behavior.
  final bool autofocus;

  /// The color to use when painting the selection.
  ///
  /// If this property is null, this widget gets the selection color from the
  /// [DefaultSelectionStyle].
  ///
  /// For [CupertinoTextField]s, the value is set to the ambient
  /// [CupertinoThemeData.primaryColor] with 20% opacity. For [TextField]s, the
  /// value is set to the ambient [TextSelectionThemeData.selectionColor].
  final Color? selectionColor;

  /// {@template flutter.widgets.editableText.selectionControls}
  /// Optional delegate for building the text selection handles.
  ///
  /// Historically, this field also controlled the toolbar. This is now handled
  /// by [contextMenuBuilder] instead. However, for backwards compatibility, when
  /// [selectionControls] is set to an object that does not mix in
  /// [TextSelectionHandleControls], [contextMenuBuilder] is ignored and the
  /// [TextSelectionControls.buildToolbar] method is used instead.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [CupertinoTextField], which wraps an [EditableText] and which shows the
  ///    selection toolbar upon user events that are appropriate on the iOS
  ///    platform.
  ///  * [TextField], a Material Design themed wrapper of [EditableText], which
  ///    shows the selection toolbar upon appropriate user events based on the
  ///    user's platform set in [ThemeData.platform].
  final TextSelectionControls? selectionControls;

  /// {@template flutter.widgets.editableText.keyboardType}
  /// The type of keyboard to use for editing the text.
  ///
  /// Defaults to [TextInputType.text] if [maxLines] is one and
  /// [TextInputType.multiline] otherwise.
  /// {@endtemplate}
  final TextInputType keyboardType;

  /// The type of action button to use with the soft keyboard.
  final TextInputAction? textInputAction;

  /// {@template flutter.widgets.editableText.onChanged}
  /// Called when the user initiates a change to the TextField's
  /// value: when they have inserted or deleted text.
  ///
  /// This callback doesn't run when the TextField's text is changed
  /// programmatically, via the TextField's [controller]. Typically it
  /// isn't necessary to be notified of such changes, since they're
  /// initiated by the app itself.
  ///
  /// To be notified of all changes to the TextField's text, cursor,
  /// and selection, one can add a listener to its [controller] with
  /// [TextEditingController.addListener].
  ///
  /// [onChanged] is called before [onSubmitted] when user indicates completion
  /// of editing, such as when pressing the "done" button on the keyboard. That
  /// default behavior can be overridden. See [onEditingComplete] for details.
  ///
  /// {@tool dartpad}
  /// This example shows how onChanged could be used to check the TextField's
  /// current value each time the user inserts or deletes a character.
  ///
  /// ** See code in examples/api/lib/widgets/editable_text/editable_text.on_changed.0.dart **
  /// {@end-tool}
  /// {@endtemplate}
  ///
  /// ## Handling emojis and other complex characters
  /// {@template flutter.widgets.EditableText.onChanged}
  /// It's important to always use
  /// [characters](https://pub.dev/packages/characters) when dealing with user
  /// input text that may contain complex characters. This will ensure that
  /// extended grapheme clusters and surrogate pairs are treated as single
  /// characters, as they appear to the user.
  ///
  /// For example, when finding the length of some user input, use
  /// `string.characters.length`. Do NOT use `string.length` or even
  /// `string.runes.length`. For the complex character "👨‍👩‍👦", this
  /// appears to the user as a single character, and `string.characters.length`
  /// intuitively returns 1. On the other hand, `string.length` returns 8, and
  /// `string.runes.length` returns 5!
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [inputFormatters], which are called before [onChanged]
  ///    runs and can validate and change ("format") the input value.
  ///  * [onEditingComplete], [onSubmitted], [onSelectionChanged]:
  ///    which are more specialized input change notifications.
  ///  * [TextEditingController], which implements the [Listenable] interface
  ///    and notifies its listeners on [TextEditingValue] changes.
  final ValueChanged<String>? onChanged;

  /// {@template flutter.widgets.editableText.onEditingComplete}
  /// Called when the user submits editable content (e.g., user presses the "done"
  /// button on the keyboard).
  ///
  /// The default implementation of [onEditingComplete] executes 2 different
  /// behaviors based on the situation:
  ///
  ///  - When a completion action is pressed, such as "done", "go", "send", or
  ///    "search", the user's content is submitted to the [controller] and then
  ///    focus is given up.
  ///
  ///  - When a non-completion action is pressed, such as "next" or "previous",
  ///    the user's content is submitted to the [controller], but focus is not
  ///    given up because developers may want to immediately move focus to
  ///    another input widget within [onSubmitted].
  ///
  /// Providing [onEditingComplete] prevents the aforementioned default behavior.
  /// {@endtemplate}
  final VoidCallback? onEditingComplete;

  /// {@template flutter.widgets.editableText.onSubmitted}
  /// Called when the user indicates that they are done editing the text in the
  /// field.
  ///
  /// By default, [onSubmitted] is called after [onChanged] when the user
  /// has finalized editing; or, if the default behavior has been overridden,
  /// after [onEditingComplete]. See [onEditingComplete] for details.
  ///
  /// ## Testing
  /// The following is the recommended way to trigger [onSubmitted] in a test:
  ///
  /// ```dart
  /// await tester.testTextInput.receiveAction(TextInputAction.done);
  /// ```
  ///
  /// Sending a `LogicalKeyboardKey.enter` via `tester.sendKeyEvent` will not
  /// trigger [onSubmitted]. This is because on a real device, the engine
  /// translates the enter key to a done action, but `tester.sendKeyEvent` sends
  /// the key to the framework only.
  /// {@endtemplate}
  final ValueChanged<String>? onSubmitted;

  /// {@template flutter.widgets.editableText.onAppPrivateCommand}
  /// This is used to receive a private command from the input method.
  ///
  /// Called when the result of [TextInputClient.performPrivateCommand] is
  /// received.
  ///
  /// This can be used to provide domain-specific features that are only known
  /// between certain input methods and their clients.
  ///
  /// See also:
  ///   * [performPrivateCommand](https://developer.android.com/reference/android/view/inputmethod/InputConnection#performPrivateCommand\(java.lang.String,%20android.os.Bundle\)),
  ///     which is the Android documentation for performPrivateCommand, used to
  ///     send a command from the input method.
  ///   * [sendAppPrivateCommand](https://developer.android.com/reference/android/view/inputmethod/InputMethodManager#sendAppPrivateCommand),
  ///     which is the Android documentation for sendAppPrivateCommand, used to
  ///     send a command to the input method.
  /// {@endtemplate}
  final AppPrivateCommandCallback? onAppPrivateCommand;

  /// {@template flutter.widgets.editableText.onSelectionChanged}
  /// Called when the user changes the selection of text (including the cursor
  /// location).
  /// {@endtemplate}
  final SelectionChangedCallback? onSelectionChanged;

  /// {@macro flutter.widgets.SelectionOverlay.onSelectionHandleTapped}
  final VoidCallback? onSelectionHandleTapped;

  /// {@template flutter.widgets.editableText.onTapOutside}
  /// Called for each tap that occurs outside of the[TextFieldTapRegion] group
  /// when the text field is focused.
  ///
  /// If this is null, [FocusNode.unfocus] will be called on the [focusNode] for
  /// this text field when a [PointerDownEvent] is received on another part of
  /// the UI. However, it will not unfocus as a result of mobile application
  /// touch events (which does not include mouse clicks), to conform with the
  /// platform conventions. To change this behavior, a callback may be set here
  /// that operates differently from the default.
  ///
  /// When adding additional controls to a text field (for example, a spinner, a
  /// button that copies the selected text, or modifies formatting), it is
  /// helpful if tapping on that control doesn't unfocus the text field. In
  /// order for an external widget to be considered as part of the text field
  /// for the purposes of tapping "outside" of the field, wrap the control in a
  /// [TextFieldTapRegion].
  ///
  /// The [PointerDownEvent] passed to the function is the event that caused the
  /// notification. It is possible that the event may occur outside of the
  /// immediate bounding box defined by the text field, although it will be
  /// within the bounding box of a [TextFieldTapRegion] member.
  /// {@endtemplate}
  ///
  /// {@tool dartpad}
  /// This example shows how to use a `TextFieldTapRegion` to wrap a set of
  /// "spinner" buttons that increment and decrement a value in the [TextField]
  /// without causing the text field to lose keyboard focus.
  ///
  /// This example includes a generic `SpinnerField<T>` class that you can copy
  /// into your own project and customize.
  ///
  /// ** See code in examples/api/lib/widgets/tap_region/text_field_tap_region.0.dart **
  /// {@end-tool}
  ///
  /// See also:
  ///
  ///  * [TapRegion] for how the region group is determined.
  final TapRegionCallback? onTapOutside;

  /// {@template flutter.widgets.editableText.inputFormatters}
  /// Optional input validation and formatting overrides.
  ///
  /// Formatters are run in the provided order when the user changes the text
  /// this widget contains. When this parameter changes, the new formatters will
  /// not be applied until the next time the user inserts or deletes text.
  /// Similar to the [onChanged] callback, formatters don't run when the text is
  /// changed programmatically via [controller].
  ///
  /// See also:
  ///
  ///  * [TextEditingController], which implements the [Listenable] interface
  ///    and notifies its listeners on [TextEditingValue] changes.
  /// {@endtemplate}
  final List<TextInputFormatter>? inputFormatters;

  /// The cursor for a mouse pointer when it enters or is hovering over the
  /// widget.
  ///
  /// If this property is null, [SystemMouseCursors.text] will be used.
  ///
  /// The [mouseCursor] is the only property of [EditableText] that controls the
  /// appearance of the mouse pointer. All other properties related to "cursor"
  /// stands for the text cursor, which is usually a blinking vertical line at
  /// the editing position.
  final MouseCursor? mouseCursor;

  /// Whether the caller will provide gesture handling (true), or if the
  /// [EditableText] is expected to handle basic gestures (false).
  ///
  /// When this is false, the [EditableText] (or more specifically, the
  /// [RenderEditable]) enables some rudimentary gestures (tap to position the
  /// cursor, long-press to select all, and some scrolling behavior).
  ///
  /// These behaviors are sufficient for debugging purposes but are inadequate
  /// for user-facing applications. To enable platform-specific behaviors, use a
  /// [TextSelectionGestureDetectorBuilder] to wrap the [EditableText], and set
  /// [rendererIgnoresPointer] to true.
  ///
  /// When [rendererIgnoresPointer] is true true, the [RenderEditable] created
  /// by this widget will not handle pointer events.
  ///
  /// This property is false by default.
  ///
  /// See also:
  ///
  ///  * [RenderEditable.ignorePointer], which implements this feature.
  ///  * [TextSelectionGestureDetectorBuilder], which implements platform-specific
  ///    gestures and behaviors.
  final bool rendererIgnoresPointer;

  /// {@template flutter.widgets.editableText.cursorWidth}
  /// How thick the cursor will be.
  ///
  /// Defaults to 2.0.
  ///
  /// The cursor will draw under the text. The cursor width will extend
  /// to the right of the boundary between characters for left-to-right text
  /// and to the left for right-to-left text. This corresponds to extending
  /// downstream relative to the selected position. Negative values may be used
  /// to reverse this behavior.
  /// {@endtemplate}
  final double cursorWidth;

  /// {@template flutter.widgets.editableText.cursorHeight}
  /// How tall the cursor will be.
  ///
  /// If this property is null, [RenderEditable.preferredLineHeight] will be used.
  /// {@endtemplate}
  final double? cursorHeight;

  /// {@template flutter.widgets.editableText.cursorRadius}
  /// How rounded the corners of the cursor should be.
  ///
  /// By default, the cursor has no radius.
  /// {@endtemplate}
  final Radius? cursorRadius;

  /// {@template flutter.widgets.editableText.cursorOpacityAnimates}
  /// Whether the cursor will animate from fully transparent to fully opaque
  /// during each cursor blink.
  ///
  /// By default, the cursor opacity will animate on iOS platforms and will not
  /// animate on Android platforms.
  /// {@endtemplate}
  final bool cursorOpacityAnimates;

  ///{@macro flutter.rendering.RenderEditable.cursorOffset}
  final Offset? cursorOffset;

  ///{@macro flutter.rendering.RenderEditable.paintCursorAboveText}
  final bool paintCursorAboveText;

  /// Controls how tall the selection highlight boxes are computed to be.
  ///
  /// See [ui.BoxHeightStyle] for details on available styles.
  final ui.BoxHeightStyle selectionHeightStyle;

  /// Controls how wide the selection highlight boxes are computed to be.
  ///
  /// See [ui.BoxWidthStyle] for details on available styles.
  final ui.BoxWidthStyle selectionWidthStyle;

  /// The appearance of the keyboard.
  ///
  /// This setting is only honored on iOS devices.
  ///
  /// Defaults to [Brightness.light].
  final Brightness keyboardAppearance;

  /// {@template flutter.widgets.editableText.scrollPadding}
  /// Configures padding to edges surrounding a [Scrollable] when the Textfield scrolls into view.
  ///
  /// When this widget receives focus and is not completely visible (for example scrolled partially
  /// off the screen or overlapped by the keyboard)
  /// then it will attempt to make itself visible by scrolling a surrounding [Scrollable], if one is present.
  /// This value controls how far from the edges of a [Scrollable] the TextField will be positioned after the scroll.
  ///
  /// Defaults to EdgeInsets.all(20.0).
  /// {@endtemplate}
  final EdgeInsets scrollPadding;

  /// {@template flutter.widgets.editableText.enableInteractiveSelection}
  /// Whether to enable user interface affordances for changing the
  /// text selection.
  ///
  /// For example, setting this to true will enable features such as
  /// long-pressing the TextField to select text and show the
  /// cut/copy/paste menu, and tapping to move the text caret.
  ///
  /// When this is false, the text selection cannot be adjusted by
  /// the user, text cannot be copied, and the user cannot paste into
  /// the text field from the clipboard.
  ///
  /// Defaults to true.
  /// {@endtemplate}
  final bool enableInteractiveSelection;

  /// Setting this property to true makes the cursor stop blinking or fading
  /// on and off once the cursor appears on focus. This property is useful for
  /// testing purposes.
  ///
  /// It does not affect the necessity to focus the EditableText for the cursor
  /// to appear in the first place.
  ///
  /// Defaults to false, resulting in a typical blinking cursor.
  static bool debugDeterministicCursor = false;

  /// {@macro flutter.widgets.scrollable.dragStartBehavior}
  final DragStartBehavior dragStartBehavior;

  /// {@template flutter.widgets.editableText.scrollController}
  /// The [ScrollController] to use when vertically scrolling the input.
  ///
  /// If null, it will instantiate a new ScrollController.
  ///
  /// See [Scrollable.controller].
  /// {@endtemplate}
  final ScrollController? scrollController;

  /// {@template flutter.widgets.editableText.scrollPhysics}
  /// The [ScrollPhysics] to use when vertically scrolling the input.
  ///
  /// If not specified, it will behave according to the current platform.
  ///
  /// See [Scrollable.physics].
  /// {@endtemplate}
  ///
  /// If an explicit [ScrollBehavior] is provided to [scrollBehavior], the
  /// [ScrollPhysics] provided by that behavior will take precedence after
  /// [scrollPhysics].
  final ScrollPhysics? scrollPhysics;

  /// {@template flutter.widgets.editableText.scribbleEnabled}
  /// Whether iOS 14 Scribble features are enabled for this widget.
  ///
  /// Only available on iPads.
  ///
  /// Defaults to true.
  /// {@endtemplate}
  final bool scribbleEnabled;

  /// {@template flutter.widgets.editableText.selectionEnabled}
  /// Same as [enableInteractiveSelection].
  ///
  /// This getter exists primarily for consistency with
  /// [RenderEditable.selectionEnabled].
  /// {@endtemplate}
  bool get selectionEnabled => enableInteractiveSelection;

  /// {@template flutter.widgets.editableText.autofillHints}
  /// A list of strings that helps the autofill service identify the type of this
  /// text input.
  ///
  /// When set to null, this text input will not send its autofill information
  /// to the platform, preventing it from participating in autofills triggered
  /// by a different [AutofillClient], even if they're in the same
  /// [AutofillScope]. Additionally, on Android and web, setting this to null
  /// will disable autofill for this text field.
  ///
  /// The minimum platform SDK version that supports Autofill is API level 26
  /// for Android, and iOS 10.0 for iOS.
  ///
  /// Defaults to an empty list.
  ///
  /// ### Setting up iOS autofill:
  ///
  /// To provide the best user experience and ensure your app fully supports
  /// password autofill on iOS, follow these steps:
  ///
  /// * Set up your iOS app's
  ///   [associated domains](https://developer.apple.com/documentation/safariservices/supporting_associated_domains_in_your_app).
  /// * Some autofill hints only work with specific [keyboardType]s. For example,
  ///   [AutofillHints.name] requires [TextInputType.name] and [AutofillHints.email]
  ///   works only with [TextInputType.emailAddress]. Make sure the input field has a
  ///   compatible [keyboardType]. Empirically, [TextInputType.name] works well
  ///   with many autofill hints that are predefined on iOS.
  ///
  /// ### Troubleshooting Autofill
  ///
  /// Autofill service providers rely heavily on [autofillHints]. Make sure the
  /// entries in [autofillHints] are supported by the autofill service currently
  /// in use (the name of the service can typically be found in your mobile
  /// device's system settings).
  ///
  /// #### Autofill UI refuses to show up when I tap on the text field
  ///
  /// Check the device's system settings and make sure autofill is turned on,
  /// and there are available credentials stored in the autofill service.
  ///
  /// * iOS password autofill: Go to Settings -> Password, turn on "Autofill
  ///   Passwords", and add new passwords for testing by pressing the top right
  ///   "+" button. Use an arbitrary "website" if you don't have associated
  ///   domains set up for your app. As long as there's at least one password
  ///   stored, you should be able to see a key-shaped icon in the quick type
  ///   bar on the software keyboard, when a password related field is focused.
  ///
  /// * iOS contact information autofill: iOS seems to pull contact info from
  ///   the Apple ID currently associated with the device. Go to Settings ->
  ///   Apple ID (usually the first entry, or "Sign in to your iPhone" if you
  ///   haven't set up one on the device), and fill out the relevant fields. If
  ///   you wish to test more contact info types, try adding them in Contacts ->
  ///   My Card.
  ///
  /// * Android autofill: Go to Settings -> System -> Languages & input ->
  ///   Autofill service. Enable the autofill service of your choice, and make
  ///   sure there are available credentials associated with your app.
  ///
  /// #### I called `TextInput.finishAutofillContext` but the autofill save
  /// prompt isn't showing
  ///
  /// * iOS: iOS may not show a prompt or any other visual indication when it
  ///   saves user password. Go to Settings -> Password and check if your new
  ///   password is saved. Neither saving password nor auto-generating strong
  ///   password works without properly setting up associated domains in your
  ///   app. To set up associated domains, follow the instructions in
  ///   <https://developer.apple.com/documentation/safariservices/supporting_associated_domains_in_your_app>.
  ///
  /// {@endtemplate}
  /// {@macro flutter.services.AutofillConfiguration.autofillHints}
  final Iterable<String>? autofillHints;

  /// The [AutofillClient] that controls this input field's autofill behavior.
  ///
  /// When null, this widget's [EditableTextState] will be used as the
  /// [AutofillClient]. This property may override [autofillHints].
  final AutofillClient? autofillClient;

  /// {@macro flutter.material.Material.clipBehavior}
  ///
  /// Defaults to [Clip.hardEdge].
  final Clip clipBehavior;

  /// Restoration ID to save and restore the scroll offset of the
  /// [EditableText].
  ///
  /// If a restoration id is provided, the [EditableText] will persist its
  /// current scroll offset and restore it during state restoration.
  ///
  /// The scroll offset is persisted in a [RestorationBucket] claimed from
  /// the surrounding [RestorationScope] using the provided restoration ID.
  ///
  /// Persisting and restoring the content of the [EditableText] is the
  /// responsibility of the owner of the [controller], who may use a
  /// [RestorableTextEditingController] for that purpose.
  ///
  /// See also:
  ///
  ///  * [RestorationManager], which explains how state restoration works in
  ///    Flutter.
  final String? restorationId;

  /// {@template flutter.widgets.shadow.scrollBehavior}
  /// A [ScrollBehavior] that will be applied to this widget individually.
  ///
  /// Defaults to null, wherein the inherited [ScrollBehavior] is copied and
  /// modified to alter the viewport decoration, like [Scrollbar]s.
  /// {@endtemplate}
  ///
  /// [ScrollBehavior]s also provide [ScrollPhysics]. If an explicit
  /// [ScrollPhysics] is provided in [scrollPhysics], it will take precedence,
  /// followed by [scrollBehavior], and then the inherited ancestor
  /// [ScrollBehavior].
  ///
  /// The [ScrollBehavior] of the inherited [ScrollConfiguration] will be
  /// modified by default to only apply a [Scrollbar] if [maxLines] is greater
  /// than 1.
  final ScrollBehavior? scrollBehavior;

  /// {@macro flutter.services.TextInputConfiguration.enableIMEPersonalizedLearning}
  final bool enableIMEPersonalizedLearning;

  /// {@template flutter.widgets.editableText.contentInsertionConfiguration}
  /// Configuration of handler for media content inserted via the system input
  /// method.
  ///
  /// Defaults to null in which case media content insertion will be disabled,
  /// and the system will display a message informing the user that the text field
  /// does not support inserting media content.
  ///
  /// Set [ContentInsertionConfiguration.onContentInserted] to provide a handler.
  /// Additionally, set [ContentInsertionConfiguration.allowedMimeTypes]
  /// to limit the allowable mime types for inserted content.
  ///
  /// {@tool dartpad}
  ///
  /// This example shows how to access the data for inserted content in your
  /// `TextField`.
  ///
  /// ** See code in examples/api/lib/widgets/editable_text/editable_text.on_content_inserted.0.dart **
  /// {@end-tool}
  ///
  /// If [contentInsertionConfiguration] is not provided, by default
  /// an empty list of mime types will be sent to the Flutter Engine.
  /// A handler function must be provided in order to customize the allowable
  /// mime types for inserted content.
  ///
  /// If rich content is inserted without a handler, the system will display
  /// a message informing the user that the current text input does not support
  /// inserting rich content.
  /// {@endtemplate}
  final ContentInsertionConfiguration? contentInsertionConfiguration;

  /// {@template flutter.widgets.EditableText.contextMenuBuilder}
  /// Builds the text selection toolbar when requested by the user.
  ///
  /// The context menu is built when [EditableTextState.showToolbar] is called,
  /// typically by one of the callbacks installed by the widget created by
  /// [TextSelectionGestureDetectorBuilder.buildGestureDetector]. The widget
  /// returned by [contextMenuBuilder] is passed to a [ContextMenuController].
  ///
  /// If no callback is provided, no context menu will be shown.
  ///
  /// The [EditableTextContextMenuBuilder] signature used by the
  /// [contextMenuBuilder] callback has two parameters, the [BuildContext] of
  /// the [EditableText] and the [EditableTextState] of the [EditableText].
  ///
  /// The [EditableTextState] has two properties that are especially useful when
  /// building the widgets for the context menu:
  ///
  /// * [EditableTextState.contextMenuAnchors] specifies the desired anchor
  ///   position for the context menu.
  ///
  /// * [EditableTextState.contextMenuButtonItems] represents the buttons that
  ///   should typically be built for this widget (e.g. cut, copy, paste).
  ///
  /// The [TextSelectionToolbarLayoutDelegate] class may be particularly useful
  /// in honoring the preferred anchor positions.
  ///
  /// For backwards compatibility, when [selectionControls] is set to an object
  /// that does not mix in [TextSelectionHandleControls], [contextMenuBuilder]
  /// is ignored and the [TextSelectionControls.buildToolbar] method is used
  /// instead.
  ///
  /// {@tool dartpad}
  /// This example shows how to customize the menu, in this case by keeping the
  /// default buttons for the platform but modifying their appearance.
  ///
  /// ** See code in examples/api/lib/material/context_menu/editable_text_toolbar_builder.0.dart **
  /// {@end-tool}
  ///
  /// {@tool dartpad}
  /// This example shows how to show a custom button only when an email address
  /// is currently selected.
  ///
  /// ** See code in examples/api/lib/material/context_menu/editable_text_toolbar_builder.1.dart **
  /// {@end-tool}
  ///
  /// See also:
  ///   * [AdaptiveTextSelectionToolbar], which builds the default text selection
  ///     toolbar for the current platform, but allows customization of the
  ///     buttons.
  ///   * [AdaptiveTextSelectionToolbar.getAdaptiveButtons], which builds the
  ///     button Widgets for the current platform given
  ///     [ContextMenuButtonItem]s.
  ///   * [BrowserContextMenu], which allows the browser's context menu on web
  ///     to be disabled and Flutter-rendered context menus to appear.
  /// {@endtemplate}
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  /// {@template flutter.widgets.EditableText.spellCheckConfiguration}
  /// Configuration that details how spell check should be performed.
  ///
  /// Specifies the [SpellCheckService] used to spell check text input and the
  /// [TextStyle] used to style text with misspelled words.
  ///
  /// If the [SpellCheckService] is left null, spell check is disabled by
  /// default unless the [DefaultSpellCheckService] is supported, in which case
  /// it is used. It is currently supported only on Android and iOS.
  ///
  /// If this configuration is left null, then spell check is disabled by default.
  /// {@endtemplate}
  final SpellCheckConfiguration? spellCheckConfiguration;

  /// The configuration for the magnifier to use with selections in this text
  /// field.
  ///
  /// {@macro flutter.widgets.magnifier.intro}
  final TextMagnifierConfiguration magnifierConfiguration;

  /// Whether user selection should be enabled or not.
  ///
  /// This is always false for read-only, obscure text.
  bool get userSelectionEnabled => enableInteractiveSelection && (!readOnly || !obscureText);

  /// Returns the [ContextMenuButtonItem]s representing the buttons in this
  /// platform's default selection menu for an editable field.
  ///
  /// For example, [EditableText] uses this to generate the default buttons for
  /// its context menu.
  ///
  /// See also:
  ///
  /// * [EditableTextState.contextMenuButtonItems], which gives the
  ///   [ContextMenuButtonItem]s for a specific EditableText.
  /// * [SelectableRegion.getSelectableButtonItems], which performs a similar
  ///   role but for content that is selectable but not editable.
  /// * [AdaptiveTextSelectionToolbar], which builds the toolbar itself, and can
  ///   take a list of [ContextMenuButtonItem]s with
  ///   [AdaptiveTextSelectionToolbar.buttonItems].
  /// * [AdaptiveTextSelectionToolbar.getAdaptiveButtons], which builds the button
  ///   Widgets for the current platform given [ContextMenuButtonItem]s.
  static List<ContextMenuButtonItem> getEditableButtonItems({
    required final ClipboardStatus? clipboardStatus,
    required final VoidCallback? onCopy,
    required final VoidCallback? onCut,
    required final VoidCallback? onPaste,
    required final VoidCallback? onSelectAll,
    required final VoidCallback? onLookUp,
    required final VoidCallback? onSearchWeb,
    required final VoidCallback? onShare,
    required final VoidCallback? onLiveTextInput,
  }) {
    final List<ContextMenuButtonItem> resultButtonItem = <ContextMenuButtonItem>[];

    // Configure button items with clipboard.
    if (onPaste == null || clipboardStatus != ClipboardStatus.unknown) {
      // If the paste button is enabled, don't render anything until the state
      // of the clipboard is known, since it's used to determine if paste is
      // shown.

      // On Android, the share button is before the select all button.
      final bool showShareBeforeSelectAll = defaultTargetPlatform == TargetPlatform.android;

      resultButtonItem.addAll(<ContextMenuButtonItem>[
        if (onCut != null)
          ContextMenuButtonItem(
            onPressed: onCut,
            type: ContextMenuButtonType.cut,
          ),
        if (onCopy != null)
          ContextMenuButtonItem(
            onPressed: onCopy,
            type: ContextMenuButtonType.copy,
          ),
        if (onPaste != null)
          ContextMenuButtonItem(
            onPressed: onPaste,
            type: ContextMenuButtonType.paste,
          ),
        if (onShare != null && showShareBeforeSelectAll)
          ContextMenuButtonItem(
            onPressed: onShare,
            type: ContextMenuButtonType.share,
          ),
        if (onSelectAll != null)
          ContextMenuButtonItem(
            onPressed: onSelectAll,
            type: ContextMenuButtonType.selectAll,
          ),
        if (onLookUp != null)
          ContextMenuButtonItem(
            onPressed: onLookUp,
            type: ContextMenuButtonType.lookUp,
          ),
        if (onSearchWeb != null)
          ContextMenuButtonItem(
            onPressed: onSearchWeb,
            type: ContextMenuButtonType.searchWeb,
          ),
        if (onShare != null && !showShareBeforeSelectAll)
          ContextMenuButtonItem(
            onPressed: onShare,
            type: ContextMenuButtonType.share,
          ),
      ]);
    }

    // Config button items with Live Text.
    if (onLiveTextInput != null) {
      resultButtonItem.add(ContextMenuButtonItem(
        onPressed: onLiveTextInput,
        type: ContextMenuButtonType.liveTextInput,
      ));
    }

    return resultButtonItem;
  }

  // Infer the keyboard type of an `EditableText` if it's not specified.
  static TextInputType _inferKeyboardType({
    required Iterable<String>? autofillHints,
    required int? maxLines,
  }) {
    if (autofillHints == null || autofillHints.isEmpty) {
      return maxLines == 1 ? TextInputType.text : TextInputType.multiline;
    }

    final String effectiveHint = autofillHints.first;

    // On iOS oftentimes specifying a text content type is not enough to qualify
    // the input field for autofill. The keyboard type also needs to be compatible
    // with the content type. To get autofill to work by default on EditableText,
    // the keyboard type inference on iOS is done differently from other platforms.
    //
    // The entries with "autofill not working" comments are the iOS text content
    // types that should work with the specified keyboard type but won't trigger
    // (even within a native app). Tested on iOS 13.5.
    if (!kIsWeb) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          const Map<String, TextInputType> iOSKeyboardType = <String, TextInputType> {
            AutofillHints.addressCity : TextInputType.name,
            AutofillHints.addressCityAndState : TextInputType.name, // Autofill not working.
            AutofillHints.addressState : TextInputType.name,
            AutofillHints.countryName : TextInputType.name,
            AutofillHints.creditCardNumber : TextInputType.number,  // Couldn't test.
            AutofillHints.email : TextInputType.emailAddress,
            AutofillHints.familyName : TextInputType.name,
            AutofillHints.fullStreetAddress : TextInputType.name,
            AutofillHints.givenName : TextInputType.name,
            AutofillHints.jobTitle : TextInputType.name,            // Autofill not working.
            AutofillHints.location : TextInputType.name,            // Autofill not working.
            AutofillHints.middleName : TextInputType.name,          // Autofill not working.
            AutofillHints.name : TextInputType.name,
            AutofillHints.namePrefix : TextInputType.name,          // Autofill not working.
            AutofillHints.nameSuffix : TextInputType.name,          // Autofill not working.
            AutofillHints.newPassword : TextInputType.text,
            AutofillHints.newUsername : TextInputType.text,
            AutofillHints.nickname : TextInputType.name,            // Autofill not working.
            AutofillHints.oneTimeCode : TextInputType.number,
            AutofillHints.organizationName : TextInputType.text,    // Autofill not working.
            AutofillHints.password : TextInputType.text,
            AutofillHints.postalCode : TextInputType.name,
            AutofillHints.streetAddressLine1 : TextInputType.name,
            AutofillHints.streetAddressLine2 : TextInputType.name,  // Autofill not working.
            AutofillHints.sublocality : TextInputType.name,         // Autofill not working.
            AutofillHints.telephoneNumber : TextInputType.name,
            AutofillHints.url : TextInputType.url,                  // Autofill not working.
            AutofillHints.username : TextInputType.text,
          };

          final TextInputType? keyboardType = iOSKeyboardType[effectiveHint];
          if (keyboardType != null) {
            return keyboardType;
          }
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          break;
      }
    }

    if (maxLines != 1) {
      return TextInputType.multiline;
    }

    const Map<String, TextInputType> inferKeyboardType = <String, TextInputType> {
      AutofillHints.addressCity : TextInputType.streetAddress,
      AutofillHints.addressCityAndState : TextInputType.streetAddress,
      AutofillHints.addressState : TextInputType.streetAddress,
      AutofillHints.birthday : TextInputType.datetime,
      AutofillHints.birthdayDay : TextInputType.datetime,
      AutofillHints.birthdayMonth : TextInputType.datetime,
      AutofillHints.birthdayYear : TextInputType.datetime,
      AutofillHints.countryCode : TextInputType.number,
      AutofillHints.countryName : TextInputType.text,
      AutofillHints.creditCardExpirationDate : TextInputType.datetime,
      AutofillHints.creditCardExpirationDay : TextInputType.datetime,
      AutofillHints.creditCardExpirationMonth : TextInputType.datetime,
      AutofillHints.creditCardExpirationYear : TextInputType.datetime,
      AutofillHints.creditCardFamilyName : TextInputType.name,
      AutofillHints.creditCardGivenName : TextInputType.name,
      AutofillHints.creditCardMiddleName : TextInputType.name,
      AutofillHints.creditCardName : TextInputType.name,
      AutofillHints.creditCardNumber : TextInputType.number,
      AutofillHints.creditCardSecurityCode : TextInputType.number,
      AutofillHints.creditCardType : TextInputType.text,
      AutofillHints.email : TextInputType.emailAddress,
      AutofillHints.familyName : TextInputType.name,
      AutofillHints.fullStreetAddress : TextInputType.streetAddress,
      AutofillHints.gender : TextInputType.text,
      AutofillHints.givenName : TextInputType.name,
      AutofillHints.impp : TextInputType.url,
      AutofillHints.jobTitle : TextInputType.text,
      AutofillHints.language : TextInputType.text,
      AutofillHints.location : TextInputType.streetAddress,
      AutofillHints.middleInitial : TextInputType.name,
      AutofillHints.middleName : TextInputType.name,
      AutofillHints.name : TextInputType.name,
      AutofillHints.namePrefix : TextInputType.name,
      AutofillHints.nameSuffix : TextInputType.name,
      AutofillHints.newPassword : TextInputType.text,
      AutofillHints.newUsername : TextInputType.text,
      AutofillHints.nickname : TextInputType.text,
      AutofillHints.oneTimeCode : TextInputType.text,
      AutofillHints.organizationName : TextInputType.text,
      AutofillHints.password : TextInputType.text,
      AutofillHints.photo : TextInputType.text,
      AutofillHints.postalAddress : TextInputType.streetAddress,
      AutofillHints.postalAddressExtended : TextInputType.streetAddress,
      AutofillHints.postalAddressExtendedPostalCode : TextInputType.number,
      AutofillHints.postalCode : TextInputType.number,
      AutofillHints.streetAddressLevel1 : TextInputType.streetAddress,
      AutofillHints.streetAddressLevel2 : TextInputType.streetAddress,
      AutofillHints.streetAddressLevel3 : TextInputType.streetAddress,
      AutofillHints.streetAddressLevel4 : TextInputType.streetAddress,
      AutofillHints.streetAddressLine1 : TextInputType.streetAddress,
      AutofillHints.streetAddressLine2 : TextInputType.streetAddress,
      AutofillHints.streetAddressLine3 : TextInputType.streetAddress,
      AutofillHints.sublocality : TextInputType.streetAddress,
      AutofillHints.telephoneNumber : TextInputType.phone,
      AutofillHints.telephoneNumberAreaCode : TextInputType.phone,
      AutofillHints.telephoneNumberCountryCode : TextInputType.phone,
      AutofillHints.telephoneNumberDevice : TextInputType.phone,
      AutofillHints.telephoneNumberExtension : TextInputType.phone,
      AutofillHints.telephoneNumberLocal : TextInputType.phone,
      AutofillHints.telephoneNumberLocalPrefix : TextInputType.phone,
      AutofillHints.telephoneNumberLocalSuffix : TextInputType.phone,
      AutofillHints.telephoneNumberNational : TextInputType.phone,
      AutofillHints.transactionAmount : TextInputType.numberWithOptions(decimal: true),
      AutofillHints.transactionCurrency : TextInputType.text,
      AutofillHints.url : TextInputType.url,
      AutofillHints.username : TextInputType.text,
    };

    return inferKeyboardType[effectiveHint] ?? TextInputType.text;
  }

  @override
  Widget build(BuildContext context) {
    final EditableTextBuilder buildEditableText = EditableTextCustomizer._of(context);
    return buildEditableText(context, this);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<TextEditingController>('controller', controller));
    properties.add(DiagnosticsProperty<FocusNode>('focusNode', focusNode));
    properties.add(DiagnosticsProperty<bool>('obscureText', obscureText, defaultValue: false));
    properties.add(DiagnosticsProperty<bool>('readOnly', readOnly, defaultValue: false));
    properties.add(DiagnosticsProperty<bool>('autocorrect', autocorrect, defaultValue: true));
    properties.add(EnumProperty<SmartDashesType>('smartDashesType', smartDashesType, defaultValue: obscureText ? SmartDashesType.disabled : SmartDashesType.enabled));
    properties.add(EnumProperty<SmartQuotesType>('smartQuotesType', smartQuotesType, defaultValue: obscureText ? SmartQuotesType.disabled : SmartQuotesType.enabled));
    properties.add(DiagnosticsProperty<bool>('enableSuggestions', enableSuggestions, defaultValue: true));
    style.debugFillProperties(properties);
    properties.add(EnumProperty<TextAlign>('textAlign', textAlign, defaultValue: null));
    properties.add(EnumProperty<TextDirection>('textDirection', textDirection, defaultValue: null));
    properties.add(DiagnosticsProperty<Locale>('locale', locale, defaultValue: null));
    properties.add(DiagnosticsProperty<TextScaler>('textScaler', textScaler, defaultValue: null));
    properties.add(IntProperty('maxLines', maxLines, defaultValue: 1));
    properties.add(IntProperty('minLines', minLines, defaultValue: null));
    properties.add(DiagnosticsProperty<bool>('expands', expands, defaultValue: false));
    properties.add(DiagnosticsProperty<bool>('autofocus', autofocus, defaultValue: false));
    properties.add(DiagnosticsProperty<TextInputType>('keyboardType', keyboardType, defaultValue: null));
    properties.add(DiagnosticsProperty<ScrollController>('scrollController', scrollController, defaultValue: null));
    properties.add(DiagnosticsProperty<ScrollPhysics>('scrollPhysics', scrollPhysics, defaultValue: null));
    properties.add(DiagnosticsProperty<Iterable<String>>('autofillHints', autofillHints, defaultValue: null));
    properties.add(DiagnosticsProperty<TextHeightBehavior>('textHeightBehavior', textHeightBehavior, defaultValue: null));
    properties.add(DiagnosticsProperty<bool>('scribbleEnabled', scribbleEnabled, defaultValue: true));
    properties.add(DiagnosticsProperty<bool>('enableIMEPersonalizedLearning', enableIMEPersonalizedLearning, defaultValue: true));
    properties.add(DiagnosticsProperty<bool>('enableInteractiveSelection', enableInteractiveSelection, defaultValue: true));
    properties.add(DiagnosticsProperty<UndoHistoryController>('undoController', undoController, defaultValue: null));
    properties.add(DiagnosticsProperty<SpellCheckConfiguration>('spellCheckConfiguration', spellCheckConfiguration, defaultValue: null));
    properties.add(DiagnosticsProperty<List<String>>('contentCommitMimeTypes', contentInsertionConfiguration?.allowedMimeTypes ?? const <String>[], defaultValue: contentInsertionConfiguration == null ? const <String>[] : kDefaultContentInsertionMimeTypes));
  }
}
