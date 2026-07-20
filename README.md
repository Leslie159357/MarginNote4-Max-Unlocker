# MarginNote 4 Max Unlocker

注入 dylib 解锁 MarginNote 4 Max 功能。适用于已砸壳的 IPA。

## 原理

MarginNote 4 使用 RMStore（开源 StoreKit 封装）+ 纯本地收据验证，  
不调用自家服务器验证订阅。本 dylib hook 以下路径：

- **NSUserDefaults** — 强制 `hasMaxLifetime` / `hasProLifetime` = YES
- **MNEntitlementSnapshot** — 权限快照返回 Max
- **RMStore** — 收据验证始终成功
- **SKPaymentQueue** — 拦截购买/恢复，伪造交易

## 编译

GitHub Actions 自动编译。去 [Actions 页面](https://github.com/Leslie159357/MarginNote4-Max-Unlocker/actions) 
点 **"Build MNMaxUnlock.dylib"** → **Run workflow**，等几分钟下载 artifact。

或本地 Mac 编译：

```bash
make build
```

## 注入到 IPA

```bash
# 解包
unzip MarginNote4.ipa -d tmp_mn4

# 复制 dylib
cp MNMaxUnlock.dylib "tmp_mn4/Payload/MarginNote 4.app/"

# 注入
optool install -c load -p @executable_path/MNMaxUnlock.dylib \
      -t "tmp_mn4/Payload/MarginNote 4.app/MarginNote 4"

# 重签名（需要 Apple 开发者证书）
codesign -f -s "Apple Development: xxx@xxx.com" \
      "tmp_mn4/Payload/MarginNote 4.app"

# 打包
cd tmp_mn4 && zip -r ../MarginNote4-Unlocked.ipa Payload/
```

然后用 SideStore / AltStore 安装。

## 注意

- 需要已有 **Pro 买断**（App Store 购买过 Pro）
- 安装后打开 App 会弹出 ✅ Max Unlocked 确认对话框
- 如果功能未生效，进设置 → 恢复购买
