import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativeflow/nativeflow.dart';
import 'package:nativeflow/src/platform/native_flow_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.nativeflow/runtime');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final platform = MethodChannelNativeFlowPlatform();

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('passes method and arguments through', () async {
    late MethodCall seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return 'running';
    });
    expect(await platform.invoke<String>('start', {'a': 1}), 'running');
    expect(seen.method, 'start');
    expect(seen.arguments, {'a': 1});
  });

  test('maps native error codes to NativeFlowErrorCode', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'permission_required', message: 'location');
    });
    await expectLater(
      platform.invoke<void>('start'),
      throwsA(
        isA<NativeFlowException>().having(
          (e) => e.code,
          'code',
          NativeFlowErrorCode.permissionRequired,
        ),
      ),
    );
  });

  test('missing implementation surfaces as unavailable', () async {
    await expectLater(
      platform.invoke<void>('start'),
      throwsA(
        isA<NativeFlowException>().having(
          (e) => e.code,
          'code',
          NativeFlowErrorCode.unavailable,
        ),
      ),
    );
  });
}
