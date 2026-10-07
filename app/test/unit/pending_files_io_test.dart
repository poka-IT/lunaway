import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/community/data/pending_files_io.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('outbox-test'));
  tearDown(() => root.delete(recursive: true));

  test('the folder of the photos waiting to be sent is marked out of the backups, once', () async {
    final marked = <String>[];
    final files = IoPendingFiles(
      () async => root,
      excludeFromBackup: (path) async => marked.add(path),
    );
    final id = await files.put(Uint8List.fromList([1, 2, 3]));
    await files.read(id);
    await files.delete(id);
    expect(marked, ['${root.path}/outbox']);
  });
}
