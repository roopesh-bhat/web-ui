#!/usr/bin/env python3
"""
FastAPI Web UI for Viewing Evaluation Reports from S3
"""

import os
import json
import boto3
from datetime import datetime
from typing import List, Dict, Optional
from pathlib import Path

import uvicorn
from fastapi import FastAPI, Request, HTTPException, Query
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

# Initialize FastAPI app
app = FastAPI(
    title="Evaluation Reports Viewer",
    description="Web UI for viewing evaluation reports from S3",
    version="1.0.0"
)

# Setup templates and static files
templates = Jinja2Templates(directory="templates")
app.mount("/static", StaticFiles(directory="static", html=True), name="static")

# S3 Configuration
S3_BUCKET = os.getenv("S3_BUCKET", "agentix-evaluation-reports-dev")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

# Initialize S3 client
s3_client = boto3.client('s3', region_name=AWS_REGION)

class ReportInfo(BaseModel):
    key: str
    channel: str
    date: str
    size: int
    last_modified: datetime
    filename: str

class ChannelStats(BaseModel):
    channel: str
    count: int
    latest_date: str

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    """Home page with report browser"""
    return templates.TemplateResponse("index.html", {"request": request})

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Test S3 connection
        s3_client.head_bucket(Bucket=S3_BUCKET)
        return {
            "status": "healthy",
            "timestamp": datetime.now().isoformat(),
            "s3_bucket": S3_BUCKET,
            "aws_region": AWS_REGION
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

@app.get("/api/channels")
async def get_channels() -> List[ChannelStats]:
    """Get list of available channels with stats"""
    try:
        print(f"Fetching channels from S3 bucket: {S3_BUCKET}")
        channel_stats = {}
        continuation_token = None

        # Paginate through all objects in the bucket
        while True:
            try:
                if continuation_token:
                    response = s3_client.list_objects_v2(
                        Bucket=S3_BUCKET,
                        ContinuationToken=continuation_token
                    )
                else:
                    response = s3_client.list_objects_v2(Bucket=S3_BUCKET)
            except Exception as s3_error:
                print(f"S3 Error: {str(s3_error)}")
                raise HTTPException(status_code=500, detail=f"S3 Error: {str(s3_error)}")

            if 'Contents' in response:
                for obj in response['Contents']:
                    key = obj['Key']

                    # Extract channel from path (assuming format: channel/date/filename)
                    parts = key.split('/')
                    if len(parts) >= 2:
                        channel = parts[0]
                        date_str = parts[1] if len(parts) > 1 else "unknown"

                        if channel not in channel_stats:
                            channel_stats[channel] = {
                                'count': 0,
                                'latest_date': date_str
                            }

                        channel_stats[channel]['count'] += 1

                        # Update latest date if this is more recent
                        if date_str > channel_stats[channel]['latest_date']:
                            channel_stats[channel]['latest_date'] = date_str

            # Check if there are more results to fetch
            if response.get('IsTruncated'):
                continuation_token = response.get('NextContinuationToken')
            else:
                break

        print(f"Found {len(channel_stats)} channels")
        return [
            ChannelStats(
                channel=channel,
                count=stats['count'],
                latest_date=stats['latest_date']
            )
            for channel, stats in sorted(channel_stats.items())
        ]

    except HTTPException:
        raise
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Error fetching channels: {str(e)}")

@app.get("/api/reports")
async def get_reports(
    channel: Optional[str] = Query(None, description="Filter by channel"),
    date: Optional[str] = Query(None, description="Filter by date (YYYY-MM-DD)"),
    limit: int = Query(100, description="Maximum number of reports to return")
) -> List[ReportInfo]:
    """Get list of reports with optional filtering"""
    try:
        print(f"Filtering reports - channel: {channel}, date: {date}")
        # Build prefix for filtering
        prefix = ""
        if channel:
            prefix = f"{channel}/"
            if date:
                prefix = f"{channel}/{date}/"
        
        print(f"Using S3 prefix: {prefix}")
        
        response = s3_client.list_objects_v2(
            Bucket=S3_BUCKET,
            Prefix=prefix,
            MaxKeys=limit
        )
        
        if 'Contents' not in response:
            return []
        
        reports = []
        
        for obj in response['Contents']:
            key = obj['Key']
            
            # Skip directories
            if key.endswith('/'):
                continue
            
            # Extract channel and date from path
            parts = key.split('/')
            report_channel = parts[0] if len(parts) > 0 else "unknown"
            report_date = parts[1] if len(parts) > 1 else "unknown"
            filename = parts[-1]
            
            # Apply date filter if specified
            if date and report_date != date:
                continue
            
            reports.append(ReportInfo(
                key=key,
                channel=report_channel,
                date=report_date,
                size=obj['Size'],
                last_modified=obj['LastModified'],
                filename=filename
            ))
        
        # Sort by last modified date (newest first)
        reports.sort(key=lambda x: x.last_modified, reverse=True)
        
        return reports
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching reports: {str(e)}")

@app.get("/api/report/{path:path}")
async def get_report_content(path: str):
    """Get report content from S3 - serves HTML directly in new tab"""
    try:
        response = s3_client.get_object(Bucket=S3_BUCKET, Key=path)
        content = response['Body'].read()

        # Check if it's an HTML file - serve it directly
        if path.endswith('.html'):
            return HTMLResponse(content=content.decode('utf-8', errors='ignore'))

        # Try to parse as JSON for pretty display
        try:
            json_content = json.loads(content)
            return JSONResponse(content=json_content)
        except json.JSONDecodeError:
            # Return as plain text if not JSON
            return {"content": content.decode('utf-8', errors='ignore')}

    except s3_client.exceptions.NoSuchKey:
        raise HTTPException(status_code=404, detail="Report not found")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching report: {str(e)}")

@app.get("/api/report/{path:path}/download")
async def download_report(path: str):
    """Generate presigned URL for downloading report"""
    try:
        url = s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': S3_BUCKET, 'Key': path},
            ExpiresIn=3600  # 1 hour
        )
        return {"download_url": url}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error generating download URL: {str(e)}")

@app.get("/reports/{channel}", response_class=HTMLResponse)
async def view_channel_reports(request: Request, channel: str):
    """View reports for a specific channel"""
    return templates.TemplateResponse(
        "channel_reports.html", 
        {"request": request, "channel": channel}
    )

@app.get("/report/{path:path}", response_class=HTMLResponse)
async def view_report(request: Request, path: str):
    """View a specific report"""
    return templates.TemplateResponse(
        "report_viewer.html", 
        {"request": request, "report_path": path}
    )

if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
