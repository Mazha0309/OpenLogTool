import 'package:flutter/material.dart';

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
