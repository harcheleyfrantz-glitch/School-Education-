package com.rodwave.studio.android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContract

/** ACTION_CREATE_DOCUMENT with a MIME type chosen per call (the stock contract fixes it up front). */
class CreateDocumentContract : ActivityResultContract<CreateDocumentContract.Request, Uri?>() {
    data class Request(val suggestedName: String, val mimeType: String)

    override fun createIntent(context: Context, input: Request): Intent =
        Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(input.mimeType)
            .putExtra(Intent.EXTRA_TITLE, input.suggestedName)

    override fun parseResult(resultCode: Int, intent: Intent?): Uri? =
        if (resultCode == Activity.RESULT_OK) intent?.data else null
}
