# OpenLogTool - 业余无线电点名记录工具

一个专为业余无线电爱好者设计的点名记录工具，支持跨平台运行。

## ✨ 主要功能

### 📝 记录管理
- **快速添加记录**: 支持主控呼号、点名呼号、设备、天线、功率、QTH、高度、时间、信号报告等字段
- **智能表单**: 自动大写呼号，保留主控呼号不清空，支持词典自动补全
- **编辑功能**: 支持修改和删除已有记录
- **撤销操作**: 支持撤销上一条记录操作
- **统计信息**: 显示总记录数、今日记录、最近7天记录

### 📚 词典管理
- **设备词典**: 管理常用设备名称，支持自动补全
- **天线词典**: 管理常用天线名称，支持自动补全
- **呼号词典**: 管理常用呼号，支持自动补全
- **QTH词典**: 管理常用QTH位置，支持自动补全
- **自动添加**: 输入新设备/天线/呼号/QTH时自动添加到词典
- **导入导出**: 支持从文本文件导入词典

### 📊 数据导入导出
- **JSON导出**: 导出所有记录为JSON格式
- **Excel导出**: 导出为Excel文件，使用index.html中的样式
- **JSON导入**: 从JSON文件导入记录数据
- **Excel导入**: 从Excel文件导入记录数据（开发中）
- **PNG导出**: 导出表格为PNG图片（开发中）

### 🎨 个性化设置
- **主题颜色**: 支持自定义主题颜色，默认淡蓝色
- **暗色模式**: 支持暗色/亮色主题切换
- **宽屏布局**: 在窗口宽度足够时，将添加记录和已有记录并排显示
- **表格对齐**: 支持表格表头左对齐、居中对齐、右对齐
- **布局设置**: 可调整宽屏布局开关

### 📱 跨平台支持
- **Linux**: 原生支持Linux桌面应用
- **Windows**: 支持Windows桌面应用（需构建）
- **macOS**: 支持macOS桌面应用（需构建）
- **移动端**: 支持Android和iOS（需构建）

## 🚀 快速开始

### 环境要求
- Flutter SDK 3.0.0 或更高版本
- Dart SDK 3.0.0 或更高版本
- 支持的操作系统：Linux、Windows、macOS

### 安装步骤

1. **克隆仓库**
   ```bash
   git clone https://github.com/Mazha0309/BG5CRL-Log-tool.git
   cd BG5CRL-Log-tool
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **运行应用**
   ```bash
   # Linux
   ./build_all.sh linux
   ./build/linux/x64/release/bundle/openlogtool
   
   # 或直接运行
   flutter run -d linux
   ```

### 构建应用

```bash
# Linux
./build_all.sh linux

# Windows (需要Windows环境)
./build_all.sh windows

# macOS (需要macOS环境)
./build_all.sh macos
```

## 📁 项目结构

```
openlogtool/
├── lib/
│   ├── main.dart                    # 应用入口
│   ├── screens/
│   │   └── home_screen.dart         # 主界面
│   ├── widgets/
│   │   ├── log_form.dart            # 记录表单
│   │   ├── log_table.dart           # 记录表格
│   │   ├── dictionary_manager.dart  # 词典管理
│   │   ├── export_panel.dart        # 导入导出面板
│   │   └── settings_panel.dart      # 设置面板
│   ├── providers/
│   │   ├── log_provider.dart        # 记录数据管理
│   │   ├── dictionary_provider.dart # 词典数据管理
│   │   └── settings_provider.dart   # 设置管理
│   └── models/
│       └── log_entry.dart           # 记录数据模型
├── pubspec.yaml                     # 项目依赖配置
├── build_all.sh                     # 构建脚本
├── update_icons.sh                  # 图标更新脚本
└── README.md                        # 项目说明文档
```

## 🔧 技术栈

- **Flutter**: 跨平台UI框架
- **Dart**: 编程语言
- **Provider**: 状态管理
- **SharedPreferences**: 本地数据存储
- **Excel**: Excel文件操作
- **FilePicker**: 文件选择器
- **PathProvider**: 路径管理
- **OpenFile**: 文件打开工具

## 🎯 使用说明

### 添加记录
1. 在"添加记录"页面填写表单
2. 主控呼号为必填项
3. 其他字段可选，支持词典自动补全
4. 点击"添加记录"按钮保存

### 管理词典
1. 在"导入导出"页面找到词典管理
2. 点击展开相应词典
3. 输入新项目并点击添加
4. 或从文本文件导入（每行一个项目）

### 导入导出数据
1. 在"导入导出"页面选择相应功能
2. 导出JSON：导出所有记录为JSON文件
3. 导出Excel：导出为Excel文件，包含样式
4. 导入JSON：从JSON文件导入记录

### 个性化设置
1. 在"设置"页面调整应用设置
2. 选择主题颜色
3. 切换暗色/亮色模式
4. 调整布局和表格对齐方式

## 📄 许可证

本项目采用 GPL-3.0 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🤝 贡献

欢迎提交Issue和Pull Request！

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启一个 Pull Request

## 📞 联系方式

- **作者**: BG5CRL (Mazha0309)
- **GitHub**: [https://github.com/Mazha0309](https://github.com/Mazha0309)


## 🙏 致谢

感谢所有业余无线电爱好者的支持和建议！

---

**版本**: 1.0.0  
**最后更新**: 2026年3月16日  
**© 2026 BG5CRL**
