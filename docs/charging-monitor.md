# main 充電モニター

保存済みmain `ac219533f1cc374ed41ffdf336490e1d952b31be` を起点としてアプリ3に追加。既存ホーム、配置、Files拡張、リスニング、WDAを継承。iOS 26以降・SwiftUI / Charts / ActivityKit / WidgetKit。Windowsでは編集とGit操作のみ、ビルドはGitHub Actions `macos-26` のXcodeを使用する。

## 調査結果と取得値の意味

- Apple仕様: iPhone 17eはA19、6.1インチ 2532×1170、USB-C（USB 2）、20W以上のアダプターで30分最大50%、MagSafe/Qi2最大15W。これは実消費電力・最大有線入力電力・電池容量を示す仕様ではない。バッテリー容量を仮定したW計算は実装しない。
- 17eはDynamic Islandを持たないためロック画面Live Activityが主体。対応端末向けDynamic Island表示も同じ拡張に実装し、OSが表示面を選択する。常時表示画面は前提にしない。
- 残量/充電状態: UIDeviceの公開APIを優先。温度・電流・PD契約は公開APIにはない。
- MiniWattsのIOKit / IOHIDEventSystemClient方式を採用。入力はVQ0u×IQ0u、バッテリー側はIQ0B×VQ0l/VP0uなど。取得できた場合のみ実測由来と表示。17eのセンサー名・スケール・入力経路・精度は未検証なので未校正表示を残す。入力よりセル電力が大きい矛盾はMiniWattsの判定で除外。
- 温度: gas gauge battery等のバッテリー領域の中央値。センサーなし、非有限値、既知の番兵値は不採用。SoC温度を電池温度として代用しない。
- IOPSCopyExternalPowerAdapterDetailsのPDO/契約電圧/電流は診断画面に表示。PDの上限Wは実測入力Wに代用しない。ワイヤレス電流がない場合も推定Wで埋めない。
- 通常のサイドロード署名に追加の非公開entitlementを要求しない。シンボル欠落・空リスト・拒否時は取得不可。IOPSCopyChargeStatusの戻りコードを診断に残す。MiniWattsはiOS実機でレジストリの大半がフィルタされ、同関数が権限拒否されると報告。特権entitlementを追加しても一般署名で権限が得られるとは扱わない。

## 予測と更新

10秒ごとの履歴から、同一接続セッションで3分以上・2%以上の進行がある場合に予測する。切断、残量低下、30秒超の欠測で連続区間を分割。残量帯ごとの履歴速度と現在速度を使い、高残量域には段階的な減速仮定を適用する。将来の未観測域の減速は実測値ではない。10分進まない場合、充電停止時、データ不足時は予測不可。80%等の充電上限・最適化充電の解除時刻は取得できず100%予測を保証しない。

前面約2秒、履歴10秒、Activity最大約15秒ごとに更新を試行する。バックグラウンドへ移行した時点で停止表示。ActivityのstaleDateは測定から20秒、OSのisStaleを使用。ウィジェットは期限のタイムラインと最終測定時刻を表示し、OSの更新予算に従う。秒単位更新、ロック中の常時監視、充電器接続による強制終了アプリの自動復帰は保証できない。既存リスニングのaudioバックグラウンド宣言は維持するが、充電監視のための無音再生は追加しない。

アプリ起動中は接続・切断を通知/ポーリングで処理しLive Activityを開始・終了。停止中の接続・切断はアプリに配信される保証がない。ショートカットの「充電器」トリガーで `maincharge://start` / `maincharge://stop` を開く設定をユーザーが作成できる。ロック状態等によってURL起動に操作が必要。自動作成不可。

## 実機確認手順

1. 既存mainと同じBundle IDで再署名し、ChargingWidget拡張とApp Groupを保持する。拡張を削除するとLive Activityも失われる。
2. ナビゲーションフォルダのアプリ3を開き、診断にモデル識別子・OS・HIDサービス・センサー値・権限結果が出るか確認。
3. USB-C電力計と同時測定し、5V/9V、低残量/80%以降、MagSafeで比較。ケーブル損失と測定点の違いも記録。異なる場合は17eで校正済みとはしない。
4. 接続・切断、ロック20秒超、再開、アプリ強制終了、ショートカット、Live Activity無許可、拡張再署名を確認。
5. 3分以上・2%以上の充電を観測して予測が出ること、保留/欠測時に予測不可になることを確認。

## 参考とライセンス

- https://support.apple.com/en-gb/126470
- https://www.apple.com/iphone-17e/specs/
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://developer.apple.com/documentation/widgetkit
- https://support.apple.com/guide/shortcuts/setting-triggers-apde31e9638b/ios
- https://github.com/ResistanceTo/MiniWatts
- https://senumy.com/ipa-library/mini-watts/

調査日2026-10-18。MiniWattsを `3a27d400b1e180172e78dc46ebe3ae3974254e1a` に固定し、センサー/モデル6ファイルを `Main/Charging/Vendor` に組み込み。SensorProbeに権限結果の返却を追加。それ以外は元コード。Apache-2.0と上流MITの帰属を `docs/licenses` に保存。公開仕様の確認・ソース調査と、17e実機での成功検証は別であり、後者は未完了。
