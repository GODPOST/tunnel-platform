# Tunnel Platform

Personal VPN Management Platform - Deploy your own WireGuard VPN servers on AWS.

## Quick Start

1. Edit `.env` with your AWS credentials
2. Run: `./deploy.sh`
3. Access: http://localhost

## Documentation

See SETUP.md for detailed setup instructions.

## Features

- 🚀 One-click VPN server deployment on AWS
- 📱 Multi-device support with WireGuard
- 🔐 Secure authentication and encryption
- 📊 Instance and peer management
- 📲 QR code generation for mobile devices

## Tech Stack

- **Backend**: FastAPI + SQLAlchemy + PostgreSQL
- **Frontend**: React + Vite + TailwindCSS
- **Infrastructure**: Docker + AWS EC2
- **VPN**: WireGuard

## License

MIT
