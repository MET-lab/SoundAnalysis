//
//  METScopeView.h
//  METScopeViewTest
//
//  Created by Jeff Gregorio on 5/7/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

/* TO DO:
 
    - modify METScopeView to automatically begin appending audio buffers when plot bounds are increased
    - don't resample portions within the plot's time bounds on successive plot updates. Only sample the incoming audio buffer at the portion of the resolution needed
 
*/


#import <UIKit/UIKit.h>
#import <Accelerate/Accelerate.h>
#import <pthread.h>

#pragma mark Defaults

#define METScopeView_Default_MaxPlotTime 2.0

#define METScopeView_Default_PlotResolution 1024
#define METScopeview_Default_MaxRefreshRate 0.02
/* Time-domain mode defaults */
#define METScopeView_Default_XMin_TD (-0.0001)
#define METScopeView_Default_XMax_TD 0.023      // For length 1024 buffer at 44.1kHz
#define METScopeView_Default_YMin_TD (-1.25)
#define METScopeView_Default_YMax_TD 1.25
#define METScopeView_Default_XTick_TD 0.005
#define METScopeView_Default_YTick_TD 0.5
#define METScopeView_Default_XMinRange_TD 0.01
#define METScopeView_Default_XMaxRange_TD 1.0
#define METScopeView_Default_YMinRange_TD 0.1
#define METScopeView_Default_YMaxRange_TD 2.0
#define METScopeView_Default_xLabelFormatString_TD @"%5.2f"
#define METScopeView_Default_yLabelFormatString_TD @"%3.2f"
/* Frequency-domain mode defaults */
#define METScopeView_Default_SamplingRate 44100 // For x-axis scaling
#define METScopeView_Default_XMin_FD (-20)
#define METScopeView_Default_XMax_FD 20000.0    // For sampling rate 44.1kHz
#define METScopeView_Default_YMin_FD (-0.04)
#define METScopeView_Default_YMax_FD 1.0
#define METScopeView_Default_XTick_FD 4000
#define METScopeView_Default_YTick_FD 0.25
#define METScopeView_Default_XMinRange_FD 10
#define METScopeView_Default_XMaxRange_FD 20000
#define METScopeView_Default_YMinRange_FD_lin 0.1
#define METScopeView_Default_YMaxRange_FD_lin 100.0
#define METScopeView_Default_YMinRange_FD_log 10
#define METScopeView_Default_YMaxRange_FD_log 100
#define METScopeView_Default_xLabelFormatString_FD @"%5.0f"
#define METScopeView_Default_yLabelFormatString_FD @"%3.2f"
/* Auto grid scaling defaults */
#define METScopeView_AutoGrid_MaxXTicksInFrame 6.0
#define METScopeView_AutoGrid_MinXTicksInFrame 4.0
#define METScopeView_AutoGrid_MaxYTicksInFrame 5.0
#define METScopeView_AutoGrid_MinYTicksInFrame 3.0
/* Label defaults */
#define METScopeView_XLabel_Outside_Extension 15
#define METScopeview_YLabel_Outside_Extension 28

@protocol METScopeViewDelegate <NSObject>
@required
- (void)finishedPinchZoom;
@end

/* Forward declaration of subview classes */
@class METScopeAxisView;
@class METScopeGridView;
@class METScopeLabelView;
@class METScopePlotDataView;

/* Whether we're sampling a time-domain waveform or doing an FFT */
typedef enum DisplayMode {
    kMETScopeViewTimeDomainMode,
    kMETScopeViewFrequencyDomainMode
} DisplayMode;

typedef enum AxisScale {
    kMETScopeViewAxesLinear,
    kMETScopeViewAxesSemilogY,
    kMETScopeViewAxesSemilogX,
    kMETScopeViewAxesLogLog
} AxisScale;

typedef enum XLabelPosition {
    kMETScopeViewXLabelsBelowAxis,
    kMETScopeViewXLabelsAboveAxis,
    kMETScopeViewXLabelsOutsideBelow,
    kMETScopeViewXLabelsOutsideAbove
} XLabelPosition;

typedef enum YLabelPosition {
    kMETScopeViewYLabelsAtAxisRight,
    kMETScopeViewYLabelsAtAxisLeft,
    kMETScopeViewYLabelsOutsideLeft,
    kMETScopeViewYLabelsOutsideRight
} YLabelPosition;

#pragma mark -
#pragma mark METScopeView
@interface METScopeView : UIView <UIGestureRecognizerDelegate> {
    
    NSMutableArray *plotDataSubviews;   // Subview array of plot waveforms
    METScopeAxisView *axesSubview;      // Subview that draws axes
    METScopeGridView *gridSubview;      // Subveiw that draws grid
    METScopeLabelView *labelsSubview;   // Subview that draws labels
    
    CGPoint unitsPerPixel;  // Plot unit <-> pixel conversion factor
    
    /* Pinch zoom */
    UIPinchGestureRecognizer *pinchRecognizer;
    CGPoint previousPinchTouches[2];
    int previousNumPinchTouches;
    bool pinchZoomEnabled;
    
    /* Spectrum mode FFT parameters */
    int fftSize;                // Length of FFT, 2*nBins
    int windowSize;             // Length of Hann window
    float *freqs;               // Frequency bin centers
    float *inRealBuffer;        // Input buffer
    float *outRealBuffer;       // Output buffer
    float *window;              // Hann window
    float scale;                // Normalization constant
    FFTSetup fftSetup;          // vDSP FFT struct
    COMPLEX_SPLIT splitBuffer;  // Buffer holding real and complex parts
}

#pragma mark -
#pragma mark Properties
@property (readonly) int plotResolution;            /* Default number of values sampled
                                                       from incoming waveforms */

@property (readonly) DisplayMode displayMode;       // Time or frequency domain
@property (readonly) AxisScale axisScale;           // Linear/semilog/loglog
@property (readonly) XLabelPosition xLabelPosition;
@property (readonly) YLabelPosition yLabelPosition;

@property (readonly) CGPoint visiblePlotMin;        // Visible bounds in plot units
@property (readonly) CGPoint visiblePlotMax;
@property (readonly) CGPoint minPlotMin;            // Hard limits constraining pinch zoom
@property (readonly) CGPoint maxPlotMax;
@property CGPoint minPlotRange;
@property CGPoint maxPlotRange;
@property (readonly) CGPoint tickUnits;             // Grid/tick spacing in plot units
@property (readonly) CGPoint tickPixels;            // Grid/tick spacing in pixels
@property (readonly) CGPoint originPixel;           // Plot origin location in pixels
@property (readonly) CGPoint unitsPerPixel;
@property (readonly) bool axesOn;                   // Drawing axes subview
@property (readonly) bool gridOn;                   // Drawing grid subview
@property (readonly) bool labelsOn;                 // Drawing labels subview

@property (readonly, getter=isCurrentlyZooming) bool currentlyZooming;

@property id <METScopeViewDelegate> delegate;

@property int samplingRate;                     /* Set for proper x-axis scaling in
                                                   frequency domain mode (default 44.1kHz) */

@property NSString *xLabelFormatString;     // Format specifiers for numerical labels
@property NSString *yLabelFormatString;

@property bool xLabelsOn;               // Labels subview drawing x/y labels
@property bool yLabelsOn;
@property bool xGridAutoScale;          // Keep a specified number of grid squares
@property bool yGridAutoScale;
@property bool xPinchZoomEnabled;       // Enable/disable built-in pinch zoom
@property bool yPinchZoomEnabled;

#pragma mark -
#pragma mark Interface Methods
/* Set the number of points sampled from incoming waveforms */
- (void)setPlotResolution:(int)res;

/* Set the display mode to time/frequency domain and automatically rescale to default limits */
- (void)setDisplayMode:(enum DisplayMode)mode;

/* Set the scaling linear/semilogx/semilogy/loglog of the axes */
- (void)setAxisScale:(AxisScale)pAxisScale;

/* Set the positions of the labels relative to the axis or plot bounds */
- (void)setXLabelPosition:(XLabelPosition)pXLabelPosition;
- (void)setYLabelPosition:(YLabelPosition)pYLabelPosition;

/* Initialize a vDSP FFT object */
- (void)setUpFFTWithSize:(int)size;

/* Hard axislimits constraining pinch zoom; update */
- (void)setHardXLim:(float)xMin max:(float)xMax;
- (void)setHardYLim:(float)yMin max:(float)yMax;

/* Set the visible ranges of the axes in plot units; update */
- (void)setVisibleXLim:(float)xMin max:(float)xMax;
- (void)setVisibleYLim:(float)yMin max:(float)yMax;

/* Set ticks and grid scale by specifying the input magnitude per tick/grid block; update */
- (void)setPlotUnitsPerXTick:(float)xTick;
- (void)setPlotUnitsPerYTick:(float)yTick;
- (void)setPlotUnitsPerTick:(float)xTick vertical:(float)yTick;

/* Add/remove subviews for axes, labels, and grid */
- (void)setAxesOn:(bool)pAxesOn;
- (void)setGridOn:(bool)pGridOn;
- (void)setLabelsOn:(bool)pLabelsOn;

/* Query the number of plot subviews */
- (int)getNumberOfPlots;
- (int)getNumberOfVisiblePlots;

/* Allocate a subview for new plot data with specified resolution/color/linewidth, return the index */
- (int)addPlotWithColor:(UIColor *)color lineWidth:(float)width;
- (int)addPlotWithResolution:(int)res color:(UIColor *)color lineWidth:(float)width;

/* Set the plot data for a subview at a specified index */
- (void)setPlotDataAtIndex:(int)idx withLength:(int)len xData:(float *)xx yData:(float *)yy;

/* Get the plot data for a subview at a specified index */
- (void)getPlotDataAtIndex:(int)idx withLength:(int)len xData:(float *)xx yData:(float *)yy;

/* Set raw coordinates (plot units) while in frequency domain mode without taking the FFT */
- (void)setCoordinatesInFDModeAtIndex:(int)idx withLength:(int)len xData:(float *)xx yData:(float *)yy;

/* Add a constant value to all x/y data in plot units */
- (void)addToPlotXData:(float)value atIndex:(int)idx;
- (void)addToPlotYData:(float)value atIndex:(int)idx;

/* Set the visiblility of waveform subviews */
- (void)setVisibilityAtIndex:(int)idx visible:(bool)visible;

/* Set/update plot resolution/color/linewidth for a waveform at a specified index */
- (void)setPlotColor:(UIColor *)color atIndex:(int)idx;
- (void)setLineWidth:(float)width atIndex:(int)idx;
- (void)setPlotResolution:(int)res atIndex:(int)idx;
- (void)setVisiblity:(bool)visible atIndex:(int)idx;

- (void)setFillMode:(bool)doFill atIndex:(int)idx;
- (bool)getFillModeAtIndex:(int)idx;

/* Get the x-axis (frequency) values for a frequency-domain mode plot */
- (void)getFreqs:(float *)outFreqs;

/* Utility methods: convert pixel values to plot scales and vice-versa */
- (CGPoint)plotScaleToPixel:(float)pX y:(float)pY;
- (CGPoint)plotScaleToPixel:(CGPoint)plotScale;
- (CGPoint)pixelToPlotScale:(CGPoint)pixel;
- (CGPoint)pixelToPlotScale:(CGPoint)pixel withOffset:(CGPoint)pixelOffset;

@end

