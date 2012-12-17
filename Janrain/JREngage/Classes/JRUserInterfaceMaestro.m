/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 Copyright (c) 2010, Janrain, Inc.

 All rights reserved.

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation and/or
   other materials provided with the distribution.
 * Neither the name of the Janrain, Inc. nor the names of its
   contributors may be used to endorse or promote products derived from this
   software without specific prior written permission.


 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
 ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

 File:   JRUserInterfaceMaestro.m
 Author: Lilli Szafranski - lilli@janrain.com, lillialexis@gmail.com
 Date:   Tuesday, August 24, 2010
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

#ifdef DEBUG
#define DLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define DLog(...)
#endif

#define ALog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)

#import "JRUserInterfaceMaestro.h"
#import "JREngage+CustomInterface.h"

#import "JRSessionData.h"
#import "JRProvidersController.h"
#import "JRUserLandingController.h"
#import "JRWebViewController.h"
#import "JRPublishActivityController.h"

static void handleCustomInterfaceException(NSException* exception, NSString* kJRKeyString)
{
    NSLog (@"*** Exception thrown. Problem is most likely with jrEngage custom interface object %@ : Caught %@ : %@",
                 (kJRKeyString ? [NSString stringWithFormat:@" possibly from kJRKeyString, %@", kJRKeyString] : @""),
                 [exception name],
                 [exception reason]);

#ifdef DEBUG
    @throw exception;
#else
    NSLog (@"*** Ignoring value and using defaults if possible.");
#endif
}

#define IS_IPAD ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad))
#define IOS6 ([[[UIDevice currentDevice] systemVersion] compare:@"6.0" options:NSNumericSearch] >= NSOrderedSame)
#define IS_PORTRAIT (UIDeviceOrientationIsPortrait([UIDevice currentDevice].orientation))
#define IS_LANDSCAPE (UIDeviceOrientationIsLandscape([UIDevice currentDevice].orientation))

// get the app window with some fallbacks for legacy bad behavior?
UIWindow *getWindow()
{
    UIWindow* window = [UIApplication sharedApplication].keyWindow;
    if (!window) window = [[UIApplication sharedApplication].windows objectAtIndex:0];
    return window;
}

// return the center of a view in it's own coordinate system
CGPoint centerOfView(UIView *v)
{
    return CGPointMake(v.bounds.origin.x + v.bounds.size.width / 2, v.bounds.origin.y + v.bounds.size.height / 2);
}

// for each view in a chain of views from a view to a root view (:= a view with no superview),
// center the view in it's superview
void centerViewChain(UIView *view)
{
    NSMutableArray *views = [NSMutableArray array];
    UIView *v = view;
    while (v && ![v isKindOfClass:[UIWindow class]])
    {
        [views insertObject:v atIndex:0];
        v = v.superview;
    }
    for (NSUInteger i = 0; i < [views count]; i++)
    {
        v = [views objectAtIndex:i];
        v.center = centerOfView(v.superview);
    }
}

// Provides a hand-made cover-vertical mimic animation to accomodate for iOS6 breaking the animation of the FormSheet
// size hacks
// Also forwards appearance and rotation events for iOS 4 iPads
@interface CustomAnimationController : UIViewController
@property (retain) UIViewController *jrPresentingViewController;
@property (retain) UIViewController *jrChildViewController;
@end

@implementation CustomAnimationController
@synthesize jrPresentingViewController, jrChildViewController;
- (void)loadView
{
    [self setView:[[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 460)] autorelease]];
    self.view.backgroundColor = jrChildViewController.view.backgroundColor;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [jrChildViewController viewDidAppear:animated];
    if (animated) return;

    // hack to resize platform provided dropshadow view that's inserted
    // into the view hierarchy above the modally presented VC when you use presentModalViewController
    // related to this SO q:
    // http://stackoverflow.com/questions/2457947/how-to-resize-a-uipresentationformsheet/4271364#4271364

    UIView *v = self.view.superview;
    while (v)
    {
        //DLog("View chain: %@", [v description]);
        if ([v isKindOfClass:NSClassFromString(@"UIDropShadowView")])
            v.bounds = CGRectMake(0, 0, 320, 460);
        v = v.superview;
    }

    centerViewChain(self.view);

    CGPoint center = self.view.superview.center;

    // move parent view offscreen. coordinate space transform fuckery to account for orientations.
    CGPoint c = [self.view.superview convertPoint:self.view.superview.center fromView:self.view.superview.superview];
    CGFloat y = c.y;
    CGPoint c_ = CGPointMake(c.x, y * 2 + 240);
    self.view.superview.center = [self.view.superview convertPoint:c_ toView:self.view.superview.superview];

    // animate parent view back onscreen
    [UIView animateWithDuration:0.5
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^ { self.view.superview.center = center; }
                     completion:nil];
}

- (BOOL)shouldAutomaticallyForwardRotationMethods
{
    return NO;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    return [jrChildViewController shouldAutorotateToInterfaceOrientation:toInterfaceOrientation];
}

- (BOOL)shouldAutorotate
{
    if ([jrChildViewController respondsToSelector:@selector(shouldAutorotate)])
        return [jrChildViewController shouldAutorotate];
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                duration:(NSTimeInterval)duration
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [jrChildViewController willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                         duration:(NSTimeInterval)duration
{
    [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [jrChildViewController willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [jrChildViewController didRotateFromInterfaceOrientation:fromInterfaceOrientation];
}

- (BOOL)shouldAutomaticallyForwardAppearanceMethods
{
    return NO;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [jrChildViewController viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [jrChildViewController viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [jrChildViewController viewDidDisappear:animated];
}

@end

// Terrible, terrible hacks.
@interface JRModalViewController : UIViewController <UIPopoverControllerDelegate>
{
    BOOL shouldUnloadSubviews;
}
@property (retain) CustomAnimationController *animationController;
@property (retain) UINavigationController *myNavigationController;
@property (retain) UIPopoverController *myPopoverController;
@end

@implementation JRModalViewController
@synthesize myPopoverController, myNavigationController, animationController;
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
        self.animationController = [[[CustomAnimationController alloc] initWithNibName:nil bundle:nil] autorelease];
    }

    return self;
}

- (void)loadView
{
    DLog (@"");
    UIView *view = [[[UIView alloc] initWithFrame:getWindow().frame] autorelease];

    [view setAutoresizingMask:
            UIViewAutoresizingNone
            | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight
            | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleLeftMargin |
            UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin
    ];

    shouldUnloadSubviews = NO;

    [self setView:view];
}

- (void)presentPopoverNavigationControllerFromBarButton:(UIBarButtonItem*)barButtonItem
                                            inDirection:(UIPopoverArrowDirection)direction
{
    DLog (@"");
    [myPopoverController presentPopoverFromBarButtonItem:barButtonItem
                                permittedArrowDirections:direction
                                                animated:YES];
}

- (void)presentPopoverNavigationControllerFromCGRect:(CGRect)rect inDirection:(UIPopoverArrowDirection)direction
{
    DLog (@"");
    CGRect popoverPresentationFrame = [self.view convertRect:rect toView:getWindow()];

    [myPopoverController presentPopoverFromRect:popoverPresentationFrame
                                         inView:self.view
                       permittedArrowDirections:direction
                                       animated:YES];
}

- (void)presentModalNavigationController
{
    DLog (@"");
    BOOL hasRvc = [getWindow() respondsToSelector:@selector(rootViewController)] && getWindow().rootViewController;
    UIViewController *rvc = hasRvc ? getWindow().rootViewController : nil;

    myNavigationController.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
    myNavigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    animationController.modalPresentationStyle = myNavigationController.modalPresentationStyle;

    // Figure out what to present
    UIViewController *vcToPresent;
    if (IS_IPAD)
    {
        vcToPresent = animationController ;
        [animationController.view addSubview:myNavigationController.view];
        animationController.jrChildViewController = myNavigationController;
    }
    else
    {
        vcToPresent = myNavigationController;
    }

    // Figure out how to present it and present it
    if (rvc)
    {
        // If we can do it the right way, and do the animation by hand
        animationController.jrPresentingViewController = rvc; // just using this property as scratch space to hang on
                                                              // to the presenting VC for dismissing the dialog
        [rvc presentModalViewController:vcToPresent animated:!IS_IPAD];
    }
    else
    {
        // Yarr, it be a pirate's life for me
        [getWindow() addSubview:self.view];
        animationController.jrPresentingViewController = self; // just using this property as scratch space to hang on
                                                               // to the presenting VC for dismissing the dialog
        [self presentModalViewController:vcToPresent animated:!IS_IPAD];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    DLog (@"");

    if (shouldUnloadSubviews)
        [self.view removeFromSuperview];

    [super viewDidAppear:animated];
}

- (void)dismissModalNavigationController:(UIModalTransitionStyle)style
{
    DLog (@"");

    if (myPopoverController)
    {
        [myPopoverController dismissPopoverAnimated:YES];
    }
    else
    {
        animationController.modalTransitionStyle = myNavigationController.modalTransitionStyle = style;
        [animationController.jrPresentingViewController dismissModalViewControllerAnimated:YES];
    }

    shouldUnloadSubviews = YES;

    [self.view removeFromSuperview];
}

// For iOS >= 6
- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

// iOS >= 6
-(BOOL)shouldAutorotate
{
    return YES;
}

// iOS <= 5
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    DLog(@"");
    return YES;
}

- (void)dealloc
{
    DLog (@"");
    [myNavigationController release];
    [myPopoverController release];

    [super dealloc];
}
@end

@interface JRUserInterfaceMaestro ()
@property (retain) JRModalViewController *jrModalViewController;
@property (retain) UINavigationController       *customModalNavigationController;
@property (retain) UINavigationController       *applicationNavigationController;
@property (retain) UINavigationController       *savedNavigationController;
@property (retain) NSDictionary                 *janrainInterfaceDefaults;
@end

@implementation JRUserInterfaceMaestro
@synthesize myProvidersController;
@synthesize myUserLandingController;
@synthesize myWebViewController;
@synthesize myPublishActivityController;
@synthesize jrModalViewController;
@synthesize customModalNavigationController;
@synthesize applicationNavigationController;
@synthesize savedNavigationController;
@synthesize customInterfaceDefaults;
@synthesize janrainInterfaceDefaults;
@synthesize directProvider;

static JRUserInterfaceMaestro* singleton = nil;

+ (JRUserInterfaceMaestro*)sharedMaestro
{
    return singleton;
}

+ (id)allocWithZone:(NSZone *)zone
{
    return [[self sharedMaestro] retain];
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (id)retain
{
    return self;
}

- (NSUInteger)retainCount
{
    return NSUIntegerMax;
}

- (oneway void)release { }

- (id)autorelease
{
    return self;
}

- (NSDictionary*)loadJanrainInterfaceDefaults
{
    NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:
                               [[[NSBundle mainBundle] resourcePath]
                                stringByAppendingPathComponent:@"/JREngage-Info.plist"]];

    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:
                                 [[infoPlist objectForKey:@"JREngage.CustomInterface"]
                                  objectForKey:@"DefaultValues"]];

    UIColor *backgroundColor = JANRAIN_BLUE_20;

    if (backgroundColor)
        [dict setObject:backgroundColor forKey:kJRAuthenticationBackgroundColor];

    return dict;
}

- (id)initWithSessionData:(JRSessionData*)newSessionData
{
    if ((self = [super init]))
    {
        singleton = self;
        sessionData = newSessionData;
        janrainInterfaceDefaults = [[self loadJanrainInterfaceDefaults] retain];
    }

    return self;
}

+ (id)jrUserInterfaceMaestroWithSessionData:(JRSessionData*)newSessionData
{
    if(singleton)
        return singleton;

    if (newSessionData == nil)
        return nil;

    return [[((JRUserInterfaceMaestro*)[super allocWithZone:nil]) initWithSessionData:newSessionData] autorelease];
}

- (void)buildCustomInterface:(NSDictionary*)customizations
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:
                                 ([customizations count] +
                                  [janrainInterfaceDefaults count] +
                                  [customInterfaceDefaults count])];

    [dict addEntriesFromDictionary:janrainInterfaceDefaults];
    [dict addEntriesFromDictionary:customInterfaceDefaults];
    [dict addEntriesFromDictionary:customizations];

    NSArray *nullKeys = [dict allKeysForObject:[NSNull null]];
    for (NSString *key in nullKeys)
        [dict removeObjectForKey:key];

    customInterface = [[NSDictionary alloc] initWithDictionary:dict];
}

- (void)setUpDialogPresentation
{
    if ([customInterface objectForKey:kJRApplicationNavigationController])
        self.applicationNavigationController = [customInterface objectForKey:kJRApplicationNavigationController];

 /* Added for backwards compatibility */
    if (savedNavigationController)
        self.applicationNavigationController = savedNavigationController;

    if ([customInterface objectForKey:kJRCustomModalNavigationController])
        self.customModalNavigationController = [customInterface objectForKey:kJRCustomModalNavigationController];

    usingAppNav = NO, usingCustomNav = NO;
    if (IS_IPAD)
    {
        if ([customInterface objectForKey:kJRPopoverPresentationBarButtonItem])
            padPopoverMode = PadPopoverFromBar;
        else if ([customInterface objectForKey:kJRPopoverPresentationFrameValue])
            padPopoverMode = PadPopoverFromFrame;
        else
            padPopoverMode = PadPopoverModeNone;

        @try
        {
            if (customModalNavigationController)// && ![customModalNavigationController isViewLoaded])
                usingCustomNav = YES;
            else
                usingCustomNav = NO;
        }
        @catch (NSException *exception)
        { handleCustomInterfaceException(exception, @"kJRUseCustomModalNavigationController"); }
    }
    else
    {
        @try
        {
            if (applicationNavigationController && [applicationNavigationController isViewLoaded])
                usingAppNav = YES;
            else if (customModalNavigationController)
                usingCustomNav = YES;
        }
        @catch (NSException *exception)
        { handleCustomInterfaceException(exception, @"kJRUseApplicationNavigationController"); }
    }

    if (usingAppNav || IS_IPAD) sessionData.canRotate = YES;
}

- (void)tearDownDialogPresentation
{
    padPopoverMode = PadPopoverModeNone;
    usingAppNav = NO, usingCustomNav = NO;

    [viewControllerToPopTo release], viewControllerToPopTo = nil;
    self.applicationNavigationController = nil;
    self.customModalNavigationController = nil;
}

- (void)setUpViewControllers
{
    DLog(@"");
    myProvidersController       = [[JRProvidersController alloc] initWithNibName:@"JRProvidersController"
                                                                          bundle:[NSBundle mainBundle]
                                                              andCustomInterface:customInterface];

    myUserLandingController     = [[JRUserLandingController alloc] initWithNibName:@"JRUserLandingController"
                                                                            bundle:[NSBundle mainBundle]
                                                                andCustomInterface:customInterface];

    myWebViewController         = [[JRWebViewController alloc] initWithNibName:@"JRWebViewController"
                                                                        bundle:[NSBundle mainBundle]
                                                            andCustomInterface:customInterface];

    myPublishActivityController = [[JRPublishActivityController alloc] initWithNibName:@"JRPublishActivityController"
                                                                                bundle:[NSBundle mainBundle]
                                                                    andCustomInterface:customInterface];

    @try
    {/* We do this here, because sometimes we pop straight to the user landing controller and we need the back-button's title to be correct */
        if ([customInterface objectForKey:kJRProviderTableTitleString] &&
            ((NSString*)[customInterface objectForKey:kJRProviderTableTitleString]).length)
            myProvidersController.title = [customInterface objectForKey:kJRProviderTableTitleString];
        else
            myProvidersController.title = @"Providers";
    }
    @catch (NSException *exception)
    {
        handleCustomInterfaceException(exception, @"kJRProviderTableTitleString");
        myProvidersController.title = @"Providers";
    }

    if (/*usingAppNav || */(IS_IPAD && padPopoverMode != PadPopoverModeNone) ||
        [[customInterface objectForKey:kJRNavigationControllerHidesCancelButton] boolValue])
    {
        myProvidersController.hidesCancelButton = YES;
        myPublishActivityController.hidesCancelButton = YES;
    }

    delegates = [[NSMutableArray alloc] initWithObjects:myProvidersController,
                 myUserLandingController,
                 myWebViewController,
                 myPublishActivityController, nil];

    sessionData.dialogIsShowing = YES;
}

- (void)tearDownViewControllers
{
    DLog(@"");

    [delegates removeAllObjects];
    [delegates release], delegates = nil;

    [myProvidersController release],        myProvidersController = nil;
    [myUserLandingController release],      myUserLandingController = nil;
    [myWebViewController release],          myWebViewController = nil;
    [myPublishActivityController release],  myPublishActivityController = nil;

    [jrModalViewController release], jrModalViewController = nil;
    [customModalNavigationController release], customModalNavigationController = nil;

    [customInterface release], customInterface = nil;
    [directProvider release], directProvider = nil;

    sessionData.dialogIsShowing = NO;
//    sessionData.skipReturningUserLandingPage = NO;
}

- (void)setUpSocialPublishing
{
    DLog(@"");
    [sessionData setSocialSharing:YES];

    if (myPublishActivityController)
        [sessionData addDelegate:myPublishActivityController];
}

- (void)tearDownSocialPublishing
{
    DLog(@"");
    [sessionData setSocialSharing:NO];
    [sessionData setActivity:nil];

    if (myPublishActivityController)
        [sessionData removeDelegate:myPublishActivityController];
}

- (UINavigationController*)createDefaultNavigationControllerWithRootViewController:(UIViewController *)root
{
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:root];
    [navigationController autorelease];
    navigationController.navigationBar.barStyle = UIBarStyleBlackOpaque;
    navigationController.navigationBar.clipsToBounds = YES;

    navigationController.view.autoresizingMask =
            UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
            | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    navigationController.view.bounds = CGRectMake(0, 0, 320, 460);

    return navigationController;
}

- (UIPopoverController*)createPopoverControllerWithNavigationController:(UINavigationController*)navigationController
{
//    UIPopoverController *popoverController =
//        [[[UIPopoverController alloc]
//            initWithContentViewController:navigationController] autorelease];
    /* Allocating UIPopoverController with class string allocation so that it compiles for iPhone OS versions < v3.2 */
    UIPopoverController *popoverController =
        [[[NSClassFromString(@"UIPopoverController") alloc]
            initWithContentViewController:navigationController] autorelease];

    if (popoverController)
    {
        popoverController.popoverContentSize = CGSizeMake(320, 460);
        popoverController.delegate = self;
    }

    return popoverController;
}

- (BOOL)shouldOpenToUserLandingPage
{
   /* Test to see if we should open the authentication dialog to the returning user landing page.
    *
    * We will only open to the user landing page if the following conditions are met:
    *   a. If we have a returning provider (the provider the user most recently signed in with);
    *   b. if there is a saved user for the returning provider (the only time this wouldn't be the case
    *         is when upgrading the library and the saved users couldn't be deserialized);
    *   c. if we don't have a currently selected provider (which will be the case when we're signing in directly
    *         to one provider);
    *   d. if alwaysForceReauth isn't set to 'true'
    *   e. if the returning provider (the provider the user most recently signed in with) isn't set to
    *         alwaysForceReath
    *   f. if we aren't opening the social sharing dialog (i.e., we are only authenticating);
    *   g. the returning provider is still in the list of providers configured with the RP (between the last
    *        time they logged in and now);
    *   h. and the returning provider hasn't been excluded from the list of providers.
    *
    * The last two cases will only happen if the user signs in with a particular provider once (which is then set as
    * the returningBasicProvider), and then the list of providers changes between the first sign in and when they
    * log in again.  If the RP's configuration has changed and their last-used provider has been dropped, but the
    * configuration call hasn't returned from the server yet, then this case may fall through the cracks (although
    * this case is very unlikely to happen). */
    if (sessionData.returningBasicProvider                                                      /* a */
        && [sessionData authenticatedUserForProviderNamed:sessionData.returningBasicProvider]   /* b */
        && !sessionData.currentProvider                                                         /* c */
        && !sessionData.alwaysForceReauth                                                       /* d */
        && ![sessionData getProviderNamed:sessionData.returningBasicProvider].forceReauth       /* e */
        && !sessionData.socialSharing                                                           /* f */
        && !sessionData.captureWidget
        && [sessionData.basicProviders containsObject:sessionData.returningBasicProvider]       /* g */
        && ![((NSArray*)[customInterface objectForKey:kJRRemoveProvidersFromAuthentication])    /* h */
                    containsObject:sessionData.returningBasicProvider])
        return YES;

    return NO;
}

- (void)loadModalNavigationControllerWithViewController:(UIViewController*)rootViewController
{
    DLog(@"");

    self.jrModalViewController = [[[JRModalViewController alloc] initWithNibName:nil bundle:nil] autorelease];

    if (usingCustomNav)
    {
        jrModalViewController.myNavigationController = customModalNavigationController;
        [jrModalViewController.myNavigationController pushViewController:rootViewController animated:NO];
    }
    else
    {
        jrModalViewController.myNavigationController =
                [self createDefaultNavigationControllerWithRootViewController:rootViewController];
    }

    if (padPopoverMode)
        jrModalViewController.myPopoverController =
            [self createPopoverControllerWithNavigationController:jrModalViewController.myNavigationController];

    /* If the code is used by a universal application and is compiled for versions of iOS that don't
       support popovercontrollers (i.e., iOS < v3.2), this will return nil;  If it does, fall back
       to modal dialog presentation. This might never happen, because the above code wouldn't be called
       on the iPhone anyway... */
    if (!jrModalViewController.myPopoverController)
        padPopoverMode = PadPopoverModeNone;

    UIPopoverArrowDirection arrowDirection = UIPopoverArrowDirectionAny;
    if ([customInterface objectForKey:kJRPopoverPresentationArrowDirection])
    {
        arrowDirection = (UIPopoverArrowDirection)
                [[customInterface objectForKey:kJRPopoverPresentationArrowDirection] intValue];
    }

    if ([self shouldOpenToUserLandingPage])
    {
        [sessionData setCurrentProvider:[sessionData getProviderNamed:sessionData.returningBasicProvider]];
        [jrModalViewController.myNavigationController pushViewController:myUserLandingController animated:NO];
    }

    if (padPopoverMode == PadPopoverFromBar)
        [jrModalViewController
            presentPopoverNavigationControllerFromBarButton:[customInterface objectForKey:kJRPopoverPresentationBarButtonItem]
                                                inDirection:arrowDirection];
    else if (padPopoverMode == PadPopoverFromFrame)
        [jrModalViewController
            presentPopoverNavigationControllerFromCGRect:[[customInterface objectForKey:kJRPopoverPresentationFrameValue] CGRectValue]
                                             inDirection:arrowDirection];
    else
        [jrModalViewController presentModalNavigationController];
}

- (void)loadApplicationNavigationControllerWithViewController:(UIViewController*)rootViewController
{
    DLog(@"");
    if (!viewControllerToPopTo)
        viewControllerToPopTo = [[applicationNavigationController topViewController] retain];

    if ([self shouldOpenToUserLandingPage])
    {
        [sessionData setCurrentProvider:[sessionData getProviderNamed:sessionData.returningBasicProvider]];
        [applicationNavigationController pushViewController:rootViewController animated:NO];
        [applicationNavigationController pushViewController:myUserLandingController animated:YES];
    }
    else
    {
        [applicationNavigationController pushViewController:rootViewController animated:YES];
    }
}


// TODO: Document this function
- (JRProvider*)weAreOnlyAuthenticatingOnThisProvider
{
    sessionData.authenticatingDirectlyOnThisProvider = YES;

    if (directProvider)
        return [sessionData getProviderNamed:directProvider];

//    NSMutableArray *providers = [NSMutableArray arrayWithArray:sessionData.basicProviders];
//    [providers removeObjectsInArray:[customInterface objectForKey:kJRRemoveProvidersFromAuthentication]];
//    if ([providers count] == 1)
//        return [sessionData getProviderNamed:[providers objectAtIndex:0]];

    sessionData.authenticatingDirectlyOnThisProvider = NO;
    return nil;
}

- (void)showAuthenticationDialogWithCustomInterface:(NSDictionary*)customizations
{
    DLog(@"");
    [self buildCustomInterface:customizations];
    [self setUpDialogPresentation];
    [self setUpViewControllers];

    UIViewController *dialogVcToPresent;
    if ((sessionData.currentProvider = [self weAreOnlyAuthenticatingOnThisProvider]))
        dialogVcToPresent = sessionData.currentProvider.requiresInput ? myUserLandingController : myWebViewController;
    else
        dialogVcToPresent = myProvidersController;

    if (usingAppNav)
        [self loadApplicationNavigationControllerWithViewController:dialogVcToPresent];
    else
        [self loadModalNavigationControllerWithViewController:dialogVcToPresent];
}

- (void)showPublishingDialogForActivityWithCustomInterface:(NSDictionary*)customizations
{
    DLog(@"");
    [self buildCustomInterface:customizations];
    [self setUpDialogPresentation];
    [self setUpViewControllers];
    [self setUpSocialPublishing];

    if (usingAppNav)
        [self loadApplicationNavigationControllerWithViewController:myPublishActivityController];
    else
        [self loadModalNavigationControllerWithViewController:myPublishActivityController];
}

- (void)unloadModalNavigationControllerWithTransitionStyle:(UIModalTransitionStyle)style
{
    DLog(@"");
    [jrModalViewController dismissModalNavigationController:style];
}

- (void)unloadApplicationNavigationController
{
    DLog(@"");
    [applicationNavigationController popToViewController:viewControllerToPopTo animated:YES];
}

- (void)unloadUserInterfaceWithTransitionStyle:(UIModalTransitionStyle)style
{
    DLog(@"");
    if (!sessionData.dialogIsShowing)
        return;

    if ([sessionData socialSharing])
        [self tearDownSocialPublishing];

    for (id<JRUserInterfaceDelegate> delegate in delegates)
        [delegate userInterfaceWillClose];

    if (usingAppNav)
        [self unloadApplicationNavigationController];
    else
        [self unloadModalNavigationControllerWithTransitionStyle:style];

    for (id<JRUserInterfaceDelegate> delegate in delegates)
        [delegate userInterfaceDidClose];

    [self tearDownViewControllers];
    [self tearDownDialogPresentation];
}

- (void)popToOriginalRootViewController
{
    DLog(@"");
    UIViewController *originalRootViewController = nil;

    if ([sessionData socialSharing])
        originalRootViewController = myPublishActivityController;
    else
        originalRootViewController = myProvidersController;

    if (usingAppNav && applicationNavigationController && [applicationNavigationController isViewLoaded])
        [applicationNavigationController popToViewController:originalRootViewController animated:YES];
    else
        [jrModalViewController.myNavigationController popToRootViewControllerAnimated:YES];
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
    DLog (@"");
    if ([sessionData socialSharing])
        [sessionData triggerPublishingDidCancel];
    else
        [sessionData triggerAuthenticationDidCancel];
}

- (void)authenticationRestarted
{
    DLog(@"");
    [self popToOriginalRootViewController];
}

- (void)authenticationCompleted
{
    DLog(@"");
    if (![sessionData socialSharing])
        [self unloadUserInterfaceWithTransitionStyle:UIModalTransitionStyleCrossDissolve];
    else
        [self popToOriginalRootViewController];
}

- (void)authenticationFailed
{
    DLog(@"");
    [self popToOriginalRootViewController];
}

- (void)authenticationCanceled
{
    DLog(@"");
    [self unloadUserInterfaceWithTransitionStyle:UIModalTransitionStyleCoverVertical];
}

- (void)publishingRestarted
{
    DLog(@"");
    [self popToOriginalRootViewController];
}

- (void)publishingCompleted
{
    DLog(@"");
    [self unloadUserInterfaceWithTransitionStyle:UIModalTransitionStyleCoverVertical];
}

- (void)publishingCanceled
{
    DLog(@"");
    [self unloadUserInterfaceWithTransitionStyle:UIModalTransitionStyleCoverVertical];
}

- (void)publishingFailed
{
    DLog(@"");
//  [self popToOriginalRootViewController];
//  [self unloadUserInterfaceWithTransitionStyle:UIModalTransitionStyleCoverVertical];
}
@end
