# はじめに

[Backlog の Git リポジトリをソースとした Docker イメージのビルドパイプラインを作ってみた](https://dev.classmethod.jp/articles/backlog-git-docker-build-cicd-pipeline)のサンプルコードになります。

# 構成図

<image src="/images/backlog_git_docker_build.png">

仕組みは以下になります。

1. Backlog Git の WebフックURL に API Gateway の URL を指定し、 push 時に API リクエストを送信
2. API Gateway は CodeBuild プロジェクトを開始させ、 CodeBuild は Backlog Git に対して`git clone`
3. クローンした成果物を元に Docker イメージのビルド、 ECR へのプッシュ、アーティファクトの配置
4. アーティファクトの配置をトリガーに CodePipeline を開始する
5. CodeDeploy が項番4のアーティファクトを元に ECS へデプロイ

詳しい使い方はブログを参照ください。