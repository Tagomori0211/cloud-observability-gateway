# GCEへのデプロイ
1. terraform stateと現在デプロイ済みバージョンを確認
2. DockerイメージタグをRegistryと照合
3. deploy.ymlに必要なシークレット（DB_PASSWORD）が書き込まれているか確認
4. OS LoginユーザーがDockerグループに追加済みか、ランナーツールがインストール済みか確認
5. コミット・プッシュ・CI実行・実行確認・同期状態確認
