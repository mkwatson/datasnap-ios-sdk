//
//  GZip.m
//  datasnap-ios-sdk
//
//  Created by Alyssa McIntyre on 6/22/16.
//  Copyright © 2016 DataSnap. All rights reserved.
//

#import "GZip.h"

@implementation GZip

+ (NSData*)gzipData:(NSData*)pUncompressedData
{
    if (!pUncompressedData || [pUncompressedData length] == 0) {
        NSLog(@"%s: Error: Can't compress an empty or null NSData object.", __func__);
        return nil;
    }
    z_stream zlibStreamStruct;
    zlibStreamStruct.zalloc = Z_NULL;
    zlibStreamStruct.zfree = Z_NULL;
    zlibStreamStruct.opaque = Z_NULL;
    zlibStreamStruct.total_out = 0;
    zlibStreamStruct.next_in = (Bytef*)[pUncompressedData bytes];
    zlibStreamStruct.avail_in = (uint)[pUncompressedData length];

    int initError = deflateInit2(&zlibStreamStruct, Z_DEFAULT_COMPRESSION, Z_DEFLATED, (15 + 16), 8, Z_DEFAULT_STRATEGY);
    if (initError != Z_OK) {
        NSString* errorMsg = nil;
        switch (initError) {
        case Z_STREAM_ERROR:
            errorMsg = @"Invalid parameter passed in to function.";
            break;
        case Z_MEM_ERROR:
            errorMsg = @"Insufficient memory.";
            break;
        case Z_VERSION_ERROR:
            errorMsg = @"The version of zlib.h and the version of the library linked do not match.";
            break;
        default:
            errorMsg = @"Unknown error code.";
            break;
        }
        NSLog(@"%s: deflateInit2() Error: \"%@\" Message: \"%s\"", __func__, errorMsg, zlibStreamStruct.msg);
        return nil;
    }
    NSMutableData* compressedData = [NSMutableData dataWithLength:[pUncompressedData length] * 1.01 + 12];

    int deflateStatus;
    do {
        zlibStreamStruct.next_out = [compressedData mutableBytes] + zlibStreamStruct.total_out;
        zlibStreamStruct.avail_out = (uint)[compressedData length] - (uint)zlibStreamStruct.total_out;
        deflateStatus = deflate(&zlibStreamStruct, Z_FINISH);
    } while (deflateStatus == Z_OK);

    if (deflateStatus != Z_STREAM_END) {
        NSString* errorMsg = nil;
        switch (deflateStatus) {
        case Z_ERRNO:
            errorMsg = @"Error occured while reading file.";
            break;
        case Z_STREAM_ERROR:
            errorMsg = @"The stream state was inconsistent (e.g., next_in or next_out was NULL).";
            break;
        case Z_DATA_ERROR:
            errorMsg = @"The deflate data was invalid or incomplete.";
            break;
        case Z_MEM_ERROR:
            errorMsg = @"Memory could not be allocated for processing.";
            break;
        case Z_BUF_ERROR:
            errorMsg = @"Ran out of output buffer for writing compressed bytes.";
            break;
        case Z_VERSION_ERROR:
            errorMsg = @"The version of zlib.h and the version of the library linked do not match.";
            break;
        default:
            errorMsg = @"Unknown error code.";
            break;
        }
        NSLog(@"%s: zlib error while attempting compression: \"%@\" Message: \"%s\"", __func__, errorMsg, zlibStreamStruct.msg);
        deflateEnd(&zlibStreamStruct);
        return nil;
    }
    deflateEnd(&zlibStreamStruct);
    [compressedData setLength:zlibStreamStruct.total_out];
    return compressedData;
}

@end