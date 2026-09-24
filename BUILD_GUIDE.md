# Guia de build — camDu Pro

## Local

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
```

## GitHub Actions

O workflow executa automaticamente:

1. Checkout.
2. Java 17.
3. Flutter 3.24.3.
4. Android SDK 34.
5. `flutter pub get`.
6. `flutter analyze`.
7. `flutter test`.
8. APK release.
9. AAB release.
10. Upload dos dois artefatos.

## Teste do aplicativo

Depois de instalar o APK em um Android:

1. Cadastre uma câmera pelo botão `+`.
2. Use uma URL RTSP real da sua câmera/NVR.
3. Se a imagem não abrir, teste `Ajustes > Transporte RTSP > TCP`.
4. Confirme que o telefone está na rede que alcança o IP da câmera.
5. Verifique usuário, senha, porta e caminho RTSP.
6. Use o botão `Reconectar` no cartão quando necessário.
7. Toque no botão de tela cheia ou dê duplo toque no vídeo.

## QR Code

O scanner aceita tanto uma URL direta quanto JSON:

```json
{"name":"Entrada","url":"rtsp://usuario:senha@192.168.1.10:554/stream1"}
```
