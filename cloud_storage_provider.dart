import 'dart:io';

/// Contrato que qualquer backend de nuvem precisa implementar.
///
/// A ideia é que o resto do app (fila de upload, tela de Ajustes) só
/// converse com esta interface. Adicionar um novo backend (WebDAV,
/// S3-compatível, Google Drive, etc.) no futuro não deve exigir mudanças
/// em nenhum outro arquivo além do registro em [CloudStorageManager].
abstract class CloudStorageProvider {
  /// Identificador estável usado para persistência (ex: 'webdav', 's3').
  String get id;

  /// Nome amigável mostrado na tela de Ajustes.
  String get displayName;

  /// Chaves de configuração que este provedor precisa do usuário
  /// (ex: ['url', 'usuario', 'senha']). Usado para montar um formulário
  /// genérico de configuração quando o backend for implementado.
  List<String> get configKeys;

  /// Testa a conexão com o servidor usando [config], sem enviar arquivos.
  Future<bool> testConnection(Map<String, String> config);

  /// Envia [file] para [remotePath] no backend.
  Future<void> upload({
    required File file,
    required String remotePath,
    required Map<String, String> config,
  });

  /// Remove um arquivo remoto já enviado (usado na limpeza por retenção).
  Future<void> delete({
    required String remotePath,
    required Map<String, String> config,
  });

  /// Lista arquivos dentro de [remoteFolder] (para uma futura tela de
  /// navegação pelos clipes gravados).
  Future<List<String>> list({
    required String remoteFolder,
    required Map<String, String> config,
  });
}

/// Provedor padrão enquanto nenhum backend real foi configurado.
///
/// Mantém a gravação funcionando normalmente (os segmentos continuam
/// sendo criados e enfileirados), só que eles permanecem apenas no
/// armazenamento local até que um provedor de verdade seja escolhido.
class NoopCloudStorageProvider implements CloudStorageProvider {
  const NoopCloudStorageProvider();

  @override
  String get id => 'none';

  @override
  String get displayName => 'Nenhum (somente armazenamento local)';

  @override
  List<String> get configKeys => const [];

  @override
  Future<bool> testConnection(Map<String, String> config) async => true;

  @override
  Future<void> upload({
    required File file,
    required String remotePath,
    required Map<String, String> config,
  }) async {
    // Nada a fazer: o clipe fica só no armazenamento local até que um
    // backend real (WebDAV, S3, Google Drive, ...) seja implementado.
  }

  @override
  Future<void> delete({
    required String remotePath,
    required Map<String, String> config,
  }) async {}

  @override
  Future<List<String>> list({
    required String remoteFolder,
    required Map<String, String> config,
  }) async =>
      const [];
}
