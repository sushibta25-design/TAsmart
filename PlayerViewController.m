#import "PlayerViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreImage/CoreImage.h>
#import <sys/socket.h>
#import <netinet/tcp.h>
#import <arpa/inet.h>
#import <unistd.h>

@interface PlayerViewController ()
@property(nonatomic,strong) CALayer *display;
@property(nonatomic,strong) UILabel *latencyLabel;
@property(nonatomic,strong) CIContext *ciContext;
@property(nonatomic,strong) dispatch_queue_t renderQ;
@property(nonatomic) VTDecompressionSessionRef decoder;
@property(nonatomic) BOOL renderBusy;
@property(nonatomic) NSUInteger shownFrames;
@property(nonatomic) NSUInteger droppedFrames;
@property(nonatomic) CFTimeInterval fpsEpoch;
@property(nonatomic) double latencyEMA;
@property(nonatomic,strong) dispatch_queue_t netQ;
@property(nonatomic,strong) NSMutableData *fu;
@property(nonatomic,strong) NSData *sps;
@property(nonatomic,strong) NSData *pps;
@property(nonatomic) CMVideoFormatDescriptionRef format;
@property(nonatomic) BOOL stopping;
@end

@implementation PlayerViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.blackColor;
    self.display=[CALayer layer];
    self.display.contentsGravity=kCAGravityResizeAspectFill;
    self.display.masksToBounds=YES;
    self.display.backgroundColor=UIColor.blackColor.CGColor;
    self.display.actions=@{@"bounds":[NSNull null],@"position":[NSNull null],@"frame":[NSNull null],@"contents":[NSNull null]};
    [self.view.layer addSublayer:self.display];
    self.latencyLabel=[[UILabel alloc] initWithFrame:CGRectZero];
    self.latencyLabel.backgroundColor=[UIColor colorWithWhite:0 alpha:.55];
    self.latencyLabel.textColor=UIColor.whiteColor;
    self.latencyLabel.font=[UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
    self.latencyLabel.textAlignment=NSTextAlignmentCenter;
    self.latencyLabel.layer.cornerRadius=6; self.latencyLabel.clipsToBounds=YES;
    self.latencyLabel.text=@"A510 -- ms";
    [self.view addSubview:self.latencyLabel];
    self.ciContext=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO}];
    self.renderQ=dispatch_queue_create("tasmart.a510.latest.render",DISPATCH_QUEUE_SERIAL);
    self.fpsEpoch=CACurrentMediaTime();
    self.netQ=dispatch_queue_create("a510.rtsp.lowlatency",DISPATCH_QUEUE_SERIAL);
    dispatch_async(self.netQ, ^{ [self runRTSPLoop]; });
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.display.frame=self.view.bounds;
    [CATransaction commit];
    UIEdgeInsets insets=self.view.safeAreaInsets;
    self.latencyLabel.frame=CGRectMake(10+insets.left,8+insets.top,190,28);
}
static BOOL sendAll(int fd,NSData*d){const uint8_t*p=d.bytes;size_t n=d.length;while(n){ssize_t x=send(fd,p,n,MSG_NOSIGNAL);if(x<=0)return NO;p+=x;n-=x;}return YES;}
static NSString* header(NSString*r,NSString*n){for(NSString*l in [r componentsSeparatedByString:@"\r\n"])if([l rangeOfString:[n stringByAppendingString:@":"] options:NSCaseInsensitiveSearch].location==0)return [[l substringFromIndex:n.length+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];return nil;}
static NSString* req(NSString*m,NSString*u,int c,NSString*x){return [NSString stringWithFormat:@"%@ %@ RTSP/1.0\r\nCSeq: %d\r\nUser-Agent: 70mai/A510Player\r\n%@\r\n",m,u,c,x?:@""];}
- (NSString*)readRTSP:(int)fd carry:(NSMutableData*)carry {
    for(;;){const uint8_t*b=carry.bytes;NSUInteger n=carry.length;for(NSUInteger i=3;i<n;i++)if(b[i-3]=='\r'&&b[i-2]=='\n'&&b[i-1]=='\r'&&b[i]=='\n'){NSUInteger he=i+1;NSData*hd=[carry subdataWithRange:NSMakeRange(0,he)];NSString*hs=[[NSString alloc]initWithData:hd encoding:NSUTF8StringEncoding];NSInteger cl=0;NSRange rr=[hs rangeOfString:@"Content-Length:" options:NSCaseInsensitiveSearch];if(rr.location!=NSNotFound)cl=[[[[hs substringFromIndex:NSMaxRange(rr)] componentsSeparatedByString:@"\r\n"] firstObject] integerValue];NSUInteger total=he+MAX(cl,0);if(carry.length>=total){NSData*a=[carry subdataWithRange:NSMakeRange(0,total)];[carry replaceBytesInRange:NSMakeRange(0,total) withBytes:NULL length:0];return [[NSString alloc]initWithData:a encoding:NSUTF8StringEncoding];}}uint8_t t[16384];ssize_t g=recv(fd,t,sizeof(t),0);if(g<=0)return nil;[carry appendBytes:t length:g];}
}
static void TAVTOutput(void *refCon, void *frameRefCon, OSStatus status, VTDecodeInfoFlags flags,
                       CVImageBufferRef imageBuffer, CMTime pts, CMTime duration) {
    PlayerViewController *self=(__bridge PlayerViewController *)refCon;
    CFTimeInterval *stamp=(CFTimeInterval *)frameRefCon;
    CFTimeInterval received=stamp?*stamp:CACurrentMediaTime();
    if(stamp) free(stamp);
    if(status!=noErr || !imageBuffer || !self) return;
    if(self.renderBusy){ self.droppedFrames++; return; }
    self.renderBusy=YES;
    CVPixelBufferRetain((CVPixelBufferRef)imageBuffer);
    dispatch_async(self.renderQ,^{
        @autoreleasepool {
            CIImage *ci=[CIImage imageWithCVPixelBuffer:(CVPixelBufferRef)imageBuffer];
            CGImageRef cg=[self.ciContext createCGImage:ci fromRect:ci.extent];
            CVPixelBufferRelease((CVPixelBufferRef)imageBuffer);
            dispatch_async(dispatch_get_main_queue(),^{
                CFTimeInterval now=CACurrentMediaTime();
                double ms=(now-received)*1000.0;
                self.latencyEMA=self.latencyEMA<=0?ms:(self.latencyEMA*.85+ms*.15);
                if(cg){
                    [CATransaction begin]; [CATransaction setDisableActions:YES];
                    self.display.contents=(__bridge id)cg;
                    [CATransaction commit];
                    CGImageRelease(cg);
                    self.shownFrames++;
                }
                CFTimeInterval span=now-self.fpsEpoch;
                if(span>=1.0){
                    double fps=self.shownFrames/span;
                    self.latencyLabel.text=[NSString stringWithFormat:@"A510 %.0fms  %.0ffps  drop %lu",
                                            self.latencyEMA,fps,(unsigned long)self.droppedFrames];
                    self.shownFrames=0; self.droppedFrames=0; self.fpsEpoch=now;
                }
                self.renderBusy=NO;
            });
        }
    });
}
- (void)destroyDecoder {
    if(self.decoder){ VTDecompressionSessionInvalidate(self.decoder); CFRelease(self.decoder); self.decoder=NULL; }
    if(self.format){ CFRelease(self.format); self.format=NULL; }
}
- (void)makeFormatIfPossible {
    if(self.decoder||!self.sps||!self.pps)return;
    const uint8_t*sets[2]={self.sps.bytes,self.pps.bytes}; size_t sizes[2]={self.sps.length,self.pps.length};
    CMVideoFormatDescriptionRef f=NULL;
    if(CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,2,sets,sizes,4,&f)!=noErr)return;
    self.format=f;
    NSDictionary *attrs=@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),
                          (id)kCVPixelBufferIOSurfacePropertiesKey:@{}};
    VTDecompressionOutputCallbackRecord cb={TAVTOutput,(__bridge void*)self};
    if(VTDecompressionSessionCreate(kCFAllocatorDefault,self.format,NULL,(__bridge CFDictionaryRef)attrs,&cb,&_decoder)==noErr){
        VTSessionSetProperty(self.decoder,kVTDecompressionPropertyKey_RealTime,kCFBooleanTrue);
    }
}
- (void)enqueueNAL:(NSData*)nal marker:(BOOL)marker {
    if(!nal.length)return; uint8_t type=((const uint8_t*)nal.bytes)[0]&0x1f;
    if(type==7){self.sps=nal;[self destroyDecoder];[self makeFormatIfPossible];return;}
    if(type==8){self.pps=nal;[self destroyDecoder];[self makeFormatIfPossible];return;}
    if(type!=1&&type!=5)return;
    [self makeFormatIfPossible]; if(!self.decoder||!self.format)return;
    uint32_t L=CFSwapInt32HostToBig((uint32_t)nal.length);
    NSMutableData*d=[NSMutableData dataWithBytes:&L length:4];[d appendData:nal];
    CMBlockBufferRef bb=NULL;CMSampleBufferRef sb=NULL;
    if(CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,NULL,d.length,kCFAllocatorDefault,NULL,0,d.length,0,&bb)!=kCMBlockBufferNoErr)return;
    CMBlockBufferReplaceDataBytes(d.bytes,bb,0,d.length);size_t sz=d.length;
    if(CMSampleBufferCreateReady(kCFAllocatorDefault,bb,self.format,1,0,NULL,1,&sz,&sb)==noErr){
        CFTimeInterval *stamp=malloc(sizeof(CFTimeInterval)); *stamp=CACurrentMediaTime();
        OSStatus st=VTDecompressionSessionDecodeFrame(self.decoder,sb,
            kVTDecodeFrame_EnableAsynchronousDecompression|kVTDecodeFrame_1xRealTimePlayback,stamp,NULL);
        if(st!=noErr)free(stamp);
    }
    if(sb)CFRelease(sb);if(bb)CFRelease(bb);
}
- (void)rtp:(NSData*)pkt {if(pkt.length<13)return;const uint8_t*r=pkt.bytes;NSUInteger cc=r[0]&15,off=12+cc*4;if(r[0]&0x10){if(pkt.length<off+4)return;off+=4+((((NSUInteger)r[off+2]<<8)|r[off+3])*4);}if(off>=pkt.length)return;const uint8_t*p=r+off;NSUInteger n=pkt.length-off;uint8_t type=p[0]&31;if(type>=1&&type<=23){[self enqueueNAL:[NSData dataWithBytes:p length:n] marker:(r[1]&0x80)!=0];return;}if(type==28&&n>=2){BOOL start=p[1]&0x80,end=p[1]&0x40;uint8_t h=(p[0]&0xE0)|(p[1]&0x1F);if(start){self.fu=[NSMutableData dataWithBytes:&h length:1];[self.fu appendBytes:p+2 length:n-2];}else if(self.fu)[self.fu appendBytes:p+2 length:n-2];if(end&&self.fu){NSData*x=[self.fu copy];self.fu=nil;[self enqueueNAL:x marker:(r[1]&0x80)!=0];}}}
- (void)runRTSPOnce {
    int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return;int one=1;setsockopt(fd,IPPROTO_TCP,TCP_NODELAY,&one,sizeof(one));int rcv=64*1024;setsockopt(fd,SOL_SOCKET,SO_RCVBUF,&rcv,sizeof(rcv));struct timeval tv={3,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv));
    struct sockaddr_in a={0};a.sin_family=AF_INET;a.sin_port=htons(554);inet_pton(AF_INET,"192.168.0.1",&a.sin_addr);if(connect(fd,(struct sockaddr*)&a,sizeof(a))){close(fd);return;}tv.tv_sec=0;tv.tv_usec=0;setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv));
    NSMutableData*c=[NSMutableData data];int q=1;NSString*u=@"rtsp://192.168.0.1:554/livestream/12";sendAll(fd,[req(@"OPTIONS",u,q++,@"") dataUsingEncoding:NSUTF8StringEncoding]);if(![self readRTSP:fd carry:c]){close(fd);return;}sendAll(fd,[req(@"DESCRIBE",u,q++,@"Accept: application/sdp\r\n") dataUsingEncoding:NSUTF8StringEncoding]);NSString*d=[self readRTSP:fd carry:c];if(!d){close(fd);return;}NSString*base=header(d,@"Content-Base");if(!base)base=@"rtsp://192.168.0.1/00000000/";NSString*track=[base stringByAppendingString:@"track1"];sendAll(fd,[req(@"SETUP",track,q++,@"Transport: RTP/AVP/TCP;unicast;interleaved=0-1\r\n") dataUsingEncoding:NSUTF8StringEncoding]);NSString*s=[self readRTSP:fd carry:c];NSString*session=header(s,@"Session");if([session containsString:@";"])session=[session componentsSeparatedByString:@";"].firstObject;if(!session){close(fd);return;}NSString*x=[NSString stringWithFormat:@"Session: %@\r\nRange: npt=0.000-\r\n",session];sendAll(fd,[req(@"PLAY",base,q++,x) dataUsingEncoding:NSUTF8StringEncoding]);
    NSMutableData*stream=c;for(;;){while(stream.length>=4){const uint8_t*b=stream.bytes;if(b[0]!='$'){[stream replaceBytesInRange:NSMakeRange(0,1) withBytes:NULL length:0];continue;}uint16_t L=((uint16_t)b[2]<<8)|b[3];if(stream.length<4+L)break;uint8_t ch=b[1];if(ch==0)[self rtp:[stream subdataWithRange:NSMakeRange(4,L)]];[stream replaceBytesInRange:NSMakeRange(0,4+L) withBytes:NULL length:0];}uint8_t t[32768];ssize_t n=recv(fd,t,sizeof(t),0);if(n<=0)break;[stream appendBytes:t length:n];if(stream.length>192*1024){/* live-first: don't allow a corrupt parser backlog to grow forever */[stream setLength:0];self.fu=nil;}}
    close(fd);
}
- (void)runRTSPLoop {while(!self.stopping){@autoreleasepool{[self runRTSPOnce];}if(!self.stopping)[NSThread sleepForTimeInterval:.12];}}
- (void)dealloc {self.stopping=YES;[self destroyDecoder];}
@end
