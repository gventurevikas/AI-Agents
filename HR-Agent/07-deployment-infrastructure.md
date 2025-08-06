# Deployment & Infrastructure Requirements

## 1. Overview

### 1.1 Purpose
The Deployment & Infrastructure Requirements document outlines the complete deployment strategy, infrastructure setup, and operational requirements for the AI interview system. It covers containerization, orchestration, monitoring, security, and scalability considerations.

### 1.2 Scope
This document covers the entire deployment lifecycle including development, staging, and production environments, infrastructure provisioning, monitoring, security, backup strategies, and disaster recovery.

## 2. Infrastructure Architecture

### 2.1 System Architecture Overview

#### 2.1.1 High-Level Architecture
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Load Balancer │    │   Web Server    │    │  Application    │
│   (NGINX)       │───▶│   (NGINX)       │───▶│   (Node.js)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Media Server  │    │   Database      │    │   Cache         │
│   (FreeSWITCH)  │◀───│   (PostgreSQL)  │◀───│   (Redis)       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

#### 2.1.2 Component Distribution
- **Frontend**: Angular application served via NGINX
- **Backend**: Node.js/Express.js API servers
- **Database**: PostgreSQL with read replicas
- **Cache**: Redis for session and data caching
- **Media Server**: FreeSWITCH for audio processing
- **Storage**: AWS S3 for file storage
- **Monitoring**: Prometheus + Grafana
- **Logging**: ELK Stack (Elasticsearch, Logstash, Kibana)

### 2.2 Environment Strategy

#### 2.2.1 Development Environment
- **Purpose**: Local development and testing
- **Infrastructure**: Docker Compose for local development
- **Database**: Local PostgreSQL instance
- **Storage**: Local file system
- **Monitoring**: Basic logging and debugging

#### 2.2.2 Staging Environment
- **Purpose**: Pre-production testing and validation
- **Infrastructure**: Kubernetes cluster (smaller scale)
- **Database**: PostgreSQL with test data
- **Storage**: S3 bucket for staging
- **Monitoring**: Full monitoring stack

#### 2.2.3 Production Environment
- **Purpose**: Live production system
- **Infrastructure**: Kubernetes cluster (full scale)
- **Database**: PostgreSQL with high availability
- **Storage**: S3 with backup and redundancy
- **Monitoring**: Comprehensive monitoring and alerting

## 3. Containerization Strategy

### 3.1 Docker Configuration

#### 3.1.1 Application Dockerfile
```dockerfile
# Node.js Application Dockerfile
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nodejs -u 1001

# Change ownership
RUN chown -R nodejs:nodejs /app
USER nodejs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Start application
CMD ["npm", "start"]
```

#### 3.1.2 Angular Frontend Dockerfile
```dockerfile
# Angular Frontend Dockerfile
FROM node:18-alpine as build

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY . .

# Build application
RUN npm run build --prod

# Production stage
FROM nginx:alpine

# Copy built application
COPY --from=build /app/dist/* /usr/share/nginx/html/

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Expose port
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
```

#### 3.1.3 FreeSWITCH Dockerfile
```dockerfile
# FreeSWITCH Dockerfile
FROM debian:bullseye-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    wget \
    gnupg2 \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Add FreeSWITCH repository
RUN wget -O - https://files.freeswitch.org/repo/deb/debian-release/fsstretch-archive-keyring.asc | apt-key add -
RUN echo "deb http://files.freeswitch.org/repo/deb/debian-release/ `lsb_release -sc` main" > /etc/apt/sources.list.d/freeswitch.list

# Install FreeSWITCH
RUN apt-get update && apt-get install -y \
    freeswitch-meta-all \
    && rm -rf /var/lib/apt/lists/*

# Copy configuration files
COPY freeswitch.xml /etc/freeswitch/freeswitch.xml
COPY vars.xml /etc/freeswitch/vars.xml

# Expose ports
EXPOSE 5060 5061 5080 5081 8021 16384-16484

# Start FreeSWITCH
CMD ["freeswitch", "-c"]
```

### 3.2 Docker Compose Configuration

#### 3.2.1 Development Docker Compose
```yaml
version: '3.8'

services:
  # Frontend
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.dev
    ports:
      - "4200:4200"
    volumes:
      - ./frontend:/app
      - /app/node_modules
    environment:
      - NODE_ENV=development
    depends_on:
      - backend

  # Backend API
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile.dev
    ports:
      - "3000:3000"
    volumes:
      - ./backend:/app
      - /app/node_modules
    environment:
      - NODE_ENV=development
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/interview_db
      - REDIS_URL=redis://redis:6379
    depends_on:
      - postgres
      - redis

  # Database
  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=interview_db
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-db.sql:/docker-entrypoint-initdb.d/init-db.sql

  # Redis Cache
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  # FreeSWITCH Media Server
  freeswitch:
    build:
      context: ./freeswitch
      dockerfile: Dockerfile
    ports:
      - "5060:5060"
      - "5061:5061"
      - "5080:5080"
      - "5081:5081"
      - "8021:8021"
      - "16384-16484:16384-16484/udp"
    volumes:
      - freeswitch_data:/var/lib/freeswitch
      - ./freeswitch/config:/etc/freeswitch

  # NGINX Reverse Proxy
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./nginx/ssl:/etc/nginx/ssl
    depends_on:
      - frontend
      - backend

volumes:
  postgres_data:
  redis_data:
  freeswitch_data:
```

### 3.3 Kubernetes Configuration

#### 3.3.1 Production Kubernetes Deployment
```yaml
# Backend API Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: interview-backend
  namespace: interview-system
spec:
  replicas: 3
  selector:
    matchLabels:
      app: interview-backend
  template:
    metadata:
      labels:
        app: interview-backend
    spec:
      containers:
      - name: backend
        image: interview-backend:latest
        ports:
        - containerPort: 3000
        env:
        - name: NODE_ENV
          value: "production"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: url
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5

---
# Frontend Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: interview-frontend
  namespace: interview-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: interview-frontend
  template:
    metadata:
      labels:
        app: interview-frontend
    spec:
      containers:
      - name: frontend
        image: interview-frontend:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

---
# Service Configuration
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: interview-system
spec:
  selector:
    app: interview-backend
  ports:
  - protocol: TCP
    port: 80
    targetPort: 3000
  type: ClusterIP

---
# Ingress Configuration
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: interview-ingress
  namespace: interview-system
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - interview.example.com
    secretName: interview-tls
  rules:
  - host: interview.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend-service
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
```

## 4. Database Configuration

### 4.1 PostgreSQL Setup

#### 4.1.1 Production Database Configuration
```sql
-- Database initialization script
CREATE DATABASE interview_db;

-- Create application user
CREATE USER interview_user WITH PASSWORD 'secure_password';

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE interview_db TO interview_user;

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Set up connection pooling
-- Install and configure PgBouncer for connection pooling
```

#### 4.1.2 Database Backup Strategy
```bash
#!/bin/bash
# Database backup script

# Configuration
DB_NAME="interview_db"
DB_USER="interview_user"
BACKUP_DIR="/backups/postgres"
RETENTION_DAYS=30

# Create backup directory
mkdir -p $BACKUP_DIR

# Generate backup filename
BACKUP_FILE="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).sql"

# Perform backup
pg_dump -h localhost -U $DB_USER -d $DB_NAME > $BACKUP_FILE

# Compress backup
gzip $BACKUP_FILE

# Remove old backups
find $BACKUP_DIR -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

# Upload to S3 (if configured)
if [ -n "$S3_BUCKET" ]; then
    aws s3 cp $BACKUP_FILE.gz s3://$S3_BUCKET/database-backups/
fi
```

### 4.2 Redis Configuration

#### 4.2.1 Redis Production Configuration
```conf
# redis.conf
# Network
bind 0.0.0.0
port 6379
timeout 300

# Memory management
maxmemory 2gb
maxmemory-policy allkeys-lru

# Persistence
save 900 1
save 300 10
save 60 10000
rdbcompression yes
rdbchecksum yes

# Security
requirepass your_redis_password

# Logging
loglevel notice
logfile /var/log/redis/redis.log

# Performance
tcp-keepalive 60
tcp-backlog 511
```

## 5. Monitoring & Observability

### 5.1 Prometheus Configuration

#### 5.1.1 Prometheus Setup
```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  - job_name: 'interview-backend'
    static_configs:
      - targets: ['backend:3000']
    metrics_path: '/metrics'
    scrape_interval: 5s

  - job_name: 'interview-frontend'
    static_configs:
      - targets: ['frontend:80']
    metrics_path: '/metrics'

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
```

#### 5.1.2 Alert Rules
```yaml
# alert_rules.yml
groups:
  - name: interview-system
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }}"

      - alert: HighResponseTime
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 2
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High response time detected"
          description: "95th percentile response time is {{ $value }}s"

      - alert: DatabaseConnections
        expr: pg_stat_activity_count > 80
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "High database connections"
          description: "Database has {{ $value }} active connections"
```

### 5.2 Grafana Dashboards

#### 5.2.1 Application Dashboard
```json
{
  "dashboard": {
    "title": "Interview System Dashboard",
    "panels": [
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "{{method}} {{endpoint}}"
          }
        ]
      },
      {
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          }
        ]
      },
      {
        "title": "Error Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=~\"5..\"}[5m])",
            "legendFormat": "5xx errors"
          }
        ]
      }
    ]
  }
}
```

### 5.3 Logging Configuration

#### 5.3.1 ELK Stack Setup
```yaml
# logstash.conf
input {
  beats {
    port => 5044
  }
}

filter {
  if [fields][service] == "interview-backend" {
    grok {
      match => { "message" => "%{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:level} %{GREEDYDATA:message}" }
    }
    date {
      match => [ "timestamp", "ISO8601" ]
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "interview-logs-%{+YYYY.MM.dd}"
  }
}
```

## 6. Security Configuration

### 6.1 SSL/TLS Configuration

#### 6.1.1 NGINX SSL Configuration
```nginx
# nginx.conf
server {
    listen 80;
    server_name interview.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name interview.example.com;

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Frontend
    location / {
        proxy_pass http://frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # API
    location /api {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 6.2 Network Security

#### 6.2.1 Firewall Configuration
```bash
#!/bin/bash
# Firewall configuration script

# Clear existing rules
iptables -F
iptables -X

# Set default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow HTTP/HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow FreeSWITCH ports
iptables -A INPUT -p tcp --dport 5060 -j ACCEPT
iptables -A INPUT -p tcp --dport 5061 -j ACCEPT
iptables -A INPUT -p tcp --dport 5080 -j ACCEPT
iptables -A INPUT -p tcp --dport 5081 -j ACCEPT
iptables -A INPUT -p tcp --dport 8021 -j ACCEPT
iptables -A INPUT -p udp --dport 16384:16484 -j ACCEPT

# Save rules
iptables-save > /etc/iptables/rules.v4
```

## 7. Backup & Disaster Recovery

### 7.1 Backup Strategy

#### 7.1.1 Automated Backup Script
```bash
#!/bin/bash
# Comprehensive backup script

# Configuration
BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Create backup directory
mkdir -p $BACKUP_DIR/{database,uploads,config}

# Database backup
echo "Backing up database..."
pg_dump -h localhost -U interview_user -d interview_db | gzip > $BACKUP_DIR/database/backup_$DATE.sql.gz

# File uploads backup
echo "Backing up uploads..."
tar -czf $BACKUP_DIR/uploads/uploads_$DATE.tar.gz /var/uploads/

# Configuration backup
echo "Backing up configuration..."
tar -czf $BACKUP_DIR/config/config_$DATE.tar.gz /etc/nginx/ /etc/postgresql/ /etc/redis/

# Upload to S3
echo "Uploading to S3..."
aws s3 sync $BACKUP_DIR s3://interview-backups/

# Cleanup old backups
find $BACKUP_DIR -name "*.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup completed successfully"
```

### 7.2 Disaster Recovery Plan

#### 7.2.1 Recovery Procedures
```bash
#!/bin/bash
# Disaster recovery script

# Configuration
BACKUP_S3_BUCKET="interview-backups"
RESTORE_DIR="/restore"

# Download latest backup from S3
echo "Downloading latest backup from S3..."
aws s3 sync s3://$BACKUP_S3_BUCKET $RESTORE_DIR

# Restore database
echo "Restoring database..."
gunzip -c $RESTORE_DIR/database/backup_*.sql.gz | psql -h localhost -U interview_user -d interview_db

# Restore uploads
echo "Restoring uploads..."
tar -xzf $RESTORE_DIR/uploads/uploads_*.tar.gz -C /

# Restore configuration
echo "Restoring configuration..."
tar -xzf $RESTORE_DIR/config/config_*.tar.gz -C /

# Restart services
echo "Restarting services..."
systemctl restart nginx
systemctl restart postgresql
systemctl restart redis

echo "Recovery completed successfully"
```

## 8. Performance Optimization

### 8.1 Application Performance

#### 8.1.1 Node.js Performance Tuning
```javascript
// Performance configuration
const performanceConfig = {
  // Cluster configuration
  cluster: {
    enabled: true,
    workers: process.env.CPU_COUNT || require('os').cpus().length
  },
  
  // Memory management
  memory: {
    maxOldSpaceSize: 2048, // 2GB
    gcInterval: 30000 // 30 seconds
  },
  
  // Connection pooling
  database: {
    pool: {
      min: 5,
      max: 20,
      acquireTimeoutMillis: 30000,
      createTimeoutMillis: 30000,
      destroyTimeoutMillis: 5000,
      idleTimeoutMillis: 30000,
      reapIntervalMillis: 1000,
      createRetryIntervalMillis: 200
    }
  },
  
  // Redis configuration
  redis: {
    maxRetriesPerRequest: 3,
    retryDelayOnFailover: 100,
    enableReadyCheck: false,
    maxLoadingTimeout: 10000
  }
};
```

### 8.2 Database Performance

#### 8.2.1 PostgreSQL Optimization
```sql
-- PostgreSQL performance tuning
-- Memory configuration
SET shared_buffers = '256MB';
SET effective_cache_size = '1GB';
SET work_mem = '4MB';
SET maintenance_work_mem = '64MB';

-- Connection configuration
SET max_connections = 200;
SET shared_preload_libraries = 'pg_stat_statements';

-- Query optimization
SET random_page_cost = 1.1;
SET effective_io_concurrency = 200;

-- Logging for performance analysis
SET log_statement = 'all';
SET log_min_duration_statement = 1000;
```

## 9. Scaling Strategy

### 9.1 Horizontal Scaling

#### 9.1.1 Auto-scaling Configuration
```yaml
# Horizontal Pod Autoscaler
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: interview-backend-hpa
  namespace: interview-system
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: interview-backend
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### 9.2 Database Scaling

#### 9.2.1 Read Replicas Setup
```yaml
# PostgreSQL StatefulSet with read replicas
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: interview-system
spec:
  serviceName: postgres
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15
        env:
        - name: POSTGRES_DB
          value: interview_db
        - name: POSTGRES_USER
          value: interview_user
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: password
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

## 10. Deployment Automation

### 10.1 CI/CD Pipeline

#### 10.1.1 GitHub Actions Workflow
```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Node.js
      uses: actions/setup-node@v3
      with:
        node-version: '18'
        cache: 'npm'
    
    - name: Install dependencies
      run: npm ci
    
    - name: Run tests
      run: npm test
    
    - name: Run linting
      run: npm run lint

  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Build Docker images
      run: |
        docker build -t interview-backend:${{ github.sha }} ./backend
        docker build -t interview-frontend:${{ github.sha }} ./frontend
    
    - name: Push to registry
      run: |
        docker tag interview-backend:${{ github.sha }} ${{ secrets.REGISTRY }}/interview-backend:${{ github.sha }}
        docker tag interview-frontend:${{ github.sha }} ${{ secrets.REGISTRY }}/interview-frontend:${{ github.sha }}
        docker push ${{ secrets.REGISTRY }}/interview-backend:${{ github.sha }}
        docker push ${{ secrets.REGISTRY }}/interview-frontend:${{ github.sha }}

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup kubectl
      uses: azure/setup-kubectl@v3
    
    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/interview-backend backend=${{ secrets.REGISTRY }}/interview-backend:${{ github.sha }}
        kubectl set image deployment/interview-frontend frontend=${{ secrets.REGISTRY }}/interview-frontend:${{ github.sha }}
    
    - name: Wait for deployment
      run: |
        kubectl rollout status deployment/interview-backend
        kubectl rollout status deployment/interview-frontend
```

### 10.2 Infrastructure as Code

#### 10.2.1 Terraform Configuration
```hcl
# main.tf
provider "aws" {
  region = "us-west-2"
}

# VPC Configuration
resource "aws_vpc" "interview_vpc" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "interview-vpc"
  }
}

# EKS Cluster
resource "aws_eks_cluster" "interview_cluster" {
  name     = "interview-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.27"

  vpc_config {
    subnet_ids = aws_subnet.interview_subnets[*].id
  }
}

# RDS Database
resource "aws_db_instance" "interview_db" {
  identifier        = "interview-db"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = "db.t3.medium"
  allocated_storage = 20
  
  db_name  = "interview_db"
  username = "interview_user"
  password = var.db_password
  
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.interview_db_subnet_group.name
}

# S3 Bucket for storage
resource "aws_s3_bucket" "interview_storage" {
  bucket = "interview-storage-${random_string.bucket_suffix.result}"
}

# ElastiCache Redis
resource "aws_elasticache_cluster" "interview_redis" {
  cluster_id           = "interview-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
}
```

This comprehensive deployment and infrastructure requirements document provides a complete blueprint for deploying the AI interview system with proper scalability, security, monitoring, and disaster recovery capabilities. 