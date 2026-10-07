import 'dart:js_interop';

@JS('lunawayPlaceTileErrors')
external JSNumber? get _errors;

int placeTileErrors() => _errors?.toDartInt ?? 0;
