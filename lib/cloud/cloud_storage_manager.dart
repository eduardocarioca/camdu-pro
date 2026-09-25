import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_storage_provider.dart';

/// Registro central + persistência do [CloudStorageProvider] ativo.
///
/// Para adicionar um novo backend no futuro: implemente
/// [CloudStorageProvider] em um arquivo próprio (ex:
/// `webdav_cloud_storage_provider.dart`) e registre a instância no mapa
/// [_providers] abaixo. Nenhum outro arquivo do app precisa mudar.
class CloudStorageManager {
  CloudStorageManager._internal();

  static final CloudStorageManager instance = CloudStorageManager._internal();

  static const _selectedProviderKey = 'cloud_provider_id';
  static const _providerConfigKey = 'cloud_provider_config';

  final Map<String, CloudStorageProvider> _providers = {
    const NoopCloudStorageProvider().id: const NoopCloudStorageProvider(),
    // TODO: registrar futuros provedores aqui, por exemplo:
    // WebDavCloudStorageProvider().id: WebDavCloudStorageProvider(),
    // S3CloudStorageProvider().id: S3CloudStorageProvider(),
  };

  CloudStorageProvider _active = const NoopCloudStorageProvider();
  Map<String, String> _activeConfig = {};

  List<CloudStorageProvider> get availableProviders =>
      _providers.values.toList(growable: false);

  CloudStorageProvider get active => _active;

  Map<String, String> get activeConfig => _activeConfig;

  /// Carrega o provedor/config salvos. Deve ser chamado uma vez na
  /// inicialização do app (ex: junto com `_loadSettings` da tela principal).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final id = prefs.getString(_selectedProviderKey);
    if (id != null && _providers.containsKey(id)) {
      _active = _providers[id]!;
    }

    final rawConfig = prefs.getString(_providerConfigKey);
    if (rawConfig != null) {
      try {
        final decoded = jsonDecode(rawConfig);
        if (decoded is Map) {
          _activeConfig =
              decoded.map((key, value) => MapEntry(key.toString(), value.toString()));
        }
      } catch (_) {
        _activeConfig = {};
      }
    }
  }

  /// Troca o provedor ativo e persiste a escolha.
  Future<void> select(String providerId, {Map<String, String> config = const {}}) async {
    final provider = _providers[providerId];
    if (provider == null) return;

    _active = provider;
    _activeConfig = Map<String, String>.of(config);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedProviderKey, providerId);
    await prefs.setString(_providerConfigKey, jsonEncode(config));
  }
}
