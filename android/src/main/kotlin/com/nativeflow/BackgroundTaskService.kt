package com.nativeflow

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import java.util.UUID

/**
 * OS-scheduled deferred work (Android side of `scheduleBackgroundTask`).
 * JobScheduler decides when it runs; each run becomes a persisted
 * `nativeflow.background.task` event that Dart completes with
 * `completeBackgroundTask(taskId)`.
 */
class BackgroundTaskService : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        RuntimeSupervisor.ensure(this)
        val kind = if (params.jobId == PROCESSING_JOB) "processing" else "refresh"
        return RuntimeSupervisor.onBackgroundTask(UUID.randomUUID().toString(), kind) { taskId, success ->
            running.remove(taskId)
            jobFinished(params, !success)
        }.also { taskId -> if (taskId != null) running[taskId] = params } != null
    }

    /** The OS revoked the window; Dart is told via an `expired` event. */
    override fun onStopJob(params: JobParameters): Boolean {
        running.entries.firstOrNull { it.value === params }?.key?.let(RuntimeSupervisor::onBackgroundTaskExpired)
        return false
    }

    private val running = mutableMapOf<String, JobParameters>()

    internal companion object {
        const val REFRESH_JOB = 0x4E46
        const val PROCESSING_JOB = 0x4E47

        fun schedule(context: Context, kind: String, earliestSeconds: Long) {
            val processing = kind == "processing"
            val job = JobInfo.Builder(
                if (processing) PROCESSING_JOB else REFRESH_JOB,
                ComponentName(context, BackgroundTaskService::class.java),
            )
                .setMinimumLatency(earliestSeconds * 1000)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                // Mirrors iOS: processing tasks prefer charging + idle-ish devices.
                .setRequiresCharging(processing)
                .build()
            val result = context.getSystemService(JobScheduler::class.java).schedule(job)
            if (result != JobScheduler.RESULT_SUCCESS) throw IllegalStateException("JobScheduler rejected the task")
        }
    }
}
