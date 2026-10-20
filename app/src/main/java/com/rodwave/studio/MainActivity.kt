package com.rodwave.studio

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import com.rodwave.studio.android.CreateDocumentContract
import com.rodwave.studio.ui.RodwaveApp

class MainActivity : ComponentActivity() {
    private val app: RodwaveApplication get() = application as RodwaveApplication

    // System pickers (Storage Access Framework). Results go back to the platform layer.
    private val pickFolder = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri -> app.platform.onFolderPicked(uri) }
    private val pickFile = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> app.platform.onFilePicked(uri) }
    private val createDocument = registerForActivityResult(CreateDocumentContract()) { uri -> app.platform.onDocumentCreated(uri) }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        app.platform.attach(pickFolder, pickFile, createDocument)
        val studio = app.studio
        setContent {
            BackHandler(enabled = studio.canGoBack) { studio.back() }
            RodwaveApp(studio)
        }
    }

    override fun onStop() {
        super.onStop()
        // Recovery snapshots and the console log are written whenever the app leaves the screen.
        app.studio.onBackground()
    }

    override fun onDestroy() {
        app.platform.detach(pickFolder)
        super.onDestroy()
    }
}
