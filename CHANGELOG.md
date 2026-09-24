# Changelog

## 2.1.1 — Rodada de correções por partes (sem SDK Flutter disponível: revisão estática)

- Build: `versionCode`/`versionName` agora vêm do `pubspec.yaml`; `buildTypes.release`
  com assinatura de debug TEMPORÁRIA (trocar por keystore própria na etapa de segurança);
  removido `android.enableR8` (obsoleto); `gradle-wrapper.properties` completo;
  CI usa `flutter analyze --no-fatal-infos`.
- Nuvem: `select()` copia o mapa de configuração (evita mapa imutável compartilhado).
- Gravação: `stop()` durante uma rotação não reinicia mais a gravação; limpeza por
  retenção não derruba o `stop()`; nome de pasta nunca vazio.
- Fila de upload: corrigida perda de segmentos enfileirados durante um ciclo de envio;
  caminho remoto inclui a câmera (`camdu/<camera>/<arquivo>`); `_isUploading` sempre liberado.
- Player: whitelist inclui `rtp`, `tls` e `crypto` (RTSP/UDP e RTSPS falhavam sem eles).
- Tile: fecha o segmento de gravação antes de descartar o player; recria a gravação
  se nome/retenção mudarem; QR com JSON abre como "Adicionar Câmera" (não "Editar").
- Removido `withOpacity` (obsoleto em Flutter recentes).

## 2.1.0 — Correções e esqueleto de gravação/nuvem

- Removidos arquivos duplicados/divergentes na raiz do repositório
  (main.dart, MainActivity.kt, AndroidManifest.xml, build.gradle,
  settings.gradle, gradle.properties, colors.xml, strings.xml, styles.xml,
  build.yml) que conflitavam com as versões corretas em `android/`, `lib/`
  e `.github/workflows/`.
- Corrigido `android/app/build.gradle`: blocos `compileOptions`/
  `kotlinOptions` duplicados removidos.
- Adicionada interface plugável `CloudStorageProvider` (`lib/cloud/`) para
  futuros backends de armazenamento gratuito (WebDAV, S3-compatível,
  Google Drive, etc.), com `CloudStorageManager` para seleção/persistência
  e um `NoopCloudStorageProvider` como padrão (somente local).
- Adicionado esqueleto de gravação contínua (`lib/recording/`):
  `RecordingService` grava segmentos rotativos localmente por câmera e
  `UploadQueue` envia para o provedor de nuvem ativo, com retentativa.
- `CameraEntry` ganhou os campos `recordingEnabled` e `retentionDays`
  (retrocompatível com câmeras salvas em versões anteriores).
- Tela de Ajustes ganhou a seção "Nuvem" para escolher o provedor ativo.
- Diálogo de câmera ganhou o toggle "Gravação contínua".

## 2.0.0+2 — Final de desenvolvimento

- Implementado player real para RTSP/RTSPS/HTTP/HTTPS usando MediaKit/MPV.
- Suporte a múltiplas câmeras simultâneas.
- Grade e lista de câmeras.
- Tela cheia por botão e duplo toque.
- Reconexão manual de streams.
- Indicador de conexão/buffering.
- Transporte RTSP TCP/UDP configurável.
- Aceleração de hardware configurável.
- Cadastro, edição e remoção de câmeras.
- Persistência em JSON com migração do formato antigo.
- Scanner QR Code aceita URL ou JSON com name/url.
- Validação de URLs suportadas.
- Compatibilidade com streams HTTP locais via cleartext traffic.
- Workflow CI com análise, testes, APK e AAB.
- README e guia de build atualizados.
