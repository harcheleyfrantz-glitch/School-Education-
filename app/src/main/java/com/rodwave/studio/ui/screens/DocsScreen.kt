package com.rodwave.studio.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.rodwave.studio.core.DocArticle
import com.rodwave.studio.core.Docs
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.LocalWideLayout
import com.rodwave.studio.ui.ScreenFrame
import com.rodwave.studio.ui.components.MarkdownText
import com.rodwave.studio.ui.components.SearchField
import com.rodwave.studio.ui.components.SectionCard
import com.rodwave.studio.ui.theme.Palette

@Composable
fun DocsScreen(studio: Studio) {
    var query by remember { mutableStateOf("") }
    var open by remember { mutableStateOf<DocArticle?>(null) }
    val wide = LocalWideLayout.current
    val results = remember(query) { Docs.search(query) }
    val article = open
    ScreenFrame(
        studio,
        if (!wide && article != null) article.title else "Documentation",
        if (!wide && article != null) article.summary else "${Docs.ARTICLES.size} articles, available offline",
        actions = {
            if (!wide && article != null) IconButton(onClick = { open = null }) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "All articles") }
        },
    ) {
        if (wide) {
            Row(Modifier.fillMaxSize()) {
                ArticleList(query, { query = it }, results, article, Modifier.width(340.dp).fillMaxHeight()) { open = it }
                VerticalDivider()
                Box(Modifier.weight(1f).fillMaxHeight()) {
                    ArticleView(article ?: Docs.ARTICLES.first())
                }
            }
        } else if (article == null) {
            ArticleList(query, { query = it }, results, null, Modifier.fillMaxSize()) { open = it }
        } else {
            ArticleView(article)
        }
    }
}

@Composable
private fun ArticleList(query: String, onQuery: (String) -> Unit, results: List<DocArticle>, selected: DocArticle?, modifier: Modifier, onOpen: (DocArticle) -> Unit) {
    LazyColumn(modifier, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { SearchField(query, onQuery, "Search the docs") }
        if (results.isEmpty()) {
            item { Text("No article mentions “$query”.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        items(results, key = { it.id }) { a ->
            SectionCard(
                a.title,
                modifier = Modifier.clickable { onOpen(a) },
                icon = Icons.AutoMirrored.Outlined.MenuBook,
                accent = if (a == selected) Palette.Sunset else MaterialTheme.colorScheme.primary,
                subtitle = a.summary,
            )
        }
    }
}

@Composable
private fun ArticleView(article: DocArticle) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp)) {
        MarkdownText(article.body)
    }
}
