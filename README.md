```markdown
# 🔥 Phone Gateway Controller v2.0

**Full Android device control via web interface — no root, no Telegram, pure freedom.**

Powered by Shizuku + Termux + Pollinations AI

---

## ✨ Features

- 🌐 **Web Gateway Interface** — Control from any device on same network
- 🧠 **Pollinations AI** — Unlimited free AI chat
- 🔍 **Free Web Search** — No API keys required
- 📱 **50+ Commands** — Complete phone control + troll tools
- 🔒 **No Root Required** — Uses Shizuku for system-level access
- 🔑 **Auto-generated Access Key** — Secure by default
- ⚡ **One-Command Install** — Everything sets up automatically

---

## 📋 Requirements

| Requirement | Details |
|---|---|
| **Android Version** | Android 11+ |
| **Shizuku** | [Download from F-Droid](https://f-droid.org/packages/moe.shizuku.privileged.api/) |
| **Termux** | [Download from F-Droid](https://f-droid.org/en/packages/com.termux/) |
| **Network** | WiFi or mobile data for AI/search features |

⚠️ **Important:** Do NOT use Termux from Play Store — it's outdated and broken.

---

## 🚀 Quick Install

### Step 1 — Enable Developer Options
```
Settings → About Phone → Tap "Build Number" 7 times
Settings → System → Developer Options → Enable "Wireless Debugging"
```

### Step 2 — Setup Shizuku
1. Open Shizuku app
2. Tap "Pairing" under Wireless Debugging
3. In phone settings, go to Developer Options → Wireless Debugging → "Pair device with pairing code"
4. Enter the 6-digit code shown in Shizuku
5. Tap "Start" in Shizuku until status shows "Shizuku is running"
6. Tap "Use Shizuku in terminal apps"
7. Tap "Export files"
8. Create folder named exactly `Shizuku` in internal storage
9. Select this folder and confirm

### Step 3 — Run Installer
Open Termux and paste this single command:
```bash
curl -sL https://raw.githubusercontent.com/OpenKlaw/main/install.sh | bash
```

The installer will:
- Update Termux packages
- Install Node.js and dependencies
- Configure Shizuku integration
- Create web gateway interface
- Generate secure access key

### Step 4 — Start Gateway
```bash
cd ~/phonegate
./start.sh
```

You'll see:
```
🌐 Gateway running on port 3000
🔑 Access key: [your-auto-generated-key]
📱 Connect via: http://192.168.x.x:3000
```

### Step 5 — Connect & Control
1. Enable hotspot on your phone (optional)
2. Connect other devices to same network
3. Open browser on any device
4. Enter the IP address shown in terminal
5. Input the access key when prompted
6. Start controlling!

---

## 📱 Command Reference

### Basic Controls
| Command | Description |
|---|---|
| `tap X Y` | Tap at coordinates |
| `longtap X Y` | Long press at coordinates |
| `doubletap X Y` | Double tap |
| `swipe X1 Y1 X2 Y2` | Swipe gesture |
| `scrollup/down/left/right` | Directional scrolling |
| `text "content"` | Type text |
| `key CODE` | Press key (3=Home, 4=Back, 26=Power) |

### System Controls
| Command | Description |
|---|---|
| `home` | Go to home screen |
| `back` | Press back button |
| `recent` | Show recent apps |
| `power` | Power button |
| `volume_up/down` | Adjust volume |
| `mute` | Toggle mute |
| `playpause` | Media play/pause |
| `next/prev` | Next/previous track |
| `screenshot` | Take screenshot |

### Network & Connectivity
| Command | Description |
|---|---|
| `wifi_on/off` | Toggle WiFi |
| `bluetooth_on/off` | Toggle Bluetooth |
| `airplane_on/off` | Toggle airplane mode |
| `hotspot_on/off` | Toggle mobile hotspot |
| `location_on/off` | Toggle GPS location |

### Apps & Media
| Command | Description |
|---|---|
| `open_app PACKAGE` | Launch any app |
| `open_url URL` | Open website |
| `youtube QUERY` | Search YouTube |
| `google QUERY` | Google search |
| `maps LOCATION` | Open Maps |
| `call NUMBER` | Make phone call |
| `sms NUMBER "MSG"` | Send SMS |

### Device Info
| Command | Description |
|---|---|
| `battery` | Battery status & level |
| `device_info` | Model & Android version |
| `storage_info` | Storage usage |
| `ram_info` | RAM statistics |
| `cpu_info` | CPU information |
| `network_info` | Network status |
| `ip_info` | IP address |
| `app_list` | List all installed apps |
| `app_info PACKAGE` | App details |
| `app_force_stop PACKAGE` | Force stop app |
| `app_clear_data PACKAGE` | Clear app data |
| `app_uninstall PACKAGE` | Uninstall app |

### Display & UI
| Command | Description |
|---|---|
| `brightness 0-255` | Set screen brightness |
| `brightness_auto 0/1` | Auto brightness |
| `rotatescreen 0/1` | Auto-rotate |
| `lockscreen` | Lock device |
| `screenon/off` | Control screen |
| `flashlight_on/off` | Toggle flashlight |
| `ui_dump` | Get all clickable UI elements |
| `ui_click "Text"` | Click element by text |

### Advanced
| Command | Description |
|---|---|
| `clipboard_get` | Get clipboard content |
| `clipboard_set "text"` | Set clipboard |
| `notify "Title" "Msg"` | Send notification |
| `toast "message"` | Show toast message |
| `vibrate MILLISECONDS` | Vibrate device |
| `ringermode 0/1/2` | Silent/Vibrate/Normal |
| `shell "command"` | Run any shell command |
| `reboot` | Reboot device |
| `poweroff` | Power off |

### Troll Tools 😈
| Command | Description |
|---|---|
| `troll_screen_flip` | Crazy animations |
| `troll_screen_normal` | Restore normal |
| `troll_invert_colors 0/1` | Invert display |
| `troll_font_huge` | Massive text size |
| `troll_font_normal` | Normal text size |
| `troll_spam_notify` | 10 spam notifications |
| `troll_vibrate_crazy` | Long vibration |
| `troll_open_random` | Launch random app |
| `troll_rotate 0-3` | Force rotation |
| `troll_volume_max` | Max volume blast |
| `troll_brightness_flash` | Strobe effect |

---

## 🔧 Troubleshooting

| Issue | Solution |
|---|---|
| "rish: command not found" | Run: `bash ~/storage/shared/Shizuku/copy.sh` |
| Shizuku not responding | Open Shizuku app → verify "Running" status → run `shizuku` in Termux |
| Can't connect to gateway | Check IP address: `ifconfig wlan0` or `ip route` |
| "Invalid access key" | Check terminal for correct key, clear browser cache |
| AI not responding | Ensure internet connection is active |
| Web search fails | Check internet, DuckDuckGo API may have rate limits |
| Commands not executing | Run `rish -c whoami` to test Shizuku connection |

---

## 🔒 Security Notes

- Access key is auto-generated on first run
- Key stored locally in `~/phonegate/data/gateway.db`
- Gateway only accessible on local network by default
- For remote access, use VPN or SSH tunneling
- Change key by editing database: `sqlite3 ~/phonegate/data/gateway.db "UPDATE settings SET value='new-key' WHERE key='access_key'"`

---

## 📂 File Structure

```
~/phonegate/
├── gateway.js          # Main server
├── phone_control.sh    # Command executor
├── start.sh           # Launcher script
├── web/
│   └── index.html     # Web interface
├── data/
│   └── gateway.db     # SQLite database
├── logs/              # Server logs
├── uploads/           # File uploads
└── temp/              # Temporary files
```

---

## 🎯 Usage Examples

### AI Chat Examples
- "What's my battery level?"
- "Open Chrome and search for weather"
- "Take a screenshot and tell me what's on screen"
- "Turn off WiFi and enable Bluetooth"
- "Send a WhatsApp message to Mom saying I'll be late"

### Web Search
- Type any query in search box
- AI automatically uses search when needed
- Results appear directly in chat

### Custom Commands
- Type any command directly: `wifi_off`
- Combine with arguments: `tap 500 1000`
- Use shell commands: `shell ls /sdcard`

---

## 🙏 Credits

- **Shizuku** — System-level Android access without root
- **Termux** — Linux environment for Android
- **Pollinations AI** — Free unlimited AI chat
- **DuckDuckGo API** — Free web search
- **Node.js** — Backend runtime

---

## 📄 License

MIT License — Free for personal and commercial use.

---

## 🌟 Pro Tips

1. **Bookmark the gateway URL** on other devices for quick access
2. **Use Termux:Boot** to auto-start gateway on phone boot
3. **Enable "Keep screen on"** in Termux for uninterrupted service
4. **Create command shortcuts** in web UI by modifying HTML
5. **Check logs** at `~/phonegate/logs/` if issues occur

---

**Made with ❤️ for the Android community**
```
