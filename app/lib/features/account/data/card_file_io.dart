import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

final _log = Logger('account');

/// The card image handed to the share sheet: a file of the app's own, in a
/// folder of its own, so it can be removed once the card page closes. The
/// file holds the recovery code; left behind, it would sit outside the
/// protected storage (share_plus never removes the copies it makes).
Future<XFile> cardFile(Uint8List png, String name) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/recovery-card');
  await forgetCardFiles();
  await dir.create(recursive: true);
  final file = File('${dir.path}/$name.png');
  await file.writeAsBytes(png, flush: true);
  return XFile(file.path, mimeType: 'image/png', name: '$name.png');
}

/// Removes the card images made for sharing, ours and share_plus's copies;
/// quiet when there is no temporary folder to look in.
Future<void> forgetCardFiles() async {
  try {
    final temp = (await getTemporaryDirectory()).path;
    final dir = Directory('$temp/recovery-card');
    if (dir.existsSync()) await dir.delete(recursive: true);
    // On Android share_plus copies what it shares into the cache folder
    // (`share_plus/`) and empties it only at the next share; the app shares
    // no other file.
    final copies = Directory('$temp/share_plus');
    if (copies.existsSync()) await copies.delete(recursive: true);
  } on Object catch (e) {
    _log.info('card images not removed: $e');
  }
}
