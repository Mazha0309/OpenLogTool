#!/bin/bash

# 业余无线电点名记录工具 - 图标更新脚本
# 将根目录的icon.png复制到各个平台的图标位置

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

# 检查icon.png是否存在
check_icon() {
    if [ ! -f "icon.png" ]; then
        log_error "icon.png不存在于项目根目录"
        log_info "请将icon.png文件放在项目根目录"
        exit 1
    fi
    
    log_info "找到图标文件: icon.png"
    log_info "文件大小: $(du -h icon.png | cut -f1)"
}

# 为Linux平台设置图标
setup_linux_icon() {
    log_info "设置Linux应用图标..."
    
    # 创建Linux图标目录
    mkdir -p linux/runner/resources
    
    # 复制图标到Linux目录
    cp icon.png linux/runner/resources/icon.png
    
    # 创建Linux桌面文件
    cat > linux/runner/openlogtool.desktop << 'EOF'
[Desktop Entry]
Name=业余无线电点名记录工具
Comment=业余无线电点名记录工具 - Flutter版本
Exec=openlogtool
Icon=icon
Terminal=false
Type=Application
Categories=Utility;
Keywords=radio;ham;log;记录;
EOF
    
    log_success "Linux图标设置完成"
}

# 为Windows平台设置图标
setup_windows_icon() {
    log_info "设置Windows应用图标..."
    
    # 创建Windows图标目录
    mkdir -p windows/runner/resources
    
    # 复制图标到Windows目录
    cp icon.png windows/runner/resources/app_icon.ico 2>/dev/null || {
        log_warning "无法直接复制为.ico格式，Windows需要.ico格式图标"
        log_info "请使用工具将icon.png转换为app_icon.ico并放在windows/runner/resources/目录"
    }
    
    log_success "Windows图标设置完成（需要手动转换为.ico格式）"
}

# 为macOS平台设置图标
setup_macos_icon() {
    log_info "设置macOS应用图标..."
    
    # 创建macOS图标目录
    mkdir -p macos/Runner/Assets.xcassets/AppIcon.appiconset
    
    log_warning "macOS需要.icns格式图标和多种尺寸"
    log_info "请使用以下命令创建macOS图标："
    echo "  sips -z 16 16 icon.png --out macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png"
    echo "  sips -z 32 32 icon.png --out macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png"
    echo "  sips -z 64 64 icon.png --out macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png"
    echo "  sips -z 128 128 icon.png --out macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png"
    echo "  sips -z 256 256 icon.png --out macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png"
    echo "  sips -z 512 512 icon.png --out macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"
    echo "  sips -z 1024 1024 icon.png --out macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
    
    log_success "macOS图标设置说明已提供"
}

# 为Web平台设置图标
setup_web_icon() {
    log_info "设置Web应用图标..."
    
    # 创建Web图标目录
    mkdir -p web/icons
    
    # 复制图标到Web目录
    cp icon.png web/icons/icon-192.png
    cp icon.png web/icons/icon-512.png
    
    log_info "Web图标已复制，但建议为Web优化图标尺寸"
    log_info "建议创建以下尺寸的图标："
    echo "  - 192x192 (icon-192.png)"
    echo "  - 512x512 (icon-512.png)"
    
    log_success "Web图标设置完成"
}

# 更新pubspec.yaml中的图标配置
update_pubspec() {
    log_info "更新pubspec.yaml图标配置..."
    
    # 检查是否已存在flutter配置
    if grep -q "flutter:" pubspec.yaml; then
        if ! grep -q "  assets:" pubspec.yaml; then
            # 在flutter:部分添加assets配置
            sed -i '/flutter:/a\  assets:\n    - icon.png' pubspec.yaml
            log_success "已添加图标到assets"
        else
            log_info "assets配置已存在，跳过"
        fi
    else
        log_warning "pubspec.yaml中没有flutter配置部分"
    fi
}

# 主函数
main() {
    log_info "开始更新应用图标..."
    
    # 检查图标文件
    check_icon
    
    # 设置各平台图标
    setup_linux_icon
    setup_windows_icon
    setup_macos_icon
    setup_web_icon
    
    # 更新pubspec配置
    update_pubspec
    
    log_success "图标更新完成！"
    log_info "各平台图标位置："
    log_info "  - Linux: linux/runner/resources/icon.png"
    log_info "  - Windows: windows/runner/resources/app_icon.ico (需要转换)"
    log_info "  - macOS: 需要手动创建多种尺寸"
    log_info "  - Web: web/icons/icon-192.png, web/icons/icon-512.png"
    log_info "  - Android: 使用默认mipmap图标"
    log_info ""
    log_info "下一步："
    log_info "1. 为Windows转换icon.png为.ico格式"
    log_info "2. 为macOS创建多种尺寸的图标"
    log_info "3. 运行构建脚本测试所有平台"
}

# 运行主函数
main "$@"