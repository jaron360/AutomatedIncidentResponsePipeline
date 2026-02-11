
# AWS GuardDuty Incident Response Pipeline

Automated incident response system that detects and isolates compromised EC2 instances using AWS GuardDuty, EventBridge, and Lambda.

## Architecture Overview

This pipeline automatically responds to security threats by:
1. **Detecting** threats using AWS GuardDuty
2. **Filtering** medium-to-high severity findings (severity > 5)
3. **Triggering** automated remediation via EventBridge
4. **Isolating** compromised EC2 instances with Lambda
5. **Notifying** security teams via SNS

## Components

### GuardDuty Configuration
- Enabled malware protection
- Finding publishing frequency: 15 minutes
- Findings published to S3 for audit trail
- Low severity findings (≤4) automatically archived
- Replica region: us-east-1

### EventBridge Rule
Monitors GuardDuty findings with the following criteria:
- Source: `aws.guardduty`
- Event type: GuardDuty Finding
- Resource type: EC2 Instance
- Severity: Greater than 5 (medium to critical)

### Lambda Auto-Remediation
When triggered, the Lambda function performs these actions:
1. Tags the compromised instance with `Incident: Auto-Isolated`
2. Identifies the instance's network interface
3. Replaces all security groups with an isolation security group
4. Creates snapshots of all attached EBS volumes for forensics
5. Sends SNS notification to security team

### Isolation Security Group
- Blocks all inbound traffic (no ingress rules)
- Blocks all outbound traffic (restricted egress to localhost only)
- Effectively quarantines the instance while preserving state

### SNS Topic
- Topic name: `guardduty-findings`
- Receives notifications when instances are isolated
- Can be subscribed to email, SMS, or other endpoints

## Prerequisites

- AWS Account with appropriate permissions
- Terraform >= 1.0
- Python 3.13 runtime support
- Existing VPC with CIDR block `10.16.0.0/16`

## Deployment

1. Clone this repository
2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Review the planned changes:
   ```bash
   terraform plan
   ```

4. Deploy the infrastructure:
   ```bash
   terraform apply
   ```

## Configuration

### Environment Variables (Lambda)
- `ENVIRONMENT`: Deployment environment (default: development)
- `LOG_LEVEL`: Logging verbosity (default: info)
- `SNS_TOPIC`: ARN of the SNS topic for notifications
- `ISOLATION_SG`: ID of the isolation security group

### Customization

To modify the severity threshold, edit the EventBridge rule in `main.tf`:
```hcl
"severity" : [{
  "numeric" : [">", 5]  # Change this value (0-10 scale)
}]
```

To change finding publishing frequency:
```hcl
finding_publishing_frequency = "FIFTEEN_MINUTES"  # Options: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS
```

## Testing

A test script is provided to simulate GuardDuty findings:
```bash
./test.sh
```

## Monitoring

### CloudWatch Logs
Lambda execution logs are available in CloudWatch Logs:
- Log group: `/aws/lambda/Automated_Remediation`

### GuardDuty Console
View all findings in the GuardDuty console:
- Archived findings: Low severity (≤4)
- Active findings: Medium to critical (>5)

### S3 Bucket
GuardDuty findings are published to S3 for long-term storage and compliance.

## Security Considerations

1. **Isolation is immediate**: Instances are isolated within seconds of detection
2. **Forensics preserved**: EBS snapshots capture the state at time of incident
3. **No data loss**: Instances remain running for investigation
4. **Audit trail**: All actions logged to CloudWatch and findings stored in S3

## Incident Response Workflow

When a threat is detected:

1. GuardDuty identifies suspicious activity
2. EventBridge filters for EC2 instance findings with severity > 5
3. Lambda function is invoked automatically
4. Instance is tagged and isolated from network
5. EBS snapshots created for forensic analysis
6. SNS notification sent to security team
7. Security team investigates using snapshots and logs

## Post-Incident Actions

After investigation:

1. Review CloudWatch logs for Lambda execution details
2. Analyze EBS snapshots for forensic evidence
3. Review GuardDuty finding details in console or S3
4. Determine if instance should be terminated or restored
5. Update security policies based on findings

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

**Warning**: This will delete all resources including S3 buckets with findings data.

## Resources

- [AWS GuardDuty Documentation](https://docs.aws.amazon.com/guardduty/)
- [EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)
- [Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)

