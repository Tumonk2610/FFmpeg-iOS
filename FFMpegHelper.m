//
//  FFMpegHelper.m
//  H264Player
//
//  Created by 刘洪彬 on 2017/11/17.
//  Copyright © 2017年 artwebs. All rights reserved.
//

#import "FFMpegHelper.h"

@implementation FFMpegHelper
@synthesize delegate,outputWidth,outputHeight;
-(id)init{
    self=[super init];
    if (self)
    {
        isStop=YES;
        theLock=[[NSLock alloc]init];
    }

    return self;
}

-(void)dealloc
{
    [self stop];
    free(Buf);
    theLock=nil;
    self.delegate=nil;
}

-(void)playWithFile:(NSString *)file{
    if(!isStop){
        [self releaseFFMPEG];
    }
   
    [self initFFMPEG:file];
    inpf = fopen([file UTF8String],"rb");
    Buf = (unsigned char*)calloc ( 1000000, sizeof(char));
    isStop=false;
    if(timer==nil)
        timer=[NSTimer scheduledTimerWithTimeInterval:1.0/30
                                               target:self
                                             selector:@selector(playSingleFrame:)
                                             userInfo:nil
                                              repeats:YES];
}

-(void)stop{
    isStop=true;
    [timer invalidate];
    timer=nil;
    [self releaseFFMPEG];
}

-(void)initFFMPEG:(NSString *)file{
    // 初始化libavformat库（注册所有的支持格式与编解码器）
    av_register_all ();
    av_init_packet(&packet);
    av_log_set_level (AV_LOG_DEBUG);
    //打开视频文件，获取格式上下文信息，从中找到视频流
    if (avformat_open_input (&pInputFormatCtx,[file UTF8String], NULL, NULL) != 0)
        goto initError;
    if (avformat_find_stream_info (pInputFormatCtx, NULL) < 0)
        goto initError;
    av_dump_format (pInputFormatCtx, 0, [file UTF8String], 0);// 打印文件信息
    videoStream = -1;
    for (uint32_t i = 0; i < pInputFormatCtx->nb_streams; i++)
    {
        if (pInputFormatCtx->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO)
        {
            videoStream = i;
            break;
            //goto initError;
        }
    }
    if (videoStream == -1)
        goto initError;
    // 获得视频流的编解码器上下文指针，根据其中的解码器ID寻找解码器

    pInputCodecCtx = pInputFormatCtx->streams[videoStream]->codec;
    pDecoderCodec = avcodec_find_decoder (pInputCodecCtx->codec_id);
    if (pDecoderCodec == NULL)
    {
        fprintf (stderr, "Unsupported codec!\n");
        goto initError;
    }

    // 根据找到的解码器分配上下文,copy输入流的编解码器上下文，并据此初始化解码器
    pDecoderCodecCtx = avcodec_alloc_context3 (pDecoderCodec);
    if (avcodec_copy_context (pDecoderCodecCtx, pInputCodecCtx) != 0)
    {
        fprintf (stderr, "Couldn't copy codec context");
        goto initError;
    }
    if (avcodec_open2 (pDecoderCodecCtx, pDecoderCodec, NULL) < 0)
    {
        fprintf (stderr, "Couldn't init decode codeccontext to use avcodec");
        goto initError;
    }
    // 为视频帧分配内存
    AVFrame *pRawFrame = av_frame_alloc ();
    if (0 == pRawFrame)
        goto initError;
//    [self playNextFrame];
    return;
    // 提取开头的关键帧，编码后存文件
initError : {
    NSLog(@"init failed");
}


}

-(void)releaseFFMPEG{
    av_frame_free (&pRawFrame);
    avcodec_close (pDecoderCodecCtx);
    avcodec_close (pInputCodecCtx);
    avformat_close_input (&pInputFormatCtx);
}


-(void)playSingleFrame:(NSTimer *)timer
{
    [self playStepFrame];
}

-(void)playStepFrame
{
    int nallen;
    nallen=[self getNextNal:Buf];
    pRawFrame = av_frame_alloc ();
    if(nallen>0&&!isStop)
        if([self decodeH264:Buf length:nallen]>0)
            if (pRawFrame->data[0]) {
                [self convertFrameToRGB];
                if ([self.delegate respondsToSelector:@selector(imageCallBack:)]) {
                    [self.delegate imageCallBack:[self imageWithSet]];
                }
            }
    av_frame_free (&pRawFrame);
}

-(int)getNextNal:(unsigned char*)Buf
{
    int pos = 0;
    int StartCodeFound = 0;
    int info2 = 0;
    int info3 = 0;

    while(!feof(inpf) && (Buf[pos++]=fgetc(inpf))==0);

    while (!StartCodeFound)
    {
        if (feof (inpf))
        {
            //            return -1;
            [timer invalidate];
            timer=nil;
            if ([delegate respondsToSelector:@selector(playEndCallBack)]) {
                [delegate playEndCallBack];
            }
            return pos-1;
        }
        Buf[pos++] = fgetc (inpf);
        info3=[self FindStartCode:&Buf[pos-4] :3];
        if(info3 != 1)
            info2=[self FindStartCode:&Buf[pos-3] :2];
        StartCodeFound = (info2 == 1 || info3 == 1);
    }
    fseek (inpf, -4, SEEK_CUR);
    return pos - 4;
}


-(int)decodeH264: (unsigned char*) buf length:(int)len
{
    packet.size = len;
    packet.data = (unsigned char *)buf;
    int got_picture_ptr=0;
    int nImageSize;
    nImageSize = avcodec_decode_video2(pDecoderCodecCtx,pRawFrame,&got_picture_ptr,&packet);

    return nImageSize;
}

-(int)FindStartCode:(unsigned char *)Buf :(int)zeros_in_startcode
{
    int info;
    int i;

    info = 1;
    for (i = 0; i < zeros_in_startcode; i++)
        if(Buf[i] != 0)
            info = 0;

    if(Buf[i] != 1)
        info = 0;
    return info;
}



-(void)setupScaler {
    // Release old picture and scaler
    avpicture_free(&picture);
    sws_freeContext(img_convert_ctx);

    // Allocate RGB picture
    avpicture_alloc(&picture, AV_PIX_FMT_RGB24, outputWidth, outputHeight);

    // Setup scaler
    static int sws_flags =  SWS_FAST_BILINEAR;
    img_convert_ctx = sws_getContext(pDecoderCodecCtx->width,
                                     pDecoderCodecCtx->height,
                                     pDecoderCodecCtx->pix_fmt,
                                     outputWidth,
                                     outputHeight,
                                     AV_PIX_FMT_RGB24,
                                     sws_flags, NULL, NULL, NULL);


}

-(void)convertFrameToRGB
{
    [self setupScaler];
    sws_scale (img_convert_ctx,pRawFrame->data, pRawFrame->linesize,
               0, pDecoderCodecCtx->height,
               picture.data, picture.linesize);
}

-(UIImage *)imageWithSet {
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, picture.data[0], picture.linesize[0]*outputHeight,kCFAllocatorNull);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    CGImageRef cgImage = CGImageCreate(outputWidth,
                                       outputHeight,
                                       8,
                                       24,
                                       picture.linesize[0],
                                       colorSpace,
                                       bitmapInfo,
                                       provider,
                                       NULL,
                                       YES,
                                       kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    //UIImage *image = [UIImage imageWithCGImage:cgImage];
    UIImage* image = [[UIImage alloc]initWithCGImage:cgImage];   //crespo modify 20111020
    CGImageRelease(cgImage);
    CGDataProviderRelease(provider);
    CFRelease(data);

    return image;

}



@end
