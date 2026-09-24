# camDu Pro

Aplicativo Flutter para monitoramento de câmeras IP com **RTSP/RTSPS/HTTP/HTTPS**, QR Code, múltiplas câmeras e visualização em tela cheia.

## Principais recursos

- Cadastro persistente de câmeras.
- Compatibilidade com URLs `rtsp://`, `rtsps://`, `http://` e `https://`.
- Player nativo baseado em MediaKit/MPV.
- Transporte RTSP configurável entre **TCP** e **UDP** (TCP é o padrão recomendado).
- Grade 2xN ou lista.
- Reconexão manual quando uma câmera fica indisponível.
- Tela cheia por botão ou duplo toque.
- Scanner QR Code para URL simples ou JSON `{ "name": "Câmera", "url": "rtsp://..." }`.
- Migração automática do formato antigo de câmeras salvo pelo projeto anterior.
- Aceleração de hardware configurável.
- GitHub Actions para análise, testes, APK e AAB.

## Como testar

1. Abra o projeto no GitHub/Codespaces ou em um ambiente Flutter.
2. Execute `flutter pub get`.
3. Execute `flutter analyze`.
4. Execute `flutter test`.
5. Execute `flutter run` ou `flutter build apk --release`.
6. No Android, dê permissão de câmera quando abrir o scanner QR Code.

### URL RTSP de exemplo

```text
rtsp://usuario:senha@192.168.1.100:554/stream1
```

> A URL exata depende do fabricante/modelo da câmera ou NVR. O aplicativo não consegue descobrir automaticamente o caminho RTSP de uma câmera apenas pelo IP.

## Observações sobre RTSP

O player usa MediaKit/MPV e aceita RTSP diretamente. A conexão depende da câmera/NVR, rede local, autenticação e codec fornecido pelo equipamento. H.264 costuma ser a opção mais compatível em Android.

Para redes com perda de pacotes, teste primeiro **TCP**. Para redes locais estáveis e quando a câmera funcionar melhor em UDP, altere para **UDP** em Ajustes.

## Build no GitHub Actions

O workflow `.github/workflows/build.yml` executa análise, testes e gera:

- `app-release.apk`
- `app-release.aab`

Os arquivos ficam disponíveis nos **Artifacts** da execução do workflow.

## Limitações conhecidas

- O aplicativo não testa uma câmera real durante o build; a câmera precisa estar acessível no aparelho de teste.
- Alguns equipamentos exigem URLs RTSP específicas do fabricante.
- Streams H.265/HEVC podem depender do suporte do dispositivo Android e do backend nativo.
- Para publicação na Google Play, configure uma chave de assinatura de release própria em vez da assinatura debug usada no workflow de testes.
