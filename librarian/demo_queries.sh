#!/bin/bash
# Demo queries for Engram Polarion Work Items
# Shows different query modes and capabilities

echo "========================================================================"
echo "Engram Demo - Polarion Work Items Knowledge Cortex"
echo "========================================================================"
echo ""

# Demo 1: Filter Mode - Query by type
echo "1. Filter Mode: Query all requirements"
echo "   Command: engram query \"type:requirement\" --json"
echo ""
engram query "type:requirement" --json | python -m json.tool | head -20
echo "   ... (truncated)"
echo ""

# Demo 2: Filter Mode - Query by tag
echo "2. Filter Mode: Query approved work items"
echo "   Command: engram query \"tag:approved\" --json"
echo ""
engram query "tag:approved" --json | python -m json.tool | head -15
echo "   ... (truncated)"
echo ""

# Demo 3: Status overview
echo "3. Status: Get cortex overview"
echo "   Command: engram status --json"
echo ""
engram status --json | python -m json.tool
echo ""

# Demo 4: Show specific work item
echo "4. Show: Display specific work item details"
echo "   Command: engram show wi.216473 --json"
echo ""
engram show wi.216473 --json | python -m json.tool
echo ""

# Demo 5: Trace dependencies
echo "5. Trace: Follow work item relationships"
echo "   Command: engram trace wi.90087 --json"
echo ""
engram trace wi.90087 --json | python -m json.tool
echo ""

# Demo 6: Complex EQL query
echo "6. EQL Query: Find sensor-related requirements"
echo "   Command: engram query \"type:requirement AND tag:sensor\" --json"
echo ""
engram query "type:requirement AND tag:sensor" --json | python -m json.tool
echo ""

# Demo 7: Text search (currently limited to title+tags)
echo "7. Text Search: Search for 'sensor'"
echo "   Command: engram query --mode text \"sensor\" --json"
echo "   Note: Text search currently only indexes title+tags, not body content"
echo ""
engram query --mode text "sensor" --json | python -m json.tool
echo ""

echo "========================================================================"
echo "Demo Complete!"
echo "========================================================================"
echo ""
echo "Summary of capabilities demonstrated:"
echo "  ✓ Filter queries by type and tags"
echo "  ✓ EQL logical operators (AND, OR, NOT)"
echo "  ✓ Work item details with metadata"
echo "  ✓ Dependency tracing across relationships"
echo "  ✓ Cortex status and metrics"
echo ""
echo "For LLM integration examples, see llm_retrieval_example.py"
echo ""
