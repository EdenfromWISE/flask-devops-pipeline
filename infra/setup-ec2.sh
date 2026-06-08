#!/usr/bin/env bash
# Bootstrap an Ubuntu EC2 instance for the flask-devops-pipeline.
# Run once on a fresh instance: ssh ubuntu@<EC2-IP>, then bash setup-ec2.sh

set -euo pipefail

PROJECT_DIR="/home/ubuntu/flask-devops-pipeline"

echo "==> Updating system packages"
sudo apt-get update -y
sudo apt-get upgrade -y

echo "==> Installing Docker"
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Allowing 'ubuntu' user to run docker without sudo"
sudo usermod -aG docker ubuntu

echo "==> Creating project directory and log files"
mkdir -p "$PROJECT_DIR"
sudo touch /var/log/deploy.log /var/log/monitor.log
sudo chown ubuntu:ubuntu /var/log/deploy.log /var/log/monitor.log

echo "==> Done. Log out and back in for docker group membership to take effect:"
echo "    exit"
echo "    ssh -i <key>.pem ubuntu@<EC2-IP>"
echo ""
echo "Verify with: docker run hello-world"
