#import "PlayerViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <unistd.h>

@interface PlayerViewController ()
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) AVSampleBufferDisplayLayer *display;
@property(nonatomic,strong) dispatch_queue_t netQ;
@property(nonatomic,strong) NSMutableData *fu;
@property(nonatomic,strong) NSData *sps;
@property(nonatomic,strong) NSData *pps;
@property(nonatomic) CMVideoFormatDescriptionRef format;
@property(nonatomic) NSUInteger diagRTPPackets;
@property(nonatomic) NSUInteger diagH264NALs;
@property(nonatomic) NSUInteger diagReconnects;
@property(nonatomic) NSTimeInterval diagLastPacket;
@property(nonatomic,strong) NSTimer *diagTimer;
@property(nonatomic,copy) NSString *diagRTSPState;
@property(nonatomic,copy) NSString *diagRendererState;

@end

@implementation PlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.blackColor;
    self.display=[AVSampleBufferDisplayLayer layer];
    self.display.videoGravity=AVLayerVideoGravityResizeAspect;
    [self.view.layer addSublayer:self.display];
    self.netQ=dispatch_queue_create("a510.rtsp", DISPATCH_QUEUE_SERIAL);
    dispatch_async(self.netQ, ^{ [self runRTSP]; });
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.display.frame=self.view.bounds;
    self.display.videoGravity=AVLayerVideoGravityResizeAspect;
    [CATransaction commit];
}
- (void)refreshDiagnostics { }
- (void)updateStatus:(NSString*)s {
    self.diagRTSPState=s ?: @"?";
}
static BOOL sendAll(int fd, NSData *d){
    const uint8_t*p=d.bytes; size_t n=d.length;
    while(n){ssize_t x=send(fd,p,n,0);if(x<=0)return NO;p+=x;n-=x;} return YES;
}
static NSString *header(NSString*r,NSString*n){
    for(NSString*l in [r componentsSeparatedByString:@"\r\n"])
        if([l rangeOfString:[n stringByAppendingString:@":"] options:NSCaseInsensitiveSearch].location==0)
            return [[l substringFromIndex:n.length+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return nil;
}
static NSString *req(NSString*m,NSString*u,int c,NSString*x){
    return [NSString stringWithFormat:@"%@ %@ RTSP/1.0\r\nCSeq: %d\r\nUser-Agent: A510Player/0.3\r\n%@\r\n",m,u,c,x?:@""];
}
- (NSString*)readRTSP:(int)fd carry:(NSMutableData*)carry {
    for(;;){
        const uint8_t*b=carry.bytes; NSUInteger n=carry.length;
        for(NSUInteger i=3;i<n;i++) if(b[i-3]=='\r'&&b[i-2]=='\n'&&b[i-1]=='\r'&&b[i]=='\n'){
            NSUInteger he=i+1; NSData*hd=[carry subdataWithRange:NSMakeRange(0,he)];
            NSString*hs=[[NSString alloc]initWithData:hd encoding:NSUTF8StringEncoding];
            NSInteger cl=0; NSRange rr=[hs rangeOfString:@"Content-Length:" options:NSCaseInsensitiveSearch];
            if(rr.location!=NSNotFound) cl=[[[[hs substringFromIndex:NSMaxRange(rr)] componentsSeparatedByString:@"\r\n"] firstObject] integerValue];
            NSUInteger total=he+MAX(cl,0);
            if(carry.length>=total){ NSData*a=[carry subdataWithRange:NSMakeRange(0,total)];
                [carry replaceBytesInRange:NSMakeRange(0,total) withBytes:NULL length:0];
                return [[NSString alloc]initWithData:a encoding:NSUTF8StringEncoding];}
        }
        uint8_t t[8192]; ssize_t g=recv(fd,t,sizeof(t),0); if(g<=0)return nil; [carry appendBytes:t length:g];
    }
}
- (void)makeFormatIfPossible {
    if(self.format||!self.sps||!self.pps)return;
    const uint8_t *sets[2]={self.sps.bytes,self.pps.bytes};
    size_t sizes[2]={self.sps.length,self.pps.length};
    CMVideoFormatDescriptionRef f=NULL;
    if(CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,2,sets,sizes,4,&f)==noErr) self.format=f;
}
- (void)enqueueNAL:(NSData*)nal marker:(BOOL)marker {
    self.diagH264NALs++;

    if(!nal.length)return;
    uint8_t type=((const uint8_t*)nal.bytes)[0]&0x1f;
    if(type==7){self.sps=nal;[self makeFormatIfPossible];return;}
    if(type==8){self.pps=nal;[self makeFormatIfPossible];return;}
    [self makeFormatIfPossible]; if(!self.format){ self.diagRendererState=@"WAIT SPS/PPS"; return; }
    uint32_t L=CFSwapInt32HostToBig((uint32_t)nal.length);
    NSMutableData*d=[NSMutableData dataWithBytes:&L length:4]; [d appendData:nal];
    CMBlockBufferRef bb=NULL; CMSampleBufferRef sb=NULL;
    if(CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,NULL,d.length,kCFAllocatorDefault,NULL,0,d.length,0,&bb)!=kCMBlockBufferNoErr)return;
    CMBlockBufferReplaceDataBytes(d.bytes,bb,0,d.length);
    size_t sz=d.length;
    if(CMSampleBufferCreateReady(kCFAllocatorDefault,bb,self.format,1,0,NULL,1,&sz,&sb)==noErr){
        CFArrayRef at=CMSampleBufferGetSampleAttachmentsArray(sb,true);
        if(at&&CFArrayGetCount(at)) CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(at,0),kCMSampleAttachmentKey_DisplayImmediately,kCFBooleanTrue);
        dispatch_async(dispatch_get_main_queue(), ^{
            if(self.display.status==AVQueuedSampleBufferRenderingStatusFailed){ self.diagRendererState=[NSString stringWithFormat:@"FAILED %@",self.display.error.localizedDescription ?: @""]; [self.display flush]; } else self.diagRendererState=@"ENQUEUE OK";
            [self.display enqueueSampleBuffer:sb]; CFRelease(sb);
        });
    }
    if(bb)CFRelease(bb);
}
- (void)rtp:(NSData*)pkt {
    self.diagRTPPackets++;
    self.diagLastPacket=[NSDate date].timeIntervalSince1970;

    if(pkt.length<13)return; const uint8_t*r=pkt.bytes; NSUInteger cc=r[0]&15, off=12+cc*4;
    if(r[0]&0x10){if(pkt.length<off+4)return;off+=4+((((NSUInteger)r[off+2]<<8)|r[off+3])*4);}
    if(off>=pkt.length)return; const uint8_t*p=r+off; NSUInteger n=pkt.length-off; uint8_t type=p[0]&31;
    if(type>=1&&type<=23){[self enqueueNAL:[NSData dataWithBytes:p length:n] marker:(r[1]&0x80)!=0];return;}
    if(type==28&&n>=2){ BOOL start=p[1]&0x80,end=p[1]&0x40; uint8_t h=(p[0]&0xE0)|(p[1]&0x1F);
        if(start){self.fu=[NSMutableData dataWithBytes:&h length:1];[self.fu appendBytes:p+2 length:n-2];}
        else if(self.fu)[self.fu appendBytes:p+2 length:n-2];
        if(end&&self.fu){NSData*x=[self.fu copy];self.fu=nil;[self enqueueNAL:x marker:(r[1]&0x80)!=0];}
    }
}
- (void)runRTSPOnce {
    [self updateStatus:@"TCP CONNECTING 192.168.0.1:554"];
    int fd=socket(AF_INET,SOCK_STREAM,0); struct sockaddr_in a={0};a.sin_family=AF_INET;a.sin_port=htons(554);inet_pton(AF_INET,"192.168.0.1",&a.sin_addr);
    if(connect(fd,(struct sockaddr*)&a,sizeof(a))){[self updateStatus:@"TCP FAILED"];close(fd);return;} [self updateStatus:@"TCP OK / RTSP HANDSHAKE"];
    NSMutableData*c=[NSMutableData data]; int q=1; NSString*u=@"rtsp://192.168.0.1:554/livestream/12";
    sendAll(fd,[req(@"OPTIONS",u,q++,@"") dataUsingEncoding:NSUTF8StringEncoding]); [self readRTSP:fd carry:c];
    sendAll(fd,[req(@"DESCRIBE",u,q++,@"Accept: application/sdp\r\n") dataUsingEncoding:NSUTF8StringEncoding]);
    NSString*d=[self readRTSP:fd carry:c]; NSString*base=header(d,@"Content-Base"); if(!base)base=@"rtsp://192.168.0.1/00000000/";
    NSString*track=[base stringByAppendingString:@"track1"];
    sendAll(fd,[req(@"SETUP",track,q++,@"Transport: RTP/AVP/TCP;unicast;interleaved=0-1\r\n") dataUsingEncoding:NSUTF8StringEncoding]);
    NSString*s=[self readRTSP:fd carry:c]; NSString*session=header(s,@"Session"); if([session containsString:@";"])session=[session componentsSeparatedByString:@";"].firstObject;
    if(!session){[self updateStatus:@"RTSP SETUP failed"];close(fd);return;}
    NSString*x=[NSString stringWithFormat:@"Session: %@\r\nRange: npt=0.000-\r\n",session];
    sendAll(fd,[req(@"PLAY",base,q++,x) dataUsingEncoding:NSUTF8StringEncoding]);
    [self updateStatus:@"PLAY SENT / RTP WAIT"];
    NSMutableData*stream=c;
    for(;;){
        while(stream.length>=4){
            const uint8_t*b=stream.bytes;
            if(b[0]!='$'){[stream replaceBytesInRange:NSMakeRange(0,1) withBytes:NULL length:0];continue;}
            uint16_t L=((uint16_t)b[2]<<8)|b[3]; if(stream.length<4+L)break; uint8_t ch=b[1];
            if(ch==0)[self rtp:[stream subdataWithRange:NSMakeRange(4,L)]];
            [stream replaceBytesInRange:NSMakeRange(0,4+L) withBytes:NULL length:0];
        }
        uint8_t t[65536];ssize_t n=recv(fd,t,sizeof(t),0);if(n<=0)break;[stream appendBytes:t length:n];
    }
    [self updateStatus:@"STREAM EOF"]; close(fd);
}

- (void)runRTSP {
    for(;;) {
        @autoreleasepool {
            self.diagReconnects++;
            [self runRTSPOnce];
        }
        [self updateStatus:@"DISCONNECTED - retry 2s"];
        [NSThread sleepForTimeInterval:2.0];
    }
}
- (void)dealloc { if(_format)CFRelease(_format); }
@end
