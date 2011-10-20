/*
 
 IPAUTIL .ipa file utiltiy
  
 Copyright 2011 Naoshi Wakatabe. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are
 permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, this list of
 conditions and the following disclaimer.
 
 2. Redistributions in binary form must reproduce the above copyright notice, this list
 of conditions and the following disclaimer in the documentation and/or other materials
 provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY NAOSHI WAKATABE ''AS IS'' AND ANY EXPRESS OR IMPLIED
 WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL NAOSHI WAKATABE OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 The views and conclusions contained in the software and documentation are those of the
 authors and should not be interpreted as representing official policies, either expressed
 or implied, of Naoshi Wakatabe. 
*/


#import <Foundation/Foundation.h>
#import <getopt.h>
#import <archive.h>
#import <archive_entry.h>
#import <fnmatch.h>

#define IPU_EXIT_SUCCESS		0
#define IPU_EXIT_ERROR			1
#define IPU_EXIT_OPEN			2
#define IPU_EXIT_NO_MATCH_FILE	3
#define IPU_EXIT_NO_MATCH_KEY	4
#define IPU_EXIT_ARGUMENT		9

BOOL catFile = NO;	// set by -c. cat Info.plist (or any other matching file) to stdout.
BOOL showKeys = NO;	// set by -k. show Info.plist keys with values
NSMutableArray* infokeys = nil;	// set by -i's output Info.plist key path
NSString* pattern = @"Payload/*.app/Info.plist";	// set by -p. Info plist search pattern
BOOL listFiles = NO;	// list files in ipa file
BOOL quiet = NO;	// set by -q. quiet
BOOL xmlplist = NO;	// set by -x. dump plist to stdout as xml
BOOL noNewlineCharacters = NO; // set by -n. No newline character after value. 

/*
 * Format and write message to stderr, with va_list argument.
 */
static void messagev(const char* format, va_list marker)
{
	if (!quiet)
		vfprintf(stderr, format, marker);
}

/*
 * Format and write message to stderr, with variable length argument.
 */
static void message(const char* format, ...)
{
	va_list marker;
	va_start(marker, format);
	messagev(format, marker);
	va_end(marker);
}

/*
 * Format and write message to stdout, with va_list argument.
 */
static void outputv(const char* format, va_list marker)
{
	if (!quiet)
		vfprintf(stdout, format, marker);
}

/*
 * Format and write message to stdout, with variable length argument.
 */
static void output(const char* format, ...)
{
	va_list marker;
	va_start(marker, format);
	outputv(format, marker);
	va_end(marker);
}

/*
 * cat NSData to file pointer
 */
static void catData(FILE* out, NSData* data)
{
	const char* p = data.bytes;
	size_t len = data.length;
	while (len > 0) {
		ssize_t r = fwrite(p, 1, len, out);
		if (r <= 0)
			break;
		if (r > 0) {
			len -= r;
		}
	}
	if (ferror(out)) {
		message("Could not output to stdout\n");
		exit(IPU_EXIT_ERROR);
	}
}

/*
 * Process .ipa(tar.gz) file.
 */
static void parsetarball(FILE* fp, const char* filename)
{
	struct archive* ar;
	struct archive_entry *entry;
	int matches = 0;
	
	if ((ar = archive_read_new()) == NULL) {
		message("archive_read_new failed");
		exit(IPU_EXIT_ERROR);
	}
	archive_read_support_compression_all(ar);
	archive_read_support_format_all(ar);
	archive_read_open_FILE(ar, fp);
	while (archive_read_next_header(ar, &entry) == ARCHIVE_OK) {
		const char* path = archive_entry_pathname(entry);
		if (!catFile && listFiles) {
			// print pathname in tar
			output("%s\n", path);
		}
		if (fnmatch([pattern UTF8String], path, 0) == 0) {
			// make autoreleasee pool inside main loop to release it early.
			@autoreleasepool {
				NSMutableData* data = [NSMutableData data];
				ssize_t r;
				char buf[8192];
				while ((r = archive_read_data(ar, buf, sizeof(buf))) > 0) {
					[data appendBytes:buf length:r];
				}
				if (catFile) {
					catData(stdout, data);
				} else {
					id plist = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:0 format:NULL errorDescription:NULL];
					if (plist == nil) {
						message("%s in %s was not parsed as property list\n", path, filename);
						exit(IPU_EXIT_ERROR);
					}
					if (xmlplist) {
						NSData* xml;
						NSString* error;
						
						xml = [NSPropertyListSerialization dataFromPropertyList:plist format:NSPropertyListXMLFormat_v1_0 errorDescription:&error];
						if (xml == nil) {
							message("%s in %s was not converted into XML format: %s\n", path, filename, [error UTF8String]);
							exit(IPU_EXIT_ERROR);
						}
						catData(stdout, xml);
					}
					
					// Do for -i options
					for (NSString* key in infokeys) {
						id text;
						text = [plist valueForKeyPath:key];
						if (text == nil) {
							message("%s does not have key path '%s'\n", path, [key UTF8String]);
							exit(IPU_EXIT_NO_MATCH_KEY);
						}
						
						if (showKeys) {
							output("%s=%s", [key UTF8String], [[text description] UTF8String]);
						} else {
							output("%s", [[text description] UTF8String]);
						}
						if (!noNewlineCharacters) {
							output("\n");
						}
					}
				}
				matches++;
			}
		}
	}
	if (matches == 0) {
		message("Nothing matches in %s for pattern %s\n", filename, [pattern UTF8String]);
		exit(IPU_EXIT_NO_MATCH_FILE);
	}
}

static void usage()
{
	fprintf(stderr, "usage: ipautil [-?] [-l] [-k] [-i info-key] [-p pattern] [-x] file ...\n");
	fprintf(stderr, "-c           Print file to stdout. -c works exclusively no output from other options will be made, such as -i.\n");
	fprintf(stderr, "-k           Show keys with values.\n");
	fprintf(stderr, "-i info-key  Key path in Info.plist file. Multiple '-i info-key' are allowed.\n");
	fprintf(stderr, "-l           List filenames in .ipa file.\n");
	fprintf(stderr, "-n           Do not print the trailing newline character.\n");
	fprintf(stderr, "-p pattern   Search pattern of Info.plist, in fnmatch(3) format. The default value is 'Payload/*.app/Info.plist'.");
	fprintf(stderr, "-q           No output. Return status as exit code.\n");
	fprintf(stderr, "-x           Print plist file to stdout as XML.\n");
}

int main (int argc, char * argv[])
{
	@autoreleasepool {
		infokeys = [[NSMutableArray alloc] init];
		int c;
		int stdin_used = 0;
		
	    while ((c = getopt(argc, argv, "?ki:lnp:qx")) != -1) {
			switch (c) {
				case 'c':
					catFile = YES;
					break;
				case 'k':
					showKeys = YES;
					break;
				case 'i':
					[infokeys addObject:[NSString stringWithCString:optarg encoding:NSUTF8StringEncoding]];
					break;
				case 'l':
					listFiles = YES;
					break;
				case 'n':
					noNewlineCharacters = YES;
					break;
				case 'p':
					pattern = [NSString stringWithCString:optarg encoding:NSUTF8StringEncoding];
					break;
				case 'q':
					quiet = YES;
					break;
				case 'x':
					xmlplist = YES;
					break;
				case '?':
					usage();
					exit(IPU_EXIT_ARGUMENT);
				default:
					fprintf(stderr, "'-%c' is invalid for an option.\n\n", c);
					usage();
					exit(IPU_EXIT_ARGUMENT);
			}
		}
		if (argc <= optind) {
			// no argument assume stdin as input
			parsetarball(stdin, "<stdin>");
		} else {
			while (optind < argc) {
				FILE* fp;
				const char* file = argv[optind++];
				
				// File argument '-' is treated as stdin. But only one.
				if (!stdin_used && strcmp(file, "-") == 0) {
					parsetarball(stdin, "<stdin>");
					stdin_used++;
				} else {					
					// normal filename or secondary '-' is treated as a file.
					if ((fp = fopen(file, "r")) == NULL) {
						perror(file);
						exit(IPU_EXIT_OPEN);
					}
					parsetarball(fp, file);
					fclose(fp);
				}
			}
		}
		[infokeys release];
	}
    return 0;
}

