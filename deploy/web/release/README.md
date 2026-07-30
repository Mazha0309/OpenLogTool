# OpenLogTool WebClient

This release bundle contains the prebuilt Flutter Web and Rust WASM assets.
Docker only packages those assets into Nginx; it does not rebuild Flutter or
Rust.

本发布包已包含构建完成的 Flutter Web 与 Rust WASM 文件。Docker 只会将它们
打包进 Nginx，不会重新编译 Flutter 或 Rust。

```bash
docker compose up -d
```

The default external port is `5973`:

默认外部端口为 `5973`：

```text
http://127.0.0.1:5973
```

To use another port:

如需修改端口：

```bash
OPENLOGTOOL_WEB_PORT=8080 docker compose up -d
```

For access from another machine, use an HTTPS reverse proxy. Rust WASM workers
require a secure browser context outside `localhost`.

从其他设备访问时请配置 HTTPS 反向代理；除 `localhost` 外，Rust WASM 工作线程
需要浏览器安全上下文。

If this WebClient and OpenLogToolServer use different origins, add the
WebClient origin to the server's `CORS_ORIGINS`, then recreate the server
container. Native clients do not require this setting.

如果 WebClient 与 OpenLogToolServer 使用不同 Origin，请将 WebClient Origin
加入服务端的 `CORS_ORIGINS`，随后重新创建服务端容器。原生客户端无需此设置。

```dotenv
CORS_ORIGINS=https://log.example.com
```
