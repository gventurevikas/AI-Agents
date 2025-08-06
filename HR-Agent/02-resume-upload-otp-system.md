# Resume Upload & OTP System Requirements

## 1. Overview

### 1.1 Purpose
The Resume Upload & OTP System is the entry point for the AI Interview platform. It handles resume file uploads, email verification through OTP, and generates secure interview links for candidates.

### 1.2 Scope
This module covers the complete workflow from resume submission to interview access, including file processing, email verification, and secure link generation.

## 2. Functional Requirements

### 2.1 Resume Upload Functionality

#### 2.1.1 File Upload Interface
- **Supported Formats**: PDF, DOCX, DOC
- **File Size Limit**: Maximum 10MB per file
- **Multiple File Support**: Single file upload only
- **Drag & Drop**: Modern drag-and-drop interface
- **Progress Indicator**: Real-time upload progress
- **Error Handling**: Clear error messages for failed uploads

#### 2.1.2 File Validation
- **Format Validation**: Verify file extension and MIME type
- **Content Validation**: Ensure file contains readable text
- **Virus Scanning**: Basic malware detection (optional)
- **Duplicate Detection**: Prevent duplicate resume uploads

#### 2.1.3 File Processing
- **Text Extraction**: Extract text content from PDF/DOCX
- **Metadata Extraction**: Extract file properties and creation date
- **Content Analysis**: Parse skills, experience, education
- **Storage**: Secure file storage with encryption

### 2.2 Email Capture & Validation

#### 2.2.1 Email Input
- **Email Field**: Required email address input
- **Validation**: Real-time email format validation
- **Auto-complete**: Browser autocomplete support
- **Error Handling**: Clear validation error messages

#### 2.2.2 Email Verification
- **Domain Validation**: Basic domain existence check
- **Disposable Email Check**: Block temporary email services
- **Rate Limiting**: Prevent email spam abuse
- **Blacklist Check**: Block known spam domains

### 2.3 OTP Generation & Delivery

#### 2.3.1 OTP Generation
- **OTP Format**: 6-digit numeric code
- **Expiration Time**: 15 minutes from generation
- **Uniqueness**: Ensure OTP uniqueness per email
- **Rate Limiting**: Maximum 3 OTP requests per hour per email

#### 2.3.2 Email Delivery
- **Email Template**: Professional HTML email template
- **Sender Identity**: Verified sender email address
- **Subject Line**: Clear, professional subject
- **Content**: Include OTP code and instructions
- **Branding**: Company logo and styling

#### 2.3.3 Email Service Configuration
- **SMTP Settings**: Configurable SMTP server settings
- **Fallback Service**: Backup email service provider
- **Delivery Tracking**: Email delivery status tracking
- **Bounce Handling**: Handle email bounces and failures

### 2.4 OTP Verification

#### 2.4.1 Verification Interface
- **OTP Input**: 6-digit code input field
- **Auto-focus**: Automatic focus on input field
- **Auto-submit**: Submit on 6th digit entry
- **Resend Option**: Resend OTP if expired

#### 2.4.2 Verification Logic
- **Code Validation**: Verify OTP matches stored value
- **Expiration Check**: Ensure OTP hasn't expired
- **Attempt Limiting**: Maximum 5 verification attempts
- **Account Lockout**: Temporary lockout after failed attempts

### 2.5 Interview Link Generation

#### 2.5.1 Link Creation
- **Unique Token**: Generate cryptographically secure token
- **Expiration**: 24-hour link expiration
- **One-time Use**: Link becomes invalid after first use
- **URL Structure**: Clean, professional URL format

#### 2.5.2 Link Storage
- **Database Storage**: Store link metadata in database
- **Encryption**: Encrypt sensitive link data
- **Audit Trail**: Log link creation and usage
- **Cleanup**: Automatic cleanup of expired links

## 3. Technical Requirements

### 3.1 Frontend Requirements

#### 3.1.1 Angular Components
```typescript
// Resume Upload Component
@Component({
  selector: 'app-resume-upload',
  template: `
    <div class="upload-container">
      <file-upload-area></file-upload-area>
      <email-input></email-input>
      <otp-verification></otp-verification>
      <interview-link></interview-link>
    </div>
  `
})
```

#### 3.1.2 File Upload Service
```typescript
@Injectable()
export class FileUploadService {
  uploadResume(file: File, email: string): Observable<UploadResponse> {
    // File upload logic
  }
  
  validateFile(file: File): boolean {
    // File validation logic
  }
}
```

#### 3.1.3 OTP Service
```typescript
@Injectable()
export class OtpService {
  sendOtp(email: string): Observable<OtpResponse> {
    // OTP generation and sending
  }
  
  verifyOtp(email: string, otp: string): Observable<VerificationResponse> {
    // OTP verification
  }
}
```

### 3.2 Backend Requirements

#### 3.2.1 API Endpoints
```javascript
// Resume upload endpoint
POST /api/resume/upload
{
  "file": "multipart/form-data",
  "email": "string"
}

// OTP generation endpoint
POST /api/otp/generate
{
  "email": "string"
}

// OTP verification endpoint
POST /api/otp/verify
{
  "email": "string",
  "otp": "string"
}

// Interview link generation
POST /api/interview/generate-link
{
  "resumeId": "string",
  "email": "string"
}
```

#### 3.2.2 Database Schema
```sql
-- Resumes table
CREATE TABLE resumes (
  id UUID PRIMARY KEY,
  email VARCHAR(255) NOT NULL,
  filename VARCHAR(255) NOT NULL,
  file_path VARCHAR(500) NOT NULL,
  file_size BIGINT NOT NULL,
  content_text TEXT,
  skills_extracted JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- OTP table
CREATE TABLE otp_codes (
  id UUID PRIMARY KEY,
  email VARCHAR(255) NOT NULL,
  otp_code VARCHAR(6) NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  attempts INTEGER DEFAULT 0,
  is_used BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Interview links table
CREATE TABLE interview_links (
  id UUID PRIMARY KEY,
  resume_id UUID REFERENCES resumes(id),
  token VARCHAR(255) UNIQUE NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  is_used BOOLEAN DEFAULT FALSE,
  used_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);
```

### 3.3 Email Service Requirements

#### 3.3.1 PHP Mailer Configuration
```php
<?php
// Email configuration
$mail = new PHPMailer(true);
$mail->isSMTP();
$mail->Host = 'smtp.gmail.com';
$mail->SMTPAuth = true;
$mail->Username = 'your-email@gmail.com';
$mail->Password = 'your-app-password';
$mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
$mail->Port = 587;

// Email template
$mail->setFrom('noreply@company.com', 'AI Interview System');
$mail->addAddress($email);
$mail->isHTML(true);
$mail->Subject = 'Your Interview Access Code';
$mail->Body = $emailTemplate;
?>
```

#### 3.3.2 Email Template
```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Interview Access Code</title>
</head>
<body>
    <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2>Your Interview Access Code</h2>
        <p>Hello,</p>
        <p>Your interview access code is: <strong>{{OTP_CODE}}</strong></p>
        <p>This code will expire in 15 minutes.</p>
        <p>If you didn't request this code, please ignore this email.</p>
        <p>Best regards,<br>AI Interview Team</p>
    </div>
</body>
</html>
```

## 4. Security Requirements

### 4.1 File Security
- **Virus Scanning**: Implement basic malware detection
- **File Type Validation**: Strict MIME type checking
- **Size Limits**: Enforce maximum file size
- **Content Sanitization**: Clean extracted text content

### 4.2 Email Security
- **Rate Limiting**: Prevent email abuse
- **Domain Validation**: Verify email domain existence
- **Spam Protection**: Block disposable email services
- **Encryption**: Encrypt sensitive email data

### 4.3 OTP Security
- **Cryptographic Strength**: Use cryptographically secure random numbers
- **Expiration**: Enforce strict expiration times
- **Attempt Limiting**: Prevent brute force attacks
- **Audit Logging**: Log all OTP attempts

### 4.4 Link Security
- **Token Generation**: Use cryptographically secure tokens
- **One-time Use**: Ensure links are single-use
- **Expiration**: Enforce link expiration
- **HTTPS Only**: Require secure connections

## 5. Performance Requirements

### 5.1 Upload Performance
- **Upload Speed**: Support for 1MB/s upload speeds
- **Processing Time**: Resume processing within 30 seconds
- **Concurrent Uploads**: Support 50+ simultaneous uploads
- **Progress Feedback**: Real-time upload progress

### 5.2 Email Performance
- **Delivery Time**: Email delivery within 60 seconds
- **Queue Management**: Handle email delivery queue
- **Retry Logic**: Automatic retry for failed deliveries
- **Monitoring**: Email delivery success tracking

### 5.3 Database Performance
- **Query Optimization**: Optimized database queries
- **Indexing**: Proper database indexing
- **Connection Pooling**: Database connection management
- **Caching**: Implement appropriate caching strategies

## 6. Error Handling

### 6.1 File Upload Errors
- **Invalid Format**: Clear error message for unsupported formats
- **File Too Large**: Informative size limit message
- **Upload Failure**: Retry mechanism for failed uploads
- **Processing Error**: Graceful handling of processing failures

### 6.2 Email Errors
- **Invalid Email**: Real-time email validation feedback
- **Delivery Failure**: Clear error message for delivery issues
- **Rate Limit**: Informative rate limiting messages
- **Spam Detection**: Clear message for blocked emails

### 6.3 OTP Errors
- **Invalid Code**: Clear error for wrong OTP
- **Expired Code**: Informative expiration message
- **Too Many Attempts**: Account lockout notification
- **System Error**: Graceful error handling

## 7. User Experience Requirements

### 7.1 Interface Design
- **Responsive Design**: Mobile-friendly interface
- **Accessibility**: WCAG 2.1 AA compliance
- **Loading States**: Clear loading indicators
- **Error States**: User-friendly error messages

### 7.2 Workflow Design
- **Step-by-Step**: Clear progression through steps
- **Progress Indicator**: Visual progress tracking
- **Back Navigation**: Allow users to go back
- **Save Progress**: Auto-save functionality

### 7.3 Feedback Mechanisms
- **Success Messages**: Clear success confirmations
- **Error Messages**: Helpful error descriptions
- **Validation Feedback**: Real-time validation
- **Help Text**: Contextual help information

## 8. Testing Requirements

### 8.1 Unit Testing
- **File Upload Tests**: Test file validation and processing
- **Email Tests**: Test OTP generation and delivery
- **Verification Tests**: Test OTP verification logic
- **Link Generation Tests**: Test secure link creation

### 8.2 Integration Testing
- **End-to-End Tests**: Complete workflow testing
- **API Testing**: Test all API endpoints
- **Database Testing**: Test database operations
- **Email Testing**: Test email delivery system

### 8.3 Security Testing
- **Penetration Testing**: Security vulnerability assessment
- **Input Validation**: Test input sanitization
- **Rate Limiting**: Test abuse prevention
- **Encryption Testing**: Test data encryption

## 9. Monitoring & Logging

### 9.1 Application Monitoring
- **Performance Metrics**: Track response times and throughput
- **Error Tracking**: Monitor error rates and types
- **User Analytics**: Track user behavior and patterns
- **System Health**: Monitor system resources

### 9.2 Audit Logging
- **File Uploads**: Log all file upload attempts
- **OTP Operations**: Log OTP generation and verification
- **Link Generation**: Log interview link creation
- **Security Events**: Log security-related events

### 9.3 Alerting
- **Error Alerts**: Alert on high error rates
- **Performance Alerts**: Alert on slow response times
- **Security Alerts**: Alert on suspicious activities
- **System Alerts**: Alert on system issues

## 10. Deployment Requirements

### 10.1 Environment Setup
- **Development**: Local development environment
- **Staging**: Pre-production testing environment
- **Production**: Live production environment
- **Configuration**: Environment-specific configurations

### 10.2 Infrastructure
- **Web Server**: NGINX or Apache configuration
- **Application Server**: Node.js deployment
- **Database**: PostgreSQL setup and configuration
- **Email Server**: SMTP server configuration

### 10.3 Security Setup
- **SSL/TLS**: HTTPS certificate configuration
- **Firewall**: Network security configuration
- **Backup**: Automated backup configuration
- **Monitoring**: System monitoring setup 