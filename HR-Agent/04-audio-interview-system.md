# Audio Interview System Requirements

## 1. Overview

### 1.1 Purpose
The Audio Interview System provides real-time audio recording capabilities for the AI interview platform. It integrates WebRTC for browser-based audio communication, FreeSWITCH for media server functionality, and handles audio processing, storage, and analysis.

### 1.2 Scope
This module covers WebRTC audio setup, FreeSWITCH media server integration, audio recording, real-time streaming, audio storage, and audio analysis capabilities.

## 2. Functional Requirements

### 2.1 WebRTC Audio Interface

#### 2.1.1 Audio Setup
- **Microphone Access**: Request and manage microphone permissions
- **Audio Device Selection**: Allow users to select audio input devices
- **Audio Quality Settings**: Configure sample rate, bit depth, and channels
- **Audio Level Monitoring**: Real-time audio level visualization
- **Connection Status**: Display WebRTC connection status

#### 2.1.2 Audio Controls
- **Start Recording**: Begin audio recording session
- **Stop Recording**: End current recording session
- **Pause Recording**: Temporarily pause recording
- **Resume Recording**: Continue paused recording
- **Audio Preview**: Playback recorded audio for verification

#### 2.1.3 Audio Quality
- **Sample Rate**: 16kHz minimum, 44.1kHz preferred
- **Bit Depth**: 16-bit minimum, 24-bit preferred
- **Channels**: Mono recording for voice clarity
- **Compression**: Adaptive bitrate compression
- **Noise Reduction**: Basic noise suppression

### 2.2 FreeSWITCH Integration

#### 2.2.1 Media Server Setup
- **WebRTC Gateway**: Handle WebRTC to SIP conversion
- **Audio Processing**: Real-time audio processing and enhancement
- **Recording Management**: Automatic recording file management
- **Session Management**: Track active audio sessions

#### 2.2.2 Audio Recording
- **File Format**: WAV format for high quality
- **Naming Convention**: `{userId}_{questionId}_{timestamp}.wav`
- **Storage Location**: Organized directory structure
- **Metadata Storage**: Store recording metadata in database
- **Backup Strategy**: Automatic backup of audio files

#### 2.2.3 Real-time Streaming
- **Live Audio Stream**: Stream audio to backend for analysis
- **WebSocket Connection**: Real-time audio data transmission
- **Buffer Management**: Handle audio buffering and streaming
- **Quality Adaptation**: Adapt stream quality based on network

### 2.3 Audio Processing

#### 2.3.1 Audio Enhancement
- **Noise Reduction**: Remove background noise
- **Echo Cancellation**: Eliminate echo and feedback
- **Voice Activity Detection**: Detect speech vs. silence
- **Audio Normalization**: Normalize audio levels

#### 2.3.2 Audio Analysis
- **Speech Recognition**: Real-time speech-to-text conversion
- **Voice Quality Metrics**: Measure audio quality indicators
- **Speaking Rate Analysis**: Analyze speaking speed and patterns
- **Confidence Scoring**: Assess audio clarity and confidence

### 2.4 Interview Session Management

#### 2.4.1 Session Control
- **Session Initialization**: Set up interview session
- **Question Progression**: Manage question flow and timing
- **Recording Segments**: Separate recordings per question
- **Session Timeout**: Automatic session termination

#### 2.4.2 Progress Tracking
- **Question Progress**: Track current question and total questions
- **Time Tracking**: Monitor time spent on each question
- **Recording Status**: Track recording state for each question
- **Session Completion**: Handle interview completion

## 3. Technical Requirements

### 3.1 Frontend Implementation

#### 3.1.1 Angular Audio Service
```typescript
@Injectable()
export class AudioService {
  private mediaRecorder: MediaRecorder;
  private audioChunks: Blob[] = [];
  private stream: MediaStream;

  async initializeAudio(): Promise<void> {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          sampleRate: 44100,
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      });
      
      this.setupMediaRecorder();
    } catch (error) {
      throw new Error(`Audio initialization failed: ${error.message}`);
    }
  }

  private setupMediaRecorder(): void {
    this.mediaRecorder = new MediaRecorder(this.stream, {
      mimeType: 'audio/webm;codecs=opus'
    });

    this.mediaRecorder.ondataavailable = (event) => {
      this.audioChunks.push(event.data);
    };

    this.mediaRecorder.onstop = () => {
      this.saveRecording();
    };
  }

  startRecording(): void {
    this.audioChunks = [];
    this.mediaRecorder.start();
  }

  stopRecording(): void {
    this.mediaRecorder.stop();
  }

  private async saveRecording(): Promise<void> {
    const audioBlob = new Blob(this.audioChunks, { type: 'audio/webm' });
    await this.uploadAudio(audioBlob);
  }
}
```

#### 3.1.2 WebRTC Connection Service
```typescript
@Injectable()
export class WebRTCService {
  private peerConnection: RTCPeerConnection;
  private dataChannel: RTCDataChannel;

  async establishConnection(): Promise<void> {
    this.peerConnection = new RTCPeerConnection({
      iceServers: [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:stun1.l.google.com:19302' }
      ]
    });

    // Add local stream
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    stream.getTracks().forEach(track => {
      this.peerConnection.addTrack(track, stream);
    });

    // Handle incoming audio
    this.peerConnection.ontrack = (event) => {
      this.handleIncomingAudio(event.streams[0]);
    };

    // Create offer
    const offer = await this.peerConnection.createOffer();
    await this.peerConnection.setLocalDescription(offer);

    // Send offer to server
    await this.sendOffer(offer);
  }

  private async sendOffer(offer: RTCSessionDescriptionInit): Promise<void> {
    const response = await this.http.post('/api/webrtc/offer', {
      sdp: offer.sdp,
      type: offer.type
    }).toPromise();

    // Set remote description
    await this.peerConnection.setRemoteDescription(response.data.answer);
  }
}
```

#### 3.1.3 Audio Interface Component
```typescript
@Component({
  selector: 'app-audio-interface',
  template: `
    <div class="audio-container">
      <div class="audio-controls">
        <button (click)="startRecording()" [disabled]="isRecording">
          Start Recording
        </button>
        <button (click)="stopRecording()" [disabled]="!isRecording">
          Stop Recording
        </button>
      </div>
      
      <div class="audio-visualizer">
        <canvas #audioCanvas></canvas>
      </div>
      
      <div class="audio-level">
        <div class="level-bar" [style.width.%]="audioLevel"></div>
      </div>
      
      <div class="recording-status">
        <span *ngIf="isRecording" class="recording-indicator">● Recording</span>
        <span class="recording-time">{{recordingTime}}</span>
      </div>
    </div>
  `
})
export class AudioInterfaceComponent {
  @ViewChild('audioCanvas') audioCanvas: ElementRef;
  
  isRecording = false;
  audioLevel = 0;
  recordingTime = '00:00';

  constructor(
    private audioService: AudioService,
    private webrtcService: WebRTCService
  ) {}

  async startRecording(): Promise<void> {
    await this.audioService.initializeAudio();
    await this.webrtcService.establishConnection();
    
    this.audioService.startRecording();
    this.isRecording = true;
    this.startTimer();
    this.startAudioVisualization();
  }

  stopRecording(): void {
    this.audioService.stopRecording();
    this.isRecording = false;
    this.stopTimer();
  }

  private startAudioVisualization(): void {
    // Implement audio level visualization
    const canvas = this.audioCanvas.nativeElement;
    const ctx = canvas.getContext('2d');
    
    // Audio visualization logic
  }
}
```

### 3.2 Backend Implementation

#### 3.2.1 FreeSWITCH Integration
```javascript
// FreeSWITCH ESL (Event Socket Library) integration
const esl = require('modesl');

class FreeSWITCHService {
  constructor() {
    this.connection = new esl.Connection('127.0.0.1', 8021, 'ClueCon', () => {
      console.log('Connected to FreeSWITCH');
    });
  }

  async createRecordingSession(userId, questionId) {
    const sessionId = `${userId}_${questionId}_${Date.now()}`;
    const recordingPath = `/recordings/${sessionId}.wav`;
    
    const command = `uuid_record ${sessionId} start ${recordingPath}`;
    
    return new Promise((resolve, reject) => {
      this.connection.api(command, (res) => {
        if (res.getHeader('Reply-Text').includes('+OK')) {
          resolve({ sessionId, recordingPath });
        } else {
          reject(new Error('Failed to create recording session'));
        }
      });
    });
  }

  async stopRecording(sessionId) {
    const command = `uuid_record ${sessionId} stop`;
    
    return new Promise((resolve, reject) => {
      this.connection.api(command, (res) => {
        if (res.getHeader('Reply-Text').includes('+OK')) {
          resolve();
        } else {
          reject(new Error('Failed to stop recording'));
        }
      });
    });
  }
}
```

#### 3.2.2 WebRTC Signaling Server
```javascript
// WebSocket server for WebRTC signaling
const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 8080 });

class WebRTCSignalingServer {
  constructor() {
    this.connections = new Map();
    this.setupWebSocket();
  }

  setupWebSocket() {
    wss.on('connection', (ws, req) => {
      const sessionId = this.extractSessionId(req);
      this.connections.set(sessionId, ws);

      ws.on('message', (message) => {
        const data = JSON.parse(message);
        this.handleSignalingMessage(sessionId, data);
      });

      ws.on('close', () => {
        this.connections.delete(sessionId);
      });
    });
  }

  handleSignalingMessage(sessionId, message) {
    switch (message.type) {
      case 'offer':
        this.handleOffer(sessionId, message);
        break;
      case 'answer':
        this.handleAnswer(sessionId, message);
        break;
      case 'ice-candidate':
        this.handleIceCandidate(sessionId, message);
        break;
    }
  }

  async handleOffer(sessionId, offer) {
    // Process WebRTC offer and create answer
    const answer = await this.createAnswer(offer);
    
    const connection = this.connections.get(sessionId);
    if (connection) {
      connection.send(JSON.stringify({
        type: 'answer',
        sdp: answer.sdp
      }));
    }
  }
}
```

#### 3.2.3 Audio Processing Service
```javascript
class AudioProcessingService {
  async processAudio(audioBuffer) {
    // Audio enhancement
    const enhancedAudio = await this.enhanceAudio(audioBuffer);
    
    // Speech recognition
    const transcription = await this.transcribeAudio(enhancedAudio);
    
    // Voice analysis
    const analysis = await this.analyzeVoice(enhancedAudio);
    
    return {
      transcription,
      analysis,
      enhancedAudio
    };
  }

  async enhanceAudio(audioBuffer) {
    // Apply noise reduction
    const denoised = await this.noiseReduction(audioBuffer);
    
    // Apply echo cancellation
    const echoCancelled = await this.echoCancellation(denoised);
    
    // Normalize audio levels
    const normalized = await this.normalizeAudio(echoCancelled);
    
    return normalized;
  }

  async transcribeAudio(audioBuffer) {
    // Use OpenAI Whisper API for transcription
    const formData = new FormData();
    formData.append('file', audioBuffer, 'audio.wav');
    formData.append('model', 'whisper-1');
    
    const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: formData
    });
    
    const result = await response.json();
    return result.text;
  }

  async analyzeVoice(audioBuffer) {
    // Analyze speaking rate
    const speakingRate = await this.calculateSpeakingRate(audioBuffer);
    
    // Analyze voice quality
    const voiceQuality = await this.analyzeVoiceQuality(audioBuffer);
    
    // Analyze confidence indicators
    const confidence = await this.analyzeConfidence(audioBuffer);
    
    return {
      speakingRate,
      voiceQuality,
      confidence
    };
  }
}
```

### 3.3 API Endpoints

#### 3.3.1 Audio Session Management
```javascript
// Initialize audio session
app.post('/api/audio/session', async (req, res) => {
  try {
    const { userId, questionId } = req.body;
    
    // Create FreeSWITCH recording session
    const session = await freeSwitchService.createRecordingSession(userId, questionId);
    
    // Initialize WebRTC connection
    const webrtcConfig = await webrtcService.initializeConnection(userId);
    
    res.json({
      success: true,
      data: {
        sessionId: session.sessionId,
        webrtcConfig,
        recordingPath: session.recordingPath
      }
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Start recording
app.post('/api/audio/start-recording', async (req, res) => {
  try {
    const { sessionId } = req.body;
    
    await freeSwitchService.startRecording(sessionId);
    
    res.json({
      success: true,
      message: 'Recording started'
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Stop recording
app.post('/api/audio/stop-recording', async (req, res) => {
  try {
    const { sessionId } = req.body;
    
    await freeSwitchService.stopRecording(sessionId);
    
    // Process recorded audio
    const audioAnalysis = await audioProcessingService.processRecording(sessionId);
    
    res.json({
      success: true,
      data: audioAnalysis
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});
```

### 3.4 Database Schema

#### 3.4.1 Audio Sessions Table
```sql
CREATE TABLE audio_sessions (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  question_id UUID REFERENCES questions(id),
  session_id VARCHAR(255) UNIQUE NOT NULL,
  recording_path VARCHAR(500),
  start_time TIMESTAMP,
  end_time TIMESTAMP,
  duration INTEGER, -- in seconds
  file_size BIGINT,
  status VARCHAR(20) DEFAULT 'active', -- 'active', 'completed', 'failed'
  created_at TIMESTAMP DEFAULT NOW()
);
```

#### 3.4.2 Audio Analysis Table
```sql
CREATE TABLE audio_analysis (
  id UUID PRIMARY KEY,
  session_id UUID REFERENCES audio_sessions(id),
  transcription TEXT,
  speaking_rate DECIMAL(5,2), -- words per minute
  voice_quality_score DECIMAL(3,2), -- 0.0 to 1.0
  confidence_score DECIMAL(3,2), -- 0.0 to 1.0
  audio_metrics JSONB, -- detailed audio analysis metrics
  processing_time INTEGER, -- milliseconds
  created_at TIMESTAMP DEFAULT NOW()
);
```

## 4. Performance Requirements

### 4.1 Audio Quality
- **Sample Rate**: Minimum 16kHz, preferred 44.1kHz
- **Bit Depth**: Minimum 16-bit, preferred 24-bit
- **Latency**: Maximum 100ms audio latency
- **Packet Loss**: Handle up to 5% packet loss gracefully

### 4.2 Recording Performance
- **Concurrent Sessions**: Support 50+ simultaneous recordings
- **File Size**: Maximum 50MB per recording
- **Processing Time**: Audio processing within 30 seconds
- **Storage Efficiency**: Compress audio files without quality loss

### 4.3 Network Performance
- **Bandwidth**: Minimum 64kbps, preferred 128kbps
- **Connection Stability**: Handle network interruptions gracefully
- **Adaptive Quality**: Adjust quality based on network conditions
- **Fallback Mechanisms**: Offline recording with sync

## 5. Security Requirements

### 5.1 Audio Security
- **Encryption**: Encrypt audio data in transit and at rest
- **Access Control**: Restrict access to audio recordings
- **Audit Logging**: Log all audio session activities
- **Data Retention**: Implement audio data retention policies

### 5.2 WebRTC Security
- **STUN/TURN Servers**: Secure ICE server configuration
- **DTLS-SRTP**: Encrypt WebRTC media streams
- **Certificate Management**: Proper SSL certificate handling
- **Connection Validation**: Validate WebRTC connections

## 6. Error Handling

### 6.1 Audio Device Errors
- **Microphone Access**: Handle permission denied scenarios
- **Device Selection**: Fallback to default audio device
- **Device Failure**: Graceful handling of device failures
- **Quality Issues**: Automatic quality adjustment

### 6.2 Network Errors
- **Connection Loss**: Automatic reconnection attempts
- **Bandwidth Issues**: Adaptive quality adjustment
- **Server Errors**: Fallback to local recording
- **Timeout Handling**: Proper timeout and retry logic

### 6.3 Recording Errors
- **Storage Full**: Handle disk space issues
- **File Corruption**: Detect and handle corrupted recordings
- **Processing Errors**: Graceful handling of processing failures
- **Upload Failures**: Retry mechanisms for failed uploads

## 7. Monitoring & Analytics

### 7.1 Audio Quality Monitoring
```javascript
class AudioQualityMonitor {
  trackAudioMetrics(sessionId, metrics) {
    this.metricsCollector.record({
      sessionId,
      audioLevel: metrics.audioLevel,
      noiseLevel: metrics.noiseLevel,
      latency: metrics.latency,
      packetLoss: metrics.packetLoss,
      qualityScore: metrics.qualityScore
    });
  }
}
```

### 7.2 Performance Analytics
- **Recording Success Rate**: Track successful vs failed recordings
- **Audio Quality Distribution**: Monitor quality score distribution
- **Processing Time**: Track audio processing performance
- **User Experience**: Monitor user satisfaction metrics

## 8. Testing Requirements

### 8.1 Audio Quality Testing
- **Device Compatibility**: Test with various audio devices
- **Network Conditions**: Test under different network conditions
- **Browser Compatibility**: Test across different browsers
- **Mobile Testing**: Test on mobile devices

### 8.2 Integration Testing
- **FreeSWITCH Integration**: Test media server integration
- **WebRTC Testing**: Test WebRTC connection stability
- **Audio Processing**: Test audio enhancement and analysis
- **Storage Integration**: Test audio file storage and retrieval

### 8.3 Performance Testing
- **Load Testing**: Test with multiple concurrent sessions
- **Stress Testing**: Test under high load conditions
- **Endurance Testing**: Test long-running sessions
- **Recovery Testing**: Test system recovery after failures

## 9. Configuration Management

### 9.1 Audio Configuration
```javascript
const audioConfig = {
  sampleRate: 44100,
  bitDepth: 16,
  channels: 1,
  echoCancellation: true,
  noiseSuppression: true,
  autoGainControl: true,
  maxRecordingDuration: 300, // 5 minutes
  maxFileSize: 50 * 1024 * 1024, // 50MB
  compressionQuality: 0.8
};
```

### 9.2 FreeSWITCH Configuration
```xml
<!-- FreeSWITCH configuration -->
<configuration name="webrtc.conf" description="WebRTC Configuration">
  <settings>
    <param name="wss-binding" value=":8089"/>
    <param name="wss-binding" value=":8088"/>
    <param name="record-path" value="/recordings"/>
    <param name="record-template" value="${uuid}.wav"/>
  </settings>
</configuration>
```

## 10. Deployment Considerations

### 10.1 Infrastructure Requirements
- **Media Server**: FreeSWITCH server with sufficient resources
- **Web Server**: NGINX with WebSocket support
- **Storage**: Adequate storage for audio recordings
- **Network**: Sufficient bandwidth for audio streaming

### 10.2 Scaling Strategy
- **Horizontal Scaling**: Multiple FreeSWITCH instances
- **Load Balancing**: Distribute audio sessions across servers
- **CDN Integration**: Use CDN for audio file delivery
- **Auto-scaling**: Automatic scaling based on demand

### 10.3 Backup & Recovery
- **Audio Backup**: Regular backup of audio recordings
- **Configuration Backup**: Backup FreeSWITCH configurations
- **Disaster Recovery**: Plan for system recovery
- **Data Retention**: Implement data retention policies 