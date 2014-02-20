//
//  TBDiagnoser.mm
//  CellScope
//
//  Created by Frankie Myers on 11/07/13.
//  Copyright (c) 2013 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "TBDiagnoser.h"
#import "Globals.h"
#import "Classifier.h"

@implementation TBDiagnoser


- (UIImage *)grayScaleImage:(UIImage*)image {
    // Create image rectangle with current image width/height
    CGRect imageRect = CGRectMake(0, 0, image.size.width * image.scale, image.size.height * image.scale);
    // Grayscale color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    // Create bitmap content with current image size and grayscale colorspace
    CGContextRef context = CGBitmapContextCreate(nil, image.size.width * image.scale, image.size.height * image.scale, 8, 0, colorSpace, kCGImageAlphaNone);
    // Draw image into current context, with specified rectangle
    // using previously defined context (with grayscale colorspace)
    CGContextDrawImage(context, imageRect, [image CGImage]);
    // Create bitmap image info from pixel data in current context
    CGImageRef grayImage = CGBitmapContextCreateImage(context);
    // release the colorspace and graphics context
    CGColorSpaceRelease(colorSpace);
    CGContextRelease(context);
    // make a new alpha-only graphics context
    context = CGBitmapContextCreate(nil, image.size.width * image.scale, image.size.height * image.scale, 8, 0, nil, kCGImageAlphaOnly);
    // draw image into context with no colorspace
    CGContextDrawImage(context, imageRect, [image CGImage]);
    // create alpha bitmap mask from current context
    CGImageRef mask = CGBitmapContextCreateImage(context);
    // release graphics context
    CGContextRelease(context);
    // make UIImage from grayscale image with alpha mask
    CGImageRef cgImage = CGImageCreateWithMask(grayImage, mask);
    UIImage *grayScaleImage = [UIImage imageWithCGImage:cgImage scale:image.scale orientation:image.imageOrientation];
    // release the CG images
    CGImageRelease(cgImage);
    CGImageRelease(grayImage);
    CGImageRelease(mask);
    // return the new grayscale image
    return grayScaleImage;
}

//convert iOS image to OpenCV image.
//TODO: look into what this is doing with color images
- (cv::Mat)cvMatWithImage:(UIImage *)image
{
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    cv::Mat cvMat;

    NSLog(@"width = %f", image.size.width);
    NSLog(@"height = %f", image.size.height);
    
    if (CGColorSpaceGetModel(colorSpace) == kCGColorSpaceModelRGB) { // 3 channels
        cvMat = cv::Mat(rows, cols, CV_8UC3);
    } else if (CGColorSpaceGetModel(colorSpace) == kCGColorSpaceModelMonochrome) { // 1 channel
        cvMat = cv::Mat(rows, cols, CV_8UC1); // 8 bits per component, 1 channels
    } 
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNone |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    CGColorSpaceRelease(colorSpace);
    

    return cvMat;
}


- (ImageAnalysisResults*) runWithImage: (UIImage*) img {

    //can prob. put this in helper file
    //NSString* pListPath = [[NSBundle mainBundle] pathForResource:@"algorithm_settings" ofType:@"plist"];
    //NSDictionary* dict = [[NSDictionary alloc] initWithContentsOfFile:pListPath];
    int numPatchesToAvg = [[NSUserDefaults standardUserDefaults] integerForKey:@"NumPatchesToAverage"]; //[[dict objectForKey:@"NumPatchesToAverage"] integerValue];
    float diagnosticThreshold = [[NSUserDefaults standardUserDefaults] floatForKey:@"DiagnosticThreshold"]; //[[dict objectForKey:@"DiagnosticThreshold"] floatValue];
    
    
    NSDate *start = [NSDate date];
    NSLog(@"Processing image");
    //convert image to OpenCV matrix
    
    cv::Mat converted_img = [self cvMatWithImage:[self grayScaleImage:img]];
    //run the image (C++ algorithm), returning a C++ vector (1D)
    
    //for debugging, get a string to the local bundle documents folder path
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs_dir = [paths objectAtIndex:0];
    
    
    cv::vector<float> resVector = Classifier::runWithImage(converted_img, [docs_dir fileSystemRepresentation]);
    
    converted_img.release();
    
    NSDate *end = [NSDate date];
    NSTimeInterval executionTime = [end timeIntervalSinceDate:start];
    NSLog(@"Execution Time: %f", executionTime);

    //get a new ImageAnalysisResults instance from Core Data
    ImageAnalysisResults* results = (ImageAnalysisResults*)[NSEntityDescription insertNewObjectForEntityForName:@"ImageAnalysisResults" inManagedObjectContext:self.managedObjectContext];
    
    //populate the ROI list based on the returned C++ vector
    for (int i = 0; i< resVector.size(); i+=3)
    {
        ROIs* roi = (ROIs*)[NSEntityDescription insertNewObjectForEntityForName:@"ROIs" inManagedObjectContext:self.managedObjectContext];
        
        roi.score = resVector.at(i);
        roi.y = (int)resVector.at(i+1);
        roi.x = (int)resVector.at(i+2);
        
        [results addImageROIsObject:roi];
    }

    //do the diagnosis
    //sort results
    NSSortDescriptor *sortDescriptor;
    sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"score"
                                                 ascending:NO];
    NSArray *sortDescriptors = [NSArray arrayWithObject:sortDescriptor];
    NSArray *sortedArray;
    sortedArray = [results.imageROIs sortedArrayUsingDescriptors:sortDescriptors];
    
    ROIs* roi;
    
    float topAverage = 0.0;
    
    //average the top N
    for (int i=0;i<numPatchesToAvg;i++)
    {
        if ([sortedArray count]>i) {
            roi = [sortedArray objectAtIndex:i];
            topAverage += roi.score;
        } else {
            topAverage += 0;
        }
    }
    
    results.score = topAverage;
    results.diagnosis = (topAverage>diagnosticThreshold);
    results.dateAnalyzed = [NSDate timeIntervalSinceReferenceDate];
    
    return results;
}

@end