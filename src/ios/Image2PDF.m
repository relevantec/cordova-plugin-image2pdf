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

static int currentImageWidth = 0;
static int currentImageHeight = 0;
static int currentImageTopMargin = 0;
static int currentImageBottomMargin = 0;

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

	@autoreleasepool {
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
    NSDictionary* options = [command.arguments objectAtIndex:2];

	@autoreleasepool {
	    __weak Image2PDF *weakSelf = self;
	    [self.commandDelegate runInBackground:^{
	        CDVPluginResult *pluginResult;

	        Image2PDFError errorCode = [Image2PDF saveImagesArray:imageFilesPaths toPDFFile:pdfFilePath options: options];

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

+ (void) drowTextLayer: (NSString *) text
              position: (NSString *) position
            alignement: (NSTextAlignment) alignement
                 color: (NSString *) color
{
    if (!text) { return; }

    @autoreleasepool {
        NSMutableParagraphStyle *textStyle = [[NSMutableParagraphStyle defaultParagraphStyle] mutableCopy];
        NSString *fixedText = text;
        textStyle.lineBreakMode = NSLineBreakByWordWrapping;
        textStyle.alignment = alignement;
        int textWidth = currentImageWidth - 10;

        if (alignement == NSTextAlignmentRight) {
            fixedText = [[NSArray arrayWithObjects:text, @" .", nil] componentsJoinedByString:@" "];
        }
        if (alignement == NSTextAlignmentLeft) {
            textWidth = currentImageWidth - 100; //leave some space for the date
        }

        UIImage *imageLayer = [Image2PDF imageFromString:fixedText
                                              attributes:@{NSFontAttributeName            : [UIFont systemFontOfSize:12],
                                                           NSParagraphStyleAttributeName  : textStyle,
                                                           NSForegroundColorAttributeName : [Image2PDF colorFromHexString:color],
                                                           NSBackgroundColorAttributeName : [UIColor clearColor]}
                                                    size:CGSizeMake(textWidth, currentImageTopMargin)];

        float startY = 0;
        if ([position isEqual: @"line2"]) { startY = 24; }
        if ([position isEqual: @"bottom"]) { startY = currentImageHeight + currentImageTopMargin; }

        [imageLayer drawInRect:CGRectMake(0, startY, imageLayer.size.width, imageLayer.size.height)];
        imageLayer = nil;
    }
}

+ (Image2PDFError) saveImagesArray: (NSArray *) images toPDFFile: (NSString *) filePath options: (NSDictionary *) options
{
    if (images == nil)
        return FILE_NOT_FOUND_ERR;

    filePath = [self _expandTargetPath:filePath];
    if (UIGraphicsBeginPDFContextToFile(filePath, CGRectZero, nil)) {
        {
            UIImage *image = nil;
            NSString* imageUri = nil;
            NSString* imagePage = nil;

            NSString* topLeft = [options objectForKey:@"topLeft"];
            NSString* topRight = [options objectForKey:@"topRight"];
            NSString* topLine2 = [options objectForKey:@"topLine2"];
            NSString* bottomLeft = [options objectForKey:@"bottomLeft"];
            NSString* bottomRight = [options objectForKey:@"bottomRight"];
            NSString* exportQuality = [options objectForKey:@"exportQuality"];

            NSString* bottomRightTr = nil;
            NSString* topLine2Tr = nil;

			//low quality
			float imageScale = 0.625;
			float imageNormalizedScale = 0.8;
			if (exportQuality == @"medium") {
				imageScale = 0.8;
				imageNormalizedScale = 0.625;
			}
			else if (exportQuality == @"high") {
				imageScale = 1;
				imageNormalizedScale = 0.5;
			}

            currentImageTopMargin = [[options objectForKey:@"topMargin"] floatValue];
            currentImageBottomMargin = [[options objectForKey:@"bottomMargin"] floatValue];

            for (int i = 0; i < [images count]; i = i + 1) {
                @autoreleasepool {
                    imageUri = [images[i] objectForKey:@"uri"];
                    imagePage = [images[i] objectForKey:@"pageNum"];

                    bottomRightTr = [bottomRight stringByReplacingOccurrencesOfString:@"{{item_num}}"
                        withString:[NSString stringWithFormat:@"%i", i+1]
                    ];
                    bottomRightTr = [bottomRightTr stringByReplacingOccurrencesOfString:@"{{item_count}}"
                        withString:[NSString stringWithFormat:@"%lu", [images count]]
                    ];
                    topLine2Tr = [topLine2 stringByReplacingOccurrencesOfString:@"{{page_num}}"
                        withString:[NSString stringWithFormat:@"%@", imagePage]
                    ];

                    image = [Image2PDF loadImageAtPath:imageUri];
                    image = [Image2PDF imageWithImage:image scaledToScale: imageScale];
                    currentImageWidth = image.size.width * imageNormalizedScale;
                    currentImageHeight = image.size.height * imageNormalizedScale;

                    UIGraphicsBeginPDFPageWithInfo(CGRectMake(0, 0, currentImageWidth,
                        currentImageHeight + currentImageTopMargin + currentImageBottomMargin), nil);
                    [image drawInRect:CGRectMake(0, currentImageTopMargin, currentImageWidth, currentImageHeight)];

                    [Image2PDF drowTextLayer: topLeft position: @"top" alignement: NSTextAlignmentLeft color: @"#575759"];
                    [Image2PDF drowTextLayer: topRight position: @"top" alignement: NSTextAlignmentRight color: @"#575759"];
                    [Image2PDF drowTextLayer: topLine2Tr position: @"line2" alignement: NSTextAlignmentLeft color: @"#000000"];
                    [Image2PDF drowTextLayer: bottomLeft position: @"bottom" alignement: NSTextAlignmentLeft color: @"#575759"];
                    [Image2PDF drowTextLayer: bottomRightTr position: @"bottom" alignement: NSTextAlignmentRight color: @"#575759"];

                    image = nil;
                    imageUri = nil;
                    bottomRightTr = nil;
                    topLine2Tr = nil;
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

+ (UIImage *)imageFromString:(NSString *)string attributes:(NSDictionary *)attributes size:(CGSize)size
{
    @autoreleasepool {
        UIGraphicsBeginImageContextWithOptions(size, NO, 0);
        [string drawInRect:CGRectMake(10, 10, size.width, size.height) withAttributes:attributes];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        return image;
    }
}

// Assumes input like "#00FF00" (#RRGGBB).
+ (UIColor *)colorFromHexString:(NSString *)hexString {
    @autoreleasepool {
        unsigned rgbValue = 0;
        NSScanner *scanner = [NSScanner scannerWithString:hexString];
        [scanner setScanLocation:1]; // bypass '#' character
        [scanner scanHexInt:&rgbValue];
        return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:1.0];
    }
}

@end
