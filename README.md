# OpenLogTool - 业余无线电点名记录工具

专为业余无线电爱好者设计的点名记录工具，支持跨平台运行。

## 功能

### 记录管理
- 快速添加记录：支持主控呼号、点名呼号、设备、天线、功率、QTH、高度、时间、信号报告等字段
- 智能表单：自动大写呼号，保留主控呼号，支持词典自动补全
- 编辑和删除记录
- 撤销上一条记录
- 统计信息：总记录数、今日记录、最近7天记录

### 词典管理
- 设备、天线、呼号、QTH词典管理
- 支持自动补全
- 输入新内容时自动添加到词典
- 支持从文本文件导入

### 数据导入导出
- JSON导出/导入
- Excel导出（开发中）
- PNG导出（开发中）

### 主题设置
- 自定义主题颜色
- 暗色/亮色模式
- 宽屏布局开关

### 跨平台
- Linux（已支持）
- Windows（需构建）
- macOS（需构建）
- Android（需构建）

## 开始使用

### 环境要求
- Flutter SDK 3.0.0+
- Dart SDK 3.0.0+

### 构建

```bash
git clone https://github.com/Mazha0309/OpenLogTool.git
cd OpenLogTool
flutter pub get
flutter build linux
```

### 项目结构

```
lib/
├── main.dart                    # 入口
├── screens/
│   └── home_screen.dart         # 主界面
├── widgets/
│   ├── log_form.dart            # 记录表单
│   ├── log_table.dart           # 记录表格
│   ├── dictionary_manager.dart  # 词典管理
│   ├── export_panel.dart        # 导入导出
│   └── settings_panel.dart      # 设置
├── providers/
│   ├── log_provider.dart        # 记录数据
│   ├── dictionary_provider.dart # 词典数据
│   └── settings_provider.dart   # 设置
└── models/
    └── log_entry.dart           # 记录模型
```

## 技术栈

- Flutter
- Provider（状态管理）
- sqflite（数据库）
- Excel（导出）

## License

GPL-3.0

## 联系方式

GitHub: https://github.com/Mazha0309
