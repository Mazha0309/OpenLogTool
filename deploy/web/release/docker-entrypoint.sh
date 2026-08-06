#!/bin/sh
set -e

# 把部署注入的默认服务器地址写进 index.html（替换占位符）。
# APP_DEFAULT_SERVER_URL 为空时占位符保持不变，Flutter 侧会忽略。
sed -i "s|__APP_DEFAULT_SERVER_URL__|${APP_DEFAULT_SERVER_URL:-}|g" \
  /usr/share/nginx/html/index.html

exec nginx -g 'daemon off;'
