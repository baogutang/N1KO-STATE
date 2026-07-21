#include <errno.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/proc_info.h>
#include <sys/resource.h>

static uint64_t absolute_time_to_nanoseconds(uint64_t value) {
    mach_timebase_info_data_t timebase = {0};
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.denom == 0) {
        return value;
    }

    __uint128_t nanoseconds = (__uint128_t)value * timebase.numer / timebase.denom;
    return (uint64_t)nanoseconds;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: proc_metrics <pid>\n");
        return 64;
    }

    char *end = NULL;
    long raw_pid = strtol(argv[1], &end, 10);
    if (end == argv[1] || *end != '\0' || raw_pid <= 0) {
        fprintf(stderr, "invalid pid: %s\n", argv[1]);
        return 64;
    }

    struct rusage_info_v4 usage = {0};
    if (proc_pid_rusage((int)raw_pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) {
        perror("proc_pid_rusage");
        return errno == 0 ? 1 : errno;
    }
    // Energy was added in rusage v6. Keep the v4 metrics as the compatibility
    // baseline and expose 0 when the running OS cannot provide the v6 counter.
    struct rusage_info_v6 energy_usage = {0};
    uint64_t energy_nanojoules = 0;
    if (proc_pid_rusage((int)raw_pid, RUSAGE_INFO_V6, (rusage_info_t *)&energy_usage) == 0) {
        energy_nanojoules = energy_usage.ri_energy_nj;
    }

    struct proc_taskinfo task = {0};
    int task_bytes = proc_pidinfo(
        (int)raw_pid,
        PROC_PIDTASKINFO,
        0,
        &task,
        (int)sizeof(task)
    );
    if (task_bytes != sizeof(task)) {
        perror("proc_pidinfo(PROC_PIDTASKINFO)");
        return errno == 0 ? 1 : errno;
    }

    int fd_bytes = proc_pidinfo((int)raw_pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (fd_bytes < 0) {
        perror("proc_pidinfo(PROC_PIDLISTFDS)");
        return errno == 0 ? 1 : errno;
    }
    int fd_count = 0;
    int socket_count = 0;
    if (fd_bytes > 0) {
        struct proc_fdinfo *fds = calloc(1, (size_t)fd_bytes);
        if (fds == NULL) {
            perror("calloc");
            return 1;
        }
        int returned = proc_pidinfo((int)raw_pid, PROC_PIDLISTFDS, 0, fds, fd_bytes);
        if (returned < 0) {
            free(fds);
            perror("proc_pidinfo(PROC_PIDLISTFDS)");
            return errno == 0 ? 1 : errno;
        }
        fd_count = returned / (int)sizeof(struct proc_fdinfo);
        for (int index = 0; index < fd_count; index++) {
            if (fds[index].proc_fdtype == PROX_FDTYPE_SOCKET) {
                socket_count++;
            }
        }
        free(fds);
    }

    printf("{\n");
    // rusage CPU fields use Mach absolute-time units. They happen to equal
    // nanoseconds on Intel but require the timebase conversion on Apple Silicon.
    printf("  \"userTimeNanoseconds\": %llu,\n", absolute_time_to_nanoseconds(usage.ri_user_time));
    printf("  \"systemTimeNanoseconds\": %llu,\n", absolute_time_to_nanoseconds(usage.ri_system_time));
    printf("  \"packageIdleWakeups\": %llu,\n", usage.ri_pkg_idle_wkups);
    printf("  \"interruptWakeups\": %llu,\n", usage.ri_interrupt_wkups);
    printf("  \"residentBytes\": %llu,\n", usage.ri_resident_size);
    printf("  \"physicalFootprintBytes\": %llu,\n", usage.ri_phys_footprint);
    printf("  \"lifetimeMaximumPhysicalFootprintBytes\": %llu,\n", usage.ri_lifetime_max_phys_footprint);
    printf("  \"pageIns\": %llu,\n", usage.ri_pageins);
    printf("  \"diskReadBytes\": %llu,\n", usage.ri_diskio_bytesread);
    printf("  \"diskWrittenBytes\": %llu,\n", usage.ri_diskio_byteswritten);
    printf("  \"threadCount\": %d,\n", (int)task.pti_threadnum);
    printf("  \"runningThreadCount\": %d,\n", (int)task.pti_numrunning);
    printf("  \"fileDescriptorCount\": %d,\n", fd_count);
    printf("  \"socketDescriptorCount\": %d,\n", socket_count);
    printf("  \"energyNanojoules\": %llu\n", energy_nanojoules);
    printf("}\n");
    return 0;
}
