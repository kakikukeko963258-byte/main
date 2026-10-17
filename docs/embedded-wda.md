# mainに同梱するWebDriverAgent

既存mainの画面、ホーム配置、PC File Bridge、File Providerを維持し、WDA本体とXCTestのエントリーポイントを `Frameworks/WebDriverAgentLib.framework` に同梱します。追加のアプリ番号やホームアイコンは作りません。通常起動時にmainはこのフレームワークへリンクせず、普段のmainとして動作します。

GitHub ActionsのmacOS runnerで、固定したAppium WebDriverAgentのソースからビルドします。BSDライセンスをIPAに同梱します。署名は既存の改造版AltForge Remoteのフレームワーク署名経路を使用します。AppleのXCTestフレームワークはIPAへコピーせず、開発者用イメージから読み込みます。

WDAを使うときにはPC側からXCTest経由の起動が必要です。mainのアイコンをタップするだけではWDAは起動しません。開発者モード、PCとの信頼済み接続、マウントしたDeveloper Disk Image、開発用署名が必要です。

```powershell
./scripts/Start-EmbeddedWDA.ps1 -Ios C:/path/ios.exe -Udid YOUR_DEVICE_ID -BundleId SIGNED_MAIN_BUNDLE_ID
```

このスクリプトは接続維持中に実行します。iOS 17以降の `XCTestBundlePath` と `libXCTestBundleInject` を使って、main内のWDAフレームワークをテストバンドルとして読み込みます。実機で `/status` の応答を確認して初めて起動成功と判断します。IPA同梱・インストール成功とWDA起動成功は別々に検証します。

PC File Bridgeのアプリグループを署名先に合わせたIPAを、設定済みAltForge Remoteで上書きインストールします。接続情報・署名用秘密情報はリポジトリやActionsへ送信しません。
