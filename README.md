<h1 align="center">
  <img src="https://github.com/charlessnow/ClashX/raw/master/clashx.png" alt="Clash" width="200">
  <br>
  ClashX
  <br>
</h1>

<div align="center">

[English](README.md) | [简体中文](README_zh-CN.md)

</div>

## ⚠️ Notice

This project is based on code originally created by [yichengchen](https://github.com/yichengchen). I discovered that the original version was not compatible with macOS 26 (Sequoia), so I modified the code to make it work on macOS 26. The source code was forked from [bannedbook/ClashX](https://github.com/bannedbook/ClashX). The git history was lost because I accidentally deleted the `.git` folder when recreating the project after encountering some issues.

---

## 🌐 Official Website

**Official Website**: [https://clashx.tech](https://clashx.tech)

- 📥 [Download Latest Version](https://clashx.tech/download)
- 📖 [Documentation & Tutorial](https://clashx.tech/tutorial)
- ❓ [FAQ](https://clashx.tech/tutorial#faq)
- 🚀 **Next-Gen Client**: [ClashFX](https://clashfx.com) — A modern macOS proxy client with advanced features

---

## 🚀 Need Advanced Features? Try ClashFX

ClashX focuses on a simple, lightweight, and compatible macOS proxy experience. If you need more advanced capabilities, we recommend migrating to [ClashFX](https://github.com/Clash-FX/ClashFX), our next-generation macOS client built around the mihomo core.

ClashFX includes advanced features such as:

- **Enhanced Mode (TUN)** for system-wide TCP/UDP traffic capture
- Support for newer proxy protocols and mihomo core capabilities
- Rule-based routing with domain, IP-CIDR, GeoIP, and process matching
- Fake-IP DNS mode and gVisor userspace network stack
- Built-in dashboard and a more complete modern macOS experience

Download ClashFX from [GitHub Releases](https://github.com/Clash-FX/ClashFX/releases) or the official website: [https://clashfx.com](https://clashfx.com).

---

A rule-based proxy client for macOS based on Clash.

ClashX aims to provide a simple and lightweight proxy client with an intuitive interface.

## ⚠️ Notice

- **Official Website**: Please visit the official website at **clashx.tech**.
- ClashX / ClashX Pro is only a proxy tool and does not provide any proxy servers. For server-related issues or renewals, please contact your service provider.

## ✨ Features

- HTTP/HTTPS and SOCKS protocol support
- Surge-like configuration
- GeoIP rule support
- Support for Vmess/Shadowsocks/Socks5/Trojan protocols
- Netfilter TCP redirect support
- macOS 10.14+ compatibility
- **macOS 15+ (Sequoia) support with compatibility fixes**

## 📥 Installation

Download ClashX from the [Releases](https://github.com/charlessnow/ClashX/releases) page.

For Enhanced Mode (TUN), newer protocol support, and other advanced capabilities, use [ClashFX](https://github.com/Clash-FX/ClashFX).

## 🔨 Build from Source

### Prerequisites

- macOS 10.14 or later
- Xcode 15.0+
- Python 3
- Golang 1.21+

### Build Steps

1. **Install Golang**
   ```bash
   brew install golang
   # or download from https://golang.org
   ```

2. **Install dependencies**
   ```bash
   bash install_dependency.sh
   ```

3. **Open and build**
   ```bash
   open ClashX.xcworkspace
   # Build in Xcode (Cmd+R)
   ```

## ⚙️ Configuration

### Default Paths

The default configuration directory is `$HOME/.config/clash`

The default configuration file name is `config.yaml`. You can use custom config names and switch between them in the `Config` menu.

For more details, check out [SS-Rule-Snippet for Clash](https://github.com/Hackl0us/SS-Rule-Snippet/blob/master/LAZY_RULES/clash.yaml).

## 🔧 Advanced Configuration

### Change Proxy Port

Go to Menu Bar → Config → More Settings and modify the corresponding port numbers.

### Customize Status Menu Icon

Place your icon file at `~/.config/clash/menuImage.png`, then restart ClashX.

### Change Default System Ignore List

Navigate to Menu → Config → Settings → Bypass proxy settings for these Hosts & Domains.

### URL Schemes

- **Import remote config:**
  ```
  clash://install-config?url=http%3A%2F%2Fexample.com&name=example
  ```

- **Reload current config:**
  ```
  clash://update-config
  ```

### Get Process Name

Add the following to your config file and set proxy mode to rule. View logs via the Help menu:

```yaml
script:
  code: |
    def main(ctx, metadata):
      # Log ProcessName
      ctx.log('Process Name: ' + ctx.resolve_process_name(metadata))
      return 'DIRECT'
```

### Disable Notifications

1. Go to System Settings and disable ClashX notification permissions
2. Enable "Reduce Notifications" in Menu Bar → Config → More Settings

**Note:** Not recommended as you may miss important error notifications.

### Global Shortcuts

- Customize shortcuts in Menu Bar → Config → More Settings (requires v1.116.1+)
- Or use AppleScript - see [Shortcuts Guide](Shortcuts.md)

## ❓ FAQ

**Q: How to get shell commands with external IP?**
A: Click the ClashX menu icon and press `Option-Command-C`

## 🤝 Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## 📄 License

See [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

Based on the original ClashX project.
