//
//  ViewController.m
//  EyeBlinking
//
//  Created by Denis on 16.12.15.
//  Copyright © 2015 axondevgroup. All rights reserved.
//

#include <opencv2/opencv.hpp>

#import "ViewController.h"
#import "CustomCamera.h"

@interface ViewController ()
{
    CascadeClassifier* _faceCascade;
    CascadeClassifier* _eyeCascade;
    
    dispatch_source_t _blinkInfoRemoveTimer;
    
    std::deque<int> _eyesCounter;
    
    BOOL _isDetecting;
    int _blinksCount;
}

@property (nonatomic, retain) CvVideoCamera* camera;
@property (nonatomic, retain) UILabel* blinkInfo;

//@property (nonatomic, retain) NSTimer* blinkLabelTimer;

@end

@implementation ViewController

- (void)dealloc {
    
    self.camera = nil;
    
    if (_blinkInfoRemoveTimer)
    {
        dispatch_source_cancel(_blinkInfoRemoveTimer);
        dispatch_release(_blinkInfoRemoveTimer);
        _blinkInfoRemoveTimer = nil;
    }
    
//    [_blinkLabelTimer invalidate];
//    self.blinkLabelTimer = nil;
    
    delete _faceCascade;
    delete _eyeCascade;
    
    [super dealloc];
};

- (void)viewDidLoad {
    
//    self.view.backgroundColor = [UIColor blackColor];
    
    [super viewDidLoad];
    
    [self initCamera];
};

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
};

- (CascadeClassifier*)loadCascadeClassifier:(NSString*)path {
    return new CascadeClassifier([[[NSBundle mainBundle] pathForResource:path ofType:@"xml"] UTF8String]);
};

- (void)initCamera {
    
    UIView* imageView = [[[UIImageView alloc] initWithFrame:self.view.bounds] autorelease];
//    imageView.backgroundColor = [UIColor greenColor];
    [self.view addSubview:imageView];
    
    self.blinkInfo = [[[UILabel alloc] initWithFrame:CGRectMake(0,
                                                                0.05f * self.view.bounds.size.height,
                                                                self.view.bounds.size.width, 0.1f * self.view.bounds.size.height)] autorelease];
    _blinkInfo.font = [UIFont fontWithName:@"Arial-BoldMT" size:0.1f * self.view.bounds.size.height];
    _blinkInfo.textColor = [UIColor greenColor];
    _blinkInfo.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_blinkInfo];
    _blinkInfo.hidden = YES;
    
    UIButton *holdButton = [UIButton buttonWithType:UIButtonTypeSystem];
    holdButton.frame = CGRectMake(0, 0.85f * self.view.bounds.size.height,
                                     self.view.bounds.size.width, 0.1f * self.view.bounds.size.height);
    holdButton.backgroundColor = [UIColor clearColor];
    holdButton.titleLabel.font = [UIFont fontWithName:@"Arial-BoldMT" size:0.05f * self.view.bounds.size.height];
    [holdButton setTitle:@"[Hold for detection]"
                   forState:UIControlStateNormal];
    
    [holdButton setTitleColor:[UIColor greenColor]
                        forState:UIControlStateNormal];
    
    [holdButton addTarget:self
                   action:@selector(startDetection)
         forControlEvents:UIControlEventTouchDown];
    
    [holdButton addTarget:self
                   action:@selector(stopDetection)
         forControlEvents:UIControlEventTouchUpInside];
    
    [holdButton addTarget:self
                   action:@selector(stopDetection)
         forControlEvents:UIControlEventTouchUpOutside];
    
    [self.view addSubview:holdButton];
    
    self.camera = [[[CustomCamera alloc] initWithParentView:imageView] autorelease];
    
    _camera.delegate = self;
    _camera.defaultAVCaptureDevicePosition = AVCaptureDevicePositionFront;
    _camera.defaultAVCaptureSessionPreset = AVCaptureSessionPresetLow;
    _camera.defaultAVCaptureVideoOrientation = AVCaptureVideoOrientationPortrait;
    _camera.defaultFPS = 30;
    _camera.rotateVideo = NO;
//    _camera.grayscaleMode = YES;
    
    _faceCascade = [self loadCascadeClassifier:@"haarcascade_frontalface_default"];
    _eyeCascade = [self loadCascadeClassifier:@"haarcascade_eye"];
    
    [_camera start];
};

- (void)processImage:(Mat&)image
{
    if (!_isDetecting)
        return;
    
    std::vector<cv::Rect> rects;
    
    int minS = MIN(image.size().width, image.size().height);
    
    _faceCascade->detectMultiScale(image, rects, 1.35, 6, CV_HAAR_SCALE_IMAGE,
                                   cv::Size(0.5f * minS, 0.6f * minS),
                                   cv::Size(0.8f * minS, 0.8f * minS));
    
    if (rects.size() == 1) // ignore more
    {
        cv::Rect& faceR = rects[0];
        
        cv::Rect faceEyeZone( cv::Point(faceR.x + 0.12f * faceR.width,
                                        faceR.y + 0.17f * faceR.height),
                              cv::Size(0.76 * faceR.width,
                                       0.4f * faceR.height));
        
       
        
        rects.clear();
        
        // draw some debug info
        
        rectangle(image, faceR, Scalar(0,255,0));
        
        rectangle(image, faceEyeZone, Scalar(0,255,0));
        
        Mat eyeImage(image, faceEyeZone);
        
        
        _eyeCascade->detectMultiScale(eyeImage, rects, 1.2f, 5, CV_HAAR_SCALE_IMAGE,
                                      cv::Size(faceEyeZone.width * 0.2f, faceEyeZone.width * 0.2f),
                                      cv::Size(0.5f * faceEyeZone.width, 0.7f * faceEyeZone.height));
        
        for (int i = 0; i < rects.size(); ++i)
            rectangle(eyeImage, rects[i], Scalar(0,0,255));
        
        [self registerEyesCount:(int)rects.size()];
        
        if ([self checkBlink])
        {
            ++_blinksCount;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                _blinkInfo.hidden = NO;
            });
          
            if (_blinkInfoRemoveTimer)
            {
                dispatch_source_cancel(_blinkInfoRemoveTimer);
                dispatch_release(_blinkInfoRemoveTimer);
                _blinkInfoRemoveTimer = nil;
            }
            
            _blinkInfoRemoveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());

            dispatch_source_set_timer(_blinkInfoRemoveTimer, dispatch_time(DISPATCH_TIME_NOW, 0.25f * NSEC_PER_SEC), 0.25f * NSEC_PER_SEC, 0);
            dispatch_source_set_event_handler(_blinkInfoRemoveTimer, ^{
                _blinkInfo.hidden = YES;
            });
            dispatch_resume(_blinkInfoRemoveTimer);
            
            
            //[self registerEyesCount:-1];
            _eyesCounter.clear();
        }
    }
    else
    {
        _eyesCounter.clear();
        //[self registerEyesCount:-1];
    }
};


- (void)registerEyesCount:(int)count {
    
    if (_eyesCounter.empty() || (_eyesCounter[_eyesCounter.size() - 1] != count))
        _eyesCounter.push_back(count);
    
    if (_eyesCounter.size() > 3)
        _eyesCounter.pop_front();
};

- (BOOL)checkBlink {
    if (_eyesCounter.size() == 3)
    {
        return (_eyesCounter[2] > 0)
                &&
                (_eyesCounter[1] == 0)
                &&
                (_eyesCounter[0] > 0);
    }
    return NO;
};

- (void)startDetection {
    _isDetecting = YES;
    _blinksCount = 0;
    
    _blinkInfo.text = @"Blink";
    _blinkInfo.hidden = YES;
};

- (void)stopDetection {
    _isDetecting = NO;
    
    if (_blinkInfoRemoveTimer)
    {
        dispatch_source_cancel(_blinkInfoRemoveTimer);
        dispatch_release(_blinkInfoRemoveTimer);
        _blinkInfoRemoveTimer = nil;
    }
    
    _blinkInfo.text = [NSString stringWithFormat:@"Blinks: %i", _blinksCount];
    _blinkInfo.hidden = NO;
    
    _eyesCounter.clear();
};

@end
