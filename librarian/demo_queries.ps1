# Demo queries for Engram Polarion Work Items
# Shows different query modes and capabilities

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "Engram Demo - Polarion Work Items Knowledge Cortex" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

# Demo 1: Filter Mode - Query by type
Write-Host "1. Filter Mode: Query all requirements" -ForegroundColor Yellow
Write-Host "   Command: engram query `"type:requirement`" --json" -ForegroundColor Gray
Write-Host ""
$result1 = engram query "type:requirement" --json | ConvertFrom-Json
$result1 | Format-Table -Property id, title, type, @{Label="tags";Expression={$_.tags.Count}} -AutoSize
Write-Host ""

# Demo 2: Filter Mode - Query by tag
Write-Host "2. Filter Mode: Query approved work items" -ForegroundColor Yellow
Write-Host "   Command: engram query `"tag:approved`" --json" -ForegroundColor Gray
Write-Host ""
$result2 = engram query "tag:approved" --json | ConvertFrom-Json
$result2 | Format-Table -Property id, title, status -AutoSize
Write-Host ""

# Demo 3: Status overview
Write-Host "3. Status: Get cortex overview" -ForegroundColor Yellow
Write-Host "   Command: engram status --json" -ForegroundColor Gray
Write-Host ""
$status = engram status --json | ConvertFrom-Json
$status | Format-Table -Property id, title, type, status, priority -AutoSize
Write-Host ""

# Demo 4: Show specific work item
Write-Host "4. Show: Display specific work item details" -ForegroundColor Yellow
Write-Host "   Command: engram show wi.216473 --json" -ForegroundColor Gray
Write-Host ""
$wi = engram show wi.216473 --json | ConvertFrom-Json
Write-Host "ID:          $($wi.id)" -ForegroundColor White
Write-Host "Title:       $($wi.title)" -ForegroundColor White
Write-Host "Type:        $($wi.type)" -ForegroundColor White
Write-Host "Status:      $($wi.context.status)" -ForegroundColor White
Write-Host "Priority:    $($wi.context.priority)" -ForegroundColor White
Write-Host "Connections: $($wi.connections)" -ForegroundColor White
Write-Host ""

# Demo 5: Trace dependencies
Write-Host "5. Trace: Follow work item relationships" -ForegroundColor Yellow
Write-Host "   Command: engram trace wi.90087 --json" -ForegroundColor Gray
Write-Host ""
$trace = engram trace wi.90087 --json | ConvertFrom-Json
Write-Host "Work item wi.90087 has connections to:" -ForegroundColor White
$trace | Where-Object { $_.level -gt 0 } | ForEach-Object {
    Write-Host "  → $($_.id) (level $($_.level))" -ForegroundColor Cyan
}
Write-Host ""

# Demo 6: Complex EQL query
Write-Host "6. EQL Query: Find sensor-related requirements" -ForegroundColor Yellow
Write-Host "   Command: engram query `"type:requirement AND tag:sensor`" --json" -ForegroundColor Gray
Write-Host ""
$sensors = engram query "type:requirement AND tag:sensor" --json | ConvertFrom-Json
$sensors | Format-Table -Property id, title -AutoSize
Write-Host ""

# Demo 7: Text search (currently limited to title+tags)
Write-Host "7. Text Search: Search for 'temperature'" -ForegroundColor Yellow
Write-Host "   Command: engram query --mode text `"temperature`" --json" -ForegroundColor Gray
Write-Host "   Note: Text search currently only indexes title+tags, not body content" -ForegroundColor DarkGray
Write-Host ""
$textSearch = engram query --mode text "temperature" --json 2>$null | ConvertFrom-Json
if ($textSearch) {
    $textSearch | Format-Table -Property id, title -AutoSize
} else {
    Write-Host "   (No results - text search needs body content indexing)" -ForegroundColor DarkGray
}
Write-Host ""

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "Demo Complete!" -ForegroundColor Green
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary of capabilities demonstrated:" -ForegroundColor White
Write-Host "  ✓ Filter queries by type and tags" -ForegroundColor Green
Write-Host "  ✓ EQL logical operators (AND, OR, NOT)" -ForegroundColor Green
Write-Host "  ✓ Work item details with metadata" -ForegroundColor Green
Write-Host "  ✓ Dependency tracing across relationships" -ForegroundColor Green
Write-Host "  ✓ Cortex status and metrics" -ForegroundColor Green
Write-Host ""
Write-Host "For LLM integration examples, see llm_retrieval_example.py" -ForegroundColor Cyan
Write-Host ""
