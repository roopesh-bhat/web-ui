# Eval Report Viewer

A web-based UI for viewing and browsing evaluation reports stored in AWS S3. Built with FastAPI and modern web technologies.

![Python](https://img.shields.io/badge/python-3.11-blue.svg)
![FastAPI](https://img.shields.io/badge/FastAPI-0.104.1-green.svg)
![Docker](https://img.shields.io/badge/docker-ready-blue.svg)

## Features

- 📊 **Browse all evaluation reports** from S3 bucket
- 🔍 **Search and filter** reports by channel and date
- 📈 **Real-time statistics** showing total channels and reports
- 🎨 **Clean, modern UI** with responsive design
- 🚀 **Docker support** for easy deployment
- ☁️ **AWS ECS ready** with included deployment scripts
- 📄 **Direct HTML viewing** - Reports open in new browser tabs
- ♾️ **Pagination support** - Shows all folders, not limited to first 1000

## Quick Start

### Local Development

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-org/eval-report-viewer.git
   cd eval-report-viewer
   ```

2. **Create virtual environment**
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

4. **Set environment variables**
   ```bash
   export S3_BUCKET="agentix-evaluation-reports-dev"
   export AWS_REGION="us-east-1"
   export PORT=8080
   ```

5. **Run the application**
   ```bash
   python3 app.py
   ```

6. **Open your browser**
   Navigate to `http://localhost:8080`

### Using Docker

1. **Build the Docker image**
   ```bash
   docker build -t eval-report-viewer .
   ```

2. **Run the container**
   ```bash
   docker run -p 8080:8080 \
     -e S3_BUCKET=agentix-evaluation-reports-dev \
     -e AWS_REGION=us-east-1 \
     eval-report-viewer
   ```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `S3_BUCKET` | S3 bucket name containing evaluation reports | `agentix-evaluation-reports-dev` |
| `AWS_REGION` | AWS region where the bucket is located | `us-east-1` |
| `PORT` | Port on which the application runs | `8080` |

## Project Structure

```
eval-report-viewer/
├── app.py                      # Main FastAPI application
├── requirements.txt            # Python dependencies
├── Dockerfile                  # Docker configuration
├── .gitignore                  # Git ignore rules
├── README.md                   # This file
├── templates/                  # HTML templates
│   ├── index.html             # Main dashboard
│   ├── channel_reports.html   # Channel reports listing
│   └── report_viewer.html     # Individual report viewer
├── static/                     # Static assets (CSS, JS, images)
├── terraform/                  # Infrastructure as Code
├── deploy.sh                   # Simple deployment script
└── build_and_deploy.sh         # Full deployment automation
```

## API Endpoints

### GET /
Main dashboard page showing all channels

### GET /api/channels
Returns list of all channels with statistics
```json
[
  {
    "channel": "channel_name",
    "count": 42,
    "latest_date": "2025-12-09"
  }
]
```

### GET /api/reports?channel={channel}&date={date}
Returns list of reports for a specific channel
```json
[
  {
    "key": "channel/date/filename.html",
    "filename": "filename.html",
    "date": "2025-12-09",
    "size": 12345,
    "last_modified": "2025-12-09T10:30:00"
  }
]
```

### GET /api/report/{path}
Serves the actual report content (HTML, JSON, or text)

### GET /health
Health check endpoint
```json
{
  "status": "healthy",
  "bucket": "bucket-name",
  "timestamp": "2025-12-09T10:30:00"
}
```

## Deployment to AWS ECS

### Option 1: Automated Deployment Script

```bash
./build_and_deploy.sh
```

This script will:
- Create ECR repository if needed
- Build Docker image
- Push to ECR
- Update ECS service
- Wait for deployment to complete

### Option 2: Manual Deployment

1. **Create ECR repository**
   ```bash
   aws ecr create-repository --repository-name eval-report-viewer --region us-east-1
   ```

2. **Login to ECR**
   ```bash
   aws ecr get-login-password --region us-east-1 | \
     docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
   ```

3. **Build and push**
   ```bash
   docker build --platform linux/amd64 -t eval-report-viewer .
   docker tag eval-report-viewer:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/eval-report-viewer:latest
   docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/eval-report-viewer:latest
   ```

4. **Deploy to ECS**
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

## Required IAM Permissions

The ECS task role needs the following S3 permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::agentix-evaluation-reports-dev",
        "arn:aws:s3:::agentix-evaluation-reports-dev/*"
      ]
    }
  ]
}
```

## Usage Instructions

### For End Users

1. **View all channels**: The main page displays all available evaluation channels
2. **Browse reports**: Click on any channel to see all reports in that channel
3. **Filter by date**: Use the date filter to narrow down reports
4. **View report**: Click on any report filename to open it in a new tab

### For Report Uploaders

1. Create a folder in the S3 bucket with your channel name
2. Upload your evaluation reports (HTML, JSON, or text files)
3. Reports will automatically appear in the web UI
4. Folder structure: `channel-name/date/report-file.html`

## Troubleshooting

### Application won't start
- Check AWS credentials are configured correctly
- Verify S3 bucket exists and is accessible
- Check environment variables are set

### No channels showing
- Verify S3 bucket has content
- Check folder structure matches expected format: `channel/date/file`
- Review application logs for errors

### Reports not loading
- Ensure files are valid HTML/JSON/text
- Check S3 bucket permissions
- Verify file paths in S3

## Recent Updates

### Version 1.0.0 (December 2025)
- ✅ Added S3 pagination support to show all folders
- ✅ Fixed UI layout with proper text spacing
- ✅ Added help section with usage instructions
- ✅ Reports now open in new browser tabs
- ✅ Removed unnecessary "Latest" date field
- ✅ Added contact information for support
- ✅ Improved error handling and logging

## Technology Stack

- **Backend**: FastAPI (Python 3.11)
- **Frontend**: Vanilla JavaScript, HTML5, CSS3
- **Cloud**: AWS S3, ECS, ECR
- **Infrastructure**: Terraform
- **Containerization**: Docker

## Contributing

This project is maintained by the RealPage Evals Team. For contributions or issues:

1. Contact the team before making changes
2. Follow existing code style and patterns
3. Test locally before submitting
4. Update documentation as needed

## Support

For any issues or questions, please contact:

- **Evals Team**: P Roopesh Bhat [prathikantamroopesh.bhat@realpage.com](mailto:prathikantamroopesh.bhat@realpage.com)
- **Manager**: Bhawana Mishra ([bhawana.mishra@realpage.com](mailto:bhawana.mishra@realpage.com))

## License

Copyright © 2025 RealPage, Inc. All rights reserved.

---

**Built with ❤️ by the RealPage Evals Team**
