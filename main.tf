provider "aws" {
  region = "ap-northeast-1" 
}

# CloudWatch Logs グループの作成(壊せるようにしたいので、検証用に作る)
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/poc-sqs/log-group"
  retention_in_days = 14
}

# SQSキューの作成
resource "aws_sqs_queue" "this" {
  name = "example-queue"
}

# オプションとして SNS を使用する場合

# SNS トピックの作成
resource "aws_sns_topic" "this" {
  name = "example-topic"
}



# SNS サブスクリプションの設定（SQS キューをサブスクライブ）
resource "aws_sns_topic_subscription" "this" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.this.arn

  # SQS キューのポリシーを設定して SNS からのメッセージを許可
  raw_message_delivery = true
}

# SQS キューのポリシーを設定
resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          Service = "sns.amazonaws.com"
        },
        Action    = "SQS:SendMessage",
        Resource  = aws_sqs_queue.this.arn,
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.this.arn
          }
        }
      }
    ]
  })
}

# CloudWatch Logs メトリックフィルターの作成
resource "aws_cloudwatch_log_metric_filter" "error_filter" {
  name           = "ErrorFilter"
  log_group_name = aws_cloudwatch_log_group.this.name

  pattern = "ERROR"

  metric_transformation {
    name      = "ErrorCount"
    namespace = "YourNamespace"
    value     = "1"
    unit      = "Count"
  }
}

# CloudWatch アラームの作成
resource "aws_cloudwatch_metric_alarm" "this" {
  alarm_name          = "CloudWatchLogs_ErrorAlarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = aws_cloudwatch_log_metric_filter.error_filter.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.error_filter.metric_transformation[0].namespace
  period              = "60" # 1分間隔
  statistic           = "Sum"
  threshold           = "1"

  # アラームが発生したときに SNS トピックに通知
  alarm_actions = [aws_sns_topic.this.arn]
  
  # OK 状態に戻ったときのアクション（オプション）
  ok_actions = [aws_sns_topic.this.arn]

  # アラームの説明（オプション）
  alarm_description = "Alarm when ERROR appears in logs"
}



# CloudWatchカスタムメトリックアラームの作成
resource "aws_cloudwatch_metric_alarm" "this2" {
  alarm_name          = "CustomMetricAlarm"
  alarm_description   = "カスタムメトリックがしきい値を超えた場合にSNS経由でSQSに通知。"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "pocCustomMetric"       # カスタムメトリック名
  namespace           = "pocCustomNamespace"    # カスタムメトリックのネームスペース
  period              = 60                       # メトリックの集計期間（秒）
  statistic           = "Sum"                     # 使用する統計値（Sum, Averageなど）
  threshold           = 100                       # しきい値に置き換えてください

  # アラームが発生したときに通知するSNSトピックのARN
  alarm_actions       = [aws_sns_topic.this.arn]

  # アラームがOK状態に戻ったときに通知するSNSトピックのARN（オプション）
  ok_actions          = [aws_sns_topic.this.arn]

  # 任意: アラームがInsufficientData状態になったときに通知するSNSトピックのARN
  # insufficient_data_actions = [aws_sns_topic.this.arn]

  # タグ（識別しやすいように）
  tags = {
    Environment = "poc"
    Service     = "custom-metrics"
  }
}