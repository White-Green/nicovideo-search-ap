# 定期デプロイセットアップ手順

情報を更新してデプロイを行う `mise run deploy` を systemd timer で定期実行できます。

## 概要

セットアップスクリプト `scripts/deploy/setup_periodic_deploy.sh` は、以下を実施します。

1. デプロイ専用の system user を作成（デフォルト: `nicovideo-ap`）
2. `https://github.com/White-Green/nicovideo-search-ap` を clone/update
3. clone先の `scripts/deploy/run_periodic_deploy.sh` と `scripts/deploy/systemd/*.template` を使って systemd を登録
4. timer を有効化

## 事前準備

[mise](https://mise.jdx.dev/)が使える状態にしておいてください

## 実行

```bash
sudo bash scripts/deploy/setup_periodic_deploy.sh
```

単体配布して使う場合:

```bash
curl -fsSL https://raw.githubusercontent.com/White-Green/nicovideo-search-ap/main/scripts/deploy/setup_periodic_deploy.sh -o setup_periodic_deploy.sh
chmod +x setup_periodic_deploy.sh
sudo ./setup_periodic_deploy.sh
```

## 実行スケジュール

- 毎日 10:00 JST
- systemd timer 設定: `OnCalendar=*-*-* 10:00:00 Asia/Tokyo`

## 秘密情報の管理

秘密情報は `EnvironmentFile` ではなく systemd credential で管理します。

- `/etc/nicovideo-search-ap/credentials/cloudflare_account_id`
- `/etc/nicovideo-search-ap/credentials/cloudflare_api_token`
- 推奨権限: ディレクトリ `700`、ファイル `600`

`mise run deploy` は `CREDENTIALS_DIRECTORY` から credential を読み取り、
`./fblog_system/deploy_scripts/cloudflare/deploy_prod.sh` 呼び出し時にのみ
`CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_API_TOKEN` を環境変数として渡します。

## セットアップ後の初回実行

セットアップスクリプトは service の初回実行を行いません。credential 設定後に手動実行してください。

```bash
sudoedit /etc/nicovideo-search-ap/credentials/cloudflare_account_id
sudoedit /etc/nicovideo-search-ap/credentials/cloudflare_api_token
sudo systemctl start nicovideo-search-ap-deploy.service
sudo journalctl -u nicovideo-search-ap-deploy.service -n 200 --no-pager
```

## 定義変更の反映

service/timer/template の変更を反映したい場合は、セットアップスクリプトを再実行してください。

```bash
sudo bash scripts/deploy/setup_periodic_deploy.sh
```

必要に応じて以下も実行してください。

```bash
sudo systemctl restart nicovideo-search-ap-deploy.service
```
