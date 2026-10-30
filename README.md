# HOTEL SHIFT — FIXED561

ホテルのスタッフ・シフト・希望休を管理するSwiftUIアプリ。iPhone、iPad、Mac Catalystに対応します。

## 起動とビルド

HOTEL_SHIFT.xcodeprojをXcodeで開き、開発チームと実行先を選択してください。MacはMy Mac（Mac Catalyst）を選びます。

ビルド確認：`bash Tests/build_iphone_mac.sh`

Macでビルドして起動：`bash Tests/run_mac_catalyst.sh`

iCloudには既存コンテナと署名設定が必要です。

## iPad横向き

iPadのアプリウィンドウが横長の場合、Mac版で修正した表示を適用します。中央見出し、余白、カード、主要ボタン、PDF出力の3操作横並びと簡易イメージ拡大、出力範囲と部署の横並び、スタッフカードの削除ボタン・詳細3操作・絞り込み・設定名が対象です。

縦長に戻すと従来のiPad表示へ切り替わります。ウィンドウ単位で判定するため、回転やマルチタスクのサイズ変更にも追従します。Macは常に共通表示を使用し、iPhoneの表示は維持します。

狭い本文ではカードや一覧を縦並びに切り替えます。PDFの3操作は横並びで、幅が不足する場合は横スクロールできます。
