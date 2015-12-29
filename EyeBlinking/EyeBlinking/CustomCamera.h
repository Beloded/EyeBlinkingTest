//
//  CustomCamera.h
//  EyeBlinking
//
//  Created by Vitalik Beloded on 28.12.15.
//  Copyright © 2015 axondevgroup. All rights reserved.
//

#import <opencv2/videoio/cap_ios.h>

//@protocol CustomCameraDelegate <CvVideoCameraDelegate>
//@end

@interface CustomCamera : CvVideoCamera

- (void)updateOrientation;
- (void)layoutPreviewLayer;

@end
