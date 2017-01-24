//
//  main.m
//  ThreadTests
//
//  Created by Galen Rhodes on 1/24/17.
//  Copyright © 2017 Project Galen. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <pthread.h>

#define OTHER ((BOOL)NO)

static void threadCleanup(void *ptr) {
	NSString *prefix = (__bridge_transfer NSString *)ptr;
	NSLog(@"%@: nanozleep thread cleanup called...", prefix);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreturn-stack-address"

static void nanozleep(struct timespec reltime, NSString *prefix, BOOL method) {
	pthread_cleanup_push(threadCleanup, (__bridge_retained void *)prefix);
		struct timespec remtime;

		NSLog(@"%@: Sleeping for %@ seconds...", prefix, @(((double)reltime.tv_sec) + (((double)reltime.tv_nsec) / 1000000000.0)));

		if(method) {
			sleep((unsigned int)reltime.tv_sec);
		}
		else {
			for(;;) {
				if(nanosleep(&reltime, &remtime) == 0) {
					NSLog(@"%@: %@", prefix, @"nanosleep stopped normally.");
					break;
				}
				else {
					NSString *msg = [NSString stringWithUTF8String:strerror(errno)];
					NSLog(@"%@: %@: %@", prefix, @"nanosleep stop reason", msg);
					reltime = remtime;
				}
			}
		}

	pthread_cleanup_pop(1);
	NSLog(@"%@: nanozleep exiting.", prefix);
}

#pragma clang diagnostic pop

static void *threadOne(void *args) {
	struct timespec reltime = *(struct timespec *)args;
	nanozleep(reltime, @"WORK", OTHER);
	return (void *)(long)0;
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		pthread_t       aThread;
		struct timespec threadTimeout = { .tv_sec = 10, .tv_nsec = 0 };
		struct timespec mainTimeout   = { .tv_sec = 3, .tv_nsec = 0 };

		NSLog(@"Starting worker thread...");
		int results = pthread_create(&aThread, NULL, threadOne, &threadTimeout);

		if(results == 0) {
			NSLog(@"Worker thread started.");
			nanozleep(mainTimeout, @"MAIN", NO);

			NSLog(@"Attempting to cancel worker thread...");
			results = pthread_cancel(aThread);

			if(results) {
				NSString *err = [NSString stringWithUTF8String:strerror(results)];
				NSLog(@"Error during cancel: %@", err);
			}

			NSLog(@"Joining worker thread to wait for completion...");
			results = pthread_join(aThread, NULL);

			if(results) {
				NSString *err = [NSString stringWithUTF8String:strerror(results)];
				NSLog(@"Error during join: %@", err);
			}
			else {
				NSLog(@"Success");
			}
		}
		else {
			NSString *err = [NSString stringWithUTF8String:strerror(results)];
			NSLog(@"Unable to start worker thread: %@", err);
		}
	}

	return 0;
}
