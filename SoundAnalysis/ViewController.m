//
//  ViewController.m
//  SoundAnalysis
//
//  Created by Jeff Gregorio on 7/6/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[self view] setBackgroundColor:[UIColor whiteColor]];
    
    /* ----------------- */
    /* == Audio Setup == */
    /* ----------------- */
    audioController = [[AudioController alloc] init];
    
    /* ----------------------------------------------------- */
    /* == Setup for time and frequency domain scope views == */
    /* ----------------------------------------------------- */
    [tdScopeView setPlotResolution:456];
    [tdScopeView setHardXLim:-0.00001 max:audioController.recordingBufferLength/kAudioSampleRate];
    [tdScopeView setVisibleXLim:-0.00001 max:audioController.audioBufferLength/kAudioSampleRate];
    [tdScopeView setPlotUnitsPerXTick:0.005];
    [tdScopeView setMinPlotRange:CGPointMake(audioController.audioBufferLength/kAudioSampleRate/2, 0.1)];
    [tdScopeView setMaxPlotRange:CGPointMake(audioController.recordingBufferLength/kAudioSampleRate, 2.0)];
    [tdScopeView setXGridAutoScale:true];
    [tdScopeView setYGridAutoScale:true];
    [tdScopeView setXPinchZoomEnabled:false];
    [tdScopeView setYPinchZoomEnabled:false];
    [tdScopeView setXLabelPosition:kMETScopeViewXLabelsOutsideAbove];
    [tdScopeView setYLabelPosition:kMETScopeViewYLabelsOutsideLeft];
    [tdScopeView addPlotWithColor:[UIColor blueColor] lineWidth:2.0];
    
    [fdScopeView setPlotResolution:fdScopeView.frame.size.width];
    [fdScopeView setUpFFTWithSize:kFFTSize];      // Set up FFT before setting FD mode
    [fdScopeView setDisplayMode:kMETScopeViewFrequencyDomainMode];
    [fdScopeView setHardXLim:0.0 max:10000];       // Set bounds after FD mode
    [fdScopeView setVisibleXLim:0.0 max:9300];
    [fdScopeView setPlotUnitsPerXTick:2000];
    [fdScopeView setXGridAutoScale:true];
    [fdScopeView setYGridAutoScale:true];
    [fdScopeView setXPinchZoomEnabled:false];
    [fdScopeView setYPinchZoomEnabled:false];
    [fdScopeView setXLabelPosition:kMETScopeViewXLabelsOutsideBelow];
    [fdScopeView setYLabelPosition:kMETScopeViewYLabelsOutsideLeft];
    [fdScopeView setAxisScale:kMETScopeViewAxesSemilogY];
    [fdScopeView setHardYLim:-80 max:0];
    [fdScopeView setPlotUnitsPerYTick:20];
    [fdScopeView setAxesOn:true];
    [fdScopeView addPlotWithColor:[UIColor blueColor] lineWidth:2.0];
    
    /* ------------------------------------ */
    /* === External gesture recognizers === */
    /* ------------------------------------ */
    
    tdPinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleTDPinch:)];
    [tdScopeView addGestureRecognizer:tdPinchRecognizer];
    fdPinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleFDPinch:)];
    [fdScopeView addGestureRecognizer:fdPinchRecognizer];
    
    tdPanRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleTDPan:)];
    [tdPanRecognizer setMinimumNumberOfTouches:1];
    [tdPanRecognizer setMaximumNumberOfTouches:1];
    [tdScopeView addGestureRecognizer:tdPanRecognizer];
    fdPanRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFDPan:)];
    [fdPanRecognizer setMinimumNumberOfTouches:1];
    [fdPanRecognizer setMaximumNumberOfTouches:1];
    [fdScopeView addGestureRecognizer:fdPanRecognizer];
    
    tdTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTDTap:)];
    [tdTapRecognizer setNumberOfTapsRequired:2];
    [tdScopeView addGestureRecognizer:tdTapRecognizer];
    
    /* Update the scope views on timers by querying AudioController's recording buffer */
    [self setTDUpdateRate:kScopeUpdateRate];
    [self setFDUpdateRate:kScopeUpdateRate];
    tdHold = fdHold = paused = false;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setTDUpdateRate:(float)rate {
    
    if ([tdScopeClock isValid])
        [tdScopeClock invalidate];
    
    tdScopeClock = [NSTimer scheduledTimerWithTimeInterval:rate
                                                    target:self
                                                  selector:@selector(tdPlotCurrent)
                                                  userInfo:nil
                                                   repeats:YES];
}

- (void)setFDUpdateRate:(float)rate {
    
    if ([fdScopeClock isValid])
        [fdScopeClock invalidate];
    
    fdScopeClock = [NSTimer scheduledTimerWithTimeInterval:rate
                                                    target:self
                                                  selector:@selector(fdPlotCurrent)
                                                  userInfo:nil
                                                   repeats:YES];
}

- (void)tdPlotCurrent {
    
    if (paused)
        return;
    
    int length = (tdScopeView.visiblePlotMax.x - fmax(tdScopeView.visiblePlotMin.x, 0.0)) * kAudioSampleRate;
    
    /* Update the plot */
    if (!tdHold) {
        
        currentXBuffer = (float *)malloc(length * sizeof(float));
        [self linspace:fmax(tdScopeView.visiblePlotMin.x, 0.0)
                   max:tdScopeView.visiblePlotMax.x
           numElements:length
                 array:currentXBuffer];
        
        float *currentYBuffer = (float *)malloc(length * sizeof(float));
        [audioController getRecordedAudioWithLength:length outBuffer:currentYBuffer];
        
        [tdScopeView setPlotDataAtIndex:0
                             withLength:length
                                  xData:currentXBuffer
                                  yData:currentYBuffer];
        free(currentXBuffer);
        free(currentYBuffer);
    }
}

- (void)tdPlotVisible {
    
    int startIdx = fmax(tdScopeView.visiblePlotMin.x, 0.0) * kAudioSampleRate;
    int endIdx = fmin(tdScopeView.visiblePlotMax.x * kAudioSampleRate, audioController.recordingBufferLength);
    int visibleBufferLength = endIdx - startIdx;
    
    /* Get buffer of times for each sample */
    float *visibleXBuffer = (float *)malloc(visibleBufferLength * sizeof(float));
    [self linspace:fmax(tdScopeView.visiblePlotMin.x, 0.0)
               max:tdScopeView.visiblePlotMax.x
       numElements:visibleBufferLength
             array:visibleXBuffer];
    
    /* Allocate wet/dry signal buffers */
    float *visibleYBuffer = (float *)malloc(visibleBufferLength * sizeof(float));
    
    /* Get current visible samples from the audio controller */
    [audioController getRecordedAudioFrom:startIdx to:endIdx outBuffer:visibleYBuffer];
    
    [tdScopeView setPlotDataAtIndex:0
                         withLength:visibleBufferLength
                              xData:visibleXBuffer
                              yData:visibleYBuffer];
    free(visibleXBuffer);
    free(visibleYBuffer);
}

- (void)fdPlotCurrent {
    
    if (paused)
        return;
    
    /* Only plot the current audio buffer */
    int length = audioController.audioBufferLength;
    
    /* Update the plot */
    if (!tdHold) {
        
        currentXBuffer = (float *)malloc(length * sizeof(float));
        [self linspace:fmax(tdScopeView.visiblePlotMin.x, 0.0)
                   max:tdScopeView.visiblePlotMax.x
           numElements:length
                 array:currentXBuffer];
        
        float *currentYBuffer = (float *)malloc(length * sizeof(float));
        [audioController getRecordedAudioWithLength:length outBuffer:currentYBuffer];
        
        [fdScopeView setPlotDataAtIndex:0
                             withLength:length
                                  xData:currentXBuffer
                                  yData:currentYBuffer];
        free(currentXBuffer);
        free(currentYBuffer);
    }
}

- (void)fdPlotVisible {
    
    int startIdx = fmax(tdScopeView.visiblePlotMin.x, 0.0) * kAudioSampleRate;
    int endIdx = fmin(tdScopeView.visiblePlotMax.x * kAudioSampleRate, audioController.recordingBufferLength);
    
    float *freqs = (float *)malloc(audioController.fftSize/2 * sizeof(float));
    [self linspace:0
               max:kAudioSampleRate/2
     numElements:audioController.fftSize/2
             array:freqs];
    
    /* Allocate wet/dry signal buffers */
    float *visibleSpec = (float *)malloc(audioController.fftSize/2 * sizeof(float));
    
    /* Get current visible samples from the audio controller */
    [audioController getAverageSpectrumFrom:startIdx to:endIdx outBuffer:visibleSpec];
    
    [fdScopeView setCoordinatesInFDModeAtIndex:0
                                    withLength:audioController.fftSize/2
                                         xData:freqs
                                         yData:visibleSpec];
    free(freqs);
    free(visibleSpec);
}

- (void)handleTDPinch:(UIPinchGestureRecognizer *)sender {
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        
        /* Save the initial pinch scale */
        tdPreviousPinchScale = sender.scale;
        
        /* Throttle spectrum plot */
        tdHold = true;
        float rate = 1000 * [fdScopeClock timeInterval];
        [self setFDUpdateRate:rate];
        
    }
    
    else if (sender.state == UIGestureRecognizerStateEnded) {
        
        /* Restart time domain plot and revert spectrum update rate to the default */
        tdHold = false;
        
        [self setFDUpdateRate:kScopeUpdateRate];
        
        if (paused) {
            [self tdPlotVisible];
            [self fdPlotVisible];
        }
    }
    
    else {
        
        CGFloat scaleChange;
        scaleChange = sender.scale - tdPreviousPinchScale;
        
        /* If we're recording, zoom into the future */
        if (!paused)
            [tdScopeView setVisibleXLim:tdScopeView.visiblePlotMin.x
                                    max:(tdScopeView.visiblePlotMax.x - scaleChange*tdScopeView.visiblePlotMax.x)];
        
        /* Otherwise, we're paused; zoom into the past */
        else
            [tdScopeView setVisibleXLim:(tdScopeView.visiblePlotMin.x + scaleChange*tdScopeView.visiblePlotMin.x)
                                    max:tdScopeView.visiblePlotMax.x];
        
        tdPreviousPinchScale = sender.scale;
    }
}

- (void)handleFDPinch:(UIPinchGestureRecognizer *)sender {
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        
        /* Save the initial pinch scale */
        fdPreviousPinchScale = sender.scale;
        
        /* Stop the spectrum plot updates */
        fdHold = true;
        return;
    }
    
    else if (sender.state == UIGestureRecognizerStateEnded) {
        
        /* Restart the spectrum plot updates */
        fdHold = false;
    }
    
    else {
        
        /* Scale the frequency axis upper bound */
        CGFloat scaleChange;
        scaleChange = sender.scale - fdPreviousPinchScale;
        
        [fdScopeView setVisibleXLim:fdScopeView.visiblePlotMin.x
                                max:(fdScopeView.visiblePlotMax.x - scaleChange*fdScopeView.visiblePlotMax.x)];
        
        fdPreviousPinchScale = sender.scale;
    }
}

- (void)handleTDPan:(UIPanGestureRecognizer *)sender {
    
    /* Location of current touch */
    CGPoint touchLoc = [sender locationInView:sender.view];
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        
        /* Save initial touch location */
        tdPreviousPanLoc = touchLoc;
        
        /* Stop the time-domain plot updates */
        tdHold = true;
    }
    
    else if (sender.state == UIGestureRecognizerStateEnded) {
        
        /* Restart time-domain plot updates */
        tdHold = false;
        
        if (paused) {
            [self tdPlotVisible];
            [self fdPlotVisible];
        }
    }
    
    else {
        
        /* Get the relative change in location; convert to plot units (time) */
        CGPoint locChange;
        locChange.x = tdPreviousPanLoc.x - touchLoc.x;
        locChange.y = tdPreviousPanLoc.y - touchLoc.y;
        
        /* Shift the plot bounds in time */
        locChange.x *= tdScopeView.unitsPerPixel.x;
        [tdScopeView setVisibleXLim:(tdScopeView.visiblePlotMin.x + locChange.x)
                                max:(tdScopeView.visiblePlotMax.x + locChange.x)];
        
        tdPreviousPanLoc = touchLoc;
    }
}

- (void)handleFDPan:(UIPanGestureRecognizer *)sender {
    
    /* Location of current touch */
    CGPoint touchLoc = [sender locationInView:sender.view];
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        
        /* Save initial touch location */
        fdPreviousPanLoc = touchLoc;
        
        /* Throttle time and spectrum plot updates */
        float rate = 500 * (tdScopeView.visiblePlotMax.x - tdScopeView.visiblePlotMin.x) * [tdScopeClock timeInterval] + 30 * [tdScopeClock timeInterval];
        [self setTDUpdateRate:rate];
        [self setFDUpdateRate:rate/2];
    }
    
    else if (sender.state == UIGestureRecognizerStateEnded) {
        
        /* Return time and spectrum plot updates to default rate */
        [self setTDUpdateRate:kScopeUpdateRate];
        [self setFDUpdateRate:kScopeUpdateRate];
    }
    
    else {
        
        /* Get the relative change in location; convert to plot units (frequency) */
        CGPoint locChange;
        locChange.x = fdPreviousPanLoc.x - touchLoc.x;
        locChange.y = fdPreviousPanLoc.y - touchLoc.y;
        locChange.x *= fdScopeView.unitsPerPixel.x;
        
        /* Shift the plot bounds in frequency */
        [fdScopeView setVisibleXLim:(fdScopeView.visiblePlotMin.x + locChange.x)
                                max:(fdScopeView.visiblePlotMax.x + locChange.x)];
        
        fdPreviousPanLoc = touchLoc;
    }
}

- (void)handleTDTap:(UITapGestureRecognizer *)sender {
    
    if ([audioController isRunning]) {
        
        paused = true;
        [audioController stopAUGraph];
        [inputEnableSwitch setOn:false animated:true];
        
        /* Show one audio buffer at the end of the reocording buffer */
//        [tdScopeView setVisibleXLim:((audioController.recordingBufferLength - audioController.audioBufferLength) / kAudioSampleRate)
//                                max:audioController.recordingBufferLength / kAudioSampleRate];
//        [tdScopeView setPlotUnitsPerTick:0.005 vertical:0.5];
        
        /* Keep the current plot range, but shift it to the end of the recording buffer */
        [tdScopeView setVisibleXLim:(audioController.recordingBufferLength / kAudioSampleRate) - (tdScopeView.visiblePlotMax.x - tdScopeView.visiblePlotMin.x)
                                max:audioController.recordingBufferLength / kAudioSampleRate];
        
        [self tdPlotVisible];
    }
    else {
        
        paused = false;
        [audioController startAUGraph];
        [inputEnableSwitch setOn:true animated:true];
        
        [tdScopeView setVisibleXLim:-0.00001
                                max:audioController.audioBufferLength / kAudioSampleRate];
        
        [tdScopeView setPlotUnitsPerTick:0.005 vertical:0.5];
    }
    
    /* Flash animation */
    UIView *flashView = [[UIView alloc] initWithFrame:tdScopeView.frame];
    [flashView setBackgroundColor:[UIColor blackColor]];
    [flashView setAlpha:0.5f];
    [[self view] addSubview:flashView];
    [UIView animateWithDuration:0.5f
                     animations:^{
                         [flashView setAlpha:0.0f];
                     }
                     completion:^(BOOL finished) {
                         [flashView removeFromSuperview];
                     }
     ];
}


- (IBAction)toggleInput:(id)sender {
    
    if ([audioController isRunning]) {
        [audioController stopAUGraph];
    }
    else {
        [audioController startAUGraph];
    }
}

- (IBAction)updateInputGain:(id)sender {
    [audioController setInputGain:inputGainSlider.value];
}

#pragma mark -
#pragma mark Utility
/* Generate a linearly-spaced set of indices for sampling an incoming waveform */
- (void)linspace:(float)minVal max:(float)maxVal numElements:(int)size array:(float*)array {
    
    float step = (maxVal-minVal)/(size-1);
    array[0] = minVal;
    int i;
    for (i = 1;i<size-1;i++) {
        array[i] = array[i-1]+step;
    }
    array[size-1] = maxVal;
}

@end
