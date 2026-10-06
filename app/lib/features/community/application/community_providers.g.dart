// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'community_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(pendingFiles)
final pendingFilesProvider = PendingFilesProvider._();

final class PendingFilesProvider
    extends $FunctionalProvider<PendingFiles, PendingFiles, PendingFiles>
    with $Provider<PendingFiles> {
  PendingFilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingFilesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingFilesHash();

  @$internal
  @override
  $ProviderElement<PendingFiles> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PendingFiles create(Ref ref) {
    return pendingFiles(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PendingFiles value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PendingFiles>(value),
    );
  }
}

String _$pendingFilesHash() => r'5bb8247bca8b5295a75deadd5242397ff4f7f2dc';

@ProviderFor(picturePicker)
final picturePickerProvider = PicturePickerProvider._();

final class PicturePickerProvider
    extends $FunctionalProvider<PicturePicker, PicturePicker, PicturePicker>
    with $Provider<PicturePicker> {
  PicturePickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'picturePickerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$picturePickerHash();

  @$internal
  @override
  $ProviderElement<PicturePicker> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PicturePicker create(Ref ref) {
    return picturePicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PicturePicker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PicturePicker>(value),
    );
  }
}

String _$picturePickerHash() => r'56b75fe4b9ecbeeb57352208bfa0e32bc669b91a';

@ProviderFor(photoPreparer)
final photoPreparerProvider = PhotoPreparerProvider._();

final class PhotoPreparerProvider
    extends $FunctionalProvider<PhotoPreparer, PhotoPreparer, PhotoPreparer>
    with $Provider<PhotoPreparer> {
  PhotoPreparerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoPreparerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoPreparerHash();

  @$internal
  @override
  $ProviderElement<PhotoPreparer> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PhotoPreparer create(Ref ref) {
    return photoPreparer(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoPreparer value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoPreparer>(value),
    );
  }
}

String _$photoPreparerHash() => r'6e4ff76d6ca3f8057000c0e823cad04b419cd74a';

/// The bytes of a photo waiting in the outbox, for its tile.

@ProviderFor(pendingPhoto)
final pendingPhotoProvider = PendingPhotoFamily._();

/// The bytes of a photo waiting in the outbox, for its tile.

final class PendingPhotoProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List?>,
          Uint8List?,
          FutureOr<Uint8List?>
        >
    with $FutureModifier<Uint8List?>, $FutureProvider<Uint8List?> {
  /// The bytes of a photo waiting in the outbox, for its tile.
  PendingPhotoProvider._({
    required PendingPhotoFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'pendingPhotoProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pendingPhotoHash();

  @override
  String toString() {
    return r'pendingPhotoProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List?> create(Ref ref) {
    final argument = this.argument as String;
    return pendingPhoto(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PendingPhotoProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pendingPhotoHash() => r'c39f063c43c8783278d9ee07638d9ad0cf573ff5';

/// The bytes of a photo waiting in the outbox, for its tile.

final class PendingPhotoFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Uint8List?>, String> {
  PendingPhotoFamily._()
    : super(
        retry: null,
        name: r'pendingPhotoProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The bytes of a photo waiting in the outbox, for its tile.

  PendingPhotoProvider call(String fileId) =>
      PendingPhotoProvider._(argument: fileId, from: this);

  @override
  String toString() => r'pendingPhotoProvider';
}

@ProviderFor(outboxStore)
final outboxStoreProvider = OutboxStoreProvider._();

final class OutboxStoreProvider
    extends $FunctionalProvider<OutboxStore, OutboxStore, OutboxStore>
    with $Provider<OutboxStore> {
  OutboxStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outboxStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outboxStoreHash();

  @$internal
  @override
  $ProviderElement<OutboxStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OutboxStore create(Ref ref) {
    return outboxStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OutboxStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OutboxStore>(value),
    );
  }
}

String _$outboxStoreHash() => r'724ab0d6bf5fe97ea08613ce9105cf93b59f8f23';

@ProviderFor(photoUploader)
final photoUploaderProvider = PhotoUploaderProvider._();

final class PhotoUploaderProvider
    extends $FunctionalProvider<PhotoUploader, PhotoUploader, PhotoUploader>
    with $Provider<PhotoUploader> {
  PhotoUploaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoUploaderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoUploaderHash();

  @$internal
  @override
  $ProviderElement<PhotoUploader> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PhotoUploader create(Ref ref) {
    return photoUploader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoUploader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoUploader>(value),
    );
  }
}

String _$photoUploaderHash() => r'fb0624cf6d8625e9b70c996ae09696dcee2a1d37';

@ProviderFor(communityApi)
final communityApiProvider = CommunityApiProvider._();

final class CommunityApiProvider
    extends $FunctionalProvider<CommunityApi, CommunityApi, CommunityApi>
    with $Provider<CommunityApi> {
  CommunityApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'communityApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$communityApiHash();

  @$internal
  @override
  $ProviderElement<CommunityApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CommunityApi create(Ref ref) {
    return communityApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CommunityApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CommunityApi>(value),
    );
  }
}

String _$communityApiHash() => r'e9073f07acaff48702eecd8239ace0819eaf078c';

@ProviderFor(outboxSender)
final outboxSenderProvider = OutboxSenderProvider._();

final class OutboxSenderProvider
    extends $FunctionalProvider<OutboxSender, OutboxSender, OutboxSender>
    with $Provider<OutboxSender> {
  OutboxSenderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outboxSenderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outboxSenderHash();

  @$internal
  @override
  $ProviderElement<OutboxSender> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OutboxSender create(Ref ref) {
    return outboxSender(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OutboxSender value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OutboxSender>(value),
    );
  }
}

String _$outboxSenderHash() => r'92a12bc655631037f8f5879e0e0ec37ace2837b8';

/// Every contribution waiting, oldest first.

@ProviderFor(outboxEntries)
final outboxEntriesProvider = OutboxEntriesProvider._();

/// Every contribution waiting, oldest first.

final class OutboxEntriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PendingContribution>>,
          List<PendingContribution>,
          Stream<List<PendingContribution>>
        >
    with
        $FutureModifier<List<PendingContribution>>,
        $StreamProvider<List<PendingContribution>> {
  /// Every contribution waiting, oldest first.
  OutboxEntriesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outboxEntriesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outboxEntriesHash();

  @$internal
  @override
  $StreamProviderElement<List<PendingContribution>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<PendingContribution>> create(Ref ref) {
    return outboxEntries(ref);
  }
}

String _$outboxEntriesHash() => r'74a5427f35ecddeaa29f0167b8d6eb7d01979e09';

/// The entries of the account this device holds, and those made before it
/// had one: another account's (a restored backup, a lost account) count
/// nowhere, and "My contributions" lists them for discarding.

@ProviderFor(ownOutboxEntries)
final ownOutboxEntriesProvider = OwnOutboxEntriesProvider._();

/// The entries of the account this device holds, and those made before it
/// had one: another account's (a restored backup, a lost account) count
/// nowhere, and "My contributions" lists them for discarding.

final class OwnOutboxEntriesProvider
    extends
        $FunctionalProvider<
          List<PendingContribution>,
          List<PendingContribution>,
          List<PendingContribution>
        >
    with $Provider<List<PendingContribution>> {
  /// The entries of the account this device holds, and those made before it
  /// had one: another account's (a restored backup, a lost account) count
  /// nowhere, and "My contributions" lists them for discarding.
  OwnOutboxEntriesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownOutboxEntriesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownOutboxEntriesHash();

  @$internal
  @override
  $ProviderElement<List<PendingContribution>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<PendingContribution> create(Ref ref) {
    return ownOutboxEntries(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<PendingContribution> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<PendingContribution>>(value),
    );
  }
}

String _$ownOutboxEntriesHash() => r'db5e154be1768d6c80a51de6610560aa57e47f3c';

/// The contributions waiting about [placeId], for the place's sheet.

@ProviderFor(pendingForPlace)
final pendingForPlaceProvider = PendingForPlaceFamily._();

/// The contributions waiting about [placeId], for the place's sheet.

final class PendingForPlaceProvider
    extends
        $FunctionalProvider<
          List<PendingContribution>,
          List<PendingContribution>,
          List<PendingContribution>
        >
    with $Provider<List<PendingContribution>> {
  /// The contributions waiting about [placeId], for the place's sheet.
  PendingForPlaceProvider._({
    required PendingForPlaceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'pendingForPlaceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pendingForPlaceHash();

  @override
  String toString() {
    return r'pendingForPlaceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<PendingContribution>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<PendingContribution> create(Ref ref) {
    final argument = this.argument as String;
    return pendingForPlace(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<PendingContribution> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<PendingContribution>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PendingForPlaceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pendingForPlaceHash() => r'41c1af383cb49b71f24c454a3ecbd15edd710180';

/// The contributions waiting about [placeId], for the place's sheet.

final class PendingForPlaceFamily extends $Family
    with $FunctionalFamilyOverride<List<PendingContribution>, String> {
  PendingForPlaceFamily._()
    : super(
        retry: null,
        name: r'pendingForPlaceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The contributions waiting about [placeId], for the place's sheet.

  PendingForPlaceProvider call(String placeId) =>
      PendingForPlaceProvider._(argument: placeId, from: this);

  @override
  String toString() => r'pendingForPlaceProvider';
}

/// The progress of each photo being sent, by outbox entry, 0 to 1.

@ProviderFor(uploadProgress)
final uploadProgressProvider = UploadProgressProvider._();

/// The progress of each photo being sent, by outbox entry, 0 to 1.

final class UploadProgressProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, double>>,
          Map<String, double>,
          Stream<Map<String, double>>
        >
    with
        $FutureModifier<Map<String, double>>,
        $StreamProvider<Map<String, double>> {
  /// The progress of each photo being sent, by outbox entry, 0 to 1.
  UploadProgressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'uploadProgressProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$uploadProgressHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, double>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, double>> create(Ref ref) {
    return uploadProgress(ref);
  }
}

String _$uploadProgressHash() => r'c467f177255929f2039d2e2b423f2b82977a4970';

/// The authors hidden from this device: the account's mutes, with the ones
/// waiting to be sent applied at once.

@ProviderFor(mutedAuthorIds)
final mutedAuthorIdsProvider = MutedAuthorIdsProvider._();

/// The authors hidden from this device: the account's mutes, with the ones
/// waiting to be sent applied at once.

final class MutedAuthorIdsProvider
    extends $FunctionalProvider<Set<String>, Set<String>, Set<String>>
    with $Provider<Set<String>> {
  /// The authors hidden from this device: the account's mutes, with the ones
  /// waiting to be sent applied at once.
  MutedAuthorIdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mutedAuthorIdsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mutedAuthorIdsHash();

  @$internal
  @override
  $ProviderElement<Set<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Set<String> create(Ref ref) {
    return mutedAuthorIds(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$mutedAuthorIdsHash() => r'073e57444bb94933d72e7a1bba83f60673060050';

/// Runs the outbox: sends at launch, when a contribution is queued, when
/// the app comes back to the foreground, when a sync shows the network is
/// back, and when an entry's wait is over. One pass at a time.
// keepAlive: the queue outlives every screen.

@ProviderFor(OutboxRunner)
final outboxRunnerProvider = OutboxRunnerProvider._();

/// Runs the outbox: sends at launch, when a contribution is queued, when
/// the app comes back to the foreground, when a sync shows the network is
/// back, and when an entry's wait is over. One pass at a time.
// keepAlive: the queue outlives every screen.
final class OutboxRunnerProvider extends $NotifierProvider<OutboxRunner, bool> {
  /// Runs the outbox: sends at launch, when a contribution is queued, when
  /// the app comes back to the foreground, when a sync shows the network is
  /// back, and when an entry's wait is over. One pass at a time.
  // keepAlive: the queue outlives every screen.
  OutboxRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outboxRunnerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outboxRunnerHash();

  @$internal
  @override
  OutboxRunner create() => OutboxRunner();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$outboxRunnerHash() => r'ee270643f6c9bafb45cf79605ad7a4c684b3b5b0';

/// Runs the outbox: sends at launch, when a contribution is queued, when
/// the app comes back to the foreground, when a sync shows the network is
/// back, and when an entry's wait is over. One pass at a time.
// keepAlive: the queue outlives every screen.

abstract class _$OutboxRunner extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The account's own contributions, read online.

@ProviderFor(myContributions)
final myContributionsProvider = MyContributionsProvider._();

/// The account's own contributions, read online.

final class MyContributionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<MyContributions>,
          MyContributions,
          FutureOr<MyContributions>
        >
    with $FutureModifier<MyContributions>, $FutureProvider<MyContributions> {
  /// The account's own contributions, read online.
  MyContributionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'myContributionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myContributionsHash();

  @$internal
  @override
  $FutureProviderElement<MyContributions> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MyContributions> create(Ref ref) {
    return myContributions(ref);
  }
}

String _$myContributionsHash() => r'4cea3d74f9441eda7c6152658acdc2b3e9cf1470';

/// Whether the device's account may do an action of level [required]; a
/// device without an account counts as level 0, the level a new account
/// starts at.

@ProviderFor(gate)
final gateProvider = GateFamily._();

/// Whether the device's account may do an action of level [required]; a
/// device without an account counts as level 0, the level a new account
/// starts at.

final class GateProvider extends $FunctionalProvider<Gate, Gate, Gate>
    with $Provider<Gate> {
  /// Whether the device's account may do an action of level [required]; a
  /// device without an account counts as level 0, the level a new account
  /// starts at.
  GateProvider._({required GateFamily super.from, required int super.argument})
    : super(
        retry: null,
        name: r'gateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gateHash();

  @override
  String toString() {
    return r'gateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<Gate> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Gate create(Ref ref) {
    final argument = this.argument as int;
    return gate(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Gate value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Gate>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$gateHash() => r'9188597352b8a3ba16fcddd8517c44669c385c89';

/// Whether the device's account may do an action of level [required]; a
/// device without an account counts as level 0, the level a new account
/// starts at.

final class GateFamily extends $Family
    with $FunctionalFamilyOverride<Gate, int> {
  GateFamily._()
    : super(
        retry: null,
        name: r'gateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the device's account may do an action of level [required]; a
  /// device without an account counts as level 0, the level a new account
  /// starts at.

  GateProvider call(int required) =>
      GateProvider._(argument: required, from: this);

  @override
  String toString() => r'gateProvider';
}
