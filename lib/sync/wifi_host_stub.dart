/// Web stub: browsers cannot host a listening socket, so this device
/// can only RECEIVE (act as client). Sending needs Android/Windows.
class HostSession {
  final String url = '';
  final String pin = '';
  Future<void> close() async {}
}

Future<HostSession> startSendServer({
  required String Function() currentSnapshot,
  String Function()? currentSnapshotV2,
  required void Function(String snapshotJson) onUpload,
  required String pin,
}) async {
  throw UnsupportedError(
    'WiFi send needs the Android/Windows app (browsers cannot host). '
    'On this device use Receive instead, and Send from the other device.',
  );
}
