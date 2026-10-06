import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// The card image handed to the browser's share or download: kept in
/// memory, nothing to remove afterwards.
Future<XFile> cardFile(Uint8List png, String name) async =>
    XFile.fromData(png, mimeType: 'image/png', name: '$name.png');

Future<void> forgetCardFiles() async {}
