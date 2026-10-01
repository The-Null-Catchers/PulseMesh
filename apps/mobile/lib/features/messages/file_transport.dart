import 'dart:io';

import 'package:dio/dio.dart';

import '../../offline/sync_transport.dart';
import 'room_message.dart';

typedef UploadProgressCallback = void Function(int sent, int total);

abstract interface class MobileFileTransport {
  Future<RoomAttachment> upload({
    required String path,
    required String name,
    required String mimeType,
    required int sizeBytes,
    UploadProgressCallback? onProgress,
  });

  Future<void> delete(String fileId);

  Future<Uri> downloadUrl(String fileId);
}

class DioMobileFileTransport implements MobileFileTransport {
  DioMobileFileTransport({
    required String baseUrl,
    required AccessTokenProvider accessToken,
    Dio? dio,
  })  : _accessToken = accessToken,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(minutes: 3),
              ),
            );

  final Dio _dio;
  final AccessTokenProvider _accessToken;

  Future<Options> _authOptions() async {
    final token = await _accessToken();
    return Options(
      headers: token == null || token.isEmpty
          ? const <String, String>{}
          : {'Authorization': 'Bearer $token'},
    );
  }

  @override
  Future<RoomAttachment> upload({
    required String path,
    required String name,
    required String mimeType,
    required int sizeBytes,
    UploadProgressCallback? onProgress,
  }) async {
    final presign = await _dio.post<Map<String, dynamic>>(
      '/files/presign',
      data: {
        'name': name,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
      },
      options: await _authOptions(),
    );

    final data = presign.data;
    if (data == null) {
      throw StateError('Upload presign returned an empty response');
    }

    final fileId = data['fileId'] as String;
    final uploadUrl = Uri.parse(data['uploadUrl'] as String);
    final headers = Map<String, dynamic>.from(
      data['headers'] as Map? ?? const <String, dynamic>{},
    );

    final file = File(path);
    final stream = file.openRead();

    await _dio.putUri<void>(
      uploadUrl,
      data: stream,
      options: Options(
        headers: {
          ...headers,
          Headers.contentLengthHeader: sizeBytes,
        },
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ),
      onSendProgress: onProgress,
    );

    await _dio.post<Map<String, dynamic>>(
      '/files/$fileId/complete',
      data: const <String, dynamic>{},
      options: await _authOptions(),
    );

    for (var attempt = 0; attempt < 40; attempt += 1) {
      final response = await _dio.get<Map<String, dynamic>>(
        '/files/$fileId',
        options: await _authOptions(),
      );
      final metadata = response.data ?? const <String, dynamic>{};
      final status = metadata['status'] as String? ?? '';

      if (status == 'ready') {
        return RoomAttachment.fromJson(metadata);
      }

      if (status == 'rejected') {
        throw StateError(
          metadata['processingError'] as String? ??
              'File processing was rejected',
        );
      }

      await Future<void>.delayed(const Duration(seconds: 1));
    }

    throw StateError('File processing timed out');
  }

  @override
  Future<void> delete(String fileId) async {
    await _dio.delete<void>(
      '/files/$fileId',
      options: await _authOptions(),
    );
  }

  @override
  Future<Uri> downloadUrl(String fileId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/files/$fileId/download',
      data: const <String, dynamic>{},
      options: await _authOptions(),
    );
    final raw = response.data?['url'] as String?;
    if (raw == null || raw.isEmpty) {
      throw StateError('Download URL was not returned');
    }
    return Uri.parse(raw);
  }
}
