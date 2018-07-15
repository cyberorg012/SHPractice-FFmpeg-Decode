//
//  ViewController.m
//  SHPractice-FFmpeg-Decode
//
//  Created by Shine on 14/04/2018.
//  Copyright © 2018 shine. All rights reserved.
//

#import "ViewController.h"


extern "C"
{
//解码需要引入的头文件
#import "avformat.h"
#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libswscale/swscale.h>
#import <libavutil/imgutils.h>
#import "SDL.h"
}

#define isOutputYUV420 0    //是否输出yuv420文件
#define SFM_REFRESH_EVENT (SDL_USEREVENT + 1)
#define SFM_BREAK_EVENT  (SDL_USEREVENT + 2)


int thread_exit=0;
int thread_pause=0;

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSString *file = [[NSBundle mainBundle] pathForResource:@"download" ofType:@"mp4"];
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *outFile = [docPath stringByAppendingPathComponent:@"test.yuv"];

    [self ffpmegDecodeVideoInPath:file outPath:outFile];
    
}


//int SDL_UpdateTexture(void *opaque){
//    thread_exit=0;
//    thread_pause=0;
//
//    while (!thread_exit) {
//        if(!thread_pause){
//            SDL_Event event;
//            event.type = SFM_REFRESH_EVENT;
//            SDL_PushEvent(&event);
//        }
//        SDL_Delay(40);
//    }
//    thread_exit=0;
//    thread_pause=0;
//    //Break
//    SDL_Event event;
//    event.type = SFM_BREAK_EVENT;
//    SDL_PushEvent(&event);
//
//    return 0;
//}

- (void)ffpmegDecodeVideoInPath:(NSString *)inPath outPath:(NSString *)outPath{
    
    /*解码步骤
     1.注册组件(av_register_all());
     2.打开封装格式。也就是打开文件。
     3.查找视频流(视频中包含视频流,音频流，字幕流)
     4.查找解码器
     5.打开解码器
     6.循环每一帧，去解码
     7.解码完成，关闭资源
     
     */
    
    int operationResult = 0;
    
    //第一步:注册组件
    av_register_all();
    
    
    //第二步:打开文件
    AVFormatContext *avformat_context = avformat_alloc_context();
    const char *url = [inPath UTF8String];
    operationResult = avformat_open_input(&avformat_context, url, NULL, NULL);   //avformatcontext传的是二级指针（可以复习下二级指针的知识)
    if(operationResult != 0){
        //        av_log(NULL, 1, "打开文件失败");
        NSLog(@"打开文件失败");
        return;
    }
    
    av_dump_format(avformat_context, 0, url, 0);
    
    //第三步:查找视频流
     operationResult = avformat_find_stream_info(avformat_context, NULL);
    if(operationResult != 0){
//        av_log(NULL, 1, "查找视频流失败");
        NSLog(@"查找视频流失败");
        return;
    }
    
    /* 第四步:查找解码器
       * 查找视频流的index
       * 根据视频流的index获取到avCodecContext
       * 根据avCodecContext获取解码器
     */
    
    int videoStremIndex = -1;
    for(int i = 0 ; i < avformat_context->nb_streams; i++){
        if(avformat_context -> streams[i] ->codec -> codec_type == AVMEDIA_TYPE_VIDEO){
            videoStremIndex = i;   //拿到视频流的index
            NSLog(@"获取到了视频流");
            break;
        }
    }
    
    AVCodecContext *avcodec_context = avformat_context -> streams[videoStremIndex] -> codec;    //根据视频流的index拿到解码器上下文
    AVCodec *decodeCodec = avcodec_find_decoder(avcodec_context -> codec_id);   //根据解码器上下文拿到解码器id ,然后得到解码器
    
    NSLog(@"解码器为%s",decodeCodec -> name);
    //第五步:打开解码器
    operationResult = avcodec_open2(avcodec_context, decodeCodec, NULL);
    if(operationResult != 0){
        //        av_log(NULL, 1, "打开解码器失败");
        NSLog(@"打开解码器失败");
        return;
    }
    
    //第六步:开始解码
    AVPacket *packet = (AVPacket *)av_malloc(sizeof(AVPacket));   //读取的一帧数据缓存区
    AVFrame *avframe_in = av_frame_alloc();
    
    
    //开辟转换格式yuv420需要的空间
    AVFrame *avframe_yuv420 = av_frame_alloc();
    int bufferSize = av_image_get_buffer_size(AV_PIX_FMT_YUV420P, avcodec_context -> width, avcodec_context -> height, 1);
    uint8_t *data = (uint8_t *)av_malloc(bufferSize);
    av_image_fill_arrays(avframe_yuv420 -> data,
                         avframe_yuv420 -> linesize,
                         data, AV_PIX_FMT_YUV420P,
                         avcodec_context -> width,
                         avcodec_context -> height,
                         1);
    
    
    //拿到格式转换上下文
    SwsContext *sws_context = sws_getContext(avcodec_context -> width,
                                             avcodec_context -> height,
                                             avcodec_context -> pix_fmt,
                                             avcodec_context -> width,
                                             avcodec_context -> height,
                                             AV_PIX_FMT_YUV420P,
                                             SWS_BICUBIC,
                                             NULL,
                                             NULL,
                                             NULL);
    
    int y_size,u_size,v_size;
    long decodeIndex = 0;
    const char *outpath = [outPath UTF8String];
    FILE *yuv420p_file = fopen(outpath, "wb+");
    
    //初始化SDL
    SDL_SetMainReady();
    if(SDL_Init(SDL_INIT_EVERYTHING < 0)){
        NSLog(@"SDL init error -------- %s",SDL_GetError());
    }
    
    int screen_width = avcodec_context -> width;
    int screen_height = avcodec_context -> height;
    
    //创建窗口
    SDL_Window *window = SDL_CreateWindow("iOSSimplePlayer", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, screen_width, screen_height, SDL_WINDOW_FULLSCREEN | SDL_WINDOW_OPENGL);
    
    
    if(!window){
        printf("SDL 创建window 失败 %s",SDL_GetError());
    }
    
    SDL_Renderer *render = SDL_CreateRenderer(window, -1, 0);
    SDL_Texture *texture = SDL_CreateTexture(render, SDL_PIXELFORMAT_IYUV, SDL_TEXTUREACCESS_STREAMING, screen_width, screen_height);
    
    SDL_Rect rect;
    rect.x = 0;
    rect.y = 0;
    rect.w = screen_width;
    rect.h = screen_height;
    
                
    while (av_read_frame(avformat_context, packet) == 0) {
        if(packet -> stream_index == videoStremIndex){  //如果是视频流
            avcodec_send_packet(avcodec_context, packet);
            operationResult = avcodec_receive_frame(avcodec_context, avframe_in);
            if(operationResult == 0){   //解码成功
                
                //进行类型转换:将解码出来的原像素数据转成我们需要的yuv420格式
                sws_scale(sws_context, avframe_in -> data, avframe_in ->linesize, 0, avcodec_context -> height, avframe_yuv420 -> data, avframe_yuv420 -> linesize);
                
#if isOutputYUV420
                //格式已经转换完成，写入yuv420p文件到本地.
                //  YUV: Y代表亮度,UV代表色度
                // YUV420格式知识: 一个Y代表一个像素点,4个像素点对应一个U和V.  4*Y = U = V
                y_size = avcodec_context -> width * avcodec_context -> height;
                u_size = y_size / 4;
                v_size = y_size / 4;
                
                //依次写入Y、U、V部分
                fwrite(avframe_yuv420 -> data[0], 1, y_size, yuv420p_file);
                fwrite(avframe_yuv420 -> data[1], 1, u_size, yuv420p_file);
                fwrite(avframe_yuv420 -> data[2], 1, v_size, yuv420p_file);
#endif
                
                SDL_UpdateTexture(texture, &rect, avframe_yuv420 -> data[0], avframe_yuv420 -> linesize[0]);
                SDL_UpdateYUVTexture(texture, &rect, avframe_yuv420 -> data[0], avframe_yuv420 -> linesize[0], avframe_yuv420 -> data[1], avframe_yuv420 -> linesize[1], avframe_yuv420 -> data[2], avframe_yuv420 -> linesize [2]);

                SDL_RenderClear(render);
                SDL_RenderCopy(render, texture, &rect, &rect);
                SDL_RenderPresent(render);
                SDL_Delay(40);
                
                
                
                decodeIndex++;
                //                av_log(NULL, 1, "解码到第%ld帧了",decodeIndex);
                NSLog(@"解码到第%ld帧了",decodeIndex);
            }
        }
    }
    
    //第七步:关闭资源
    av_packet_free(&packet);
    fclose(yuv420p_file);
    av_frame_free(&avframe_in);
    av_frame_free(&avframe_yuv420);
    free(data);
    avcodec_close(avcodec_context);
    avformat_free_context(avformat_context);
    SDL_Quit();
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


@end
