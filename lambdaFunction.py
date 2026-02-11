import boto3
import json
import os

ec2 = boto3.client('ec2')
sns = boto3.client('sns')

ISOLATION_SG = os.environ('ISOLATION_SG')
SNS_TOPIC = os.environ('SNS_TOPIC')

def lambda_handler(event, context):
    print("Event:", json.dumps(event))
    
    detail = event['detail']
    instance_id = detail['resource']['instanceDetails']['instanceId']
    region = event['region']
    
    try:
        # 1️⃣ Tag the instance
        ec2.create_tags(
            Resources=[instance_id],
            Tags=[{'Key': 'Incident', 'Value': 'Auto-Isolated'}]
        )
        
        # 2️⃣ Get current ENI
        eni = ec2.describe_instances(InstanceIds=[instance_id])['Reservations'][0]['Instances'][0]['NetworkInterfaces'][0]['NetworkInterfaceId']
        
        # 3️⃣ Replace SGs with Isolation SG
        ec2.modify_network_interface_attribute(
            NetworkInterfaceId=eni,
            Groups=[ISOLATION_SG]
        )
        
        # 4️⃣ Create snapshot for each volume
        volumes = ec2.describe_instances(InstanceIds=[instance_id])['Reservations'][0]['Instances'][0]['BlockDeviceMappings']
        for v in volumes:
            vol_id = v['Ebs']['VolumeId']
            ec2.create_snapshot(
                VolumeId=vol_id,
                Description=f"Incident snapshot for {instance_id}"
            )
        
        # 5️⃣ Send SNS Notification
        message = f"Instance {instance_id} isolated successfully in region {region}"
        sns.publish(TopicArn=SNS_TOPIC, Message=message, Subject="GuardDuty Auto-Isolation")
        
        print("✅ Isolation completed:", message)
        
    except Exception as e:
        print("❌ Error isolating instance:", e)
        raise e
