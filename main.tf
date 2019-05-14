# This HACK installs NPM packages on every run so we get lambda function ready to be published
resource "null_resource" "pull_and_install_github_repo" {
  triggers {
    force_run = "${uuid()}"
  }
  provisioner "local-exec" {
    command = "cd ${path.module}/aws-codepipeline-slack-integration && npm install -production"
  }
}

# Zip up Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/aws-codepipeline-slack-integration"
  output_path = "${path.module}/tmp/aws-codepipeline-slack-integration.zip"

  depends_on = ["null_resource.pull_and_install_github_repo"]
}

# Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.APP_NAME}-slack-integration-lambda-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# IAM Policy for Lambda function
resource "aws_iam_role_policy" "lambda_role_policy" {
  name = "${var.APP_NAME}-slack-integration-lambda-role-policy"
  role = "${aws_iam_role.lambda_role.id}"

  policy = <<EOF
{
  "Version" : "2012-10-17",
  "Statement" : [{
      "Sid": "WriteLogsToCloudWatch",
      "Effect" : "Allow",
      "Action" : [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource" : "arn:aws:logs:*:*:*"
    }, {
      "Sid": "AllowAccesstoPipeline",
      "Effect" : "Allow",
      "Action" : [
        "codepipeline:GetPipeline",
        "codepipeline:GetPipelineState",
        "codepipeline:GetPipelineExecution",
        "codepipeline:ListPipelineExecutions",
        "codepipeline:ListActionTypes",
        "codepipeline:ListPipelines"
      ],
      "Resource" : ${jsonencode(formatlist("arn:aws:codepipeline:*:*:%s", var.PIPELINE_NAMES))}
    }
  ]
}
EOF
}

resource "aws_lambda_function" "lambda" {
  filename         = "${data.archive_file.lambda_zip.output_path}"
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
  description      = "Posts a message to Slack channel '${var.SLACK_CHANNEL}' every time there is an update to codepipeline execution."
  function_name    = "${var.APP_NAME}-slack-integration-lambda"
  role             = "${aws_iam_role.lambda_role.arn}"
  handler          = "handler.handle"
  runtime          = "nodejs8.10"
  timeout          = "${var.LAMBDA_TIMEOUT}"
  memory_size      = "${var.LAMBDA_MEMORY_SIZE}"

  environment {
    variables = {
      "SLACK_WEBHOOK_URL" = "${var.SLACK_WEBHOOK_URL}"
      "SLACK_CHANNEL"     = "${var.SLACK_CHANNEL}"
      "RELEVANT_STAGES"   = "${var.RELEVANT_STAGES}"
    }
  }
}

# Alias pointing to latest for Lambda function
resource "aws_lambda_alias" "lambda_alias" {
  name             = "latest"
  function_name    = "${aws_lambda_function.lambda.arn}"
  function_version = "$LATEST"
}

# Cloudwatch event rule
resource "aws_cloudwatch_event_rule" "pipeline_state_update" {
  name        = "${var.APP_NAME}-slack-integration-pipeline-updated"
  description = "Capture state changes in pipelines '${join(", ", var.PIPELINE_NAMES)}'"

  event_pattern = <<PATTERN
{
  "detail": {
    "pipeline": ${jsonencode(var.PIPELINE_NAMES)}
  },
  "detail-type": [
    "CodePipeline Pipeline Execution State Change"
  ],
  "source": [
    "aws.codepipeline"
  ]
}
PATTERN
}


# Allow Cloudwatch to invoke Lambda function
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id   = "AllowExecutionFromCloudWatch"
  action         = "lambda:InvokeFunction"
  function_name  = "${aws_lambda_function.lambda.function_name}"
  principal      = "events.amazonaws.com"
  source_arn     = "${aws_cloudwatch_event_rule.pipeline_state_update.arn}"
  qualifier      = "${aws_lambda_alias.lambda_alias.name}"
}

# Map event rule to trigger lambda function
resource "aws_cloudwatch_event_target" "lambda_trigger" {
  rule = "${aws_cloudwatch_event_rule.pipeline_state_update.name}"
  arn  = "${aws_lambda_alias.lambda_alias.arn}"
}
