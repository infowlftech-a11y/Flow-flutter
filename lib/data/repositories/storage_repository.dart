import 'dart:io';
import 'dart:math';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Upload contract (§12.1): files are downscaled before upload by
/// [ImageService]; names are `{ownerId|anon}_{millis}_{base36 random}{ext}`;
/// content type comes from the extension. Multi-file uploads are sequential,
/// and there is no client-side timeout race — the task's own retry handles
/// slow beach connections.
class StorageRepository {
  StorageRepository(this._storage);
  final FirebaseStorage _storage;

  static final _rng = Random();

  String _fileName(String? ownerId, String path) {
    final ext = _extension(path);
    final rand = _rng.nextInt(0x7FFFFFFF).toRadixString(36);
    return '${ownerId ?? 'anon'}_${DateTime.now().millisecondsSinceEpoch}_$rand$ext';
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    return path.substring(dot).toLowerCase();
  }

  String _contentType(String ext) => switch (ext) {
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        '.heic' => 'image/heic',
        '.pdf' => 'application/pdf',
        _ => 'image/jpeg',
      };

  Future<String> upload({
    required String folder,
    required XFile file,
    String? ownerId,
  }) async {
    final name = _fileName(ownerId, file.path);
    final ref = _storage.ref('$folder/$name');
    await ref.putFile(
      File(file.path),
      SettableMetadata(contentType: _contentType(_extension(file.path))),
    );
    return ref.getDownloadURL();
  }

  /// Sequential by design (§12.1).
  Future<List<String>> uploadAll({
    required String folder,
    required List<XFile> files,
    String? ownerId,
  }) async {
    final urls = <String>[];
    for (final f in files) {
      urls.add(await upload(folder: folder, file: f, ownerId: ownerId));
    }
    return urls;
  }
}
