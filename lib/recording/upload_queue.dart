import 'dart:async';
import 'dart:io';

import '../cloud/cloud_storage_manager.dart';

/// Tenta enviar arquivos de clipe locais para o [CloudStorageProvider]
/// ativo no momento, com retentativa automática.
///
/// A gravação nunca fica bloqueada esperando o upload: um segmento
/// terminado é apenas colocado nesta fila. Se o envio falhar (sem
/// internet, servidor fora, nenhum provedor configurado ainda) o arquivo
/// continua no disco e a fila tenta de novo no próximo ciclo, sem perder
/// a gravação.
class UploadQueue {
  UploadQueue._internal();

  static final UploadQueue instance = UploadQueue._internal();

  final List<File> _pending = [];
  Timer? _retryTimer;
  bool _isUploading = false;

  void enqueue(File file) {
    _pending.add(file);
    _scheduleDrain();
  }

  void _scheduleDrain() {
    _retryTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => _drain());
    _drain();
  }

  Future<void> _drain() async {
    if (_isUploading || _pending.isEmpty) return;
    _isUploading = true;

    try {
      final manager = CloudStorageManager.instance;

      // Percorre uma cópia: enqueue() pode adicionar itens durante os awaits.
      // Só removemos de _pending o que foi realmente tratado, para nunca
      // perder um segmento que chegou no meio do ciclo.
      for (final file in List<File>.from(_pending)) {
        try {
          if (await file.exists()) {
            await manager.active.upload(
              file: file,
              remotePath: _remotePathFor(file),
              config: manager.activeConfig,
            );
          }
          // Enviado, ou já removido (ex: limpeza por retenção): sai da fila.
          _pending.remove(file);
        } catch (_) {
          // Mantém na fila; a próxima rodada do timer tenta de novo.
        }
      }
    } finally {
      _isUploading = false;
    }
  }

  /// `camdu/<pasta-da-camera>/<arquivo>` — inclui a câmera para que dois
  /// clipes de câmeras diferentes nunca colidam no mesmo caminho remoto.
  String _remotePathFor(File file) {
    final segments = file.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final name = segments.isNotEmpty ? segments.last : 'clip.mkv';
    final camera = segments.length >= 2 ? segments[segments.length - 2] : 'camera';
    return 'camdu/$camera/$name';
  }

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
