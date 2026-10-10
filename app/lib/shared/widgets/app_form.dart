import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/busy_button.dart';
import 'package:lunaway/shared/widgets/field_label.dart';

final _log = Logger('forms');

/// The one behaviour of every form of the app (`.claude/rules/screens.md`,
/// "Forms"):
///
/// - a field is checked when the user leaves it, then at every keystroke
///   while it is wrong, so the error goes as soon as it is right; no error
///   on a field the user has not touched;
/// - the button is never silent: with errors, the form scrolls to the first
///   one, gives it the focus, says under each field what to do, sums them
///   up above the button ("2 champs à corriger") and tells the screen
///   reader;
/// - valid, [onSubmit] runs with the button busy; a failure keeps what was
///   typed and offers to try again ([FormFailure]), a refusal of a field
///   shows on the field ([FormRefused]).
///
/// The fields are [LunaTextField] and [LunaFormField], the button
/// [SubmitButton]; a group folded away is [FoldedFields], which opens when
/// a field inside is wrong.
class LunaForm extends StatefulWidget {
  const new({required this.onSubmit, required this.child, super.key});

  /// What a valid form does (save, send, close). Its own success shows
  /// itself: the form closes with a short message, or a tick.
  final Future<void> Function() onSubmit;
  final Widget child;

  /// The form around [context]; null outside one.
  static LunaFormState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_FormScope>()?.state;

  @override
  State<LunaForm> createState() => LunaFormState();
}

/// Where a form stands, for its button and the line above it.
@immutable
class FormStatus {
  const new({
    this.busy = false,
    this.slow = false,
    this.errors = 0,
    this.failure,
    this.retry = false,
  });

  /// [LunaForm.onSubmit] is running.
  final bool busy;

  /// It has been running for longer than [slowWait].
  final bool slow;

  /// The fields still wrong since the last submit; 0 before one.
  final int errors;

  /// Why the last submit did not go through.
  final String? failure;

  /// The failure may pass on a second try (the network).
  final bool retry;

  @override
  bool operator ==(Object other) =>
      other is FormStatus &&
      other.busy == busy &&
      other.slow == slow &&
      other.errors == errors &&
      other.failure == failure &&
      other.retry == retry;

  @override
  int get hashCode => Object.hash(busy, slow, errors, failure, retry);
}

/// What [LunaForm.onSubmit] throws when it could not finish: [message] shows
/// above the button, with "Try again" when [retry]. Any other error counts
/// as a failure that may pass on a second try.
class FormFailure implements Exception {
  const new(this.message, {this.retry = true});

  final String message;
  final bool retry;

  @override
  String toString() => 'FormFailure($message)';
}

/// What [LunaForm.onSubmit] throws once it has set the error of a field the
/// server refused (the field's `error`): the form then shows it like its own
/// errors.
class FormRefused implements Exception {
  const new();
}

/// A field of a [LunaForm], as the form sees it.
abstract interface class _Field {
  BuildContext get context;
  FormFieldState<Object?>? get state;
  FocusNode get focus;
  String get label;
}

/// The form's state: [submit] is what its button calls.
class LunaFormState extends State<LunaForm> {
  final _fields = <_Field>{};
  final ValueNotifier<FormStatus> _status = ValueNotifier(const FormStatus());
  bool _tried = false;
  Timer? _slowTimer;
  bool _recountPending = false;

  /// Where the form stands, for its button.
  ValueListenable<FormStatus> get status => _status;

  void _add(_Field field) => _fields.add(field);

  void _remove(_Field field) {
    if (_fields.remove(field)) _fieldChanged();
  }

  /// A field changed or was checked: the count above the button follows,
  /// once the frame has run the checks the fields make as they build.
  void _fieldChanged() {
    if (!_tried || _recountPending) return;
    _recountPending = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _recountPending = false;
        if (!mounted) return;
        final errors = _fields.where((f) => f.state?.hasError ?? false).length;
        final now = _status.value;
        if (errors != now.errors) _status.value = _copy(now, errors: errors);
      })
      ..ensureVisualUpdate();
  }

  /// Checks again the fields that show an error: a choice another field
  /// depends on has changed (the note a reason "other" asks for).
  void recheckShown() {
    for (final f in _fields) {
      if (f.state?.hasError ?? false) f.state?.validate();
    }
    _fieldChanged();
  }

  FormStatus _copy(FormStatus s, {bool? busy, bool? slow, int? errors}) => FormStatus(
    busy: busy ?? s.busy,
    slow: slow ?? s.slow,
    errors: errors ?? s.errors,
    failure: s.failure,
    retry: s.retry,
  );

  /// Checks every field; with errors, shows them and leads to the first;
  /// without, runs [LunaForm.onSubmit]. A second call while it runs does
  /// nothing.
  Future<void> submit() async {
    if (_status.value.busy) return;
    _tried = true;
    final wrong = [
      for (final f in _inTreeOrder())
        if (!(f.state?.validate() ?? true)) f,
    ];
    if (wrong.isNotEmpty) {
      _status.value = FormStatus(errors: wrong.length);
      await _leadTo(wrong);
      return;
    }
    final t = context.t;
    _status.value = const FormStatus(busy: true);
    _slowTimer = Timer(slowWait, () {
      if (!mounted) return;
      _status.value = _copy(_status.value, slow: true);
      _announce(t.busy.slow);
    });
    try {
      await widget.onSubmit();
      if (mounted) _status.value = const FormStatus();
    } on FormRefused {
      if (!mounted) return;
      _status.value = const FormStatus();
      // The refused field shows its error once rebuilt.
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      final refused = [
        for (final f in _inTreeOrder())
          if (f.state?.hasError ?? false) f,
      ];
      _status.value = FormStatus(errors: refused.length);
      if (refused.isNotEmpty) await _leadTo(refused);
    } on FormFailure catch (e) {
      if (mounted) _status.value = FormStatus(failure: e.message, retry: e.retry);
      _announce(e.message);
    } on Object catch (e, s) {
      // The type alone: a form's error may carry a position or a name.
      _log.warning('a form was not saved: ${e.runtimeType}', null, s);
      if (mounted) _status.value = FormStatus(failure: t.forms.failed, retry: true);
      _announce(t.forms.failed);
    } finally {
      _slowTimer?.cancel();
      _slowTimer = null;
    }
  }

  /// The fields in the order a reader meets them, a folded one included.
  List<_Field> _inTreeOrder() {
    final rank = <Element, int>{};
    var next = 0;
    void visit(Element e) {
      rank[e] = next++;
      e.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    int at(_Field f) => rank[f.context as Element] ?? next;
    return _fields.toList()..sort((a, b) => at(a).compareTo(at(b)));
  }

  /// Says what is wrong, opens what folds the first wrong field away,
  /// brings it into view and gives it the focus.
  Future<void> _leadTo(List<_Field> wrong) async {
    final t = context.t;
    final first = wrong.first;
    final scroll = Motion.of(context, Motion.medium);
    unawaited(HapticFeedback.mediumImpact());
    final error = first.state?.errorText;
    _announce(
      [
        t.forms.toFix(n: wrong.length),
        if (error != null) t.forms.fieldError(label: first.label, error: error),
      ].join('. '),
    );
    final reveal = _RevealField()..dispatch(first.context);
    if (reveal.opening case final opening?) await opening;
    if (!first.context.mounted) return;
    await Scrollable.ensureVisible(
      first.context,
      alignment: 0.2,
      duration: scroll,
      curve: Motion.standard,
    );
    if (first.context.mounted) first.focus.requestFocus();
  }

  /// Tells the screen reader [text] at once, where the platform still lets
  /// an app do so; elsewhere the line above the button is a live region.
  void _announce(String text) {
    if (!mounted || !MediaQuery.supportsAnnounceOf(context)) return;
    final view = View.of(context);
    final direction = Directionality.of(context);
    unawaited(
      SemanticsService.sendAnnouncement(
        view,
        text,
        direction,
        assertiveness: Assertiveness.assertive,
      ),
    );
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormScope(
    state: this,
    // While the form is sent it stays: closed meanwhile, the answer would
    // land on whatever screen lies under it.
    child: ValueListenableBuilder<FormStatus>(
      valueListenable: _status,
      builder: (context, s, child) => PopScope(canPop: !s.busy, child: child!),
      // Flutter's form gives the fields their role for assistive
      // technology; the checks are this one's.
      child: Form(child: widget.child),
    ),
  );
}

class _FormScope extends InheritedWidget {
  const new({required this.state, required super.child});

  final LunaFormState state;

  @override
  bool updateShouldNotify(_FormScope oldWidget) => false;
}

/// Asks the folds above a field to open; [opening] completes once the
/// field is in sight.
class _RevealField extends Notification {
  Future<void>? opening;
}

/// What a text field expects, which sets its keyboard and what it accepts.
enum FieldKind {
  /// A line of text.
  text,

  /// Several lines; the keyboard's key goes to the next line.
  multiline,

  /// A number with decimals: the keyboard with a decimal key, a point or a
  /// comma accepted whatever the language ([parseDecimal]).
  decimal,

  /// A whole number.
  integer,

  /// A web address.
  url,

  /// A phone number.
  phone,
}

/// A text field of a [LunaForm], with the form's behaviour (see there).
/// [label] names the field on screen and to the screen reader; [unit]
/// follows the value (`m`, `t`); [error] is an error from outside (the
/// server's), which its owner clears when the text changes; with
/// [showLabel] false the label only names the field to the screen reader
/// and in the form's summary, where a title above already says it.
class LunaTextField extends StatefulWidget {
  const new({
    required this.controller,
    required this.label,
    this.kind = FieldKind.text,
    this.validator,
    this.error,
    this.hint,
    this.helper,
    this.unit,
    this.icon,
    this.suffixIcon,
    this.maxLength,
    this.minLines,
    this.maxLines,
    this.textCapitalization,
    this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enableIMEPersonalizedLearning = true,
    this.style,
    this.focusNode,
    this.showLabel = true,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final FieldKind kind;
  final FormFieldValidator<String>? validator;
  final String? error;
  final String? hint;
  final String? helper;
  final String? unit;
  final IconData? icon;
  final Widget? suffixIcon;
  final int? maxLength;
  final int? minLines;
  final int? maxLines;
  final TextCapitalization? textCapitalization;

  /// The keyboard's action key: "next" for a line, a new line for several,
  /// unless said. "Done" or "go" submits the form.
  final TextInputAction? textInputAction;

  /// The keyboard, when [kind]'s does not fit (a code to type as it is).
  final TextInputType? keyboardType;

  /// Filters added to [kind]'s.
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  /// What the keyboard's done key does, in place of submitting the form.
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool enableIMEPersonalizedLearning;
  final TextStyle? style;
  final FocusNode? focusNode;
  final bool showLabel;

  @override
  State<LunaTextField> createState() => _LunaTextFieldState();
}

class _LunaTextFieldState extends State<LunaTextField> implements _Field {
  final _key = GlobalKey<FormFieldState<String>>();
  FocusNode? _ownFocus;
  LunaFormState? _form;

  /// Typed into since it was shown: only then does leaving it check it.
  bool _edited = false;

  @override
  FocusNode get focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  FormFieldState<Object?>? get state => _key.currentState;

  @override
  String get label => widget.label;

  @override
  void initState() {
    super.initState();
    focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(LunaTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_focusChanged);
      focus.addListener(_focusChanged);
    }
    if (oldWidget.error != widget.error) _form?._fieldChanged();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final form = LunaForm.maybeOf(context);
    if (form != _form) {
      _form?._remove(this);
      _form = form?.._add(this);
    }
  }

  @override
  void dispose() {
    focus.removeListener(_focusChanged);
    _form?._remove(this);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (focus.hasFocus || !_edited || !mounted) return;
    _key.currentState?.validate();
    _form?._fieldChanged();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final multiline = kind == FieldKind.multiline;
    final action =
        widget.textInputAction ?? (multiline ? TextInputAction.newline : TextInputAction.next);
    final submits = action == TextInputAction.done || action == TextInputAction.go;
    final field = TextFormField(
      key: _key,
      controller: widget.controller,
      focusNode: focus,
      autofocus: widget.autofocus,
      // Once wrong, checked at every keystroke: the error leaves as soon as
      // the value is right.
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
      validator: widget.validator,
      forceErrorText: widget.error,
      keyboardType: widget.keyboardType ?? _keyboard(kind),
      textInputAction: action,
      textCapitalization:
          widget.textCapitalization ??
          switch (kind) {
            FieldKind.text || FieldKind.multiline => TextCapitalization.sentences,
            _ => TextCapitalization.none,
          },
      autocorrect: widget.autocorrect && (kind == FieldKind.text || multiline),
      enableSuggestions: widget.enableSuggestions,
      enableIMEPersonalizedLearning: widget.enableIMEPersonalizedLearning,
      inputFormatters: [...?_formatters(kind), ...?widget.inputFormatters],
      maxLength: widget.maxLength,
      minLines: widget.minLines,
      maxLines: multiline ? (widget.maxLines ?? 6) : (widget.maxLines ?? 1),
      style: widget.style ?? Theme.of(context).textTheme.bodyLarge,
      onChanged: (value) {
        _edited = true;
        widget.onChanged?.call(value);
        _form?._fieldChanged();
      },
      onFieldSubmitted: submits
          ? (value) {
              if (widget.onSubmitted case final onSubmitted?) {
                onSubmitted(value);
              } else {
                unawaited(_form?.submit());
              }
            }
          : null,
      decoration: InputDecoration(
        label: widget.showLabel ? FieldLabel(widget.label) : null,
        hintText: widget.hint,
        // A hint of examples whole at a large text size, not cut.
        hintMaxLines: 4,
        helperText: widget.helper,
        suffixText: widget.unit,
        prefixIcon: widget.icon == null ? null : Icon(widget.icon),
        suffixIcon: widget.suffixIcon,
        alignLabelWithHint: multiline,
      ),
    );
    // Without a label on screen, the field still has its name.
    return widget.showLabel ? field : Semantics(label: widget.label, child: field);
  }

  static TextInputType _keyboard(FieldKind kind) => switch (kind) {
    FieldKind.text => TextInputType.text,
    FieldKind.multiline => TextInputType.multiline,
    FieldKind.decimal => const TextInputType.numberWithOptions(decimal: true),
    FieldKind.integer => TextInputType.number,
    FieldKind.url => TextInputType.url,
    FieldKind.phone => TextInputType.phone,
  };

  static List<TextInputFormatter>? _formatters(FieldKind kind) => switch (kind) {
    // Either separator: a value pasted from elsewhere keeps its own.
    FieldKind.decimal => [FilteringTextInputFormatter.allow(RegExp('[0-9.,]'))],
    FieldKind.integer => [FilteringTextInputFormatter.digitsOnly],
    _ => null,
  };
}

/// A field of a [LunaForm] that is not text: a choice among chips or
/// tiles, a rating. [builder] draws the choice; the field writes its error
/// under it, in the form's words, and takes the focus when it is the first
/// one wrong. [value] is the current choice, kept by the caller.
class LunaFormField<T> extends StatefulWidget {
  const new({
    required this.label,
    required this.value,
    required this.builder,
    this.validator,
    super.key,
  });

  final String label;
  final T? value;
  final Widget Function(BuildContext context) builder;
  final FormFieldValidator<T>? validator;

  @override
  State<LunaFormField<T>> createState() => _LunaFormFieldState<T>();
}

class _LunaFormFieldState<T> extends State<LunaFormField<T>> implements _Field {
  final _key = GlobalKey<FormFieldState<T>>();
  final _focus = FocusNode(skipTraversal: true);
  LunaFormState? _form;

  @override
  FocusNode get focus => _focus;

  @override
  FormFieldState<Object?>? get state => _key.currentState;

  @override
  String get label => widget.label;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final form = LunaForm.maybeOf(context);
    if (form != _form) {
      _form?._remove(this);
      _form = form?.._add(this);
    }
  }

  @override
  void didUpdateWidget(LunaFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      // A choice made: the field holds it, and an error it had is checked
      // again at once.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final field = _key.currentState;
        if (!mounted || field == null) return;
        if (field.hasError) field.validate();
        _form?.recheckShown();
      });
    }
  }

  @override
  void dispose() {
    _form?._remove(this);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      focusNode: _focus,
      child: FormField<T>(
        key: _key,
        initialValue: widget.value,
        // The caller keeps the choice: the check reads it there.
        validator: widget.validator == null ? null : (_) => widget.validator!(widget.value),
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.builder(context),
            if (field.errorText case final error?)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(AppIcons.error, size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        error,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The form's button: [label] names the action; the line above it sums up
/// the fields to correct, says why a submit failed (with "Try again") or
/// that a long wait goes on. Busy while the form is sent, never twice.
///
/// [statusLine] false leaves the line out, for a dialog whose buttons sit
/// in a row: [FormStatusBar] then shows it under the fields.
class SubmitButton extends StatelessWidget {
  const new({
    required this.label,
    this.icon,
    this.look = BusyLook.filled,
    this.style,
    this.slowText,
    this.secondary,
    this.statusLine = true,
    super.key,
  });

  final String label;
  final Widget? icon;
  final BusyLook look;
  final ButtonStyle? style;

  /// What a long wait says; the network's slowness when null.
  final String? slowText;

  /// A second action beside the button, a third of the width (forget the
  /// vehicle).
  final Widget? secondary;
  final bool statusLine;

  @override
  Widget build(BuildContext context) {
    final form = LunaForm.maybeOf(context);
    assert(form != null, 'A SubmitButton sits inside a LunaForm.');
    if (form == null) return const SizedBox.shrink();
    return ValueListenableBuilder<FormStatus>(
      valueListenable: form.status,
      builder: (context, s, _) {
        final button = BusyButton(
          // The form's own state turns the button, not the tap: leading to a
          // wrong field is no wait.
          onPressed: () async => unawaited(form.submit()),
          busy: s.busy,
          look: look,
          style: style,
          icon: icon,
          slowLine: false,
          label: Text(label),
        );
        if (!statusLine) return button;
        final secondary = this.secondary;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormStatusLine(status: s, slowText: slowText, onRetry: form.submit),
            if (secondary == null)
              button
            else
              Row(
                children: [
                  // Not while the form is sent: the two would close the
                  // sheet, and the screen under it, twice.
                  Expanded(
                    child: IgnorePointer(ignoring: s.busy, child: secondary),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(flex: 2, child: button),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// A dialog's "Cancel" beside its [SubmitButton]: off while the form is
/// sent, which then finishes before anything closes.
class FormCancelButton extends StatelessWidget {
  const new({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final form = LunaForm.maybeOf(context);
    if (form == null) {
      return TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(label));
    }
    return ValueListenableBuilder<FormStatus>(
      valueListenable: form.status,
      builder: (context, s, _) => TextButton(
        onPressed: s.busy ? null : () => Navigator.of(context).pop(),
        child: Text(label),
      ),
    );
  }
}

/// The form's [FormStatusLine] on its own, where the button sits apart (a
/// dialog's row of buttons).
class FormStatusBar extends StatelessWidget {
  const new({this.slowText, super.key});

  final String? slowText;

  @override
  Widget build(BuildContext context) {
    final form = LunaForm.maybeOf(context);
    if (form == null) return const SizedBox.shrink();
    return ValueListenableBuilder<FormStatus>(
      valueListenable: form.status,
      builder: (context, s, _) =>
          FormStatusLine(status: s, slowText: slowText, onRetry: form.submit),
    );
  }
}

/// The line above a form's button: the fields to correct, a failure with
/// "Try again", or a long wait. Nothing when all is well.
class FormStatusLine extends StatelessWidget {
  const new({required this.status, this.slowText, this.onRetry, super.key});

  final FormStatus status;
  final String? slowText;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (text, error) = switch (status) {
      FormStatus(busy: true, slow: true) => (slowText ?? t.busy.slow, false),
      FormStatus(busy: false, :final failure?) => (failure, true),
      FormStatus(busy: false, errors: > 0) => (t.forms.toFix(n: status.errors), true),
      _ => (null, false),
    };
    final retry = status.failure != null && status.retry && !status.busy ? onRetry : null;
    final announces = MediaQuery.supportsAnnounceOf(context);
    return AnimatedSize(
      duration: Motion.of(context, Motion.short),
      curve: Motion.standard,
      alignment: Alignment.bottomCenter,
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Semantics(
                // Where the platform cannot announce, the line speaks when
                // it changes.
                container: true,
                liveRegion: !announces,
                child: Row(
                  children: [
                    Icon(
                      error ? AppIcons.error : AppIcons.waiting,
                      size: 20,
                      color: error ? scheme.error : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: Text(
                        text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: error ? scheme.error : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (retry != null)
                      TextButton.icon(
                        onPressed: () => unawaited(retry()),
                        icon: const Icon(AppIcons.retry),
                        label: Text(t.common.retry),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// How long a [FoldedFields] takes to open and lay its fields out: the
/// tile's animation and the frames after it, with room, since the scroll
/// to the field reads the height the fold has then.
const Duration _foldOpens = Duration(milliseconds: 400);

/// Fields folded under a title ([ExpansionTile]), kept alive while folded
/// so the form still checks them; the fold opens by itself when the form
/// leads to a wrong field inside.
class FoldedFields extends StatefulWidget {
  const new({required this.title, required this.children, super.key});

  final Widget title;
  final List<Widget> children;

  @override
  State<FoldedFields> createState() => _FoldedFieldsState();
}

class _FoldedFieldsState extends State<FoldedFields> {
  final _controller = ExpansibleController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationListener<_RevealField>(
    onNotification: (reveal) {
      if (_controller.isExpanded) return false;
      _controller.expand();
      final previous = reveal.opening;
      // The tile's own animation (200 ms, whatever the motion setting),
      // then a frame for the fields to lay out.
      reveal.opening = Future.wait([?previous, Future<void>.delayed(_foldOpens)]);
      return false;
    },
    child: ExpansionTile(
      controller: _controller,
      maintainState: true,
      tilePadding: EdgeInsets.zero,
      title: widget.title,
      childrenPadding: const EdgeInsets.only(top: Space.s),
      children: widget.children,
    ),
  );
}

/// A number typed with a point or a comma, spaces ignored; null when empty
/// or not a number.
double? parseDecimal(String text) {
  final cleaned = text.trim().replaceAll(',', '.').replaceAll(RegExp(r'\s'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// [value] with [digits] decimals in the app's language: `2,90` in French,
/// `2.90` in English.
String formatDecimal(BuildContext context, double value, {int digits = 2}) => NumberFormat(
  digits == 0 ? '0' : '0.${'0' * digits}',
  context.t.$meta.locale.languageCode,
).format(value);

/// The check of a decimal field: empty passes unless [required] says what
/// to type; a value outside [range] says the range with [digits] decimals
/// and the [unit] ("Entre 1,50 et 4,50 m").
FormFieldValidator<String> decimalCheck(
  BuildContext context, {
  ({double min, double max})? range,
  String unit = '',
  int digits = 2,
  String? required,
}) {
  final t = context.t;
  String format(double v) => formatDecimal(context, v, digits: digits);
  return (text) {
    if (text == null || text.trim().isEmpty) return required;
    final value = parseDecimal(text);
    if (range == null) {
      return value == null || value < 0 ? t.forms.number(example: format(12.5)) : null;
    }
    final min = format(range.min);
    final max = format(range.max);
    if (value == null) return t.forms.numberBetween(min: min, max: max, unit: unit).trim();
    if (value < range.min || value > range.max) {
      return t.forms.between(min: min, max: max, unit: unit).trim();
    }
    return null;
  };
}
