#ifndef BB_COMPAT_MACOS_PTHREAD_H
#define BB_COMPAT_MACOS_PTHREAD_H
#ifdef __APPLE__
#include <pthread.h>
#include <time.h>
#include <errno.h>

/* macOS omits POSIX timed mutex/rwlock acquisition. These are low-rate guest
 * synchronization fallbacks for the CPU feasibility build. */
static inline int bb_macos_deadline_passed(const struct timespec *deadline) {
    struct timespec now;
    clock_gettime(CLOCK_REALTIME,&now);
    return now.tv_sec>deadline->tv_sec ||
           (now.tv_sec==deadline->tv_sec && now.tv_nsec>=deadline->tv_nsec);
}
static inline void bb_macos_lock_pause(void) {
    struct timespec delay={0,1000000};
    nanosleep(&delay,NULL);
}
static inline int bb_macos_mutex_timedlock(pthread_mutex_t *lock,const struct timespec *deadline) {
    for (;;) {
        int e=pthread_mutex_trylock(lock);
        if (e!=EBUSY) return e;
        if (bb_macos_deadline_passed(deadline)) return ETIMEDOUT;
        bb_macos_lock_pause();
    }
}
static inline int bb_macos_rwlock_timedlock(pthread_rwlock_t *lock,
                                            const struct timespec *deadline,int writer) {
    for (;;) {
        int e=writer ? pthread_rwlock_trywrlock(lock) : pthread_rwlock_tryrdlock(lock);
        if (e!=EBUSY) return e;
        if (bb_macos_deadline_passed(deadline)) return ETIMEDOUT;
        bb_macos_lock_pause();
    }
}
#endif
#endif
