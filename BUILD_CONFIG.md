# 构建配置说明

本文档详细说明业余无线电点名记录工具的构建配置和跨平台打包方法。

## 许可证

本项目采用 **GNU General Public License v3 (GPL-3.0-or-later)** 许可证。所有分发版本必须包含完整的许可证文本和源代码。

## 构建要求

### 基础要求
- Flutter SDK 3.0+
- Dart SDK 3.0+
- Git

### 平台特定要求

#### Android
- Android Studio 或 Android SDK
- Java JDK 11+
- Gradle 7.0+

#### Linux
- CMake 3.10+
- GTK 3.0+
- GCC/G++ 9.0+
- appimagetool (用于创建AppImage)

#### Windows
- Visual Studio 2019+ 或 MSBuild
- Windows 10 SDK

#### macOS
- Xcode 12+
- macOS 10.15+

## 构建配置

### 1. Android 配置

#### 应用ID
```
com.mazha0309.openlogtool
```

#### 架构支持
- armeabi-v7a (32位ARM)
- arm64-v8a (64位ARM)
- x86 (32位Intel)
- x86_64 (64位Intel)

#### 构建类型
- **Debug**: 调试版本，包含调试符号
- **Release**: 发布版本，代码优化和混淆
- **Profile**: 性能分析版本

#### 签名配置
发布版本需要配置签名：
1. 创建密钥库：
   ```bash
   keytool -genkey -v -keystore keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias openlogtool
   ```
2. 设置环境变量：
   ```bash
   export KEYSTORE_PASSWORD=your_password
   export KEY_ALIAS=openlogtool
   export KEY_PASSWORD=your_password
   ```

### 2. Linux 配置

#### 架构支持
- x86_64 (amd64)
- aarch64 (arm64)

#### 打包格式
1. **AppImage**: 便携式应用包
2. **tar.gz**: 源代码和二进制包
3. **deb/rpm**: 系统包（需要额外配置）

#### 桌面集成
- `.desktop` 文件：桌面快捷方式
- 图标：256x256 PNG格式
- 元数据：AppStream元数据

### 3. Windows 配置

#### 架构支持
- x86 (32位)
- x64 (64位)

#### 构建工具
- MSBuild (Visual Studio)
- Flutter Windows工具链

### 4. macOS 配置

#### 架构支持
- x86_64 (Intel)
- arm64 (Apple Silicon)

#### 代码签名
需要Apple开发者账号进行代码签名。

## 构建命令

### 使用构建脚本
```bash
# 一键构建所有平台
./build_all.sh all

# 构建特定平台
./build_all.sh android
./build_all.sh linux
./build_all.sh windows
./build_all.sh macos
./build_all.sh web

# 其他命令
./build_all.sh clean    # 清理项目
./build_all.sh deps     # 获取依赖
./build_all.sh analyze  # 代码分析
```

### 手动构建命令

#### Android
```bash
# 调试版本
flutter build apk --debug

# 发布版本
flutter build apk --release

# App Bundle
flutter build appbundle --release

# 特定架构
flutter build apk --release --target-platform android-arm64
```

#### Linux
```bash
# 启用Linux桌面支持
flutter config --enable-linux-desktop

# 构建Linux应用
flutter build linux --release

# 调试版本
flutter build linux --debug
```

#### Windows
```bash
# 启用Windows桌面支持
flutter config --enable-windows-desktop

# 构建Windows应用
flutter build windows --release
```

#### macOS
```bash
# 启用macOS桌面支持
flutter config --enable-macos-desktop

# 构建macOS应用
flutter build macos --release
```

#### Web
```bash
# 构建Web应用
flutter build web --release

# 指定基础路径
flutter build web --release --base-href /openlogtool/
```

## 多架构构建

### Android 多架构
```bash
# 构建所有支持的架构
flutter build apk --release --split-per-abi

# 输出文件：
# app-armeabi-v7a-release.apk
# app-arm64-v8a-release.apk  
# app-x86_64-release.apk
```

### Linux 多架构
需要在对应架构的系统上构建，或使用交叉编译。

## 优化配置

### 代码压缩和混淆 (Android)
在 `android/app/build.gradle` 中配置：
```gradle
buildTypes {
    release {
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
    }
}
```

### 资源优化
```bash
# 压缩图片资源
flutter pub run flutter_native_splash:create
flutter pub run flutter_launcher_icons:main
```

## 发布检查清单

### 通用检查项
- [ ] 更新版本号 (`pubspec.yaml`)
- [ ] 更新CHANGELOG.md
- [ ] 测试所有平台功能
- [ ] 验证许可证文件
- [ ] 检查依赖许可证

### Android 检查项
- [ ] 配置发布签名
- [ ] 测试不同屏幕尺寸
- [ ] 验证权限配置
- [ ] 检查ProGuard规则

### Linux 检查项
- [ ] 验证桌面集成
- [ ] 测试AppImage运行
- [ ] 检查依赖库
- [ ] 验证图标显示

### Windows 检查项
- [ ] 测试安装和卸载
- [ ] 验证注册表项
- [ ] 检查快捷方式

### macOS 检查项
- [ ] 代码签名
- [ ] 公证 (Notarization)
- [ ] 测试沙盒运行

## 故障排除

### 常见问题

#### 1. Flutter命令找不到
```bash
# 检查Flutter安装
flutter doctor

# 添加Flutter到PATH
export PATH="$PATH:/path/to/flutter/bin"
```

#### 2. 依赖安装失败
```bash
# 使用国内镜像
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# 清理并重试
flutter clean
flutter pub get
```

#### 3. 构建失败
```bash
# 查看详细日志
flutter build apk --release --verbose

# 清理构建缓存
flutter clean
rm -rf build/
```

#### 4. 多架构问题
```bash
# 检查支持的架构
flutter doctor -v

# 安装缺失的工具链
sudo apt-get install gcc-aarch64-linux-gnu  # Linux交叉编译
```

## 持续集成

### GitHub Actions 示例
```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.0.0'
          
      - name: Build Android
        run: flutter build apk --release
        
      - name: Build Linux
        run: flutter build linux --release
        
      - name: Upload Artifacts
        uses: actions/upload-artifact@v3
        with:
          name: releases
          path: build/
```

## 更新日志

### 版本 1.0.0
- 初始发布版本
- 支持Android、Linux、Windows、macOS、Web
- 多架构支持 (x86_64, aarch64)
- GPL-3.0许可证

## 支持与贡献

如有问题或建议，请通过以下方式联系：
- GitHub Issues: https://www.github.com/mazha0309/openlogtool

欢迎提交Pull Request和Issue报告。