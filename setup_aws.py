# setup_aws.py - Helper script to configure AWS resources
import boto3
import os
from dotenv import load_dotenv

load_dotenv()

def setup_aws_resources():
    """Setup AWS security group and key pair"""
    ec2 = boto3.client('ec2', region_name=os.getenv('AWS_REGION', 'us-east-1'))
    
    print("🔧 Setting up AWS resources...")
    
    # 1. Create Security Group
    try:
        sg_response = ec2.create_security_group(
            GroupName='tunnel-platform-sg',
            Description='Security group for Tunnel Platform VPN servers'
        )
        sg_id = sg_response['GroupId']
        print(f"✅ Created security group: {sg_id}")
        
        # Add inbound rules
        ec2.authorize_security_group_ingress(
            GroupId=sg_id,
            IpPermissions=[
                {
                    'IpProtocol': 'tcp',
                    'FromPort': 22,
                    'ToPort': 22,
                    'IpRanges': [{'CidrIp': '0.0.0.0/0', 'Description': 'SSH'}]
                },
                {
                    'IpProtocol': 'udp',
                    'FromPort': 51820,
                    'ToPort': 51820,
                    'IpRanges': [{'CidrIp': '0.0.0.0/0', 'Description': 'WireGuard'}]
                },
                {
                    'IpProtocol': 'icmp',
                    'FromPort': -1,
                    'ToPort': -1,
                    'IpRanges': [{'CidrIp': '0.0.0.0/0', 'Description': 'Ping'}]
                }
            ]
        )
        print("✅ Added security group rules")
        
    except ec2.exceptions.ClientError as e:
        if 'InvalidGroup.Duplicate' in str(e):
            # Get existing security group
            sgs = ec2.describe_security_groups(GroupNames=['tunnel-platform-sg'])
            sg_id = sgs['SecurityGroups'][0]['GroupId']
            print(f"ℹ️  Using existing security group: {sg_id}")
        else:
            raise
    
    # 2. Get latest Ubuntu AMI
    try:
        ami_response = ec2.describe_images(
            Owners=['099720109477'],  # Canonical
            Filters=[
                {'Name': 'name', 'Values': ['ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*']},
                {'Name': 'state', 'Values': ['available']}
            ]
        )
        
        # Sort by creation date and get latest
        images = sorted(ami_response['Images'], key=lambda x: x['CreationDate'], reverse=True)
        ami_id = images[0]['ImageId']
        print(f"✅ Found Ubuntu AMI: {ami_id}")
        
    except Exception as e:
        print(f"❌ Error finding AMI: {e}")
        ami_id = "ami-0866a3c8686eaeeba"  # Fallback
        print(f"ℹ️  Using fallback AMI: {ami_id}")
    
    # 3. Update .env file
    print("\n📝 Updating .env file...")
    
    env_updates = {
        'SECURITY_GROUP_ID': sg_id,
        'AMI_ID': ami_id
    }
    
    # Read existing .env
    env_path = '.env'
    if os.path.exists(env_path):
        with open(env_path, 'r') as f:
            lines = f.readlines()
    else:
        lines = []
    
    # Update or add values
    for key, value in env_updates.items():
        found = False
        for i, line in enumerate(lines):
            if line.startswith(f'{key}='):
                lines[i] = f'{key}={value}\n'
                found = True
                break
        if not found:
            lines.append(f'{key}={value}\n')
    
    # Write back
    with open(env_path, 'w') as f:
        f.writelines(lines)
    
    print("\n✅ AWS setup complete!")
    print(f"\n📋 Add these to your .env file if not already present:")
    print(f"SECURITY_GROUP_ID={sg_id}")
    print(f"AMI_ID={ami_id}")
    print(f"\n⚠️  Note: Make sure you have created an SSH key pair named 'tunnel-key' in AWS Console")
    print("   or run: aws ec2 create-key-pair --key-name tunnel-key --query 'KeyMaterial' --output text > secrets/aws-tunnel-key")

if __name__ == "__main__":
    setup_aws_resources()