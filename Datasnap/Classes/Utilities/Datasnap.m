//
//  Datasnap.m
//  dataSnapSample
//
//  Created by Alyssa McIntyre on 6/10/16.
//  Copyright © 2016 Datasnapio. All rights reserved.
//

#import "Datasnap.h"
//TODO: move file to root
static Datasnap* sharedInstance = nil;
static NSString* appInstalledEventType = @"app_installed";

NSString* const GimbalClientClassName = @"GimbalClient";
NSString* const GimbalClientInitializerMethod = @"initWithVendorProperties:device:organizationId:projectId:andUser:";

NSString* const IsAppAlreadyLaunchedOnceKey = @"isAppAlreadyLaunchedOnceKey";
NSString* const AppInstalledEventType = @"appInstalledEventType";

@interface Datasnap ()
@property (nonatomic) EventEntity* event;
@property (nonatomic) Device* device;
@property (nonatomic, strong) User* user;
@property (nonatomic, strong) Identifier* identifier;
@property (nonatomic) VendorProperties* vendorProperties;
@property (nonatomic) id gimbalClient;
@property (nonatomic, strong) NSString* organizationId;
@property (nonatomic, strong) NSString* projectId;
@property (nonatomic) BaseClient* baseClient;
@property (nonatomic) NSTimer* timer;
@property (nonatomic) bool googleAdOptIn;
@property (nonatomic) NSString* email;
@property (nonatomic) NSString* mobileDeviceIosIdfa;
@property (nonatomic) NSInteger maxElements;
@end

@implementation Datasnap

+ (id)sharedClient
{
    static Datasnap* sharedClient = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedClient = [self new];
    });
    return sharedClient;
}

#pragma mark Datasnap Initialization

- (id)initWithApiKey:(NSString*)apiKey
        apiKeySecret:(NSString*)apiKeySecret
      organizationId:(NSString*)organizationId
           projectId:(NSString*)projectId
           IDFAOptIn:(bool)googleAdOptIn
               email:(NSString*)email
 andVendorProperties:(VendorProperties*)vendorProperties
{
    if (self = [self init]) {
        self.organizationId = organizationId;
        self.projectId = projectId;
        self.api = [[DatasnapAPI alloc] initWithKey:apiKey secret:apiKeySecret];
        self.googleAdOptIn = googleAdOptIn;
        self.email = email;
        self.vendorProperties = vendorProperties;
    }
    [self initializeData];
    return self;
}

- (void)initializeData
{
    self.device = [[Device alloc] init];
    self.identifier = [[Identifier alloc] initWithGlobalDistinctId:[[NSUUID UUID] UUIDString]
                                                   opt_in_location:self.googleAdOptIn ? @"YES" : @"NO"
                                           andSha1_lowercase_email:self.email ? [self.email toSha1] : nil];

    self.user = [[User alloc] initWithIdentifier:self.identifier
                                            tags:nil
                                        audience:nil
                               andUserProperties:nil];

    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        [self checkQueue];
        // Ensure Gimbal is started if application is started offline.
        // Gimbal cannot properly initialize if the app is offline during startup.
        if (!self.gimbalClient && self.vendorProperties && self.vendorProperties.vendor == GIMBAL && [self connected]) {
            [self initializeGimbal];
        }
    }];

    [[AFNetworkReachabilityManager sharedManager] startMonitoring];
    [self onDataInitialized];
}

- (void)onDataInitialized
{
    if (!self.vendorProperties) {
        return;
    }
    switch (self.vendorProperties.vendor) {
    case GIMBAL:
        if ([self connected]) {
            // Dynamically call GimbalClient's initialization method
            [self initializeGimbal];
        }
        break;
    case ESTIMOTE:
        break;
    default:
        self.baseClient = [[BaseClient alloc] initWithOrganizationId:self.organizationId
                                                           projectId:self.projectId
                                                              device:self.device
                                                             andUser:self.user];
        break;
    }

    if (![[NSUserDefaults standardUserDefaults] boolForKey:IsAppAlreadyLaunchedOnceKey]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:IsAppAlreadyLaunchedOnceKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        BaseEvent* event = [[BaseEvent alloc] initWithEventType:AppInstalledEventType];
        [self trackEvent:event];
    }
}

#pragma mark Gimbal

- (void)initializeGimbal
{
    SEL gimbalInit = NSSelectorFromString(GimbalClientInitializerMethod);
    self.gimbalClient = [[NSClassFromString(GimbalClientClassName) alloc] init];
    if ([self.gimbalClient respondsToSelector:gimbalInit]) {
        NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[self.gimbalClient methodSignatureForSelector:gimbalInit]];
        [inv setSelector:gimbalInit];
        [inv setTarget:self.gimbalClient];
        [inv setArgument:&self->_vendorProperties atIndex:2];
        [inv setArgument:&self->_device atIndex:3];
        [inv setArgument:&self->_organizationId atIndex:4];
        [inv setArgument:&self->_projectId atIndex:5];
        [inv setArgument:&self->_user atIndex:6];
        [inv invoke];
    }
    else {
        NSLog(@"Gimbal library not found, please add Gimbal to podfile using pod 'Gimbal' and run pod install");
    }
}

#pragma mark Network Reachability

- (BOOL)connected
{
    return [AFNetworkReachabilityManager sharedManager].reachable;
}

#pragma mark Event Queue Handling

- (void)setFlushParamsWithDuration:(NSInteger)durationInMillis
                   withMaxElements:(NSInteger)maxElements
{
    self.maxElements = maxElements;
    self.eventQueue = [[EventQueue alloc] initWithSize:maxElements andTime:durationInMillis];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:maxElements
                                                  target:self
                                                selector:@selector(checkQueue)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)checkQueue
{
    if ([self connected]) {
        NSMutableArray* events = [self.eventQueue getEvents];
        if (events.count > 0) {
            if ([[self.api sendEvents:events] isEqualToString:@"200"]) {
                NSLog(@"Queue is full. %d events will be sent to service and flushed.", events.count);
                [self.eventQueue flushQueue:events];
                if ([EventEntity returnAllEvents].count > 0) {
                    [self checkQueue];
                }
            }
            else {
                [self.timer invalidate];
                self.maxElements = self.maxElements * 2;
                self.timer = [NSTimer scheduledTimerWithTimeInterval:self.maxElements
                                                              target:self
                                                            selector:@selector(checkQueue)
                                                            userInfo:nil
                                                             repeats:YES];
            }
        }
    }
}

#pragma mark Event Tracking

- (void)trackEvent:(BaseEvent*)event
{
    event.organization_Ids = @[ self.organizationId ];
    event.project_Ids = @[ self.projectId ];
    event.user = self.user;
    event.device = self.device;
    if (![event isValid]) {
        NSLog(@"Mandatory event data missing. Please call Datasnap.initialize before using the library");
    }
    NSDictionary* eventJson = [event convertToDictionary];
    [self.eventQueue recordEvent:eventJson];
}

@end
