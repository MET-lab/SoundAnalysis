//
//  AudioController.m
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 5/11/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "AudioController.h"

/* Main render callback method */
static OSStatus processingCallback(void *inRefCon, // Reference to the calling object
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp 		*inTimeStamp,
                                 UInt32 					inBusNumber,
                                 UInt32 					inNumberFrames,
                                 AudioBufferList 			*ioData)
{
    OSStatus status;
    
	/* Cast void to AudioController input object */
	AudioController *controller = (__bridge AudioController *)inRefCon;
    
    /* Update the audio buffer length if it has changed */
    if (controller.audioBufferLength != inNumberFrames)
        controller.audioBufferLength = inNumberFrames;
    
    /* Copy samples from input bus into the ioData (buffer to output) */
    status = AudioUnitRender(controller.remoteIOUnit,
                             ioActionFlags,
                             inTimeStamp,
                             1, // Input bus
                             inNumberFrames,
                             ioData);
    if (status != noErr)
        printf("Error rendering from remote IO unit\n");
    
    /* Allocate a buffer for processing samples and copy the ioData into it */
    Float32 *inputBuffer = (Float32 *)calloc(inNumberFrames, sizeof(Float32));
    memcpy(inputBuffer, (Float32 *)ioData->mBuffers[0].mData, sizeof(Float32) * inNumberFrames);
    
    /* Apply pre-gain */
    for (int i = 0; i < inNumberFrames; i++)
        inputBuffer[i] *= controller.inputGain;
    
//    Float32 *inputBufferCopy = (Float32 *)calloc(inNumberFrames, sizeof(Float32));
//    memcpy(inputBufferCopy, inputBuffer, inNumberFrames * sizeof(Float32));
    
    /* Set the pre-processing buffer with pre-gain applied */
    [controller appendBufferWithLength:inNumberFrames buffer:inputBuffer];
//    free(inputBufferCopy);
    
    /* Temporary: write zeros to the output buffer. To do: input only audio controller */
    for (int i = 0; i < inNumberFrames; i++)
        inputBuffer[i] = 0.0f;
    
    /* Copy the processing buffer into the left and right output channels */
    memcpy((Float32 *)ioData->mBuffers[0].mData, inputBuffer, inNumberFrames * sizeof(Float32));
    memcpy((Float32 *)ioData->mBuffers[1].mData, inputBuffer, inNumberFrames * sizeof(Float32));
    
    free(inputBuffer);
	return status;
}

/* Interrupt handler to stop/start audio for incoming notifications/alarms/calls */
void interruptListener(void *inUserData, UInt32 inInterruptionState) {
    
    AudioController *audioController = (__bridge AudioController *)inUserData;
    
    if (inInterruptionState == kAudioSessionBeginInterruption)
        [audioController stopAUGraph];
    else if (inInterruptionState == kAudioSessionEndInterruption)
        [audioController startAUGraph];
}

@implementation AudioController

@synthesize remoteIOUnit;
@synthesize inputGain;

@synthesize hardwareSampleRate;

@synthesize audioBufferLength;
@synthesize recordingBufferLength;
@synthesize fftSize;
@synthesize nFFTFrames;

@synthesize inputEnabled;
@synthesize isInitialized;
@synthesize isRunning;


- (id)init {
    
    self = [super init];
    
    if (self) {
        
        inputEnabled = false;
        isInitialized = false;
        isRunning = false;
        inputGain = 1.0;
        
        audioBufferLength = kAudioBufferSize;
        
        [self allocateRecordingBufferWithLength:kRecordingBufferLengthSeconds*kAudioSampleRate];
        [self setUpAUGraph];
    }
    
    return self;
}

- (void)dealloc {
    
    if (recordingBuffer)
        free(recordingBuffer);
    
    pthread_mutex_destroy(&recordingBufferMutex);
}

- (void)allocateRecordingBufferWithLength:(int)length {
    
    /* Time domain */
    recordingBufferLength = length;
    
    if (recordingBuffer)
        free(recordingBuffer);
    
    recordingBuffer = (Float32 *)calloc(length, sizeof(Float32));
    pthread_mutex_init(&recordingBufferMutex, NULL);
    
    /* Frequency domain */
    if (spectrumBuffer)
        free(spectrumBuffer);
    
    fftSize = kFFTSize;
    fftScale = 2.0f / (float)(fftSize/2);
    nFFTFrames = ceil(recordingBufferLength / kFFTSize);
    
    spectrumBuffer = (Float32 *)calloc(nFFTFrames * fftSize/2, sizeof(Float32));
    pthread_mutex_init(&spectrumBufferMutex, NULL);
    
    inRealBuffer = (float *)malloc(fftSize * sizeof(float));
    outRealBuffer = (float *)malloc(fftSize * sizeof(float));
    splitBuffer.realp = (float *)malloc(fftSize/2 * sizeof(float));
    splitBuffer.imagp = (float *)malloc(fftSize/2 * sizeof(float));
    
    fftSetup = vDSP_create_fftsetup(log2f(fftSize), FFT_RADIX2);
    
    windowSize = kFFTSize;
    window = (float *)calloc(windowSize, sizeof(float));
    vDSP_hann_window(window, windowSize, vDSP_HANN_NORM);
}

- (void)setUpAUGraph {
    
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    OSStatus status;
    
    /* ------------------------ */
    /* == Create the AUGraph == */
    /* ------------------------ */
    
    status = NewAUGraph(&graph);
    if (status != noErr) {
        [self printErrorMessage:@"NewAUGraph failed" withStatus:status];
    }
    
    /* ----------------------- */
    /* == Add RemoteIO Node == */
    /* ----------------------- */
    
    AudioComponentDescription IOUnitDescription;    // Description
    IOUnitDescription.componentType          = kAudioUnitType_Output;
    IOUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
    IOUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    IOUnitDescription.componentFlags         = 0;
    IOUnitDescription.componentFlagsMask     = 0;
    
    AUNode IONode;
    status = AUGraphAddNode(graph, &IOUnitDescription, &IONode);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphAddNode[RemoteIO] failed" withStatus:status];
    }
    
    /* ---------------------- */
    /* == Open the AUGraph == */
    /* ---------------------- */
    
    status = AUGraphOpen(graph);    // Instantiates audio units, but doesn't initialize
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphOpen failed" withStatus:status];
    }
    
    /* ----------------------------------------------------- */
    /* == Get AudioUnit instances from the opened AUGraph == */
    /* ----------------------------------------------------- */
    
    status = AUGraphNodeInfo(graph, IONode, NULL, &remoteIOUnit);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphNodeInfo[RemoteIO] failed" withStatus:status];
    }
    
    /* ------------------------------------------------------------- */
    /* ==== Set up: render callback instead of connections ========= */
    /* ------------------------------------------------------------- */
    
    /* Set an input callback rather than making any audio unit connections.  */
    AudioUnitElement outputBus = 0;
    AURenderCallbackStruct inputCallbackStruct;
    inputCallbackStruct.inputProc = processingCallback;
    inputCallbackStruct.inputProcRefCon = (__bridge void*) self;
    
    status = AudioUnitSetProperty(remoteIOUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  outputBus,
                                  &inputCallbackStruct,
                                  sizeof(inputCallbackStruct));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_SetRenderCallback] failed" withStatus:status];
    }
    
    /* ------------------------------------ */
    /* == Set Stream Formats, Parameters == */
    /* ------------------------------------ */
    
//    [self setOutputEnabled:true];       // Enable output on the remoteIO unit
    [self setInputEnabled:true];        // Enable input on the remoteIO unit
    [self setIOStreamFormat];           // Set up stream format on input/output of the remoteIO
    
    /* ------------------------ */
    /* == Initialize and Run == */
    /* ------------------------ */
    
    [self initializeGraph];     // Initialize the AUGraph (allocates resources)
    [self startAUGraph];        // Start the AUGraph
    
    CAShow(graph);

}

/* Set the stream format on the remoteIO audio unit */
- (void)setIOStreamFormat {
    
    OSStatus status;
    
    /* Set up the stream format for the I/O unit */
    memset(&IOStreamFormat, 0, sizeof(IOStreamFormat));
    IOStreamFormat.mSampleRate = kAudioSampleRate;
    IOStreamFormat.mFormatID = kAudioFormatLinearPCM;
    IOStreamFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    IOStreamFormat.mBytesPerPacket = kAudioBytesPerPacket;
    IOStreamFormat.mFramesPerPacket = kAudioFramesPerPacket;
    IOStreamFormat.mBytesPerFrame = kAudioBytesPerPacket / kAudioFramesPerPacket;
    IOStreamFormat.mChannelsPerFrame = kAudioChannelsPerFrame;
    IOStreamFormat.mBitsPerChannel = 8 * kAudioBytesPerPacket;
    
    /* Set the stream format for the input bus */
    status = AudioUnitSetProperty(remoteIOUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &IOStreamFormat,
                                  sizeof(IOStreamFormat));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_StreamFormat - Input] failed" withStatus:status];
    }
    
//    /* Set the stream format for the output bus */
//    status = AudioUnitSetProperty(remoteIOUnit,
//                                  kAudioUnitProperty_StreamFormat,
//                                  kAudioUnitScope_Output,
//                                  1,
//                                  &IOStreamFormat,
//                                  sizeof(IOStreamFormat));
//    if (status != noErr) {
//        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_StreamFormat - Output] failed" withStatus:status];
//    }
}

/* Initialize the AUGraph (allocates resources) */
- (void)initializeGraph {
    
    OSStatus status = AUGraphInitialize(graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphInitialize failed" withStatus:status];
    }
    else
        isInitialized = true;
}

/* Uninitialize the AUGraph in case we need to set properties that require an uninitialized graph */
- (void)uninitializeGraph {
    
    OSStatus status = AUGraphUninitialize(graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphUninitialize failed" withStatus:status];
    }
    else
        isInitialized = false;
}

#pragma mark -
#pragma mark Interface Methods
/* Run audio */
- (void)startAUGraph {
    
    OSStatus status = AUGraphStart(graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphStart failed" withStatus:status];
    }
    else
        isRunning = true;
}

/* Stop audio */
- (void)stopAUGraph {
    
    OSStatus status = AUGraphStop(graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphStop failed" withStatus:status];
    }
    else
        isRunning = false;
}

/* Enable/disable audio input */
- (void)setInputEnabled:(bool)enabled {
    
    OSStatus status;
    UInt32 enableInput = (UInt32)enabled;
    AudioUnitElement inputBus = 1;
    bool wasInitialized = false;
    bool wasRunning = false;
    
    /* Stop if running */
    if (isRunning) {
        [self stopAUGraph];
        wasRunning = true;
    }
    /* Uninitialize if initialized */
    if (isInitialized) {
        [self uninitializeGraph];
        wasInitialized = true;
    }
    
    /* Set up the remoteIO unit to enable/disable input */
    status = AudioUnitSetProperty(remoteIOUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  inputBus,
                                  &enableInput,
                                  sizeof(enableInput));
    if (status != noErr) {
        [self printErrorMessage:@"Enable/disable input failed" withStatus:status];
    }
    else
        inputEnabled = enabled;
    
    /* Reinitialize if needed */
    if (wasInitialized)
        [self initializeGraph];
    
    /* Restart if needed */
    if (wasRunning)
        [self startAUGraph];
}

/* Enable/disable audio output */
- (void)setOutputEnabled:(bool)enabled {
    
//    outputEnabled = enabled;
    
//    OSStatus status;
//    UInt32 enableOutput = (UInt32)enabled;
//    AudioUnitElement outputBus = 0;
//    bool wasInitialized = false;
//    bool wasRunning = false;
//    
//    /* Stop if running */
//    if (isRunning) {
//        [self stopAUGraph];
//        wasRunning = true;
//    }
//    /* Uninitialize if initialized */
//    if (isInitialized) {
//        [self uninitializeGraph];
//        wasInitialized = true;
//    }
//    
//    /* Set up the remoteIO unit to enable/disable output */
//    status = AudioUnitSetProperty(remoteIOUnit,
//                                  kAudioOutputUnitProperty_EnableIO,
//                                  kAudioUnitScope_Output,
//                                  outputBus,
//                                  &enableOutput,
//                                  sizeof(enableOutput));
//    if (status != noErr) {
//        [self printErrorMessage:@"Enable/disable output failed" withStatus:status];
//    }
//    else outputEnabled = enabled;
//    
//    /* Reinitialize if needed */
//    if (wasInitialized)
//        [self initializeGraph];
//    
//    /* Restart if needed */
//    if (wasRunning)
//        [self startAUGraph];
}

/* Internal pre/post processing buffer setters/getters */
- (void)appendBufferWithLength:(int)length buffer:(Float32 *)inBuffer {
    
//    float *inBufferCopy = (float *)calloc(length, sizeof(float));
//    for (int i = 0; i < length; i++)
//        inBufferCopy[i] = inBuffer[i];
    
    pthread_mutex_lock(&recordingBufferMutex);
    
    /* Shift old values back */
    for (int i = 0; i < recordingBufferLength - length; i++)
        recordingBuffer[i] = recordingBuffer[i + length];
    
    /* Append new values to the front */
    for (int i = 0; i < length; i++)
        recordingBuffer[recordingBufferLength - (length-i)] = inBuffer[i];
    
    pthread_mutex_unlock(&recordingBufferMutex);

    /* Take the FFT and add it to the spectrum buffer */
    pthread_mutex_lock(&spectrumBufferMutex);
    
    float *fftBuffer = (float *)malloc(fftSize/2 * sizeof(float));
    [self computeMagnitudeFFT:inBuffer inBufferLength:length outMagnitude:fftBuffer window:true];
    
    int specBufferLength = fftSize/2 * nFFTFrames;
    
    /* Shift the old values back */
    for (int i = 0; i < specBufferLength - fftSize/2; i++)
        spectrumBuffer[i] = spectrumBuffer[i + fftSize/2];
    
    /* Append the new values to the front */
    for (int i = 0; i < fftSize/2; i++)
        spectrumBuffer[specBufferLength - (fftSize/2-i)] = fftBuffer[i];
    
    free(fftBuffer);
    
    pthread_mutex_unlock(&spectrumBufferMutex);
    
//    free(inBufferCopy);
}

/* Get n = length most recent audio samples from the recording buffer */
- (void)getRecordedAudioWithLength:(int)length outBuffer:(Float32 *)outBuffer {
    
    if (length >= recordingBufferLength)
        NSLog(@"%s: Invalid buffer length", __PRETTY_FUNCTION__);
    
    pthread_mutex_lock(&recordingBufferMutex);
    for (int i = 0; i < length; i++)
        outBuffer[i] = recordingBuffer[recordingBufferLength - (length-i)];
    pthread_mutex_unlock(&recordingBufferMutex);
    
}

/* Get recorded audio samples in a specified range */
- (void)getRecordedAudioFrom:(int)startIdx to:(int)endIdx outBuffer:(Float32 *)outBuffer {
    
    if (startIdx < 0 || endIdx >= recordingBufferLength || endIdx < startIdx)
        NSLog(@"%s: Invalid buffer indices", __PRETTY_FUNCTION__);
    
    int length = endIdx - startIdx;
    
    pthread_mutex_lock(&recordingBufferMutex);
    for (int i = 0, j = startIdx; i < length; i++, j++)
        outBuffer[i] = recordingBuffer[j];
    pthread_mutex_unlock(&recordingBufferMutex);
}

- (void)getAverageSpectrumFrom:(int)startIdx to:(int)endIdx outBuffer:(Float32 *)outBuffer {
    
    if (startIdx < 0 || endIdx >= recordingBufferLength || endIdx < startIdx)
        NSLog(@"%s: Invalid buffer indices", __PRETTY_FUNCTION__);
    
    int startFFTFrame = floor(startIdx / fftSize);
    int endFFTFrame = floor(endIdx / fftSize);
    int nFrames = endFFTFrame - startFFTFrame;
    
    pthread_mutex_lock(&spectrumBufferMutex);
    for (int i = 0; i < fftSize/2; i++) {
        
        outBuffer[i] = 0.0f;
        for (int j = startFFTFrame; j <= endFFTFrame; j++)
            outBuffer[i] += spectrumBuffer[i + j*fftSize/2] / nFrames;
    }
    pthread_mutex_unlock(&spectrumBufferMutex);
}

#pragma mark Utility Methods
/* Compute the single-sided magnitude spectrum using Accelerate's vDSP methods */
- (void)computeMagnitudeFFT:(float *)inBuffer inBufferLength:(int)len outMagnitude:(float *)magnitude window:(bool)doWindow {
    
    /* Recomputer the window if it's not the length of the input signal and we're windowing */
    if (doWindow && len != windowSize) {
        windowSize = len;
        free(window);
        window = (float *)malloc(windowSize * sizeof(float));
        vDSP_hann_window(window, windowSize, vDSP_HANN_NORM);
    }
    
    /* If the input signal is shorter than the fft size, zero-pad */
    if (len < fftSize) {
        
        /* Window and zero-pad */
        if (doWindow) {
            
            /* Window the input signal */
            float *windowed = (float *)malloc(len * sizeof(float));
            vDSP_vmul(inBuffer, 1, window, 1, windowed, 1, len);
            
            /* Copy */
            for (int i = 0; i < len; i++)
                inRealBuffer[i] = windowed[i];
            
            /* Zero-pad */
            for (int i = len; i < fftSize; i++)
                inRealBuffer[i] = 0.0f;

            free(windowed);
        }
        
        /* Just copy and zero-pad */
        else {
            for (int i = 0; i < len; i++)
                inRealBuffer[i] = inBuffer[i];
            
            for (int i = len; i < fftSize; i++)
                inRealBuffer[i] = 0.0f;
        }
    }
    
    /* No zero-padding */
    else {
        
        /* Multiply by Hann window */
        if (doWindow)
            vDSP_vmul(inBuffer, 1, window, 1, inRealBuffer, 1, len);
        
        /* Otherwise just copy into the real input buffer */
        else
            cblas_scopy(fftSize, inBuffer, 1, inRealBuffer, 1);
    }
    
    /* Transform the real input data into the even-odd split required by vDSP_fft_zrip() explained in: https://developer.apple.com/library/ios/documentation/Performance/Conceptual/vDSP_Programming_Guide/UsingFourierTransforms/UsingFourierTransforms.html */
    vDSP_ctoz((COMPLEX *)inRealBuffer, 2, &splitBuffer, 1, fftSize/2);
    
    /* Computer the FFT */
    vDSP_fft_zrip(fftSetup, &splitBuffer, 1, log2f(fftSize), FFT_FORWARD);
    
    splitBuffer.imagp[0] = 0.0;     // ?? Shitty did this
    
    /* Convert the split complex data splitBuffer to an interleaved complex coordinate pairs */
    vDSP_ztoc(&splitBuffer, 1, (COMPLEX *)inRealBuffer, 2, fftSize/2);
    
    /* Convert the interleaved complex vector to interleaved polar coordinate pairs (magnitude, phase) */
    vDSP_polar(inRealBuffer, 2, outRealBuffer, 2, fftSize/2);
    
    /* Copy the even indices (magnitudes) */
    cblas_scopy(fftSize/2, outRealBuffer, 2, magnitude, 1);
    
    /* Normalize the magnitude */
    for (int i = 0; i < fftSize/2; i++)
        magnitude[i] *= fftScale;
    
    //    /* Copy the odd indices (phases) */
    //    cblas_scopy(fftSize/2, outRealBuffer+1, 2, phase, 1);
}


- (void)printErrorMessage:(NSString *)errorString withStatus:(OSStatus)result {
    
    char errorDetail[20];
    
    /* Check if the error is a 4-character code */
    *(UInt32 *)(errorDetail + 1) = CFSwapInt32HostToBig(result);
    if (isprint(errorDetail[1]) && isprint(errorDetail[2]) && isprint(errorDetail[3]) && isprint(errorDetail[4])) {
        
        errorDetail[0] = errorDetail[5] = '\'';
        errorDetail[6] = '\0';
    }
    else /* Format is an integer */
        sprintf(errorDetail, "%d", (int)result);
    
    fprintf(stderr, "Error: %s (%s)\n", [errorString cStringUsingEncoding:NSASCIIStringEncoding], errorDetail);
}

@end



















