# macOS 构建步骤

环境:macOS(Apple Silicon)· Flutter SDK(stable)· .NET 8 SDK

```bash
flutter create . --platforms=macos --project-name dst_mod_publisher

for f in macos/Runner/*.entitlements; do
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.app-sandbox false" "$f" || true
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$f" || true
done

flutter pub get
flutter build macos --release

dotnet publish helper/CpSteamHelper.csproj -c Release -r osx-arm64 -o helper_out
APP=build/macos/Build/Products/Release/dst_mod_publisher.app
mkdir -p "$APP/Contents/MacOS/helper"
cp -R helper_out/* "$APP/Contents/MacOS/helper/"
cp helper/native/libsteam_api.dylib "$APP/Contents/MacOS/helper/"
chmod +x "$APP/Contents/MacOS/helper/CpSteamHelper"
codesign --force --deep --sign - "$APP"
```

运行前确保 Steam 客户端已登录且账号拥有饥荒。
如被 Gatekeeper 拦截:`xattr -dr com.apple.quarantine 应用路径`。

说明:关闭 App Sandbox 是必须的,否则无法拉起 helper 子进程/连接 Steam。
Steamworks 以 Mod Tools(245850)身份初始化,这条链路在 macOS 上尚未实测,
发布若失败请把日志页内容反馈给作者(1713597367@qq.com)。
