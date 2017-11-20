//
// FFMpegHelper.h
//  H264Player
//
//  Created by 刘洪彬 on 2017/11/17.
//  Copyright © 2017年 artwebs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "libavformat/avformat.h"
#import "libswscale/swscale.h"
#import "libavcodec/avcodec.h"
@protocol FFMpegHelperCallBack;
@interface FFMpegHelper : NSObject
{
    AVFormatContext   *pInputFormatCtx;
    AVCodecContext *pInputCodecCtx;
    AVCodec *pDecoderCodec;
    AVCodecContext *pDecoderCodecCtx;
    AVFrame *pRawFrame;
    int videoStream;
    AVPicture          picture;
    AVPacket           packet;
    struct SwsContext  *img_convert_ctx;

    NSTimer *timer;
    FILE * inpf;
    unsigned char* Buf;
    Boolean isStop;
    NSLock *theLock;

    int outputWidth, outputHeight;
}
@property (retain) id<FFMpegHelperCallBack> delegate;
@property (assign,nonatomic) int outputWidth;
@property (assign,nonatomic) int outputHeight;
-(void)playWithFile:(NSString *)file;
-(void)stop;

@end

@protocol FFMpegHelperCallBack <NSObject>
-(void)imageCallBack:(UIImage *)image;
-(void)playEndCallBack;
@end
