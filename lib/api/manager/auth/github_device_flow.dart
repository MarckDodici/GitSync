import 'dart:async';
import 'dart:convert';

import 'package:GitSync/global.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// GitHub OAuth Device Authorization Flow (RFC 8628).
///
/// Uses only the public client id of a GitHub OAuth App with "Enable Device Flow" turned on.
/// No client secret is needed or stored. Returns the access token, or null if the user
/// cancelled or something failed (an explanatory dialog is shown for failures).
class GithubDeviceFlow {
  static const String _base = 'https://github.com';
  static const String _grantType = 'urn:ietf:params:oauth:grant-type:device_code';
  static const Map<String, String> _headers = {'Accept': 'application/json'};

  static BuildContext? get _overlayContext => rootNavigatorKey.currentState?.overlay?.context;

  static Future<String?> authorize({required String clientId, List<String>? scopes}) async {
    if (clientId.isEmpty) {
      await _showMessage('GitHub sign-in is not configured', 'Set gitHubClientId in lib/constant/secrets.dart (a GitHub OAuth App with Device Flow enabled).');
      return null;
    }

    final Map<String, dynamic> code;
    try {
      final res = await http
          .post(Uri.parse('$_base/login/device/code'), headers: _headers, body: {'client_id': clientId, 'scope': (scopes ?? const <String>[]).join(' ')})
          .timeout(const Duration(seconds: 20));
      code = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      await _showMessage('GitHub sign-in failed', 'Could not reach GitHub: $e');
      return null;
    }
    if (code['error'] != null || code['device_code'] == null) {
      await _showMessage(
        'GitHub sign-in failed',
        '${code['error_description'] ?? code['error'] ?? 'Unexpected response'}. Make sure "Enable Device Flow" is on for the OAuth App.',
      );
      return null;
    }

    final deviceCode = code['device_code'] as String;
    final userCode = code['user_code'] as String;
    final verificationUri = (code['verification_uri'] as String?) ?? '$_base/login/device';
    var interval = ((code['interval'] as num?)?.toInt() ?? 5).clamp(1, 60).toInt();
    final expiresAt = DateTime.now().add(Duration(seconds: (code['expires_in'] as num?)?.toInt() ?? 900));

    var cancelled = false;
    var dialogOpen = false;
    final overlayContext = _overlayContext;
    if (overlayContext != null && overlayContext.mounted) {
      dialogOpen = true;
      showDialog<void>(
        context: overlayContext,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) => _CodeDialog(
          userCode: userCode,
          verificationUri: verificationUri,
          onCancel: () {
            cancelled = true;
            Navigator.of(dialogContext).pop();
          },
        ),
      ).then((_) => dialogOpen = false);
    }

    try {
      await Clipboard.setData(ClipboardData(text: userCode));
      await launchUrl(Uri.parse(verificationUri), mode: LaunchMode.externalApplication);
    } catch (_) {
      // The dialog still shows the code and has an "Open GitHub" button.
    }

    String? token;
    String? failure;
    var networkErrors = 0;
    while (!cancelled) {
      await Future.delayed(Duration(seconds: interval));
      if (cancelled) break;
      if (DateTime.now().isAfter(expiresAt)) {
        failure = 'The code expired. Please try again.';
        break;
      }
      try {
        final res = await http
            .post(Uri.parse('$_base/login/oauth/access_token'), headers: _headers, body: {'client_id': clientId, 'device_code': deviceCode, 'grant_type': _grantType})
            .timeout(const Duration(seconds: 20));
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        networkErrors = 0;

        final accessToken = body['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          token = accessToken;
          break;
        }

        switch (body['error']) {
          case 'authorization_pending':
            break;
          case 'slow_down':
            interval = ((body['interval'] as num?)?.toInt() ?? interval + 5).clamp(1, 120).toInt();
            break;
          case 'expired_token':
            failure = 'The code expired. Please try again.';
            break;
          case 'access_denied':
            failure = 'Authorization was denied.';
            break;
          default:
            failure = 'GitHub returned an error: ${body['error_description'] ?? body['error'] ?? 'unknown'}';
        }
        if (failure != null) break;
      } catch (_) {
        networkErrors++;
        if (networkErrors >= 5) {
          failure = 'Network error while waiting for authorization.';
          break;
        }
      }
    }

    if (dialogOpen) {
      rootNavigatorKey.currentState?.pop();
    }
    if (failure != null) {
      await _showMessage('GitHub sign-in failed', failure);
    }
    return token;
  }

  static Future<void> _showMessage(String title, String message) async {
    final context = _overlayContext;
    if (context == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
      ),
    );
  }
}

class _CodeDialog extends StatelessWidget {
  final String userCode;
  final String verificationUri;
  final VoidCallback onCancel;

  const _CodeDialog({required this.userCode, required this.verificationUri, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect to GitHub'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Open this page and enter the code below (it has been copied to the clipboard):'),
          const SizedBox(height: 8),
          SelectableText(verificationUri),
          const SizedBox(height: 12),
          Center(
            child: SelectableText(userCode, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Expanded(child: Text('Waiting for authorization...')),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: userCode)), child: const Text('Copy code')),
        TextButton(onPressed: () => launchUrl(Uri.parse(verificationUri), mode: LaunchMode.externalApplication), child: const Text('Open GitHub')),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}
