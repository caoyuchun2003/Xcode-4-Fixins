#import <Cocoa/Cocoa.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/objc-runtime.h>
#import <objc/runtime.h>

#include <sys/stat.h>

#import "XCFixin.h"

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

static NSString *GetObjectDescription(id obj)
{
	if(!obj)
		return @"nil";
	else
		return [NSString stringWithFormat:@"(%s *)%p: %@",class_getName([obj class]),obj,obj];
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

static NSTextView *FindIDETextView(void)
{
	NSWindow *mainWindow=[[NSApplication sharedApplication] mainWindow];
	if(!mainWindow)
	{
		NSLog(@"Can't find IDE text view - no main window.\n");
		return nil;
	}
	
	if(![mainWindow isKindOfClass:objc_getClass("IDEWorkspaceWindow")])
	{
		NSLog(@"Can't find IDE text view - main window is class %@.\n",[mainWindow class]);
		return nil;
	}
	
	id windowController=objc_msgSend(objc_getClass("IDEWorkspaceWindowController"),
									 @selector(workspaceWindowControllerForWindow:),
									 (id)mainWindow);
	//NSLog(@"%s: wc=%p (%s)\n",__FUNCTION__,wc,class_getName([wc class]));
	if(!windowController)
	{
		NSLog(@"Can't find IDE text view - no window controller.\n");
		return nil;
	}
	
	id tabController=objc_msgSend(windowController,@selector(activeWorkspaceTabController));
	//NSLog(@"%s: tc=%p (%s)\n",__FUNCTION__,tc,class_getName([tc class]));
	if(!tabController)
	{
		NSLog(@"Can't find IDE text view - no tab controller.\n");
		return nil;
	}
	
	id editorArea=objc_msgSend(tabController,@selector(editorArea));
	//NSLog(@"%s: ea=%p (%s)\n",__FUNCTION__,editorArea,class_getName([ea class]));
	if(!editorArea)
	{
		NSLog(@"Can't find IDE text view - no editor area.\n");
		return nil;
	}
	
	id primaryEditorContext=objc_msgSend(editorArea,@selector(primaryEditorContext));
	if(!primaryEditorContext)
	{
		NSLog(@"Can't find IDE text view - no primary editor context.\n");
		return nil;
	}
	
	if(![primaryEditorContext isKindOfClass:objc_getClass("IDEEditorContext")])
	{
		NSLog(@"Can't find IDE text view - primary editor context is class %@.\n",[mainWindow class]);
		return nil;
	}
	
	id editor=objc_msgSend(primaryEditorContext,@selector(editor));
	if(!editor)
	{
		NSLog(@"Can't find IDE text view - no primary editor context editor.\n");
		return nil;
	}
	
	if([editor isKindOfClass:objc_getClass("IDESourceCodeEditor")])
	{
		id textView=objc_msgSend(editor,@selector(textView));
		if(!textView)
		{
			NSLog(@"Can't find IDE text view - primary editor context's IDESourceCodeEditor editor has nil text view.\n");
			return nil;
		}
		
		return textView;
	}
	else if([editor isKindOfClass:objc_getClass("IDEComparisonEditor")])
	{
		id keyEditor=objc_msgSend(editor,@selector(keyEditor));
		if(!keyEditor)
		{
			NSLog(@"Can't find IDE text view - primary editor context's IDEComparisonEditor has nil keyEditor.\n");
			return nil;
		}

		if(![keyEditor isKindOfClass:objc_getClass("IDESourceCodeEditor")])
		{
			NSLog(@"Can't find IDE text view - primary editor context's IDEComparisonEditor keyEditor is class %@.\n",[keyEditor class]);
			return nil;
		}
		
		id textView=objc_msgSend(keyEditor,@selector(textView));
		if(!textView)
		{
			NSLog(@"Can't find IDE text view - primary editor context's IDEComparisonEditor IDESourceCodeEditor keyEditor has nil text view.\n");
			return nil;
		}

		return textView;
	}
	else
	{
		NSLog(@"Can't find IDE text view - primary editor context's editor is unsupported class %@.\n",[editor class]);
		return nil;
	}
	
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

enum ScriptStdinMode
{
	SSM_NONE,
	SSM_SELECTION,
	SSM_LINETEXT_OR_SELECTION,
	SSM_LINE_OR_SELECTION,
};
typedef enum ScriptStdinMode ScriptStdinMode;

//////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////

@interface XCFixin_Script:NSObject
{
	NSString *fileName_;
	ScriptStdinMode stdinMode_;
}
@end

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

@implementation XCFixin_Script

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

-(id)initWithFileName:(NSString *)fileName
{
	if((self=[super init]))
	{
		fileName_=[fileName retain];
		stdinMode_=SSM_SELECTION;
	}
	
	return self;
}

//////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////

-(void)setStdinMode:(ScriptStdinMode)stdinMode
{
	stdinMode_=stdinMode;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

static NSRange NSMakeRangeFromStartAndEnd(NSUInteger start,NSUInteger end)
{
	NSRange r;
	
	r.location=start;
	r.length=end-start;
	
	return r;
}

-(void)run
{
	NSLog(@"%s: path=%@\n",__FUNCTION__,fileName_);
	
	NSTextView *textView=FindIDETextView();
	if(!textView)
	{
		NSLog(@"Not running scripts - can't find IDE text view.\n");
		return;
	}
	
	NSTextStorage *textStorage=[textView textStorage];
	if(!textStorage)
	{
		NSLog(@"Not running scripts - IDE text view has no text storage.\n");
		return;
	}

	NSString *inputStr=nil;
	NSData *inputData=nil;
	NSRange inputRange=[textView selectedRange];
	{
		NSString *textStorageString=[textStorage string];
		
		switch(stdinMode_)
		{
			case SSM_LINETEXT_OR_SELECTION:
			case SSM_LINE_OR_SELECTION:
				if(inputRange.length==0)
				{
					NSUInteger startIndex,contentsEndIndex,endIndex;
					[textStorageString getLineStart:&startIndex
												end:&endIndex
										contentsEnd:&contentsEndIndex
										   forRange:inputRange];
					
					inputRange.location=startIndex;
					
					if(stdinMode_==SSM_LINE_OR_SELECTION)
						inputRange.length=endIndex-startIndex;
					else
						inputRange.length=contentsEndIndex-startIndex;
				}
				
				// fall through
			case SSM_SELECTION:
				inputStr=[textStorageString substringWithRange:inputRange];
				inputData=[inputStr dataUsingEncoding:NSUTF8StringEncoding];
				
				// fall through
			default:
				break;
		}
	}
	
	NSTask *task=[[[NSTask alloc] init] autorelease];
	
	[task setLaunchPath:fileName_];
	NSLog(@"%s: [task launchPath] = %@\n",__FUNCTION__,[task launchPath]);
	
	NSPipe *stdinPipe=[NSPipe pipe];
	NSPipe *stdoutPipe=[NSPipe pipe];
	NSPipe *stderrPipe=[NSPipe pipe];
	
	[task setStandardOutput:stdoutPipe];
	[task setStandardInput:stdinPipe];
	[task setStandardError:stderrPipe];
	
	int exitCode=0;
	NSData *outputData=nil;
	
	@try
	{
		NSLog(@"%s: launching task...\n",__FUNCTION__);
		[task launch];
		NSLog(@"%s: task launched.\n",__FUNCTION__);
		
		if(inputData)
		{
			@try
			{
				NSLog(@"%s: writing %u bytes to task's stdin...\n",__FUNCTION__,[inputData length]);
				[[stdinPipe fileHandleForWriting] writeData:inputData];
				NSLog(@"%s: wrote to task's stdin.\n",__FUNCTION__);
			}
			@catch(NSException *e)
			{
				// Maybe the task finished really quickly and it doesn't care what's in its stdin.
				NSLog(@"%s: ignoring error (%@) writing to task's stdin.\n",__FUNCTION__,e);
			}
		}
		
		[[stdinPipe fileHandleForWriting] closeFile];
		
		@try
		{
			NSLog(@"%s: reading from task's stdout...\n",__FUNCTION__);
			outputData=[[stdoutPipe fileHandleForReading] readDataToEndOfFile];
			NSLog(@"%s: read %u bytes from task's stdout.\n",__FUNCTION__,[outputData length]);
		}
		@catch(NSException *e)
		{
			NSLog(@"%s: error (%@) reading from task's stdout.\n",__FUNCTION__,e);
		}
		
		NSLog(@"%s: waiting for task exit...\n",__FUNCTION__);
		[task waitUntilExit];
		NSLog(@"%s: task exit.\n",__FUNCTION__);
		
		exitCode=[task terminationStatus];
		if(exitCode!=0)
			NSLog(@"Script failed - exit code %d.\n",exitCode);
	}
	@catch(NSException *e)
	{
		if([[e name] isEqualToString:@"NSInvalidArgumentException"])
		{
			exitCode=-1;
		
			NSLog(@"Script launch failed.\n");
		}
		else
			@throw e;
	}
	@finally
	{
	}
	
	if(exitCode!=0)
		outputData=nil;
	
	if(outputData)
	{
		NSString *selectionMarker=@"%%\x25{PBXSelection}%%%";
		
		NSString *outputStr=[[[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] autorelease];
		
		NSRange a;//before 1st marker
		NSRange b;//between 1st marker and 2nd marker (selection goes here)
		NSRange c;//after 2nd marker
		
		NSRange r1=[outputStr rangeOfString:selectionMarker
									options:NSLiteralSearch
									  range:NSMakeRangeFromStartAndEnd(0,
																	   [outputStr length])];
		
		if(r1.location==NSNotFound)
		{
			// no selection anywhere
			a=NSMakeRangeFromStartAndEnd(0,
										 [outputStr length]);
			c=b=NSMakeRange([outputStr length],
							0);
		}
		else
		{
			a=NSMakeRangeFromStartAndEnd(0,
										 r1.location);
			
			NSRange r2=[outputStr rangeOfString:selectionMarker
										options:NSLiteralSearch
										  range:NSMakeRangeFromStartAndEnd(r1.location+[selectionMarker length],
																		   [outputStr length])];
			
			if(r2.location==NSNotFound)
			{
				b=NSMakeRange(r1.location+[selectionMarker length],
							  0);
				c=NSMakeRangeFromStartAndEnd(r1.location+[selectionMarker length],
											 [outputStr length]);
			}
			else
			{
				b=NSMakeRangeFromStartAndEnd(r1.location+[selectionMarker length],
											 r2.location);
				c=NSMakeRangeFromStartAndEnd(r2.location+[selectionMarker length],
											 [outputStr length]);
			}
		}
		
		outputStr=[[[outputStr substringWithRange:a] stringByAppendingString:[outputStr substringWithRange:b]] stringByAppendingString:[outputStr substringWithRange:c]];
		
		[textView breakUndoCoalescing];
		
		// don't insert text if the two strings are actually the same.
		//
		// this is a fix for scripts that just pop a %%%{PBXSeleciton}%%%
		// into their input to put the cursor somewhere.
		if(![outputStr isEqualToString:inputStr])
		{
			[textView insertText:outputStr
				replacementRange:inputRange];
		}
		
		[textView setSelectedRange:NSMakeRange(inputRange.location+a.length,
											   b.length)];
	}
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

-(void)dealloc
{
	NSLog(@"%s: (%s *)%p: %@\n",__FUNCTION__,class_getName([self class]),self,fileName_);
	
	[fileName_ release];
	fileName_=nil;
	
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

@end

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

@interface XCFixin_ScriptsHandler:NSObject

@end

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

@implementation XCFixin_ScriptsHandler

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

static NSString *SystemFolderName(int folderType,int domain)
{
	OSErr err;
	
	FSRef folder;
	err=FSFindFolder(domain,folderType,kCreateFolder,&folder);
	if(err!=noErr)
		return nil;
	
	CFURLRef url=CFURLCreateFromFSRef(kCFAllocatorDefault,&folder);
	NSString *result=[(NSURL *)url path];
	CFRelease(url);
	
	return result;
}

-(void)refreshScriptsMenu
{
	NSMenu *mainMenu=[NSApp mainMenu];
	if(!mainMenu)
	{
		NSLog(@"%s: main menu not found.\n",__FUNCTION__);
		return;
	}
	
	int scriptsMenuIndex=[mainMenu indexOfItemWithTitle:@"Scripts"];
	if(scriptsMenuIndex<0)
	{
		NSLog(@"%s: Scripts menu not found.\n",__FUNCTION__);
		return;
	}
	
	NSMenu *scriptsMenu=[[mainMenu itemAtIndex:scriptsMenuIndex] submenu];
	
	//
	[scriptsMenu removeAllItems];
	
	NSString *appSupportFolderName=SystemFolderName(kApplicationSupportFolderType,kUserDomain);
	NSLog(@"appSupportFolderName=%@\n",appSupportFolderName);
	
	NSString *scriptsFolderName=[NSString pathWithComponents:[NSArray arrayWithObjects:appSupportFolderName,@"Developer/Shared/Xcode/Scripts",nil]];
	NSLog(@"scriptsFolderName=%@\n",scriptsFolderName);
	
	NSString *scriptsPListName=[NSString pathWithComponents:[NSArray arrayWithObjects:scriptsFolderName,@"Scripts.xml",nil]];
	NSLog(@"scriptsPListName=%@\n",scriptsPListName);
	NSDictionary *scriptsProperties=[NSDictionary dictionaryWithContentsOfFile:scriptsPListName];
	if(!scriptsProperties)
		NSLog(@"%s: No scripts plist loaded.\n",__FUNCTION__);
	else
		NSLog(@"%s: Scripts plist: %@\n",__FUNCTION__,scriptsProperties);

	NSArray *scriptsFolderContents=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:scriptsFolderName
																					   error:nil];
	if([scriptsFolderContents count]>0)
	{
		NSMutableArray *scripts=[NSMutableArray arrayWithCapacity:0];
		
		NSFileManager *defaultManager=[NSFileManager defaultManager];
		
		for(NSUInteger i=0;i<[scriptsFolderContents count];++i)
		{
			NSString *name=[scriptsFolderContents objectAtIndex:i];
			NSString *path=[NSString pathWithComponents:[NSArray arrayWithObjects:scriptsFolderName,name,nil]];
			
			struct stat st;
			if(stat([path UTF8String],&st)!=0)
			{
				NSLog(@"%@: not a script (stat failed)\n",path);
				continue;
			}
			
			if(!(st.st_mode&(S_IFLNK|S_IFREG)))
			{
				NSLog(@"%@: not a script (not symlink or regular file)\n",path);
				continue;
			}
			
			if(![defaultManager isExecutableFileAtPath:path])
			{
				NSLog(@"%@: not a script (not executable)\n",path);
				continue;
			}
			
			[scripts addObject:name];
		}
		
		if([scripts count]>0)
		{
			for(NSUInteger scriptIdx=0;scriptIdx<[scripts count];++scriptIdx)
			{
				NSString *name=[scripts objectAtIndex:scriptIdx];
				NSString *path=[NSString pathWithComponents:[NSArray arrayWithObjects:scriptsFolderName,name,nil]];
				
				NSLog(@"Creating XCFixin_Script for %@.\n",path);
				XCFixin_Script *script=[[[XCFixin_Script alloc] initWithFileName:path] autorelease];
				
				NSMenuItem *scriptMenuItem=[[[NSMenuItem alloc] initWithTitle:name
																	   action:nil
																keyEquivalent:@""] autorelease];
				[scriptMenuItem setTarget:self];
				[scriptMenuItem setAction:@selector(runScriptAction:)];
				[scriptMenuItem setRepresentedObject:script];
				
				NSDictionary *scriptProperties=[scriptsProperties objectForKey:name];
				if(![scriptProperties isKindOfClass:[NSDictionary class]])
					scriptProperties=nil;
				
				NSLog(@"    Script properties: %@\n",scriptProperties);

				NSString *keyEquivalent=[scriptProperties objectForKey:@"keyEquivalent"];
				if(keyEquivalent&&[keyEquivalent length]>0)
				{
					// Yeah, OK, so I just completely could NOT work out how you're supposed to
					// do this officially. So you have to use emacs notation.
					//
					// C- = control
					// M- = Alt/Option ("Meta")
					// S- = Shift
					// s- = Command ("super")
					
					unsigned modifiers=0;
					
					for(NSUInteger i=0;i+1<[keyEquivalent length];i+=2)
					{
						char c=[keyEquivalent characterAtIndex:i];
						
						switch(c)
						{
							case 'C':
								modifiers|=NSControlKeyMask;
								break;
								
							case 'M':
								modifiers|=NSAlternateKeyMask;
								break;
								
							case 'S':
								modifiers|=NSShiftKeyMask;
								break;
								
							case 's':
								modifiers|=NSCommandKeyMask;
								break;
								
							default:
								// some kind of error here, or something??
								//
								// not like it's hard to spot or complicated to fix...
								break;
						}
					}
					
					[scriptMenuItem setKeyEquivalent:[keyEquivalent substringFromIndex:[keyEquivalent length]-1]];
					[scriptMenuItem setKeyEquivalentModifierMask:modifiers];
				}
				
				NSString *stdinMode=[scriptProperties objectForKey:@"stdinMode"];
				if(stdinMode)
				{
					if([stdinMode caseInsensitiveCompare:@"none"]==NSOrderedSame)
						[script setStdinMode:SSM_NONE];
					else if([stdinMode caseInsensitiveCompare:@"selection"]==NSOrderedSame)
						[script setStdinMode:SSM_SELECTION];
					else if([stdinMode caseInsensitiveCompare:@"lineorselection"]==NSOrderedSame)
						[script setStdinMode:SSM_LINE_OR_SELECTION];
					else if([stdinMode caseInsensitiveCompare:@"linetextorselection"]==NSOrderedSame)
						[script setStdinMode:SSM_LINETEXT_OR_SELECTION];
				}
				
				[scriptsMenu addItem:scriptMenuItem];
			}
		}
		
		if([scriptsMenu numberOfItems]>0)
			[scriptsMenu addItem:[NSMenuItem separatorItem]];
		
		[[scriptsMenu addItemWithTitle:@"Refresh"
								action:@selector(refreshScriptsMenuAction:)
						 keyEquivalent:@""] setTarget:self];
	}
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

-(IBAction)runScriptAction:(id)arg
{
	[[arg representedObject] run];
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

-(IBAction)refreshScriptsMenuAction:(id)arg
{
	[self refreshScriptsMenu];
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

-(BOOL)install
{
	NSMenu *mainMenu=[NSApp mainMenu];
	if(!mainMenu)
	{
		NSLog(@"%s: main menu not found!\n",__FUNCTION__);
		return NO;
	}
	
	NSInteger helpIndex=[mainMenu indexOfItemWithTitle:@"Help"];
	if(helpIndex<0)
		helpIndex=[mainMenu numberOfItems];
	
	NSMenuItem *scriptsMenuItem=[mainMenu insertItemWithTitle:@"Scripts"
													   action:NULL
												keyEquivalent:@""
													  atIndex:helpIndex];
	[scriptsMenuItem setEnabled:YES];
	
	NSMenu *scriptsMenu=[[[NSMenu alloc] initWithTitle:@"Scripts"] autorelease];
	[scriptsMenu setAutoenablesItems:YES];
	
	[scriptsMenuItem setSubmenu:scriptsMenu];
	
	[self refreshScriptsMenu];
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

-(BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	NSLog(@"%s: title=\"%@\"\n",__FUNCTION__,[menuItem title]);
	return YES;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

static BOOL GetClasses(const char *name0,...)
{
	va_list v;
	va_start(v,name0);
	
	for(const char *name=name0;name;name=va_arg(v,const char *))
	{
		Class *c=va_arg(v,Class *);
		
		*c=objc_getClass(name);
		if(!*c)
		{
			NSLog(@"FATAL: class %s not found.\n",name);
			return NO;
		}
	}
	
	return YES;
}

@end

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

@interface XCFixin_UserScripts : NSObject
@end

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

@implementation XCFixin_UserScripts

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

+ (void)pluginDidLoad: (NSBundle *)plugin
{
    XCFixinPreflight();
    
	XCFixin_ScriptsHandler *handler=[[XCFixin_ScriptsHandler alloc] init];
	if(!handler)
		NSLog(@"%s: handler init failed.\n",__FUNCTION__);
	else
	{
		BOOL goodInstall=[handler install];
		NSLog(@"%s: handler installed: %s\n",__FUNCTION__,goodInstall?"YES":"NO");
	}
    
    XCFixinPostflight();
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

@end
