# zawer_jewellery_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Release builds

Release builds block plain HTTP (cleartext is only allowed in debug/profile on
Android, and only local networking on iOS), so point the app at an HTTPS backend:

```
flutter build apk --release --dart-define=API_BASE_URL=https://your-server
```
