######################################
# ECR Configuration
######################################
resource "aws_ecr_repository" "web" {
  name                 = "${local.prefix}-repo"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  provisioner "local-exec" {
    command = "docker image build -t ${self.repository_url}:first docker"
  }
  provisioner "local-exec" {
    command = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${data.aws_caller_identity.self.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
  }
  provisioner "local-exec" {
    command = "docker image push ${self.repository_url}:first"
  }
}

resource "aws_ecr_lifecycle_policy" "web" {
  repository = aws_ecr_repository.web.id
  policy     = file("${path.module}/ecr_lifecycle/lifecycle.json")
}

######################################
# CodePipeline Configuration (Artifact)
######################################
resource "aws_s3_bucket" "pipeline_artifact" {
  bucket        = "${local.prefix}-pipeline-artifact-${data.aws_caller_identity.self.account_id}"
  force_destroy = true # for testing
  tags = {
    Name = "${local.prefix}-pipeline-artifact-${data.aws_caller_identity.self.account_id}"
  }
}

resource "aws_s3_bucket_ownership_controls" "pipeline_artifact" {
  bucket = aws_s3_bucket.pipeline_artifact.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifact" {
  bucket = aws_s3_bucket.pipeline_artifact.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "pipeline_artifact" {
  bucket = aws_s3_bucket.pipeline_artifact.id

  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Disabled"
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifact" {
  bucket = aws_s3_bucket.pipeline_artifact.id

  restrict_public_buckets = true
  ignore_public_acls      = true
  block_public_acls       = true
  block_public_policy     = true
}


######################################
# CodeBuild Configuration (S3 Cache)
######################################
resource "aws_s3_bucket" "codebuild_cache" {
  bucket        = "${local.prefix}-codebuild-cache-${data.aws_caller_identity.self.account_id}"
  force_destroy = true # for testing

  tags = {
    Name = "${local.prefix}-codebuild-cache-${data.aws_caller_identity.self.account_id}"
  }
}

resource "aws_s3_bucket_ownership_controls" "codebuild_cache" {
  bucket = aws_s3_bucket.codebuild_cache.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "codebuild_cache" {
  bucket = aws_s3_bucket.codebuild_cache.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# resource "aws_s3_bucket_versioning" "codebuild_cache" {
#   bucket = aws_s3_bucket.codebuild_cache.bucket

#   versioning_configuration {
#     status     = "Disabled"
#     mfa_delete = "Disabled" # ignore SNYK-CC-TF-127
#   }
# }

resource "aws_s3_bucket_public_access_block" "codebuild_cache" {
  bucket = aws_s3_bucket.codebuild_cache.id

  restrict_public_buckets = true
  ignore_public_acls      = true
  block_public_acls       = true
  block_public_policy     = true
}

######################################
# CodeBuild Configuration (Role)
######################################
resource "aws_iam_role" "codebuild" {
  name               = "${local.prefix}-codebuild-role"
  assume_role_policy = file("${path.module}/iam_policy_document/assume_codebuild.json")

  tags = {
    Name = "${local.prefix}-codebuild-role"
  }
}

resource "aws_iam_policy" "codebuild" {
  name   = "${local.prefix}-codebuild-policy"
  policy = templatefile("${path.module}/iam_policy_document/iam_codebuild.json", {
    secrets_arn = aws_secretsmanager_secret.backlog_info.arn
  })

  tags = {
    Name = "${local.prefix}-codebuild-policy"
  }
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.codebuild.name
  policy_arn = aws_iam_policy.codebuild.arn
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.prefix}-project"
  retention_in_days = 7

  tags = {
    Name = "/aws/codebuild/${local.prefix}-project"
  }
}

######################################
# CodeBuild Configuration (Secure String)
######################################
resource "aws_secretsmanager_secret" "backlog_info" {
  name                    = "${local.prefix}/backlog_info"
  recovery_window_in_days = 0
  policy = templatefile("${path.module}/iam_policy_document/resource_secretsmanager.json", {
    role_arn = aws_iam_role.codebuild.arn
  })
}

resource "aws_secretsmanager_secret_version" "backlog_info" {
  secret_id = aws_secretsmanager_secret.backlog_info.id
  secret_string = jsonencode({
    space_id        = var.backlog.space_id
    domain_name     = var.backlog.domain_name
    project_key     = var.backlog.project_key
    repository_name = var.backlog.repository_name
    ssh_key         = tls_private_key.backlog.private_key_pem
  })
}

######################################
# CodeBuild Configuration (Project)
######################################
resource "aws_codebuild_project" "codebuild" {
  name         = "${local.prefix}-project"
  description  = "${local.prefix}-project"
  service_role = aws_iam_role.codebuild.arn

  source {
    type      = "NO_SOURCE"
    buildspec = file("${path.module}/codesries/buildspec.yaml")
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image_pull_credentials_type = "CODEBUILD"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      type  = "PLAINTEXT"
      value = data.aws_caller_identity.self.account_id
    }

    environment_variable {
      name  = "ECR_REPOSITORY_NAME"
      type  = "PLAINTEXT"
      value = aws_ecr_repository.web.name
    }

    environment_variable {
      name  = "TASK_FAMILY"
      value = aws_ecs_task_definition.web.family
    }

    environment_variable {
      name  = "TASK_EXECUTION_ROLE_ARN"
      value = aws_iam_role.task_exec.arn
    }

    environment_variable {
      name  = "CONTAINER_NAME"
      value = "web" # 場合によって変わる
    }

    environment_variable {
      name  = "LOG_GROUP_NAME"
      value = aws_cloudwatch_log_group.ecs.name
    }

    environment_variable {
      name  = "LOG_STREAM_PREFIX"
      value = "ecs"
    }

    # BackLog
    environment_variable {
      name  = "BACKLOG_SPACE_ID"
      type  = "SECRETS_MANAGER"
      value = "${aws_secretsmanager_secret.backlog_info.name}:space_id"
    }

    environment_variable {
      name  = "BACKLOG_DOMAIN_NAME"
      type  = "SECRETS_MANAGER"
      value = "${aws_secretsmanager_secret.backlog_info.name}:domain_name"
    }

    environment_variable {
      name  = "BACKLOG_PROJECT_KEY"
      type  = "SECRETS_MANAGER"
      value = "${aws_secretsmanager_secret.backlog_info.name}:project_key"
    }

    environment_variable {
      name  = "BACKLOG_REPOSITORY_NAME"
      type  = "SECRETS_MANAGER"
      value = "${aws_secretsmanager_secret.backlog_info.name}:repository_name"
    }

    environment_variable {
      name  = "BACKLOG_GIT_CREDENTIAL"
      type  = "SECRETS_MANAGER"
      value = "${aws_secretsmanager_secret.backlog_info.name}:ssh_key"
    }
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  cache {
    type     = "S3"
    location = aws_s3_bucket.codebuild_cache.id
  }

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.pipeline_artifact.id
    name      = "BuildArtifact"
    packaging = "ZIP"
  }
}

#####################################
# CodeDeploy Configuration
#####################################
resource "aws_codedeploy_app" "codedeploy" {
  name             = "${local.prefix}-application"
  compute_platform = "ECS"

  tags = {
    Name = "${local.prefix}-application"
  }
}

resource "aws_iam_role" "codedeploy" {
  name               = "${local.prefix}-codedeploy-role"
  assume_role_policy = file("${path.module}/iam_policy_document/assume_codedeploy.json")
  tags = {
    Name = "${local.prefix}-codedeploy-role"
  }
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

resource "aws_codedeploy_deployment_group" "codedeploy" {
  app_name               = aws_codedeploy_app.codedeploy.name
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  deployment_group_name  = "${local.prefix}-dg"
  service_role_arn       = aws_iam_role.codedeploy.arn

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout    = "STOP_DEPLOYMENT"
      wait_time_in_minutes = 5
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.cluster.name
    service_name = aws_ecs_service.service.name
  }

  load_balancer_info {
    target_group_pair_info {

      prod_traffic_route {
        listener_arns = [aws_lb_listener.alb_80.arn]
      }

      test_traffic_route {
        listener_arns = [aws_lb_listener.alb_8080.arn]
      }

      target_group {
        name = aws_lb_target_group.blue.name
      }

      target_group {
        name = aws_lb_target_group.green.name
      }
    }
  }
}

#####################################
# CodePipeline Configuration
#####################################
resource "aws_iam_role" "codepipeline" {
  name               = "${local.prefix}-codepipeline-role"
  assume_role_policy = file("${path.module}/iam_policy_document/assume_codepipeline.json")

  tags = {
    Name = "${local.prefix}-codepipeline-role"
  }
}

resource "aws_iam_policy" "codepipeline" {
  name = "${local.prefix}-codepipeline-policy"
  policy = templatefile("${path.module}/iam_policy_document/iam_codepipeline.json", {
    task_execution_role_arn = aws_iam_role.task_exec.arn
  })

  tags = {
    Name = "${local.prefix}-codepipeline-policy"
  }
}

resource "aws_iam_role_policy_attachment" "codepipeline" {
  role       = aws_iam_role.codepipeline.name
  policy_arn = aws_iam_policy.codepipeline.arn
}

resource "aws_codepipeline" "pipeline" {
  name     = "${local.prefix}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.pipeline_artifact.bucket
  }

  stage {
    name = "Source"

    action {
      name      = "Source"
      category  = "Source"
      owner     = "AWS"
      namespace = "SourceVariables"
      provider  = "S3"
      version   = 1

      configuration = {
        S3Bucket             = aws_s3_bucket.pipeline_artifact.id
        S3ObjectKey          = "BuildArtifact"
        PollForSourceChanges = false
      }
      output_artifacts = ["BuildArtifact"]
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      run_order       = 1
      provider        = "CodeDeployToECS"
      input_artifacts = ["BuildArtifact"]
      version         = 1

      configuration = {
        ApplicationName                = aws_codedeploy_app.codedeploy.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.codedeploy.deployment_group_name
        TaskDefinitionTemplateArtifact = "BuildArtifact"
        AppSpecTemplateArtifact        = "BuildArtifact"
        Image1ArtifactName             = "BuildArtifact"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }
}

#####################################
# Start CodePipeline Configuration
#####################################
resource "aws_cloudwatch_event_rule" "codepipeline" {
  name = "${local.prefix}-codepipeline-event"
  event_pattern = templatefile("${path.module}/event_pattern/codepipeline.json", {
    bucket_name = aws_s3_bucket.pipeline_artifact.id
    object_key  = "BuildArtifact"
  })
}

resource "aws_cloudwatch_event_target" "codepipeline" {
  rule     = aws_cloudwatch_event_rule.codepipeline.name
  arn      = aws_codepipeline.pipeline.arn
  role_arn = aws_iam_role.eventbridge_pipeline.arn
}

resource "aws_iam_role" "eventbridge_pipeline" {
  name               = "${local.prefix}-eventbridge-pipeline-role"
  assume_role_policy = file("${path.module}/iam_policy_document/assume_eventbridge.json")

  tags = {
    Name = "${local.prefix}-eventbridge-pipeline-role"
  }
}

resource "aws_iam_policy" "eventbridge_pipeline" {
  name = "${local.prefix}-eventbridge-pipeline-policy"
  policy = templatefile("${path.module}/iam_policy_document/iam_eventbridge_pipeline.json", {
    pipeline_arn = aws_codepipeline.pipeline.arn
  })

  tags = {
    Name = "${local.prefix}-eventbridge-pipeline-policy"
  }
}

resource "aws_iam_role_policy_attachment" "eventbridge_pipeline" {
  role       = aws_iam_role.eventbridge_pipeline.name
  policy_arn = aws_iam_policy.eventbridge_pipeline.arn
}