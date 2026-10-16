# main

iPhone用のSwiftUIアプリ。4列×8行、合計32個の番号付きアイコンを表示し、各番号のページへ移動します。左上の戻るボタン、または画面左端からのスワイプで戻れます。

アプリ名・プロジェクトIDは `main`。iOSのBundle IDは `com.kakikukeko.main`、iOS 16以降に対応します。iPhoneホーム画面風の壁紙・角丸アイコン・番号ラベルを使用し、8行が1画面に入るよう画面高に合わせて縮小します。ステータスバーは実際のiOSの表示です。OSのホーム画面を置き換える機能や、他のIPAをこのアプリ内にインストールする機能はありません。

## 公開ビルド

mainへのpushまたはActionsの手動実行でmacOS runner + XcodeがReleaseビルドします。Actions Artifact `main-ipa` とGitHub Releasesから `main.ipa` を取得できます。

WindowsではXcode不要です。AltServerとAltStore Classicを用意し、ダウンロードしたIPAをiPhoneのAltStore Classicの「My Apps」→「+」から選んでインストールしてください。IPAは未署名で、AltStore側でApple IDを使って再署名します。AltStore PAL向け配布ではありません。

## 拡張

`Main/MainApp.swift` の `AppSlot` と `SlotPage` を拡張すると、番号ごとの機能を追加できます。外部のiOSアプリを埋め込むのではなく、このプロジェクト内に機能を実装する構成です。
