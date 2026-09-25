import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'upload_queue.dart';

/// Grava o stream de uma câmera em segmentos locais rotativos e entrega
/// cada segmento pronto para a [UploadQueue].
///
/// Implementação: usa a propriedade `stream-record` do mpv (já exposta
/// pelo `media_kit` via `player.platform`, no mesmo padrão usado em
/// `_setTransport()` no main.dart para `rtsp-transport`). Essa propriedade
/// grava o stream bruto em disco enquanto ele continua sendo exibido
/// normalmente — sem recodificar.
///
/// mpv não tem rotação de segmento nativa: "rotacionar" aqui significa
/// trocar o valor de `stream-record` para um novo arquivo periodicamente.
///
/// ⚠️ TODO antes de usar em produção: validar o nome exato da propriedade
/// e o comportamento de `setProperty` na versão do `media_kit` fixada no
/// `pubspec.yaml` — a API nativa já mudou entre versões do pacote.
class RecordingService {
  RecordingService({
    required this.cameraName,
    required this.player,
    this.segmentDuration = const Duration(minutes: 5),
    this.retentionDays = 7,
  });

  final String cameraName;
  final Player player;
  final Duration segmentDuration;
  final int retentionDays;

  Timer? _rotationTimer;
  File? _currentSegment;
  bool _recording = false;

  bool get isRecording => _recording;

  Future<void> start() async {
    if (_recording) return;
    _recording = true;
    await _rotateSegment();
    _rotationTimer = Timer.periodic(segmentDuration, (_) => _rotateSegment());
  }

  Future<void> stop() async {
    _recording = false;
    _rotationTimer?.cancel();
    _rotationTimer = null;
    await _stopCurrentSegment();
  }

  Future<Directory> _segmentsDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/recordings/${_safeName(cameraName)}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _safeName(String name) {
    final safe =
        name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return safe.isEmpty ? 'camera' : safe;
  }

  Future<void> _rotateSegment() async {
    await _stopCurrentSegment();
    if (!_recording) return;

    final dir = await _segmentsDirectory();
    // stop() pode ter sido chamado enquanto esperávamos o diretório.
    if (!_recording) return;

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/$timestamp.mkv');
    _currentSegment = file;

    try {
      final platform = player.platform;
      if (platform != null) {
        await (platform as dynamic).setProperty('stream-record', file.path);
      }
    } catch (_) {
      // Gravação é best-effort: se a propriedade nativa falhar (ex:
      // plataforma sem suporte), a exibição ao vivo continua normal.
    }
  }

  Future<void> _stopCurrentSegment() async {
    final segment = _currentSegment;
    if (segment == null) return;
    _currentSegment = null;

    try {
      final platform = player.platform;
      if (platform != null) {
        await (platform as dynamic).setProperty('stream-record', '');
      }
    } catch (_) {}

    if (await segment.exists() && await segment.length() > 0) {
      UploadQueue.instance.enqueue(segment);
    }
    await _cleanupOldSegments();
  }

  Future<void> _cleanupOldSegments() async {
    try {
      final dir = await _segmentsDirectory();
      final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Limpeza é best-effort: falha aqui não pode derrubar a gravação.
    }
  }
}
