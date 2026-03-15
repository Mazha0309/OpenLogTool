# 业余无线电点名记录工具 - Flutter版本

这是一个使用Flutter框架重构的业余无线电点名记录工具，支持跨平台运行（Windows、macOS、Linux、Android）。

## 功能特性

- 📝 **点名记录管理**：添加、编辑、删除、撤销点名记录
- 📚 **智能词库**：设备、天线、呼号、QTH词典管理，支持自动补全
- 🎨 **主题切换**：亮色/暗色模式，自动保存偏好设置
- 📊 **数据表格**：清晰展示所有点名记录
- 📁 **导入导出**：支持JSON格式导入导出，Excel导出（需安装excel包）
- 💾 **本地存储**：所有数据自动保存在本地
- 🌐 **跨平台**：支持Windows、macOS、Linux、Android

## 项目结构

```
openlogtool/
├── lib/
│   ├── main.dart                    # 应用入口
│   ├── models/
│   │   └── log_entry.dart           # 数据模型
│   ├── providers/
│   │   ├── theme_provider.dart      # 主题管理
│   │   ├── log_provider.dart        # 日志管理
│   │   └── dictionary_provider.dart # 词典管理
│   ├── screens/
│   │   └── home_screen.dart         # 主界面
│   └── widgets/
│       ├── log_form.dart            # 表单组件
│       ├── log_table.dart           # 表格组件
│       ├── dictionary_manager.dart  # 词库管理器
│       └── export_panel.dart        # 导出面板
├── pubspec.yaml                     # 依赖配置
└── README.md                        # 说明文档
```

## 安装和运行

### 前提条件

1. 安装 [Flutter SDK](https://flutter.dev/docs/get-started/install)
2. 安装 [Dart SDK](https://dart.dev/get-dart)
3. 配置开发环境（Android Studio / VS Code）

### 安装步骤

1. 克隆项目或下载源代码
2. 进入项目目录：
   ```bash
   cd openlogtool
   ```

3. 安装依赖：
   ```bash
   flutter pub get
   ```

4. 运行应用：

   **桌面平台（Linux/macOS/Windows）：**
   ```bash
   flutter run -d linux   # Linux
   flutter run -d macos   # macOS
   flutter run -d windows # Windows
   ```

   **Android：**
   ```bash
   flutter run -d android
   ```

   **Web：**
   ```bash
   flutter run -d chrome
   ```

## 编译打包

### Android APK
```bash
flutter build apk --release
```

### Android App Bundle
```bash
flutter build appbundle --release
```

### Linux AppImage
```bash
flutter build linux --release
# 生成的AppImage文件在 build/linux/x64/release/bundle/
```

### Windows
```bash
flutter build windows --release
```

### macOS
```bash
flutter build macos --release
```

## 依赖包

- `provider`: 状态管理
- `shared_preferences`: 本地存储
- `file_picker`: 文件选择
- `path_provider`: 路径获取
- `open_file`: 打开文件
- `excel`: Excel文件操作（可选）
- `flutter_svg`: SVG图标支持
- `intl`: 国际化支持

## 开发说明

### 添加新功能

1. 在 `lib/models/` 中添加数据模型
2. 在 `lib/providers/` 中添加状态管理
3. 在 `lib/widgets/` 中添加UI组件
4. 在 `lib/screens/` 中添加页面

### 主题定制

修改 `lib/providers/theme_provider.dart` 中的主题配置，或调整 `lib/main.dart` 中的主题定义。

### 数据持久化

所有数据使用 `shared_preferences` 存储在本地，支持跨会话保存。

## 故障排除

### 常见问题

1. **Flutter命令找不到**
   - 确保Flutter SDK已正确安装并添加到PATH
   - 运行 `flutter doctor` 检查环境

2. **依赖安装失败**
   - 检查网络连接
   - 尝试使用国内镜像源

3. **编译错误**
   - 运行 `flutter clean` 清理缓存
   - 运行 `flutter pub get` 重新获取依赖

### 调试

- 使用 `flutter run --verbose` 查看详细日志
- 使用 `flutter analyze` 检查代码问题
- 使用 `flutter test` 运行测试

## 贡献指南

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 作者

- **Mazha0309 / BG5CRL**
- GitHub: [@Mazha0309](https://github.com/Mazha0309)
- Gitee: [@Mazha0309](https://gitee.com/Mazha0309)
- GitCode: [@Mazha0309](https://gitcode.com/Mazha0309)

## 致谢

感谢所有业余无线电爱好者的支持和建议！

---

**注意**：这是一个开源项目，欢迎任何形式的贡献和反馈。如果您在使用过程中遇到问题或有改进建议，请提交Issue或Pull Request。