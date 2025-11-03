import asyncio
import boto3
import os
import time
import logging
from models import Instance, AllocState, Peer
from sqlalchemy.orm import Session
from botocore.exceptions import ClientError
from functools import partial

logger = logging.getLogger(__name__)

WG_SUBNET_PREFIX = os.getenv("WG_SUBNET_PREFIX", "10.10.0")
WG_PORT = int(os.getenv("WG_PORT", 51820))

async def launch_instance_async(db: Session, instance: Instance):
    """Launch EC2 + WireGuard (auto-creates SG, no external setup needed)"""
    try:
        # Get latest Ubuntu AMI
        ssm = boto3.client('ssm', region_name=instance.region)
        ami_id = ssm.get_parameter(
            Name='/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id'
        )['Parameter']['Value']

        ec2 = boto3.client('ec2', region_name=instance.region)

        # Create unique security group
        sg_name = f"wg-vpn-{instance.id}-{int(time.time())}"
        sg = ec2.create_security_group(
            GroupName=sg_name,
            Description="WireGuard VPN"
        )
        sg_id = sg['GroupId']

        # Open ports
        ec2.authorize_security_group_ingress(
            GroupId=sg_id,
            IpPermissions=[
                {'IpProtocol': 'udp', 'FromPort': WG_PORT, 'ToPort': WG_PORT, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]},
                {'IpProtocol': 'tcp', 'FromPort': 22, 'ToPort': 22, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]}
            ]
        )

        # Full user-data script
        user_data = f"""#!/bin/bash
set -e
apt-get update -y
apt-get install -y wireguard jq curl
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
cat > /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = {WG_SUBNET_PREFIX}.1/24
PrivateKey = $(cat /etc/wireguard/private.key)
ListenPort = {WG_PORT}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
touch /root/.setup_complete
curl -s http://169.254.169.254/latest/meta-data/public-ipv4 > /etc/wireguard/public_ip.txt
"""

        # Launch EC2
        response = ec2.run_instances(
            ImageId=ami_id,
            InstanceType=instance.instance_type,
            MinCount=1,
            MaxCount=1,
            SecurityGroupIds=[sg_id],
            UserData=user_data,
            TagSpecifications=[{
                'ResourceType': 'instance',
                'Tags': [{'Key': 'Name', 'Value': f"VPN-{instance.id}"}]
            }]
        )

        aws_id = response['Instances'][0]['InstanceId']
        instance.aws_instance_id = aws_id
        db.commit()
        logger.info(f"EC2 launched: {aws_id}")

        # Wait for running
        waiter = ec2.get_waiter('instance_running')
        waiter.wait(InstanceIds=[aws_id])

        # Get public IP
        desc = ec2.describe_instances(InstanceIds=[aws_id])
        public_ip = desc['Reservations'][0]['Instances'][0]['PublicIpAddress']
        instance.public_ip = public_ip
        instance.state = "running"

        # Allocate IPs
        alloc = AllocState(instance_id=instance.id, last_octet=2)
        db.add(alloc)
        db.commit()

        logger.info(f"Instance ready: {public_ip} | WG on {WG_PORT}")
    except Exception as e:
        logger.error(f"Launch failed: {str(e)}")
        instance.state = "failed"
        db.commit()
        raise

async def wait_for_setup_async(db: Session, instance: Instance):
    """Wait for WireGuard setup to complete"""
    pass

async def add_peer_async(db: Session, instance: Instance, peer: Peer):
    """Add peer to WireGuard server"""
    pass

def stop_instance(aws_instance_id: str):
    """Stop EC2 instance - FIXED SIGNATURE"""
    try:
        ec2 = boto3.client('ec2')
        ec2.stop_instances(InstanceIds=[aws_instance_id])
        logger.info(f"Stopped instance: {aws_instance_id}")
    except ClientError as e:
        logger.error(f"Failed to stop instance: {str(e)}")
        raise

def terminate_instance(aws_instance_id: str):
    """Terminate EC2 instance - FIXED SIGNATURE"""
    try:
        ec2 = boto3.client('ec2')
        ec2.terminate_instances(InstanceIds=[aws_instance_id])
        logger.info(f"Terminated instance: {aws_instance_id}")
    except ClientError as e:
        logger.error(f"Failed to terminate instance: {str(e)}")
        raise