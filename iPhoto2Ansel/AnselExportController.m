//
//  AnselExportController.m
//  iPhoto2Ansel
//
//  Created by Michael Rubinsky on 10/23/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//
#import "TURAnsel.h";
#import "TURAnselGallery.h";
#import "AnselExportController.h";
#import "TURAnselGalleryPanelController.h";
#import "FBProgressController.h";
#import "ImageResizer.h";

@interface AnselExportController (PrivateAPI)
- (void)showNewServerSheet;
- (void)doConnect;
- (void)connect;
- (void)disconnect;
- (void)postProgressStatus:(NSString *)status;
- (void)privatePerformExport;
- (void)runExport;
- (void)canExport;
- (void)setStatusText: (NSString *)message withColor:(NSColor *)theColor;
- (void)setStatusText: (NSString *)message;
@end

// User default keys
NSString * const TURAnselServersKey = @"AnselServers";
NSString * const TURAnselExportSize = @"AnselExportSize";

// Server property keys
NSString * const TURAnselServerNickKey = @"nickname";
NSString * const TURAnselServerEndpointKey = @"endpoint";
NSString * const TURAnselServerUsernameKey = @"username";
NSString * const TURAnselServerPasswordKey = @"password";


@implementation AnselExportController

@synthesize currentGallery;

#pragma mark Overrides
/**
 * Set up UI defaults
 */
- (void)awakeFromNib
{
    // Register Application Defaults
    NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];
    [defaultValues setObject: [NSNumber numberWithInt: 2]
                      forKey: TURAnselExportSize];    
    [defaultValues setObject: [[NSMutableArray alloc] init] forKey: TURAnselServersKey];
    NSUserDefaults *userPrefs = [NSUserDefaults standardUserDefaults];
    [userPrefs registerDefaults: defaultValues];
        
    // UI Defaults
    [mSizePopUp selectItemWithTag: [userPrefs integerForKey:TURAnselExportSize]];
    [self setStatusText: @"Not Connected" withColor: [NSColor redColor]];
    [spinner stopAnimation: self];
    
    // For now, update the user pref for size every time it changes - will
    // eventually put this in a pref sheet.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(sizeChoiceWillChange:)
                                               name: @"NSPopUpButtonWillPopUpNotification"
                                             object: nil];
    
    // See if we have any configured servers (need a mutable array, hence the extra step here)
    anselServers = [[NSMutableArray alloc] initWithArray: [userPrefs objectForKey:TURAnselServersKey]];
    
    // Wait until iPhoto's export window is fully loaded before attempting a sheet
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(exportWindowDidBecomeKey:)
                                                 name: NSWindowDidBecomeKeyNotification 
                                               object :nil];
}
-(void)dealloc
{
    //anselController is released from the AnselController delegate method.
    [progressController release];
    [anselServers release];
    [currentServer release];
    [super dealloc];
}

#pragma mark Getter Setters
- (NSWindow *)window {
    return [mExportMgr window];
}

#pragma mark Actions
// Put up the newGallerySheet NSPanel
- (IBAction)showNewGallery: (id)sender
{
    TURAnselGalleryPanelController *newGalleryController;
    NSString *albumName;
    
    // Make sure we're not doing this for nothing
    if ([anselController state] == TURAnselStateConnected) {
        
        // It *looks* like index 0 is the first selected album?
        albumName = [mExportMgr albumNameAtIndex: 0];
        newGalleryController = [[TURAnselGalleryPanelController alloc] initWithController: anselController
                                                                          withGalleryName: albumName
                                                                   withGalleryDescription: [mExportMgr albumCommentsAtIndex:0]];
        [newGalleryController setDelegate: self];
        [newGalleryController showSheetForWindow: [self window]];
    }
}

- (IBAction)clickServer: (id)sender
{
      // Servers list
//    if ([mServersPopUp indexOfSelectedItem] == [mServersPopUp numberOfItems] - 1) {
//        [galleryListTable reloadData];
//        [NSApp beginSheet:galleryListPanel modalForWindow:[exportManager window] modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
//    }
    
    // Add new server
    if ([mServersPopUp indexOfSelectedItem] == [mServersPopUp numberOfItems] - 1) {
        [self showNewServerSheet];
    } else if (![[[mServersPopUp selectedItem] title] isEqual:@"(None)"]) {
            
        if (currentServer == [[mServersPopUp selectedItem] representedObject]) {
            return;
        }
        [self disconnect];
        currentServer = [[mServersPopUp selectedItem] representedObject];
        [self doConnect];
    }
}

// Server setup sheet
-(IBAction)doAddServer: (id)sender
{
    // Sanity Checking
    // TODO - make sure we don't have more than one gallery with the same nick??
//    if (![[serverNickName stringValue] length]) {
//        // TODO: Errors - for now, just silently fail, yea, I know....
//        return;
//    }

    NSDictionary *newServer = [[NSDictionary alloc] initWithObjectsAndKeys:
                               [serverNickName stringValue], TURAnselServerNickKey,
                               [anselHostURL stringValue], TURAnselServerEndpointKey,
                               [username stringValue], TURAnselServerUsernameKey,
                               [password stringValue], TURAnselServerPasswordKey,
                                nil];
    [anselServers addObject: newServer];
    [NSApp endSheet: newServerSheet];
    [newServerSheet orderOut: nil];
    
    [self disconnect];
    currentServer = [newServer retain];
    [self doConnect];
    
    // Save it to the userdefaults
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:anselServers  forKey:TURAnselServersKey];
    [mServers reloadData];
    [newServer release];
}

- (IBAction)doCancelAddServer: (id)sender
{
    [NSApp endSheet: newServerSheet];
    [newServerSheet orderOut: nil];
}

#pragma mark ExportPluginProtocol
// Initialize
- (id)initWithExportImageObj:(id <ExportImageProtocol>)obj
{
    if (self = [super init])
    {
        mExportMgr = obj;
    }
    
    [mExportMgr disableControls];
    return self;
}

- (NSView <ExportPluginBoxProtocol> *)settingsView
{
    return mSettingsBox;
}
- (NSView *)firstView
{
    return firstView;
}

// These seem to be called when the plugin panel is actived/deactivated while
// export screen is open, not when the plugin is finished.
- (void)viewWillBeActivated
{
    [self canExport];
}
- (void)viewWillBeDeactivated
{
}

// These are all pretty much moot for saving across the network, but are part
// of the protocol, so we must implement them.
- (NSString *)requiredFileType
{
    return @"";
}
- (BOOL)wantsDestinationPrompt
{
    return NO;
}
- (NSString*)getDestinationPath
{
    return @"";
}
- (NSString *)defaultFileName
{
    return @"";
}
- (NSString *)defaultDirectory
{
    return @"";
}
- (BOOL)treatSingleSelectionDifferently
{
    return NO;
}
- (BOOL)validateUserCreatedPath:(NSString*)path
{
    return NO;
}

// No movies allowed, at least for now ;)
- (BOOL)handlesMovieFiles
{
    return NO;
}

// Export was clicked in the UI.
// noop for us.
- (void)clickExport
{
}


// Export was clicked in the UI
// Do any preperations/validations and call our own privatePerformExport
// (We don't want the iPhoto progress controller).
- (void)startExport:(NSString *)path
{
    [self privatePerformExport];
}

// We use our own class for this so we don't use iPhoto's progress controller.
- (void)performExport: (NSString *)path
{
}

#pragma mark Progress (We don't use these)
- (ExportPluginProgress *)progress
{
    return &progress;
}
- (void)lockProgress
{
    [progressLock lock];
}
- (void)unlockProgress
{
    [progressLock unlock];
}
- (void)cancelExport
{
    cancelExport = YES;
}

// Return the name of our plugin.
- (NSString *)name
{
    return @"iPhoto2Ansel Export Plugin v1.0";
}

#pragma mark PrivateAPI
- (void) showNewServerSheet
{
    [NSApp beginSheet: newServerSheet
       modalForWindow: [self window]
        modalDelegate: nil
       didEndSelector: nil
          contextInfo: nil];
}

// See if we have everything we need to export...
- (void)canExport
{
    if ([anselController state] == TURAnselStateConnected) {
        [newGalleryButton setEnabled: YES];
        [galleryCombo setEnabled: YES];
        if (currentGallery != nil) {
            [mExportMgr enableControls];
        }
    } else {
        [newGalleryButton setEnabled: NO];
        [mExportMgr disableControls];   
        [galleryCombo setEnabled: YES];
    }
}

- (void)updateServersPopupMenu
{
    [mServersPopUp removeAllItems];
    for (NSDictionary *server in anselServers) {
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle: [server objectForKey: TURAnselServerNickKey]
                                                          action: nil
                                                   keyEquivalent: @""];
        [menuItem setRepresentedObject: server];
        [[mServersPopUp menu] addItem: menuItem];
    }
    if ([anselServers count] == 0) {
        [mServersPopUp addItemWithTitle:@"(None)"];
       //[mainStatusString setStringValue:@"No galleries configured"];
    }
    
    // add separator
    [[mServersPopUp menu] addItem:[NSMenuItem separatorItem]];
    
    // add Add Gallery... and Edit List... options
    [mServersPopUp addItemWithTitle:@"Add Server..."];
    //[mServersPopUp addItemWithTitle:@"Edit Server List..."];
    
    // fix selection
    [mServersPopUp selectItemAtIndex:0];
}

// Make sure we clean up from any previous connection
-(void)disconnect
{
    [galleryCombo setDelegate: nil];
    [galleryCombo setDataSource: nil];

    [currentServer release];
    currentServer = nil;
    [anselController release];
    anselController = nil;
    [self setStatusText:@"Not logged in" withColor: [NSColor redColor]];
}

// Start the connection process.
-(void)doConnect
{
    [self setStatusText: @"Connecting..."];
    [spinner startAnimation: self];
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *p = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects:
                                                              [currentServer objectForKey:TURAnselServerEndpointKey],
                                                              [currentServer objectForKey:TURAnselServerUsernameKey],
                                                              [currentServer objectForKey:TURAnselServerPasswordKey]]
                                                    forKeys: [NSArray arrayWithObjects:@"endpoint", @"username", @"password", nil]];
    // Create our controller
    anselController = [[TURAnsel alloc] initWithConnectionParameters:p];
    [anselController setDelegate:self];
    
    // Set up the galleryCombo
    [galleryCombo setUsesDataSource:YES];
    [galleryCombo setDataSource:anselController];
    [galleryCombo setDelegate:self];
    [spinner startAnimation:self];
    // Detach to a new thread and do the actual login/retrieval of gallery list
    [NSApplication detachDrawingThread: @selector(connect)
                              toTarget: self 
                            withObject: nil];
    [p release];
    [pool release];
}

// Runs in a new thread.
- (void)connect
{
    [anselController connect];
}

// Update our progress controller. Always update on the main thread.
- (void)postProgressStatus:(NSString *)status {
    [progressController performSelectorOnMainThread: @selector(setStatus:) withObject: status waitUntilDone: NO];
}

// This is our own version of performExport. We aren't using iPhoto's progress
// indicator, so we can't tell it we are running...
- (void)privatePerformExport
{
    cancelExport = NO;
    
    // Init our own progress controller.
    if (progressController == nil) {
        progressController = [[FBProgressController alloc] initWithFBExport: self];
    }
    [progressController startProgress];
    [progressController setStatus: @"Starting export"];    
    
    // Detach to a new thread for the export.
    [NSApplication detachDrawingThread: @selector(runExport) 
                              toTarget: self
                            withObject: nil];
}
        
// Runs the actual export (This is run in it's own thread)
- (void) runExport
{   
    // Init the progress bar and image counts.
    int count = [mExportMgr imageCount];
    currentImageCount = 0;   
    int i = 0;
    while (i < count && !cancelExport == YES) {
        // Don't hog memory...
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        // use 99% max so the last photo upload doesn't make the progress bar look finished
        // (Thanks to Facebook exporter for this tip and code)
        double progressPercent = (double) 99. * (i+1) / count;

        [progressController performSelectorOnMainThread: @selector(setPercent:) 
                                             withObject: [NSNumber numberWithDouble: progressPercent]
                                          waitUntilDone: NO];
        
        // Prepare the image data
        NSData *theImage = [[NSData alloc] initWithContentsOfFile: [mExportMgr imagePathAtIndex:i]];
        
        CGFloat imageSize;
        switch([mSizePopUp selectedTag])
        {
            case 0:
                imageSize = 320;
                break;
            case 1:
                imageSize = 640;
                break;
            case 2:
                imageSize = 1280;
                break;
            case 3:
                imageSize = 99999;
                break;
            default:
                imageSize = 1280;
                break;
        }
        
        
        [self postProgressStatus: [NSString stringWithFormat: @"Resizing image %d out of %d", (i+1), count]];
        NSData *scaledData = [ImageResizer getScaledImageFromData: theImage
                                                           toSize: NSMakeSize(imageSize, imageSize)];

        [self postProgressStatus: [NSString stringWithFormat: @"Encoding image %d out of %d", (i+1), count]];
        NSString *base64ImageData = [NSString base64StringFromData: scaledData  
                                                            length: [scaledData length]];
        
        // Get the filename/path for this image. This returns either the most
        // recent version of the image, the original, or (if RAW) the jpeg 
        // version of the original. Still need to figure out how to modify
        // the image size/quality etc... when not doing a file export.
        NSString *filename = [mExportMgr imageFileNameAtIndex:i];
        NSString *imageDescription = [mExportMgr imageTitleAtIndex:i];
        NSArray *keywords = [mExportMgr imageKeywordsAtIndex: i];
        
        NSLog(@"Keywords: %@", keywords);
        NSArray *keys = [[NSArray alloc] initWithObjects:
                         @"filename", @"description", @"data", @"type", @"tags", nil];
        
        NSString *fileType = NSFileTypeForHFSTypeCode([mExportMgr imageFormatAtIndex:i]);
        NSArray *values = [[NSArray alloc] initWithObjects:
                           filename,
                           imageDescription,
                           base64ImageData,
                           fileType,
                           keywords,
                           nil];
        
        NSDictionary *imageData = [[NSDictionary alloc] initWithObjects:values
                                                                forKeys:keys];
        NSDictionary *params = [[NSDictionary alloc] initWithObjectsAndKeys:
                                imageData, @"data", 
                                [NSNumber numberWithBool:NO], @"default",
                                nil];
        
        //Start upload with current gallery.
        [self postProgressStatus: [NSString stringWithFormat: @"Uploading photo %d out of %d", (i+1), count]];
        [currentGallery uploadImageObject: params];
        [keys release];
        [values release];
        [imageData release];
        [params release];
        [pool release];
        i++;
    }
    
    // We are done - kill the progress controller and close the export window.
    [progressController performSelectorOnMainThread: @selector(setPercent:)
                                         withObject: nil 
                                      waitUntilDone: NO];
    
    [progressController performSelectorOnMainThread: @selector(stopProgress) 
                                         withObject: nil 
                                      waitUntilDone: YES];
    
    [progressController release];
    progressController = nil;
    
    // Need to do this ourselves since we aren't using iPhoto's progress bar.
    // Not really cancelling the export, but all this method does is close
    // the export interface and notify iPhoto that we are done.
    [mExportMgr cancelExportBeforeBeginning];
}

- (void)setStatusText: (NSString *)message withColor:(NSColor *)theColor
{
    [statusLabel setStringValue: message];
    [statusLabel setTextColor: theColor];
}
- (void)setStatusText: (NSString *)message
{
    [statusLabel setStringValue: message];
    [statusLabel setTextColor: [NSColor blackColor]];
}

#pragma mark TURAnselDelegate

// The ansel controller is initialized, populate the gallery data
// and update the UI.
- (void)TURAnselDidInitialize
{   
    [galleryCombo reloadData];
    [self setStatusText: @"Connected" withColor: [NSColor greenColor]];
    [self canExport];
    [spinner stopAnimation: self];
}

- (void)TURAnselHadError: (NSError *)error
{
    // Stop the spinner
    [spinner stopAnimation: self];
    [self disconnect];
    
    NSAlert *alert;
    // For some reason, this method doesn't pick up our userInfo dictionary...
    if ([[error userInfo] valueForKey:@"NSLocalizedDescriptionKey"] == nil) {
        alert = [[NSAlert alertWithError: error] retain];
        [mExportMgr disableControls];
    } else {
        alert = [[NSAlert alloc] init];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert setMessageText:[[error userInfo] valueForKey:@"NSLocalizedDescriptionKey"]];
        if ([[error userInfo] valueForKey: @"NSLocalizedRecoverySuggestionErrorKey"] != nil) {
            [alert setInformativeText: [[error userInfo] valueForKey: @"NSLocalizedRecoverySuggestionErrorKey"]];
        }
    }
    
    [alert beginSheetModalForWindow:[self window]
                      modalDelegate:nil
                     didEndSelector:nil
                        contextInfo:nil];
    [mExportMgr disableControls];
    [alert release];
}

#pragma mark TURAnselGalleryDelegate
- (void)TURAnselGalleryDidUploadImage: (TURAnselGallery *)gallery {
    if (++currentImageCount == [mExportMgr imageCount] || cancelExport == YES) {
        [currentGallery setDelegate:nil];
        [currentGallery release];
        [anselController setDelegate:nil];
        [anselController release];
        [galleryCombo setDelegate:nil];
    }
}

#pragma mark comboBoxDelegate
// Probably should have a seperate controller for each combobox, but this is
// pretty small stuff...
- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{    
    // Yes, I'm comparing the pointers here on purpose
    if ([notification object] == galleryCombo) {
        int row = [galleryCombo indexOfSelectedItem];
        [currentGallery setDelegate:nil];
        [currentGallery autorelease];
        currentGallery = [[anselController getGalleryByIndex:row] retain];
        [currentGallery setDelegate: self];
        NSImage *theImage = [[NSImage alloc] initWithContentsOfURL: [currentGallery galleryDefaultImageURL]];
        [defaultImageView setImage: theImage];
        [theImage release];
        [self canExport];
    }
}

#pragma mark TURAnselGalleryPanel Notifications
- (void)TURAnselGalleryPanelDidAddGallery
{
    // Reload the NSComboBox and autoselect the last item.
    [galleryCombo reloadData];
    [galleryCombo selectItemAtIndex: [galleryCombo numberOfItems] - 1];
}

#pragma mark export notifications
- (void)exportWindowDidBecomeKey: (NSNotification *)notification
{
    // We only want to do this once...
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: NSWindowDidBecomeKeyNotification 
                                                  object: nil];
    [self updateServersPopupMenu];
    if ([anselServers count] == 0) {
        [self showNewServerSheet];
    } else {
        // Autoconnect to default server. For now, just make it the first one.
        currentServer = [[mServersPopUp selectedItem] representedObject];
        [self doConnect];
    }
}
- (void)sizeChoiceWillChange: (NSNotification *)notification
{
    NSInteger newSize = [mSizePopUp selectedTag];
    NSUserDefaults *userPrefs = [NSUserDefaults standardUserDefaults]; 
    [userPrefs setInteger: newSize forKey:TURAnselExportSize];
    [userPrefs synchronize];
}

#pragma mark NSComboBoxDatasource delegates (used for server list)
- (id)comboBox: (NSComboBox *)aComboBox objectValueForItemAtIndex: (NSInteger)index
{
    NSDictionary *server = [anselServers objectAtIndex: index];
    return [server objectForKey:TURAnselServerNickKey];
}
- (NSInteger)numberOfItemsInComboBox: (NSComboBox *)aComboBox
{
    return [anselServers count];
}
@end