//
//  main.m
//  ThreadTests
//
//  Created by Galen Rhodes on 1/24/17.
//  Copyright © 2017 Project Galen. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <pthread.h>
#import <semaphore.h>

#define OTHER ((BOOL)NO)

typedef void *pVoid;

typedef struct {
	struct timespec timeout;
	pthread_t       mainThread;
}            WaitData;

static void cancelTimeoutThread(pthread_t aThread, int results) {
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

static void threadCleanup(void *ptr) {
	NSString *prefix = (__bridge_transfer NSString *)ptr;
	NSLog(@"%@: nanozleep thread cleanup called...", prefix);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreturn-stack-address"

static void nanozleep(struct timespec reltime, NSString *prefix, BOOL method) {
	pthread_cleanup_push(threadCleanup, (__bridge_retained pVoid)prefix);
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

static void *threadOne(pVoid args) {
	struct timespec reltime = *(struct timespec *)args;
	nanozleep(reltime, @"WORK", OTHER);
	return (pVoid)(long)0;
}

static void ignoreSignal(int Signal) {
	Signal = 0;
}

static void *threadTwo(pVoid ptr) {
	WaitData *waitData = (WaitData *)ptr;
	int      results   = 0;

	nanozleep(waitData->timeout, @"TIMER", NO);

	if(pthread_kill(waitData->mainThread, 0) == 0) {
		NSLog(@"Sending %@ signal to main thread...", @"SIGUSR2");

		struct sigaction sigAction;
		sigAction.sa_flags   = 0;
		sigAction.sa_handler = ignoreSignal;
		sigemptyset(&sigAction.sa_mask);
		results = sigaction(SIGUSR2, &sigAction, NULL);

		if(results == 0) {
			results = pthread_kill(waitData->mainThread, SIGUSR2);
			if(results == 0) {
				NSLog(@"Signal sent.");
			}
			else {
				NSLog(@"Signal not sent: %@", [NSString stringWithUTF8String:strerror(results)]);
			}
		}
		else {
			NSLog(@"Signal not sent: %@", [NSString stringWithUTF8String:strerror(results)]);
		}
	}
	else {
		NSLog(@"Signal not sent: %@", @"Main thread not active.");
	}

	return (pVoid)(long)results;
}

static int createTestSemaphore(sem_t **sem) {
	*sem = sem_open("/test", O_CREAT, S_IWUSR | S_IRUSR, 1);

	if(*sem == SEM_FAILED) {
		NSLog(@"Open semaphore failed: %@", [NSString stringWithUTF8String:strerror(errno)]);
		return 1;
	}

	if(sem_wait(*sem)) {
		NSLog(@"Unable to aquire only semaphore: %@", [NSString stringWithUTF8String:strerror(errno)]);
		return 2;
	}

	return 0;
}

static int createWorkerThread(pthread_t *aThread, WaitData *waitData) {
	NSLog(@"Starting worker thread...");
	int results2 = pthread_create(aThread, NULL, threadTwo, waitData);

	if(results2) {
		NSString *err = [NSString stringWithUTF8String:strerror(results2)];
		NSLog(@"Unable to start worker thread: %@", err);
		return 3;
	}

	NSLog(@"Worker thread started.");
	return 0;
}

static void threadCleanup2(void *ptr) {
	NSLog(@"sem_wait() thread cleanup routine called...");
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		pthread_t       aThread;
		sem_t           *sem          = SEM_FAILED;
		struct timespec threadTimeout = { .tv_sec = 7, .tv_nsec = 0 };
		struct timespec mainTimeout   = { .tv_sec = 3, .tv_nsec = 0 };
		WaitData        waitData      = { .mainThread = pthread_self(), .timeout = threadTimeout };
		int             results       = 0;
		int             savedState;
		int             ignoreState;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreturn-stack-address"
		pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &savedState);
		pthread_cleanup_push(threadCleanup2, NULL);

			results = createTestSemaphore(&sem);

			if(results == 0) {
				results = createWorkerThread(&aThread, &waitData);
				pthread_setcancelstate(savedState, &ignoreState);

				if(results == 0) {
					NSLog(@"Entring sem_wait()");

					if(sem_wait(sem)) {
						NSLog(@"Error while waiting for semaphore: %@", [NSString stringWithUTF8String:strerror(errno)]);
						results = 3;
					}
					else {
						NSLog(@"sem_wait() exited normally.");
					}
				}
			}

		pthread_cleanup_pop(1);
#pragma clang diagnostic pop
		// cancelTimeoutThread(aThread, results);
		NSLog(@"Done waiting...");

		return results;
	}
}

