# DualMic

**DualMic** 是一款 macOS 应用，可同时录制**麦克风**和**系统声音**，并将两路音频混合导出为 `.m4a` 文件。

下载安装链接：https://github.com/askfanxiaojun/DualMic/releases

---

## 为什么做这个

找工作面试的时候，我希望把整个面试过程录下来，方便事后复盘——对方问了什么、自己答得怎么样，都能回溯分析。

但问题来了：**视频面试时通常戴着耳机**。这种情况下，Mac 自带录音或飞书文档的录音功能，只能录到自己说话的声音，对方的声音走的是系统音频，根本录不进去。录完一听，只有自己的独白，完全没有意义。

找了一圈市面上的方案：

- **钉钉**：有双轨录制能力，但每月有免费额度限制，用完就没了
- **其他方案**：需要下一堆软件，配置复杂，门槛很高

索性自己动手，把需求描述清楚交给 Cursor，很快就做出了这款 App。这也是我第一次做 macOS App，说实话还挺有成就感的。虽然界面简陋，但完全可用，效果也不错。

现在把它开源出来，**有面试录音需求的同学可以直接下载使用，希望大家都能拿到满意的 Offer。**

<img src="https://github.com/askfanxiaojun/picx-images-hosting/raw/master/20260312/CleanShot-2026-03-12-at-11.35.34@2x.mmmx1ufe.png" width="520" />

---

## 功能特性

- 🎙️ **双轨录制**：同时捕获麦克风输入与系统内部声音
- ⏸️ **暂停 / 继续**：支持录制中途暂停，继续后无缝衔接，不产生时间断层
- 📊 **实时电平表**：分别显示麦克风和系统声音的实时音量，直观掌握录音状态
- 🎛️ **多设备切换**：有多个麦克风时，可在录制前自由选择输入设备
- 🔊 **系统声音可选**：可单独关闭系统声音，仅录制麦克风
- 🖥️ **菜单栏模式**：可切换到菜单栏图标模式，隐藏 Dock 图标，轻量常驻后台
- 💾 **本地导出**：录制完成后通过系统存储面板自由指定保存位置，输出 AAC 编码的 `.m4a` 文件

---

## 界面预览

| 主窗口 | 菜单栏模式 |
|--------|-----------|
| ![主窗口](https://github.com/askfanxiaojun/picx-images-hosting/raw/master/20260312/CleanShot-2026-03-12-at-11.35.34@2x.mmmx1ufe.png) | ![菜单栏模式](https://github.com/askfanxiaojun/picx-images-hosting/raw/master/20260312/CleanShot-2026-03-12-at-11.40.28@2x.73ui2jd0uq.png) |

| 录制中 | 录制完成 |
|--------|---------|
| ![录制中](https://github.com/askfanxiaojun/picx-images-hosting/raw/master/20260312/CleanShot-2026-03-12-at-11.43.32@2x.77e4099oeg.png) | ![录制完成](https://github.com/askfanxiaojun/picx-images-hosting/raw/master/20260312/CleanShot-2026-03-12-at-11.43.53@2x.2yywqfjyzo.png) |

---

## 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Apple Silicon 或 Intel Mac

---

## 安装

### 方式一：直接下载（推荐）

前往 [Releases](https://github.com/askfanxiaojun/DualMic/releases) 页面，下载最新版本的 `DualMic.app`，拖入 `/Applications` 即可使用。

### 方式二：自行编译

**环境要求**：Xcode 16 或更高版本

```bash
# 克隆仓库
git clone https://github.com/askfanxiaojun/DualMic.git
cd DualMic

# 使用构建脚本（Release 模式，可选择是否自动安装到 /Applications）
./build.sh
```

或直接用 Xcode 打开 `DualMic.xcodeproj`，选择你的开发团队后运行即可。

> **注意**：首次编译需要在 Xcode 中 `Signing & Capabilities` 处填写你自己的 Apple Developer Team，代码签名是 macOS TCC 权限（麦克风、屏幕录制）正常工作的前提。

---

## 使用方法

### 第一步：授权权限

首次启动时，应用会请求以下两项权限：

| 权限 | 用途 |
|------|------|
| **麦克风** | 录制麦克风声音 |
| **屏幕录制** | 通过 ScreenCaptureKit 捕获系统内部声音 |

点击界面顶部的授权按钮，或前往 **系统设置 → 隐私与安全性** 手动授权。


### 第二步：开始录制

1. 确认界面顶部两个权限标志均为绿色
2. 如有多个麦克风，在电平表下方的下拉菜单中选择输入设备
3. 如需录制系统声音，确保"系统声音"电平行处于开启状态（点击标签可切换）
4. 点击**红色圆形按钮**开始录制

### 第三步：暂停 / 停止

- 点击**橙色暂停按钮**可暂停录制，再次点击继续
- 点击**方形停止按钮**结束录制，应用将自动混合两路音频并导出

### 第四步：保存文件

录制完成后，底部会出现文件操作栏：

- **在 Finder 中显示**：打开临时目录定位文件
- **存储...**：通过系统存储面板选择保存位置，文件格式为 `.m4a`（AAC 192kbps）

### 菜单栏模式

点击界面底部的**菜单栏模式**开关，应用将隐藏 Dock 图标，通过顶部菜单栏图标进行操作，适合长时间后台录制场景。

---
## 安装报错

Mac 提示“已损坏，无法打开。您应该将它移到废纸篓”，通常是由于 macOS 系统安全机制拦截了未签名或第三方应用。最有效的解决方法是使用终端命令清除应用的隔离属性。

**核心解决步骤（终端操作）**：
- 打开终端 (Terminal)。
- 输入命令：sudo xattr -r -d com.apple.quarantine
- 在命令末尾输入一个空格。
- 将应用程序（.app）从“应用程序”文件夹中拖入终端窗口。
- 按下回车键，输入你的电脑开机密码（输入时不会显示）再按回车。 

**其他解决方法**：
- 开启任何来源：在终端输入 sudo spctl --master-disable，然后在“系统设置”的“隐私与安全性”中勾选“任何来源”。
- 尝试右键打开：在访达中右键点击该软件，选择“打开”来绕过安全限制。


## 技术实现

| 模块 | 技术方案 |
|------|---------|
| 麦克风录制 | `AVAudioEngine` + `installTap` |
| 系统声音捕获 | `ScreenCaptureKit`（`SCStream` 音频输出） |
| 音频混合导出 | `AVAudioEngine` 离线渲染模式（Offline Manual Rendering） |
| UI 框架 | SwiftUI |
| 状态管理 | `@Observable` 宏 |

---

## License

MIT License. 详见 [LICENSE](LICENSE) 文件。
