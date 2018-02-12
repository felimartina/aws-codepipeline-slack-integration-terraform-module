variable "APP_NAME" {
  description = "Lambda function name."
}

variable "PIPELINE_NAME" {
  description = "CodePipeline name."
}

variable "SLACK_WEBHOOK_URL" {
  description = "Webhook URL provided by Slack when configured Incoming Webhook."
}

variable "SLACK_CHANNEL" {
  description = "Slack channel where messages are going to be posted."
}

variable "RELEVANT_STAGES" {
  description = "Stages for which you want to get notified (ie. 'SOURCE,BUILD,DEPLOY'). Defaults to all)"
  default     = "SOURCE,BUILD,DEPLOY"
}

variable "LAMBDA_TIMEOUT" {
  default = "10"
}

variable "LAMBDA_MEMORY_SIZE" {
  default = "128"
}
