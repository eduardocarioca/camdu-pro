import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud/cloud_storage_manager.dart';
import 'recording/recording_service.dart';

/// Protocolos que o FFmpeg/MPV pode abrir. `rtp` é necessário para RTSP sobre
/// UDP e `tls`/`crypto` para RTSPS; sem eles esses modos falham com
/// "Protocol not on whitelist".
const List<String> _kProtocolWhitelist = [
  'rtsp',
  'rtsps',
  'rtp',
  'tcp',
  'udp',
  'tls',
  'crypto',
  'http',
  'https',
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const CamDuProApp());
}

class CamDuProApp extends StatelessWidget {
  const CamDuProApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF101114);
    const surface = Color(0xFF1B1D22);

    return MaterialApp(
      title: 'camDu Pro',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          surface: surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          elevation: 2,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surface,
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.grey,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class CameraEntry {
  final String name;
  final String url;
  final bool recordingEnabled;
  final int retentionDays;

  const CameraEntry({
    required this.name,
    required this.url,
    this.recordingEnabled = false,
    this.retentionDays = 7,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'recordingEnabled': recordingEnabled,
        'retentionDays': retentionDays,
      };

  factory CameraEntry.fromJson(Map<String, dynamic> json) {
    return CameraEntry(
      name: (json['name'] ?? 'Câmera').toString(),
      url: (json['url'] ?? '').toString(),
      // Câmeras salvas antes desta versão não têm esses campos; assume
      // gravação desligada e retenção padrão de 7 dias.
      recordingEnabled: json['recordingEnabled'] == true,
      retentionDays: (json['retentionDays'] is int) ? json['retentionDays'] as int : 7,
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  static const _camerasKey = 'cameras_v2';
  static const _legacyCamerasKey = 'cameras';
  static const _hardwareKey = 'hardware_acceleration';
  static const _transportKey = 'rtsp_transport';

  int _selectedIndex = 0;
  bool _isGridView = true;
  bool _hardwareAcceleration = true;
  String _rtspTransport = 'tcp';
  bool _loading = true;
  bool _scanLocked = false;

  final List<CameraEntry> _cameras = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      await CloudStorageManager.instance.load();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_camerasKey);
      final legacy = prefs.getStringList(_legacyCamerasKey);
      final cameras = <CameraEntry>[];

      for (final item in saved ?? <String>[]) {
        try {
          final decoded = jsonDecode(item);
          if (decoded is Map<String, dynamic>) {
            final camera = CameraEntry.fromJson(decoded);
            if (camera.url.trim().isNotEmpty) cameras.add(camera);
          }
        } catch (_) {
          // Ignore malformed entries and keep loading the remaining cameras.
        }
      }

      if (cameras.isEmpty && legacy != null) {
        for (final item in legacy) {
          final separator = item.indexOf('|');
          if (separator <= 0 || separator >= item.length - 1) continue;
          final camera = CameraEntry(
            name: item.substring(0, separator),
            url: item.substring(separator + 1),
          );
          if (camera.url.trim().isNotEmpty) cameras.add(camera);
        }
        if (cameras.isNotEmpty) await _persistCameras(cameras);
      }

      if (!mounted) return;
      setState(() {
        _cameras
          ..clear()
          ..addAll(cameras);
        _hardwareAcceleration = prefs.getBool(_hardwareKey) ?? true;
        _rtspTransport = prefs.getString(_transportKey) == 'udp' ? 'udp' : 'tcp';
        _loading = false;
      });
    } catch (_) {
      // Widget tests and unusual Android plugin states can start without a
      // SharedPreferences implementation. The app can still run with defaults.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _persistCameras([List<CameraEntry>? source]) async {
    final prefs = await SharedPreferences.getInstance();
    final list = source ?? _cameras;
    await prefs.setStringList(
      _camerasKey,
      list.map((camera) => jsonEncode(camera.toJson())).toList(),
    );
  }

  Future<void> _saveHardwareSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hardwareKey, value);
  }

  Future<void> _saveTransport(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_transportKey, value);
  }

  bool _isSupportedUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    return uri.hasScheme &&
        {'rtsp', 'rtsps', 'http', 'https'}.contains(uri.scheme.toLowerCase());
  }

  Future<CameraEntry?> _showCameraDialog({
    CameraEntry? existing,
    String? initialUrl,
    String? initialName,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? initialName ?? '');
    final urlController = TextEditingController(text: existing?.url ?? initialUrl ?? '');
    bool recordingEnabled = existing?.recordingEnabled ?? false;
    final retentionDays = existing?.retentionDays ?? 7;

    final result = await showDialog<CameraEntry>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Adicionar Câmera' : 'Editar Câmera'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: existing == null && initialUrl == null && initialName == null,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nome da Câmera',
                        prefixIcon: Icon(Icons.videocam),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'URL RTSP / HTTP',
                        hintText: 'rtsp://usuario:senha@192.168.1.10:554/stream',
                        prefixIcon: Icon(Icons.link),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Gravação contínua'),
                      subtitle: const Text(
                        'Grava segmentos localmente e envia para a nuvem configurada em Ajustes.',
                      ),
                      value: recordingEnabled,
                      onChanged: (value) => setDialogState(() => recordingEnabled = value),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final url = urlController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() => error = 'Informe um nome para a câmera.');
                      return;
                    }
                    if (!_isSupportedUrl(url)) {
                      setDialogState(() => error = 'URL inválida. Use RTSP, RTSPS, HTTP ou HTTPS.');
                      return;
                    }
                    Navigator.pop(
                      dialogContext,
                      CameraEntry(
                        name: name,
                        url: url,
                        recordingEnabled: recordingEnabled,
                        retentionDays: retentionDays,
                      ),
                    );
                  },
                  child: Text(existing == null ? 'Adicionar' : 'Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    urlController.dispose();
    return result;
  }

  Future<void> _addCamera({String? initialUrl}) async {
    final result = await _showCameraDialog(initialUrl: initialUrl);
    if (result == null || !mounted) return;
    setState(() => _cameras.add(result));
    await _persistCameras();
  }

  Future<void> _editCamera(int index) async {
    final result = await _showCameraDialog(existing: _cameras[index]);
    if (result == null || !mounted) return;
    setState(() => _cameras[index] = result);
    await _persistCameras();
  }

  Future<void> _removeCamera(int index) async {
    final camera = _cameras[index];
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover câmera?'),
        content: Text('Remover "${camera.name}" da lista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (remove != true || !mounted) return;
    setState(() => _cameras.removeAt(index));
    await _persistCameras();
  }

  Future<void> _clearCameras() async {
    if (_cameras.isEmpty) return;

    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar câmeras?'),
        content: const Text('Todas as câmeras cadastradas serão removidas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );

    if (clear != true || !mounted) return;
    setState(() => _cameras.clear());
    await _persistCameras();
  }

  void _handleBarcode(String? rawValue) {
    if (_scanLocked || rawValue == null) return;
    final value = rawValue.trim();
    if (value.isEmpty) return;

    _scanLocked = true;
    final decoded = _decodeQrCamera(value);
    _showCameraDialog(
      initialUrl: decoded.url,
      initialName: decoded.name,
    ).then((result) async {
      if (result != null && mounted) {
        setState(() => _cameras.add(result));
        await _persistCameras();
      }
    }).whenComplete(() {
      Future<void>.delayed(const Duration(milliseconds: 1000), () {
        _scanLocked = false;
      });
    });
  }

  ({String? name, String? url}) _decodeQrCamera(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        final url = decoded['url']?.toString();
        final name = decoded['name']?.toString();
        if (url != null && _isSupportedUrl(url)) {
          return (name: name, url: url);
        }
      }
    } catch (_) {
      // The QR code may simply contain a raw URL.
    }
    return (name: null, url: value);
  }

  void _openFullscreen(CameraEntry camera) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullscreenCameraScreen(
          camera: camera,
          transport: _rtspTransport,
          hardwareAcceleration: _hardwareAcceleration,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('camDu Pro'),
        actions: [
          if (_selectedIndex == 0) ...[
            IconButton(
              icon: Icon(_isGridView ? Icons.view_stream : Icons.grid_view),
              tooltip: _isGridView ? 'Modo Lista' : 'Modo Grade',
              onPressed: () => setState(() => _isGridView = !_isGridView),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Adicionar Câmera',
              onPressed: () => _addCamera(),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildSelectedScreen(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.videocam), label: 'Câmeras'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Scanner'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }

  Widget _buildSelectedScreen() {
    switch (_selectedIndex) {
      case 1:
        return _buildScannerScreen();
      case 2:
        return _buildSettingsScreen();
      default:
        return _buildCamerasScreen();
    }
  }

  Widget _buildCamerasScreen() {
    if (_cameras.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Nenhuma câmera configurada.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _addCamera(),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar Câmera'),
              ),
            ],
          ),
        ),
      );
    }

    return CameraGrid(
      cameras: _cameras,
      isGridView: _isGridView,
      transport: _rtspTransport,
      hardwareAcceleration: _hardwareAcceleration,
      onRemove: _removeCamera,
      onEdit: _editCamera,
      onFullscreen: _openFullscreen,
    );
  }

  Widget _buildScannerScreen() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                _handleBarcode(barcode.rawValue);
                if (_scanLocked) break;
              }
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1B1D22),
          child: const SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, color: Colors.blueAccent),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Aponte para o QR Code da câmera. Um URL RTSP/HTTP ou um JSON com name e url é aceito.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Configurações Gerais',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('Aceleração de Hardware'),
          subtitle: const Text('Usa aceleração de vídeo do Android quando disponível.'),
          value: _hardwareAcceleration,
          onChanged: (value) {
            setState(() => _hardwareAcceleration = value);
            _saveHardwareSetting(value);
          },
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: const Text('Transporte RTSP'),
          subtitle: Text(_rtspTransport == 'tcp' ? 'TCP (recomendado para redes instáveis)' : 'UDP'),
          trailing: DropdownButton<String>(
            value: _rtspTransport,
            items: const [
              DropdownMenuItem(value: 'tcp', child: Text('TCP')),
              DropdownMenuItem(value: 'udp', child: Text('UDP')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _rtspTransport = value);
              _saveTransport(value);
            },
          ),
        ),
        const ListTile(
          leading: Icon(Icons.live_tv),
          title: Text('Player'),
          subtitle: Text('MediaKit/MPV com suporte a RTSP, HTTP e HTTPS.'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Nuvem',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('Provedor de Armazenamento'),
          subtitle: Text(CloudStorageManager.instance.active.displayName),
          trailing: DropdownButton<String>(
            value: CloudStorageManager.instance.active.id,
            items: CloudStorageManager.instance.availableProviders
                .map((provider) => DropdownMenuItem(
                      value: provider.id,
                      child: Text(provider.displayName),
                    ))
                .toList(),
            onChanged: (value) async {
              if (value == null) return;
              await CloudStorageManager.instance.select(value);
              if (!mounted) return;
              setState(() {});
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'A gravação continua funcionando com "Nenhum" selecionado — os '
            'clipes ficam salvos apenas no aparelho até que um provedor de '
            'nuvem gratuito (WebDAV, S3, Google Drive, etc.) seja adicionado.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.delete_sweep, color: Colors.redAccent),
          title: const Text('Limpar Câmeras Cadastradas', style: TextStyle(color: Colors.redAccent)),
          onTap: _clearCameras,
        ),
        const SizedBox(height: 12),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('camDu Pro 2.0'),
          subtitle: Text('Monitoramento RTSP • QR Code • múltiplas câmeras • tela cheia'),
        ),
      ],
    );
  }
}

class CameraGrid extends StatelessWidget {
  final List<CameraEntry> cameras;
  final bool isGridView;
  final String transport;
  final bool hardwareAcceleration;
  final Future<void> Function(int index) onRemove;
  final Future<void> Function(int index) onEdit;
  final void Function(CameraEntry camera) onFullscreen;

  const CameraGrid({
    super.key,
    required this.cameras,
    required this.isGridView,
    required this.transport,
    required this.hardwareAcceleration,
    required this.onRemove,
    required this.onEdit,
    required this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    if (isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.35,
        ),
        itemCount: cameras.length,
        itemBuilder: (context, index) {
          final camera = cameras[index];
          return CameraPlayerTile(
            key: ValueKey('${camera.url}|$transport|$hardwareAcceleration'),
            camera: camera,
            transport: transport,
            hardwareAcceleration: hardwareAcceleration,
            onRemove: () => onRemove(index),
            onEdit: () => onEdit(index),
            onFullscreen: () => onFullscreen(camera),
          );
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: cameras.length,
      itemBuilder: (context, index) {
        final camera = cameras[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            height: 230,
            child: CameraPlayerTile(
              key: ValueKey('${camera.url}|$transport|$hardwareAcceleration'),
              camera: camera,
              transport: transport,
              hardwareAcceleration: hardwareAcceleration,
              onRemove: () => onRemove(index),
              onEdit: () => onEdit(index),
              onFullscreen: () => onFullscreen(camera),
            ),
          ),
        );
      },
    );
  }
}

class CameraPlayerTile extends StatefulWidget {
  final CameraEntry camera;
  final String transport;
  final bool hardwareAcceleration;
  final VoidCallback onRemove;
  final VoidCallback onEdit;
  final VoidCallback onFullscreen;

  const CameraPlayerTile({
    super.key,
    required this.camera,
    required this.transport,
    required this.hardwareAcceleration,
    required this.onRemove,
    required this.onEdit,
    required this.onFullscreen,
  });

  @override
  State<CameraPlayerTile> createState() => _CameraPlayerTileState();
}

class _CameraPlayerTileState extends State<CameraPlayerTile> {
  late final Player _player;
  late final VideoController _controller;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  StreamSubscription<String>? _errorSubscription;
  String? _error;
  bool _buffering = true;
  bool _playing = false;
  bool _disposed = false;
  RecordingService? _recordingService;

  @override
  void initState() {
    super.initState();
    _createPlayer();
  }

  void _createPlayer() {
    _player = Player(
      configuration: const PlayerConfiguration(
        osc: false,
        pitch: false,
        muted: false,
        libass: false,
        bufferSize: 4 * 1024 * 1024,
        protocolWhitelist: _kProtocolWhitelist,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: widget.hardwareAcceleration,
        scale: 0.75,
      ),
    );

    _errorSubscription = _player.stream.error.listen((message) {
      if (!mounted) return;
      setState(() {
        _error = message.isEmpty ? 'Falha ao reproduzir o stream.' : message;
        _buffering = false;
      });
    });
    _subscriptions.add(_player.stream.buffering.listen((value) {
      if (mounted) setState(() => _buffering = value);
    }));
    _subscriptions.add(_player.stream.playing.listen((value) {
      if (mounted) setState(() => _playing = value);
    }));

    _open();
  }

  Future<void> _open() async {
    try {
      await _setTransport();
      await _player.open(Media(widget.camera.url));
      if (!mounted) return;
      setState(() {
        _error = null;
        _buffering = true;
      });
      await _syncRecording();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _buffering = false;
      });
    }
  }

  /// Liga ou desliga a gravação contínua de acordo com [CameraEntry.recordingEnabled].
  Future<void> _syncRecording() async {
    if (widget.camera.recordingEnabled) {
      if (_recordingService == null) {
        _recordingService = RecordingService(
          cameraName: widget.camera.name,
          player: _player,
          retentionDays: widget.camera.retentionDays,
        );
        await _recordingService!.start();
      }
    } else {
      await _recordingService?.stop();
      _recordingService = null;
    }
  }

  Future<void> _restartRecording() async {
    await _recordingService?.stop();
    _recordingService = null;
    if (_disposed) return;
    await _syncRecording();
  }

  Future<void> _setTransport() async {
    final platform = _player.platform;
    if (platform == null) return;
    try {
      await (platform as dynamic).setProperty('rtsp-transport', widget.transport);
    } catch (_) {
      // Older/native backends may not expose this property; MPV will negotiate normally.
    }
  }

  Future<void> _retry() async {
    if (_disposed) return;
    setState(() {
      _error = null;
      _buffering = true;
    });
    try {
      await _player.stop();
    } catch (_) {}
    await _open();
  }


  @override
  void didUpdateWidget(covariant CameraPlayerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.camera;
    final now = widget.camera;
    if (old.recordingEnabled != now.recordingEnabled ||
        old.name != now.name ||
        old.retentionDays != now.retentionDays) {
      // Nome/retenção são fixados na criação do RecordingService; se mudaram
      // com a gravação ligada, encerra o serviço atual para recriar já com
      // os valores novos.
      _restartRecording();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _errorSubscription?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    // Fecha o segmento em andamento ANTES de destruir o player; senão o
    // último clipe ficaria truncado/sem envio.
    final recording = _recordingService;
    _recordingService = null;
    if (recording != null) {
      recording.stop().catchError((_) {}).whenComplete(_player.dispose);
    } else {
      _player.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF050607),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onDoubleTap: widget.onFullscreen,
            child: Video(
              controller: _controller,
              fit: BoxFit.cover,
              controls: NoVideoControls,
              wakelock: true,
              resumeUponEnteringForegroundMode: true,
            ),
          ),
          if (_error != null)
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.orange, size: 32),
                    const SizedBox(height: 8),
                    const Text('Sem conexão com a câmera', textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text(
                      _shortError(_error!),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          else if (_buffering)
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              color: const Color(0xA6000000),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    color: _playing ? Colors.greenAccent : Colors.orange,
                    size: 9,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.camera.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Tela cheia',
                    onPressed: widget.onFullscreen,
                    icon: const Icon(Icons.fullscreen, size: 20),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'edit') widget.onEdit();
                      if (value == 'remove') widget.onRemove();
                      if (value == 'retry') _retry();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'retry', child: Text('Reconectar')),
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'remove', child: Text('Remover')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 8,
            bottom: 6,
            child: Text(
              'Duplo toque: tela cheia',
              style: TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  String _shortError(String error) {
    final normalized = error.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length > 160 ? '${normalized.substring(0, 157)}...' : normalized;
  }
}

class FullscreenCameraScreen extends StatefulWidget {
  final CameraEntry camera;
  final String transport;
  final bool hardwareAcceleration;

  const FullscreenCameraScreen({
    super.key,
    required this.camera,
    required this.transport,
    required this.hardwareAcceleration,
  });

  @override
  State<FullscreenCameraScreen> createState() => _FullscreenCameraScreenState();
}

class _FullscreenCameraScreenState extends State<FullscreenCameraScreen> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSubscription;
  String? _error;
  bool _buffering = true;

  @override
  void initState() {
    super.initState();
    _player = Player(
      configuration: const PlayerConfiguration(
        osc: false,
        pitch: false,
        bufferSize: 8 * 1024 * 1024,
        protocolWhitelist: _kProtocolWhitelist,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: widget.hardwareAcceleration,
      ),
    );
    _errorSubscription = _player.stream.error.listen((message) {
      if (mounted) setState(() => _error = message);
    });
    _player.stream.buffering.listen((value) {
      if (mounted) setState(() => _buffering = value);
    });
    _open();
  }

  Future<void> _open() async {
    try {
      final platform = _player.platform;
      if (platform != null) {
        try {
          await (platform as dynamic).setProperty('rtsp-transport', widget.transport);
        } catch (_) {}
      }
      await _player.open(Media(widget.camera.url));
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.camera.name),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _controller,
              fit: BoxFit.contain,
              controls: AdaptiveVideoControls,
              wakelock: true,
              resumeUponEnteringForegroundMode: true,
            ),
            if (_buffering && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 48, color: Colors.orange),
                      const SizedBox(height: 12),
                      const Text('Não foi possível conectar à câmera.', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _error = null;
                            _buffering = true;
                          });
                          _open();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reconectar'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
