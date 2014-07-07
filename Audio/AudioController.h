//
//  AudioController.h
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 5/11/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#import <pthread.h>

#define kAudioSampleRate        44100.0
#define kAudioBytesPerPacket    4
#define kAudioFramesPerPacket   1
#define kAudioChannelsPerFrame  2

// Potentially unsafe assumption. Is there a way to force this buffer size or is it hardware-dependent?
#define kAudioBufferSize 1024
#define kRecordingBufferLengthSeconds 3.0

#define kFFTSize 1024

#pragma mark -
#pragma mark AudioController
@interface AudioController : NSObject {

    AUGraph graph;
    AudioUnit remoteIOUnit;
    AudioStreamBasicDescription IOStreamFormat;
    
    Float32 *recordingBuffer;
    pthread_mutex_t recordingBufferMutex;
    
    Float32 *spectrumBuffer;
    pthread_mutex_t spectrumBufferMutex;
    
    int windowSize;
    FFTSetup fftSetup;
    float *inRealBuffer;
    float *outRealBuffer;
    float *window;
    float fftScale;
    COMPLEX_SPLIT splitBuffer;
}

@property (readonly) AudioUnit remoteIOUnit;
@property Float32 inputGain;

@property Float32 hardwareSampleRate;

@property int audioBufferLength;
@property (readonly) int recordingBufferLength;
@property (readonly) int fftSize;
@property (readonly) int nFFTFrames;

@property (readonly) bool inputEnabled;
@property (readonly) bool isInitialized;
@property (readonly) bool isRunning;

/* Memory allocation for recording */
- (void)allocateRecordingBufferWithLength:(int)length;

/* Start/stop audio */
- (void)startAUGraph;
- (void)stopAUGraph;

/* Enable/disable audio input */
- (void)setInputEnabled: (bool)enabled;
- (void)setOutputEnabled:(bool)enabled;

/* Append to and read most recent data from the internal recording buffer */
- (void)appendBufferWithLength:(int)length buffer:(Float32 *)inBuffer;
- (void)getRecordedAudioWithLength:(int)length outBuffer:(Float32 *)outBuffer;
- (void)getRecordedAudioFrom:(int)startIdx to:(int)endIdx outBuffer:(Float32 *)outBuffer;
- (void)getAverageSpectrumFrom:(int)startIdx to:(int)endIdx outBuffer:(Float32 *)outBuffer;

@end
