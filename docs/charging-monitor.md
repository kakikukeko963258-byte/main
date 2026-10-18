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

最速設定は0.1秒間隔（10Hz）の取得試行。0.25秒・1秒へ変更できる。処理時間を差し引いた待機で周期を保ち、重複/遅延した読取りを積み上げない。実取得Hzと処理msを画面・診断に表示する。センサーそのものの更新周期が10Hzとは主張しない。無制限のポーリングや60fpsへの値の補間は行わない。

全測定点を直近2分/最大1,200点に保持し、電力・温度・残量グラフを取得ごとに更新。長期履歴は10秒ごと、最大12,000点/7日。グラフは1分/10分/1時間/6時間/24時間を選択し、ピーク・谷・欠測境界を残して描画点を整理する。長期ファイル書込みは別actorで実行。予測と共有キャッシュは1秒ごと。Live Activityは1秒ごとに更新を試行し、FrequentUpdates対応を宣言。ウィジェットの更新要求は15秒ごとで、実表示の更新頻度はOSの予算に従う。ActivityのstaleDateは20秒を維持。

「小窓で継続測定」をユーザーが押すとAVSampleBufferDisplayLayerの480×270ライブ動画をPiPで表示する。電力・温度・残量・電力グラフ・100%予測・実取得Hz・最終時刻を描画。Core Graphicsとピクセルバッファプールを使い、高頻度のImageRenderer生成を避ける。既存audioバックグラウンド宣言とAVAudioSession.playback/mixWithOthersを使用し、音声トラック・無音音声ループは追加しない。既存リスニングとセッションを共有するのでPiP終了時に一律に音声セッションを解除しない。

PiP開始待機/実行中は背景でもループを維持し、閉じる・開始失敗・割込み・監視OFFでは背景取得を停止して古い値と表示する。接続から切断に変わった場合は小窓も終了。PiPを使わない通常の背景移行時は従来どおり測定停止。PiPはOSに拒否/終了されることがあり、ロック中の常時動作、強制終了後の復帰、ハードウェアの新規データ周期を保証しない。PiPの実際の開始可否・ロック中の継続は17e実機で要確認。シミュレーターがPiPを許可しない場合は検証不能として明記する。

アプリ起動中は接続・切断を通知/ポーリングで処理しLive Activityを開始・終了。停止中の接続・切断はアプリに配信される保証がない。ショートカットの「充電器」トリガーで `maincharge://start` / `maincharge://stop` を開く設定をユーザーが作成できる。ロック状態等によってURL起動に操作が必要。自動作成不可。

## 実機確認手順

1. 既存mainと同じBundle IDで再署名し、ChargingWidget拡張とApp Groupを保持する。拡張を削除するとLive Activityも失われる。
2. ナビゲーションフォルダのアプリ3を開き、診断にモデル識別子・OS・HIDサービス・センサー値・権限結果が出るか確認。
3. USB-C電力計と同時測定し、5V/9V、低残量/80%以降、MagSafeで比較。ケーブル損失と測定点の違いも記録。異なる場合は17eで校正済みとはしない。
4. 小窓を開始し、他アプリへ移動/ロック20秒超から復帰して「PiP背景取得回数」が増えたか確認。小窓終了/割込み/切断で背景取得が止まること、リスニング再生が継続することを確認。高頻度測定の発熱・CPU・実取得Hzを記録する。
5. 接続・切断、再開、アプリ強制終了、ショートカット、Live Activity無許可、拡張再署名を確認。
6. 3分以上・2%以上の充電を観測して予測が出ること、保留/欠測時に予測不可になることを確認。

## 参考とライセンス

- https://support.apple.com/en-gb/126470
- https://www.apple.com/iphone-17e/specs/
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://developer.apple.com/documentation/widgetkit
- https://support.apple.com/guide/shortcuts/setting-triggers-apde31e9638b/ios
- https://github.com/ResistanceTo/MiniWatts
- https://senumy.com/ipa-library/mini-watts/

調査日2026-10-18。MiniWattsを `3a27d400b1e180172e78dc46ebe3ae3974254e1a` に固定し、センサー/モデル6ファイルを `Main/Charging/Vendor` に組み込み。SensorProbeに権限結果の返却と時間基準の再走査を追加。それ以外は元コード。PiPはMiniWattsの方式を参考に独自実装。Apache-2.0と上流MITの帰属を `docs/licenses` に保存。公開仕様の確認・ソース調査と、17e実機での成功検証は別であり、後者は未完了。
