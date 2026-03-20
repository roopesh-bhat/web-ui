#!/usr/bin/env python3
"""
FastAPI Web UI for Viewing Evaluation Reports from S3
"""

import asyncio
import os
import json
import boto3
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from typing import List, Optional
import time

import uvicorn
from fastapi import FastAPI, Request, HTTPException, Query
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
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

# Thread pool for running blocking S3 calls from async handlers
_executor = ThreadPoolExecutor(max_workers=20)

# Cache for channels data (TTL: 5 minutes)
channels_cache = {"data": None, "timestamp": 0}
CACHE_TTL = 300  # 5 minutes

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

class ReportsResponse(BaseModel):
    reports: List[ReportInfo]
    total: int
    has_more: bool
    next_token: Optional[str] = None

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

def _fetch_channel_stats(channel: str) -> Optional[ChannelStats]:
    """Sync helper — executes in thread pool, one call per channel."""
    try:
        resp = s3_client.list_objects_v2(
            Bucket=S3_BUCKET,
            Prefix=f"{channel}/",
            MaxKeys=500
        )
    except Exception as err:
        print(f"S3 Error for channel {channel}: {err}")
        return None

    objects = resp.get('Contents', [])
    if not objects:
        return ChannelStats(channel=channel, count=0, latest_date="unknown")

    latest_date = max(obj['LastModified'] for obj in objects).strftime('%Y-%m-%d')
    return ChannelStats(channel=channel, count=len(objects), latest_date=latest_date)


@app.get("/api/channels")
async def get_channels() -> List[ChannelStats]:
    """Get list of available channels with stats (cached for 5 minutes)"""
    try:
        # Check cache first
        current_time = time.time()
        if channels_cache["data"] and (current_time - channels_cache["timestamp"]) < CACHE_TTL:
            print("Returning cached channels data")
            return channels_cache["data"]

        print(f"Fetching channels from S3 bucket: {S3_BUCKET}")

        # Use Delimiter='/' to list top-level prefixes (channels) without
        # scanning every object — avoids loading the entire bucket into memory.
        try:
            prefix_response = s3_client.list_objects_v2(
                Bucket=S3_BUCKET,
                Delimiter='/'
            )
        except Exception as s3_error:
            print(f"S3 Error: {str(s3_error)}")
            raise HTTPException(status_code=500, detail=f"S3 Error: {str(s3_error)}")

        channel_prefixes = [
            p['Prefix'].rstrip('/')
            for p in prefix_response.get('CommonPrefixes', [])
        ]

        # Fetch per-channel stats in parallel — all channels fire concurrently
        # instead of sequentially, so N channels takes ~1 S3 RTT instead of N.
        loop = asyncio.get_event_loop()
        stats = await asyncio.gather(*[
            loop.run_in_executor(_executor, _fetch_channel_stats, ch)
            for ch in sorted(channel_prefixes)
        ])
        result = [s for s in stats if s is not None]

        print(f"Found {len(result)} channels")

        # Update cache
        channels_cache["data"] = result
        channels_cache["timestamp"] = current_time

        return result

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
    limit: int = Query(100, ge=1, le=1000, description="Number of reports to return per page"),
    continuation_token: Optional[str] = Query(None, description="Token for pagination")
) -> ReportsResponse:
    """Get list of reports with optional filtering and pagination"""
    try:
        print(f"Filtering reports - channel: {channel}, date: {date}, limit: {limit}")
        # Build prefix for filtering (only use channel, not date, since dates may be in filenames)
        prefix = ""
        if channel:
            prefix = f"{channel}/"

        print(f"Using S3 prefix: {prefix}")

        reports = []

        # Build S3 list request with pagination
        list_params = {
            'Bucket': S3_BUCKET,
            'Prefix': prefix,
            'MaxKeys': limit * 2  # Fetch more to account for filtering
        }

        if continuation_token:
            list_params['ContinuationToken'] = continuation_token

        try:
            response = s3_client.list_objects_v2(**list_params)
        except Exception as s3_error:
            print(f"S3 Error: {str(s3_error)}")
            raise HTTPException(status_code=500, detail=f"S3 Error: {str(s3_error)}")

        if 'Contents' in response:
            for obj in response['Contents']:
                # Stop if we have enough reports
                if len(reports) >= limit:
                    break

                key = obj['Key']

                # Skip directories
                if key.endswith('/'):
                    continue

                # Extract channel and date from S3 metadata
                parts = key.split('/')
                report_channel = parts[0] if len(parts) > 0 else "unknown"
                filename = parts[-1]

                # Use LastModified from S3 as the date
                last_modified = obj.get('LastModified')
                if last_modified:
                    report_date = last_modified.strftime('%Y-%m-%d')
                else:
                    report_date = "unknown"

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

        # Limit to requested number
        reports = reports[:limit]

        # Determine if there are more results
        has_more = response.get('IsTruncated', False)
        next_token = response.get('NextContinuationToken') if has_more else None

        return ReportsResponse(
            reports=reports,
            total=len(reports),
            has_more=has_more,
            next_token=next_token
        )

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error fetching reports: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error fetching reports: {str(e)}")

@app.get("/api/report/{path:path}")
async def get_report_content(path: str):
    """Get report content from S3 - serves HTML directly in new tab"""
    try:
        response = s3_client.get_object(Bucket=S3_BUCKET, Key=path)
        body = response['Body']

        # Stream HTML directly — avoids buffering potentially large files in memory
        if path.endswith('.html'):
            return StreamingResponse(
                body.iter_chunks(chunk_size=65536),
                media_type="text/html; charset=utf-8"
            )

        # JSON/other files are typically small — read and parse
        content = body.read()
        try:
            return JSONResponse(content=json.loads(content))
        except json.JSONDecodeError:
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
    uvicorn.run(app, host="0.0.0.0", port=port, loop="uvloop", http="httptools")
