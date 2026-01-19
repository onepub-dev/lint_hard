import 'dart:async';
import 'dart:io';

import 'package:analysis_server_plugin/src/plugin_server.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/channel/channel.dart';
import 'package:analyzer_plugin/protocol/protocol.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart';
import 'package:lint_hard/main.dart';
import 'package:test/test.dart';

void main() {
  test('plugin reports custom lints via plugin server', () async {
    final tempDir = await Directory.systemTemp
        .createTemp('lint_hard_plugin_integration_');
    try {
      final packageDir = Directory(_joinPath(tempDir.path, 'app'));
      await packageDir.create(recursive: true);

      final rootPath = Directory.current.path;
      await _writeFile(
        _joinPath(packageDir.path, 'pubspec.yaml'),
        '''
name: lint_hard_plugin_integration_test
environment:
  sdk: '>=3.7.0 <4.0.0'
''',
      );

      await _writeFile(
        _joinPath(packageDir.path, 'analysis_options.yaml'),
        '''
plugins:
  lint_hard:
    path: $rootPath
    diagnostics:
      - document_thrown_exceptions
      - fields_first_constructors_next
      - throwing_unthrown_exception
''',
      );

      await _writeFile(
        _joinPath(packageDir.path, 'lib/sample.dart'),
        '''
import 'package:document_throws_annotation/document_throws_annotation.dart';

class BadStateException implements Exception {}
class UnthrownException implements Exception {}

class Thrower {
  void undocumented() {
    throw BadStateException();
  }
}

/// @Throwing(UnthrownException)
void docUnknown() {
  throw BadStateException();
}

@Throwing(UnthrownException)
void annotationUnknown() {
  throw BadStateException();
}

class BadOrder {
  BadOrder();
  final int value = 0;
}
''',
      );

      final channel = _TestPluginChannel();
      final server = PluginServer(
        resourceProvider: PhysicalResourceProvider.INSTANCE,
        plugins: [LintHardPlugin()],
      );
      server.start(channel);
      await server.initialize();

      await server.handlePluginVersionCheck(
        PluginVersionCheckParams(
          tempDir.path,
          _sdkPath(),
          '0.1.0',
        ),
      );

      await channel.sendRequest(
        AnalysisSetContextRootsParams([
          ContextRoot(packageDir.path, []),
        ]).toRequest(channel.nextRequestId()),
      );

      await channel.waitForAnalysisComplete().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError('Analysis did not complete'),
      );

      final codes = channel.analysisErrors.map((e) => e.code).toSet();
      expect(codes, contains('document_thrown_exceptions'));
      expect(codes, contains('fields_first_constructors_next'));
      expect(codes, contains('throwing_unthrown_exception'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

Future<void> _writeFile(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

String _sdkPath() {
  final dartExecutable = File(Platform.resolvedExecutable);
  return dartExecutable.parent.parent.path;
}

String _joinPath(String left, String right) {
  final sep = Platform.pathSeparator;
  if (left.endsWith(sep)) return '$left$right';
  return '$left$sep$right';
}

class _TestPluginChannel implements PluginCommunicationChannel {
  void Function(Request request)? _onRequest;
  final _notifications = StreamController<Notification>.broadcast();
  final _pendingResponses = <String, Completer<Response>>{};

  final List<Notification> notifications = [];
  final List<AnalysisError> analysisErrors = [];

  @override
  void close() {
    _notifications.close();
  }

  @override
  void listen(
    void Function(Request request) onRequest, {
    Function? onError,
    void Function()? onDone,
  }) {
    _onRequest = onRequest;
  }

  @override
  void sendNotification(Notification notification) {
    notifications.add(notification);
    if (notification.event == 'analysis.errors') {
      final params = AnalysisErrorsParams.fromNotification(notification);
      analysisErrors.addAll(params.errors);
    }
    _notifications.add(notification);
  }

  @override
  void sendResponse(Response response) {
    final completer = _pendingResponses.remove(response.id);
    completer?.complete(response);
  }

  String nextRequestId() => (_pendingResponses.length + 1).toString();

  Future<Response> sendRequest(Request request) {
    final completer = Completer<Response>();
    _pendingResponses[request.id] = completer;
    _onRequest?.call(request);
    return completer.future;
  }

  Future<void> waitForAnalysisComplete() async {
    if (_hasAnalysisCompleted(notifications)) return;
    await for (final notification in _notifications.stream) {
      if (notification.event != 'plugin.status') continue;
      final params = PluginStatusParams.fromNotification(notification);
      final analysis = params.analysis;
      if (analysis != null && analysis.isAnalyzing == false) {
        break;
      }
    }
  }

  bool _hasAnalysisCompleted(List<Notification> notifications) {
    for (final notification in notifications) {
      if (notification.event != 'plugin.status') continue;
      final params = PluginStatusParams.fromNotification(notification);
      final analysis = params.analysis;
      if (analysis != null && analysis.isAnalyzing == false) {
        return true;
      }
    }
    return false;
  }
}
