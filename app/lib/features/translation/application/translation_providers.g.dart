// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(translationSource)
final translationSourceProvider = TranslationSourceProvider._();

final class TranslationSourceProvider
    extends
        $FunctionalProvider<
          TranslationSource,
          TranslationSource,
          TranslationSource
        >
    with $Provider<TranslationSource> {
  TranslationSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationSourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationSourceHash();

  @$internal
  @override
  $ProviderElement<TranslationSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranslationSource create(Ref ref) {
    return translationSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationSource>(value),
    );
  }
}

String _$translationSourceHash() => r'c142afe436409efea14963875cc98e298c39d2e4';

@ProviderFor(translationMemory)
final translationMemoryProvider = TranslationMemoryProvider._();

final class TranslationMemoryProvider
    extends
        $FunctionalProvider<
          TranslationMemory,
          TranslationMemory,
          TranslationMemory
        >
    with $Provider<TranslationMemory> {
  TranslationMemoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationMemoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationMemoryHash();

  @$internal
  @override
  $ProviderElement<TranslationMemory> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranslationMemory create(Ref ref) {
    return translationMemory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationMemory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationMemory>(value),
    );
  }
}

String _$translationMemoryHash() => r'8607eb555e6302f734f9ce97295f5fe71804f57b';

/// The translation of [item] into [targetLang], asked when the reader
/// touches "Translate" (or by itself, for a review, when the setting says
/// so). Going back and forth between the original and the translation asks
/// nothing more of the server.

@ProviderFor(ItemTranslation)
final itemTranslationProvider = ItemTranslationFamily._();

/// The translation of [item] into [targetLang], asked when the reader
/// touches "Translate" (or by itself, for a review, when the setting says
/// so). Going back and forth between the original and the translation asks
/// nothing more of the server.
final class ItemTranslationProvider
    extends $NotifierProvider<ItemTranslation, TranslationState> {
  /// The translation of [item] into [targetLang], asked when the reader
  /// touches "Translate" (or by itself, for a review, when the setting says
  /// so). Going back and forth between the original and the translation asks
  /// nothing more of the server.
  ItemTranslationProvider._({
    required ItemTranslationFamily super.from,
    required (TranslatableItem, String) super.argument,
  }) : super(
         retry: null,
         name: r'itemTranslationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$itemTranslationHash();

  @override
  String toString() {
    return r'itemTranslationProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ItemTranslation create() => ItemTranslation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ItemTranslationProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$itemTranslationHash() => r'b8871e7316aacfe2cdf04b3926fe4f8181d13fda';

/// The translation of [item] into [targetLang], asked when the reader
/// touches "Translate" (or by itself, for a review, when the setting says
/// so). Going back and forth between the original and the translation asks
/// nothing more of the server.

final class ItemTranslationFamily extends $Family
    with
        $ClassFamilyOverride<
          ItemTranslation,
          TranslationState,
          TranslationState,
          TranslationState,
          (TranslatableItem, String)
        > {
  ItemTranslationFamily._()
    : super(
        retry: null,
        name: r'itemTranslationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The translation of [item] into [targetLang], asked when the reader
  /// touches "Translate" (or by itself, for a review, when the setting says
  /// so). Going back and forth between the original and the translation asks
  /// nothing more of the server.

  ItemTranslationProvider call(TranslatableItem item, String targetLang) =>
      ItemTranslationProvider._(argument: (item, targetLang), from: this);

  @override
  String toString() => r'itemTranslationProvider';
}

/// The translation of [item] into [targetLang], asked when the reader
/// touches "Translate" (or by itself, for a review, when the setting says
/// so). Going back and forth between the original and the translation asks
/// nothing more of the server.

abstract class _$ItemTranslation extends $Notifier<TranslationState> {
  late final _$args = ref.$arg as (TranslatableItem, String);
  TranslatableItem get item => _$args.$1;
  String get targetLang => _$args.$2;

  TranslationState build(TranslatableItem item, String targetLang);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TranslationState, TranslationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TranslationState, TranslationState>,
              TranslationState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
