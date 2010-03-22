#import "libactivator.h"
#import "libactivator-private.h"
#import <Foundation/Foundation.h>
#import <SpringBoard/SpringBoard.h>
#import <CaptainHook/CaptainHook.h>

CHDeclareClass(SBApplicationController);
CHDeclareClass(SBApplication);
CHDeclareClass(SBDisplayStack);
CHDeclareClass(SBIconModel);

static NSMutableDictionary *applications;
static LAApplicationListener *sharedApplicationListener;
static NSMutableArray *displayStacks;

#define SBWPreActivateDisplayStack        (SBDisplayStack *)[displayStacks objectAtIndex:0]
#define SBWActiveDisplayStack             (SBDisplayStack *)[displayStacks objectAtIndex:1]
#define SBWSuspendingDisplayStack         (SBDisplayStack *)[displayStacks objectAtIndex:2]
#define SBWSuspendedEventOnlyDisplayStack (SBDisplayStack *)[displayStacks objectAtIndex:3]

#define SBApp(dispId) [CHSharedInstance(SBApplicationController) applicationWithDisplayIdentifier:dispId]

@implementation LAApplicationListener

+ (void)initialize
{
	sharedApplicationListener = [[self alloc] init];
}

+ (LAApplicationListener *)sharedInstance
{
	return sharedApplicationListener;
}

- (BOOL)activateApplication:(SBApplication *)application;
{
	SBApplication *springBoard = [CHSharedInstance(SBApplicationController) springBoard];
	if (!application)
		application = springBoard;
    SBApplication *oldApplication = [SBWActiveDisplayStack topApplication] ?: springBoard;
    if (oldApplication == application)
    	return NO;
	SBIcon *icon = [CHSharedInstance(SBIconModel) iconForDisplayIdentifier:[application displayIdentifier]];
	if (icon && [[LAActivator sharedInstance] currentEventMode] == LAEventModeSpringBoard)
		[icon launch];
	else {
		if (oldApplication == springBoard) {
			[application setDisplaySetting:0x4 flag:YES];
			[SBWPreActivateDisplayStack pushDisplay:application];
		} else if (application == springBoard) {
			[oldApplication setDeactivationSetting:0x2 flag:YES];
			[SBWActiveDisplayStack popDisplay:oldApplication];
			[SBWSuspendingDisplayStack pushDisplay:oldApplication];
		} else {
			[application setDisplaySetting:0x4 flag:YES];
			[application setActivationSetting:0x40 flag:YES];
			[application setActivationSetting:0x20000 flag:YES];
			[SBWPreActivateDisplayStack pushDisplay:application];
			[oldApplication setDeactivationSetting:0x2 flag:YES];
			[SBWActiveDisplayStack popDisplay:oldApplication];
			[SBWSuspendingDisplayStack pushDisplay:oldApplication];
		}
	}
	return YES;
}

- (void)activator:(LAActivator *)activator receiveEvent:(LAEvent *)event
{
	SBApplication *application = SBApp([activator assignedListenerNameForEvent:event]);
	if ([activator currentEventMode] == LAEventModeSpringBoard) {
		[self performSelector:@selector(activateApplication:) withObject:application afterDelay:0.0f];
		[event setHandled:YES];
	} else if ([self activateApplication:application]) {
		[event setHandled:YES];
	}
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedTitleForListenerName:(NSString *)listenerName
{
	return [SBApp(listenerName) displayName];
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedGroupForListenerName:(NSString *)listenerName
{
	if ([SBApp(listenerName) isSystemApplication])
		return [activator localizedStringForKey:@"LISTENER_GROUP_TITLE_System Applications" value:@"System Applications"];
	else
		return [activator localizedStringForKey:@"LISTENER_GROUP_TITLE_User Applications" value:@"User Applications"];
}

- (NSArray *)activator:(LAActivator *)activator requiresCompatibleEventModesForListenerWithName:(NSString *)name
{
	return [NSArray arrayWithObjects:LAEventModeSpringBoard, LAEventModeApplication, nil];
}

- (UIImage *)activator:(LAActivator *)activator requiresIconForListenerName:(NSString *)listenerName
{
	SBIcon *icon = [CHSharedInstance(SBIconModel) iconForDisplayIdentifier:listenerName];
	return [icon icon] ?: [UIImage imageWithContentsOfFile:[SBApp(listenerName) pathForIcon]];
}
- (UIImage *)activator:(LAActivator *)activator requiresSmallIconForListenerName:(NSString *)listenerName
{
	SBIcon *icon = [CHSharedInstance(SBIconModel) iconForDisplayIdentifier:listenerName];
	UIImage *result = [icon smallIcon];
	if (!result) {
		result = [UIImage imageWithContentsOfFile:[SBApp(listenerName) pathForSmallIcon]];
		if (!result) {
			result = [self activator:activator requiresIconForListenerName:listenerName];
			if (!result)
				return nil;
		}
	}
	CGSize size = [result size];
	if (size.width > 29.0f || size.height > 29.0f) {
		size.width = 29.0f;
		size.height = 29.0f;
		result = [result _imageScaledToSize:size interpolationQuality:kCGInterpolationDefault];
	}
	return result;
}

@end

CHOptimizedMethod(8, self, id, SBApplication, initWithBundleIdentifier, NSString *, bundleIdentifier, roleIdentifier, NSString *, roleIdentifier, path, NSString *, path, bundle, id, bundle, infoDictionary, NSDictionary *, infoDictionary, isSystemApplication, BOOL, isSystemApplication, signerIdentity, id, signerIdentity, provisioningProfileValidated, BOOL, validated)
{
	if ((self = CHSuper(8, SBApplication, initWithBundleIdentifier, bundleIdentifier, roleIdentifier, roleIdentifier, path, path, bundle, bundle, infoDictionary, infoDictionary, isSystemApplication, isSystemApplication, signerIdentity, signerIdentity, provisioningProfileValidated, validated))) {
		if (isSystemApplication) {
			NSString *displayIdentifier = [self displayIdentifier];
			if ([displayIdentifier isEqualToString:@"com.apple.DemoApp"] ||
				[displayIdentifier isEqualToString:@"com.apple.fieldtest"] ||
				[displayIdentifier isEqualToString:@"com.apple.springboard"] ||
				[displayIdentifier isEqualToString:@"com.apple.WebSheet"]
			) {
				return self;
			}
			if (![[NSFileManager defaultManager] fileExistsAtPath:[bundle executablePath]]) {
				return self;
			}
		}
		NSString *listenerName = [self displayIdentifier];
		LAActivator *activator = [LAActivator sharedInstance];
		if (![activator listenerForName:listenerName])
			[activator registerListener:[LAApplicationListener sharedInstance] forName:listenerName];
	}
	return self;
}

CHOptimizedMethod(0, self, void, SBApplication, dealloc)
{
	[applications removeObjectForKey:[self displayIdentifier]];
	CHSuper(0, SBApplication, dealloc);
}

CHOptimizedMethod(0, self, id, SBDisplayStack, init)
{
	if ((self = CHSuper(0, SBDisplayStack, init))) {
		if (!displayStacks)
			displayStacks = (NSMutableArray *)CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
		[displayStacks addObject:self];
	}
	return self;
}

CHOptimizedMethod(0, self, void, SBDisplayStack, dealloc)
{
	[displayStacks removeObject:self];
	CHSuper(0, SBDisplayStack, dealloc);
}

CHConstructor {
	CHLoadLateClass(SBApplicationController);
	CHLoadLateClass(SBApplication);
	CHHook(8, SBApplication, initWithBundleIdentifier, roleIdentifier, path, bundle, infoDictionary, isSystemApplication, signerIdentity, provisioningProfileValidated);
	CHHook(0, SBApplication, dealloc);
	CHLoadLateClass(SBDisplayStack);
	CHHook(0, SBDisplayStack, init);
	CHHook(0, SBDisplayStack, dealloc);
	CHLoadLateClass(SBIconModel);
}
