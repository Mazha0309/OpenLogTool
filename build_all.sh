#!/bin/bash

# 业余无线电点名记录工具 - 跨平台编译脚本
# 作者: Mazha0309 / BG5CRL

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查Flutter是否安装
check_flutter() {
    if ! command -v flutter &> /dev/null; then
        log_error "Flutter未安装！请先安装Flutter SDK。"
        log_info "安装指南: https://flutter.dev/docs/get-started/install"
        exit 1
    fi
    
    log_info "Flutter版本: $(flutter --version | head -1)"
}

# 清理项目
clean_project() {
    log_info "清理项目..."
    flutter clean
    log_success "项目清理完成"
}

# 获取依赖
get_dependencies() {
    log_info "获取依赖..."
    flutter pub get
    log_success "依赖获取完成"
}

# 检查代码
analyze_code() {
    log_info "分析代码..."
    flutter analyze
    log_success "代码分析完成"
}

# 构建Android APK
build_android_apk() {
    log_info "构建Android APK..."
    
    # 检查Android环境
    if ! flutter doctor | grep -q "Android toolchain"; then
        log_warning "Android开发环境未配置，跳过Android构建"
        return
    fi
    
    # 构建APK
    flutter build apk --release
    
    # 显示构建结果
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
    if [ -f "$APK_PATH" ]; then
        log_success "Android APK构建完成: $APK_PATH"
        log_info "文件大小: $(du -h "$APK_PATH" | cut -f1)"
    else
        log_error "Android APK构建失败"
    fi
}

# 构建Android App Bundle
build_android_bundle() {
    log_info "构建Android App Bundle..."
    
    # 检查Android环境
    if ! flutter doctor | grep -q "Android toolchain"; then
        log_warning "Android开发环境未配置，跳过Android Bundle构建"
        return
    fi
    
    # 构建App Bundle
    flutter build appbundle --release
    
    # 显示构建结果
    BUNDLE_PATH="build/app/outputs/bundle/release/app-release.aab"
    if [ -f "$BUNDLE_PATH" ]; then
        log_success "Android App Bundle构建完成: $BUNDLE_PATH"
        log_info "文件大小: $(du -h "$BUNDLE_PATH" | cut -f1)"
    else
        log_error "Android App Bundle构建失败"
    fi
}

# 构建Linux应用
build_linux() {
    log_info "构建Linux应用..."
    
    # 检查Linux桌面支持
    if ! flutter config | grep -q "enable-linux-desktop: true"; then
        log_warning "Linux桌面支持未启用，启用中..."
        flutter config --enable-linux-desktop
    fi
    
    # 构建Linux应用
    if flutter build linux --release 2>&1 | grep -q "Permission denied"; then
        log_warning "安装阶段权限被拒绝（正常现象，应用已构建成功）"
    fi
    
    # 显示构建结果
    LINUX_EXECUTABLE="build/linux/x64/release/intermediates_do_not_run/openlogtool"
    LINUX_DESKTOP="build/linux/x64/release/openlogtool.desktop"
    
    if [ -f "$LINUX_EXECUTABLE" ]; then
        log_success "Linux应用构建完成"
        log_info "可执行文件: $LINUX_EXECUTABLE"
        log_info "文件大小: $(du -h "$LINUX_EXECUTABLE" | cut -f1)"
        
        # 检查桌面文件
        if [ -f "$LINUX_DESKTOP" ]; then
            log_info "桌面文件: $LINUX_DESKTOP"
        fi
        
        # 复制到bundle目录以便使用
        mkdir -p build/linux/x64/release/bundle
        cp "$LINUX_EXECUTABLE" build/linux/x64/release/bundle/
        if [ -f "$LINUX_DESKTOP" ]; then
            cp "$LINUX_DESKTOP" build/linux/x64/release/bundle/
        fi
        
        log_info "应用已复制到: build/linux/x64/release/bundle/"
        ls -la build/linux/x64/release/bundle/
    else
        log_error "Linux应用构建失败"
    fi
}

# 构建Windows应用
build_windows() {
    log_info "构建Windows应用..."
    
    # 检查Windows桌面支持
    if ! flutter config | grep -q "enable-windows-desktop: true"; then
        log_warning "Windows桌面支持未启用，启用中..."
        flutter config --enable-windows-desktop
    fi
    
    # 构建Windows应用
    flutter build windows --release
    
    # 显示构建结果
    WINDOWS_DIR="build/windows/runner/Release"
    if [ -d "$WINDOWS_DIR" ]; then
        log_success "Windows应用构建完成: $WINDOWS_DIR"
        log_info "目录内容:"
        ls -la "$WINDOWS_DIR/"
    else
        log_error "Windows应用构建失败"
    fi
}

# 构建macOS应用
build_macos() {
    log_info "构建macOS应用..."
    
    # 检查macOS桌面支持
    if ! flutter config | grep -q "enable-macos-desktop: true"; then
        log_warning "macOS桌面支持未启用，启用中..."
        flutter config --enable-macos-desktop
    fi
    
    # 构建macOS应用
    flutter build macos --release
    
    # 显示构建结果
    MACOS_DIR="build/macos/Build/Products/Release"
    if [ -d "$MACOS_DIR" ]; then
        log_success "macOS应用构建完成: $MACOS_DIR"
        log_info "目录内容:"
        ls -la "$MACOS_DIR/"
    else
        log_error "macOS应用构建失败"
    fi
}

# 构建Web应用
build_web() {
    log_info "构建Web应用..."
    
    # 构建Web应用
    flutter build web --release
    
    # 显示构建结果
    WEB_DIR="build/web"
    if [ -d "$WEB_DIR" ]; then
        log_success "Web应用构建完成: $WEB_DIR"
        log_info "目录大小: $(du -sh "$WEB_DIR" | cut -f1)"
        
        # 创建简单的启动脚本
        cat > "$WEB_DIR/start_server.sh" << 'EOF'
#!/bin/bash
# 简单的HTTP服务器启动脚本
PORT=8080
echo "在 http://localhost:$PORT 启动Web服务器..."
python3 -m http.server $PORT
EOF
        chmod +x "$WEB_DIR/start_server.sh"
        log_info "已创建启动脚本: $WEB_DIR/start_server.sh"
    else
        log_error "Web应用构建失败"
    fi
}

# 显示帮助信息
show_help() {
    echo "业余无线电点名记录工具 - 跨平台编译脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  all         构建所有平台（默认）"
    echo "  android     构建Android应用（APK和App Bundle）"
    echo "  linux       构建Linux应用"
    echo "  windows     构建Windows应用"
    echo "  macos       构建macOS应用"
    echo "  web         构建Web应用"
    echo "  clean       清理项目"
    echo "  deps        获取依赖"
    echo "  analyze     分析代码"
    echo "  help        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 all        # 构建所有平台"
    echo "  $0 android    # 只构建Android应用"
    echo "  $0 linux      # 只构建Linux应用"
}

# 主函数
main() {
    log_info "开始构建业余无线电点名记录工具..."
    log_info "当前目录: $(pwd)"
    
    # 检查Flutter
    check_flutter
    
    # 处理参数
    if [ $# -eq 0 ]; then
        TARGET="all"
    else
        TARGET="$1"
    fi
    
    case "$TARGET" in
        "all")
            clean_project
            get_dependencies
            analyze_code
            build_android_apk
            build_android_bundle
            build_linux
            build_windows
            build_macos
            build_web
            ;;
        "android")
            clean_project
            get_dependencies
            build_android_apk
            build_android_bundle
            ;;
        "linux")
            clean_project
            get_dependencies
            build_linux
            ;;
        "windows")
            clean_project
            get_dependencies
            build_windows
            ;;
        "macos")
            clean_project
            get_dependencies
            build_macos
            ;;
        "web")
            clean_project
            get_dependencies
            build_web
            ;;
        "clean")
            clean_project
            ;;
        "deps")
            get_dependencies
            ;;
        "analyze")
            analyze_code
            ;;
        "help"|"-h"|"--help")
            show_help
            exit 0
            ;;
        *)
            log_error "未知选项: $TARGET"
            show_help
            exit 1
            ;;
    esac
    
    log_success "构建完成！"
    log_info "构建时间: $(date)"
}

# 运行主函数
main "$@"