import 'package:flutter/material.dart';
import 'package:openlogtool/providers/sync_provider.dart';

class ServerSettingsFields extends StatefulWidget {
  final SyncProvider syncProvider;

  const ServerSettingsFields({super.key, required this.syncProvider});

  @override
  State<ServerSettingsFields> createState() => _ServerSettingsFieldsState();
}

class _ServerSettingsFieldsState extends State<ServerSettingsFields> {
  late TextEditingController _serverUrlController;
  late TextEditingController _deviceIdController;

  @override
  void initState() {
    super.initState();
    _serverUrlController =
        TextEditingController(text: widget.syncProvider.settings.serverUrl);
    _deviceIdController =
        TextEditingController(text: widget.syncProvider.settings.deviceId);
  }

  @override
  void didUpdateWidget(ServerSettingsFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.syncProvider.settings.serverUrl != _serverUrlController.text) {
      _serverUrlController.text = widget.syncProvider.settings.serverUrl;
    }
    if (widget.syncProvider.settings.deviceId != _deviceIdController.text) {
      _deviceIdController.text = widget.syncProvider.settings.deviceId;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextField(
        decoration: const InputDecoration(
            labelText: '服务器地址',
            hintText: 'http://localhost:3000',
            border: OutlineInputBorder()),
        controller: _serverUrlController,
        onChanged: (value) => widget.syncProvider.setServerUrl(value),
      ),
      const SizedBox(height: 8),
      TextField(
        decoration: const InputDecoration(
            labelText: '设备ID',
            hintText: 'device-001',
            border: OutlineInputBorder()),
        controller: _deviceIdController,
        onChanged: (value) => widget.syncProvider.setDeviceId(value),
      ),
    ]);
  }
}

class LoginDialog extends StatefulWidget {
  static String? username;
  static String? password;

  const LoginDialog({super.key});

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('子账号登录'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          decoration: const InputDecoration(
              labelText: '用户名', border: OutlineInputBorder()),
          controller: _usernameController,
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
              labelText: '密码', border: OutlineInputBorder()),
          obscureText: true,
          controller: _passwordController,
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消')),
        ElevatedButton(
          onPressed: () {
            LoginDialog.username = _usernameController.text;
            LoginDialog.password = _passwordController.text;
            Navigator.pop(context, true);
          },
          child: const Text('登录'),
        ),
      ],
    );
  }
}
