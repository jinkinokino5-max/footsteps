# Phase 0 セットアップ手順（ビルド〜実機インストール）

このドキュメントは、Windows PC + 実機iPhone + 無料Apple ID + GitHub（無料枠）だけで
「コード変更 → 自動ビルド → 実機インストール」を回すための手順書。
GUIでの操作が中心のため、ユーザー自身の作業が必要な箇所を明記する。

## 全体の流れ
```
コード変更をpush
   ↓（自動）
GitHub Actionsがビルド → 署名なし.ipaを生成
   ↓（手動）
.ipaをダウンロード
   ↓（手動）
AltStore経由でiPhoneにインストール（この時に無料Apple IDで自動署名される）
```

## 手順1：GitHubリポジトリの作成（ユーザー作業）
1. https://github.com/new でリポジトリを作成（**Public**でOK＝合意済み）
2. リポジトリ名は任意（例：`his-footsteps`）
3. 作成後に表示されるリポジトリURLを控える

→ URLを教えてもらえれば、こちらで `git remote add` してpushします。

## 手順2：AltServerのインストール（ユーザー作業・Windows PC）
1. https://altstore.io/ から Windows版 AltServer をダウンロード・インストール
2. AltServerの動作には「iTunes」または「Apple Devices」アプリ（Microsoft Store版）のインストールが必要な場合がある。案内に従ってインストール
3. iPhoneをUSBケーブルでPCに接続（初回は有線接続を推奨）

## 手順3：iPhoneにAltStoreをインストール（ユーザー作業）
1. タスクトレイのAltServerアイコンから「Install AltStore」→ 対象のiPhoneを選択
2. 無料のApple ID／パスワードを入力（Apple Developer Programへの加入は不要）
3. iPhone側で「設定」→「一般」→「VPNとデバイス管理」から、開発元（Apple ID）のプロファイルを信頼する
4. iPhoneのホーム画面にAltStoreアプリが追加されていればOK

## 手順4：.ipaのビルド（自動）
1. コードをmaster/mainブランチにpushすると `.github/workflows/build.yml` が自動実行される
2. GitHubリポジトリの「Actions」タブ → 該当のワークフロー実行 → 「Artifacts」から
   `HisFootsteps-unsigned-ipa` をダウンロードしてzipを展開（`HisFootsteps-unsigned.ipa` が出てくる）

## 手順5：実機へインストール（ユーザー作業）
1. iPhoneとPCを同じWi-Fiに接続（またはUSB接続）し、AltServerを起動しておく
2. iPhoneのAltStoreアプリ →「マイApp」タブ → 左上の「+」→ 手順4でダウンロードした `.ipa` を選択
3. インストールが始まり、完了するとホーム画面にアプリが追加される
4. アプリを開き、「ハプティクスをテスト」ボタンで振動することを確認する（これでPhase 0〜1の疎通確認は完了）

## 注意点：7日ごとの再署名
- 無料Apple IDで署名したアプリは**7日間で失効**する
- AltStoreは、iPhoneとPCが同じWi-Fi上にあり、AltServerが起動していれば自動でバックグラウンド再署名を試みる
- 再署名に失敗した場合は、手順5を再実行してインストールし直す
- より自動化したい場合は、後日 **SideStore**（Wi-Fi/VPN経由で自動更新、PC常時起動不要）への切り替えを検討する

## トラブルシューティングの目安
| 症状 | 想定原因 |
|---|---|
| AltServerがiPhoneを認識しない | iTunes/Apple Devicesアプリ未インストール、USBの信頼確認未実施 |
| インストール後すぐにアプリが開けない（未信頼の開発元） | 手順3-③のプロファイル信頼設定を再確認 |
| 7日後にアプリが起動しなくなる | 署名失効。手順5を再実行 |
| GitHub Actionsのビルドが失敗する | Actionsのログを確認し、該当エラーを共有してもらえれば対応する |
