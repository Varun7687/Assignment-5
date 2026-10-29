resource "aws_sns_topic" "operations" {
  name = "${local.name}-operations"
  tags = merge(local.tags.shared, { Name = "${local.name}-operations" })
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.notification_emails)
  topic_arn = aws_sns_topic.operations.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_event_rule" "autoscaling" {
  name          = "${local.name}-autoscaling-events"
  event_pattern = jsonencode({ source = ["aws.autoscaling"], "detail-type" = ["EC2 Instance Launch Successful", "EC2 Instance Launch Unsuccessful", "EC2 Instance Terminate Successful"], detail = { AutoScalingGroupName = [aws_autoscaling_group.prod.name] } })
  tags          = merge(local.tags.shared, { Name = "${local.name}-autoscaling-events" })
}

resource "aws_cloudwatch_event_target" "autoscaling" {
  rule      = aws_cloudwatch_event_rule.autoscaling.name
  target_id = "operations-sns"
  arn       = aws_sns_topic.operations.arn
}


resource "aws_sns_topic_policy" "eventbridge" {
  arn = aws_sns_topic.operations.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "EventBridgePublish", Effect = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action = "sns:Publish", Resource = aws_sns_topic.operations.arn
        Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.autoscaling.arn } }
      },
      {
        Sid = "RDSPublish", Effect = "Allow"
        Principal = { Service = "rds.amazonaws.com" }
        Action = "sns:Publish", Resource = aws_sns_topic.operations.arn
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })
}
