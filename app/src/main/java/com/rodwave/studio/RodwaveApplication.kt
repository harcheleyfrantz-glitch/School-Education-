package com.rodwave.studio

import android.app.Application
import com.rodwave.studio.android.AndroidPlatform
import com.rodwave.studio.core.Studio
import kotlinx.coroutines.MainScope

/** Owns the process-wide [Studio], so open documents survive activity recreation. */
class RodwaveApplication : Application() {
    val platform: AndroidPlatform by lazy { AndroidPlatform(this) }
    val studio: Studio by lazy { Studio(platform, MainScope()) }
}
