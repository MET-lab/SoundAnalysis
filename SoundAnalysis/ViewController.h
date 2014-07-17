//
//  ViewController.h
//  SoundAnalysis
//
//  Created by Jeff Gregorio on 7/6/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

/* To do: Keep a current X buffer so we don't have to keep malloc-ing and freeing on every plot update (especially longer time scales where performance is key). Only update it when the plot bounds change
 */

#import <UIKit/UIKit.h>

#import "METScopeView.h"
#import "AudioController.h"

#define kScopeUpdateRate 0.003

@interface ViewController : UIViewController {
    
    /* Audio */
    AudioController *audioController;
    
    /* Scopes */
    IBOutlet METScopeView *tdScopeView;
    IBOutlet METScopeView *fdScopeView;
    bool tdHold, fdHold;
    NSTimer *tdScopeClock;
    NSTimer *fdScopeClock;
    
    /* Pinch zoom controls */
    UIPinchGestureRecognizer *tdPinchRecognizer;
    CGFloat tdPreviousPinchScale;
    UIPinchGestureRecognizer *fdPinchRecognizer;
    CGFloat fdPreviousPinchScale;
    
    /* Panning controls */
    UIPanGestureRecognizer *tdPanRecognizer;
    CGPoint tdPreviousPanLoc;
    UIPanGestureRecognizer *fdPanRecognizer;
    CGPoint fdPreviousPanLoc;
    
    /* Tap recognizer for pausing recording */
    UITapGestureRecognizer *tdTapRecognizer;
    
    IBOutlet UISwitch *inputEnableSwitch;
    IBOutlet UISlider *inputGainSlider;
    
    float *currentXBuffer;
    bool paused;
}

@end
