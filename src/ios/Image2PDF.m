/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "Image2PDF.h"

@interface Image2PDF ()
@end


@implementation Image2PDF

- (instancetype)init
{
	self = [super init];
	if (self) {
		[self pluginInitialize];
	}
	
	return self;
}

- (void)pluginInitialize
{
	// Nothing to do here...
}


//------------------------
#pragma mark -
#pragma mark API Methods

#pragma clang diagnostic push
#pragma ide diagnostic ignored "OCUnusedMethodInspection"

/**
 *	Converts the image at the given file path to a PDF file.
 *
 *  Parameter: [0] source image file path (String); if relative then "<appBundle>/www" is prepended
 *  Parameter: [1] target PDF file path (String); if relative then "~/tmp" is prepended
 *
 *  Returns (through Callback): OK: -, ERROR: Error Code (Int)
 */
- (void)convert:(CDVInvokedUrlCommand *)command
{
	NSString *imageFilePath = command.arguments[0];
	NSString *pdfFilePath = command.arguments[1];

	__weak Image2PDF *weakSelf = self;
	[self.commandDelegate runInBackground:^{
		CDVPluginResult *pluginResult;
		UIImage *image = [Image2PDF loadImageAtPath:imageFilePath];
		Image2PDFError errorCode = [Image2PDF saveImage:image toPDFFile:pdfFilePath];
		
		if (errorCode == NO_ERROR) {
			pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
		} else {
			pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
												messageAsInt:errorCode];
		}
		
		[weakSelf.commandDelegate sendPluginResult:pluginResult
										callbackId:command.callbackId];
	}];
}

/**
 *	Converts the image array, containing file paths, to a PDF file.
 *
 *  Parameter: [0] source image file path (String); if relative then "<appBundle>/www" is prepended
 *  Parameter: [1] target PDF file path (String); if relative then "~/tmp" is prepended
 *
 *  Returns (through Callback): OK: -, ERROR: Error Code (Int)
 */
- (void)convertArray:(CDVInvokedUrlCommand *)command
{
    NSArray *imageFilesPaths = command.arguments[0];
    NSString *pdfFilePath = command.arguments[1];
    
    __weak Image2PDF *weakSelf = self;
    [self.commandDelegate runInBackground:^{
        CDVPluginResult *pluginResult;
        
        Image2PDFError errorCode = [Image2PDF saveImagesArray:imageFilesPaths toPDFFile:pdfFilePath];
        
        if (errorCode == NO_ERROR) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                messageAsInt:errorCode];
        }
        
        [weakSelf.commandDelegate sendPluginResult:pluginResult
                                        callbackId:command.callbackId];
    }];
}

/**
 Loads the given file as an UIImage.
 @param path the file path, either relative to www/ or absolute ("/...")
 @return the UIImage, or nil if file cannot be loaded
 */
+ (UIImage*)loadImageAtPath:(NSString *)path
{
	path = [self _expandSourcePath:path];
	return (path != nil) ? [UIImage imageWithContentsOfFile:path] : nil;
}

+ (Image2PDFError) saveImage: (UIImage *) image toPDFFile: (NSString *) filePath
{
	if (image == nil)
		return FILE_NOT_FOUND_ERR;
	
	filePath = [self _expandTargetPath:filePath];
	CGRect theBounds = (CGRect){.size=image.size};
	if (UIGraphicsBeginPDFContextToFile(filePath, theBounds, nil)) {
		{
			UIGraphicsBeginPDFPage();
			[image drawInRect:theBounds];
		}
		UIGraphicsEndPDFContext();
		
		return [self _checkExistingFile:filePath] ? NO_ERROR : PDF_WRITE_ERR;
	}
	else
		return PDF_WRITE_ERR;
}

+ (Image2PDFError) saveImagesArray: (NSArray *) images toPDFFile: (NSString *) filePath
{
    if (images == nil)
        return FILE_NOT_FOUND_ERR;
    
    filePath = [self _expandTargetPath:filePath];
    if (UIGraphicsBeginPDFContextToFile(filePath, CGRectZero, nil)) {
        {
            UIImage *image = nil;
            for (int i = 0; i < [images count]; i = i + 1) {
                @autoreleasepool {
                    image = [Image2PDF loadImageAtPath:images[i]];
                    image = [Image2PDF imageWithImage:image scaledToScale: 1];
                    UIGraphicsBeginPDFPageWithInfo(CGRectMake(0, 0, image.size.width * 0.5, image.size.height * 0.5), nil);
                    [image drawInRect:CGRectMake(0, 0, image.size.width * 0.5, image.size.height * 0.5)];
                    image = nil;
                }
            }
            
        }
        UIGraphicsEndPDFContext();
        
        return [self _checkExistingFile:filePath] ? NO_ERROR : PDF_WRITE_ERR;
    }
    else
        return PDF_WRITE_ERR;
}

#pragma mark File support

+ (NSString*)_expandSourcePath:(NSString *)path
{
	if (path) {
		path = [path stringByExpandingTildeInPath];
		if (![path isAbsolutePath]) {
			path = [[[[NSBundle mainBundle] resourcePath]
					 stringByAppendingPathComponent:@"www"]
					stringByAppendingPathComponent:path];
		}
		return path;
	}
	return nil;
}

+ (NSString*)_expandTargetPath:(NSString *)path
{
	if (path) {
		path = [path stringByExpandingTildeInPath];
		if (![path isAbsolutePath]) {
			path = [[@"~/tmp" stringByExpandingTildeInPath]
					stringByAppendingPathComponent:path];
		}
		return path;
	}
	return nil;
}

// check if file exists
+ (BOOL)_checkExistingFile:(NSString *)filePath
{
	NSFileManager *fileMgr = [NSFileManager defaultManager];
	BOOL bExists = [fileMgr fileExistsAtPath:filePath];
	if (bExists) {
		NSError *__autoreleasing error = nil;
		NSDictionary *fileAttrs = [fileMgr attributesOfItemAtPath:filePath error:&error];
		NSNumber *fileSizeNumber = [fileAttrs objectForKey:NSFileSize];
		long long fileSize = [fileSizeNumber longLongValue];
		return (fileSize > 0);
	}
	else {
		return FALSE;
	}
}

#pragma mark Test support

+ (void) convertTestImage {
	NSString *destination = [NSHomeDirectory() stringByAppendingString:@"/tmp/test.pdf"];
	if ([[NSFileManager defaultManager] fileExistsAtPath:destination])
		[[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
	Image2PDFError errorCode = [self saveImage:[self loadTestImage] toPDFFile:destination];
	NSLog(@"errorCode: %d", errorCode);
}

+ (UIImage*) loadTestImage {
	return [self loadImageAtPath:@"test.jpg"]; //[UIImage imageNamed:@"test.jpg"];
}

+ (UIImage *)imageWithImage:(UIImage *)image scaledToScale:(CGFloat)scale
{
    UIGraphicsBeginImageContextWithOptions(image.size, YES, scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

@end
