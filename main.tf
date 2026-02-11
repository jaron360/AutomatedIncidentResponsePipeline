data "aws_vpc" "development" {
  cidr_block = "10.16.0.0/16"
}

#Deploying guardduty and suppressing low severity findings
module "guardduty" {
  source = "aws-ia/guardduty/aws"

  replica_region               = "us-east-1"
  enable_guardduty             = true
  enable_malware_protection    = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  filter_config = [{
    name        = "guardduty_filter"
    description = "Archive Low Severity."
    rank        = 1
    action      = "ARCHIVE"
    criterion = [

      {
        field  = "region"
        equals = ["us-east-1"]
      },
      {
        field              = "severity"
        less_than_or_equal = "4"
      }
  ] }]


  publish_to_s3        = true
  tags                 = {
    ManagedBy = "Terraform"
    Environment = "Development"
  }
}

#SNS Topic for Finding Notifications
resource "aws_sns_topic" "user_updates" {
  name = "guardduty-findings"
}


#Deploying the EventBridge rule for GuardDuty findings
module "eventbridge" {
  source = "terraform-aws-modules/eventbridge/aws"
  create_bus = false
  rules = {
    logs = {
      description   = "Capture GuardDuty Findings for EC2 Instances"
      event_pattern = jsonencode({
        "source" : ["aws.guardduty"],
        "detail-type" : ["GuardDuty Finding"],
        "detail" : {
          "resource" : {
            "resourceType" : ["Instance"]
          }
        "severity" : [{
            "numeric" : [">", 5]
          }]
        }
      })
    }
  }

  targets = {
    logs = [{
      name = "send-to-lambda"
      arn  = aws_lambda_function.AutoRemediation.arn
    }]
  }
}


#Security group for isolated instances
resource "aws_security_group" "isolated" {
  name        = "isolated-sg"
  description = "Isolation security group - blocks all traffic"
  vpc_id      = data.aws_vpc.development.id
  
  # No ingress rules = blocks all inbound traffic
  # No egress rules defined = blocks all outbound traffic (after removing default)
  
  tags = {
    Name      = "isolated-sg"
    Purpose   = "GuardDuty-Isolation"
    ManagedBy = "Terraform"
  }
}

# Remove the default egress rule that allows all outbound traffic
resource "aws_vpc_security_group_egress_rule" "isolated_remove_default" {
  security_group_id = aws_security_group.isolated.id
  
  # This effectively removes all egress by not defining any rules
  # AWS creates a default "allow all" egress rule, so we need to revoke it
  ip_protocol = "-1"
  cidr_ipv4   = "127.0.0.1/32"  # Dummy rule to localhost only
}


#Creating the Lambda function for automated remediation
# IAM role for Lambda execution
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "execution_role" {
  name               = "lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Add EC2 permissions policy for Lambda
resource "aws_iam_role_policy" "lambda_ec2_permissions" {
  name = "lambda-ec2-permissions"
  role = aws_iam_role.execution_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:CreateSecurityGroup",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateSnapshot",
          "ec2:DescribeVolumes"
        ]
        Resource = "*"
      }
    ]
  })
}

# Add SNS permissions
resource "aws_iam_role_policy" "lambda_sns" {
  name = "lambda-sns"
  role = aws_iam_role.execution_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.user_updates.arn
      }
    ]
  })
}

#Allow eventbridge to invoke lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.AutoRemediation.function_name
  principal     = "events.amazonaws.com"
}


# Package the Lambda function code
data "archive_file" "Function" {
  type        = "zip"
  source_file = "${path.module}/lambdaFunction.py"
  output_path = "${path.module}/function.zip"
}


# Lambda function
resource "aws_lambda_function" "AutoRemediation" {
  filename      = data.archive_file.Function.output_path
  function_name = "Automated_Remediation"
  role          = aws_iam_role.execution_role.arn
  handler       = "lambdaFunction.lambda_handler"
  runtime = "python3.13"

  environment {
    variables = {
      ENVIRONMENT = "development"
      LOG_LEVEL   = "info"
      SNS_TOPIC = aws_sns_topic.user_updates.arn
      ISOLATION_SG = aws_security_group.isolated.id
    }
  }

  tags = {
    Environment = "development"
    ManagedBy = "Terraform"
  }
}

