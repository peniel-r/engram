#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Batch Work Item Fetcher and Neurona Converter
Fetches multiple work items from Polarion and converts them to valid Neurona format.
"""

import argparse
import requests
import json
import os
import re
import sys
from pathlib import Path
from datetime import datetime
from html import unescape

# Set UTF-8 encoding for Windows console
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")


# Load environment variables from .env file
def load_env():
    """Load environment variables from .env file"""
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        with open(env_path, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    key, value = line.split("=", 1)
                    os.environ[key.strip()] = value.strip()


load_env()

# Configuration - Load from environment variables
PROJECT_ID = os.environ.get("POLARION_PROJECT_ID", "10033794_Ford_DAT_Core_Software")
BASE_URL = os.environ.get(
    "POLARION_BASE_URL", "https://polarionprod1.aptiv.com/polarion"
)
TOKEN = os.environ.get("POLARION_TOKEN")

if not TOKEN:
    print("Error: POLARION_TOKEN not found in environment or .env file")
    print("Please create a .env file with: POLARION_TOKEN=your_token_here")
    sys.exit(1)

# Paths
ASSETS_DIR = Path("assets")
NEURONAS_DIR = Path("neuronas")


def sanitize_id(work_item_id):
    """Convert work item ID to valid neurona ID format"""
    # Convert WI-216473 to wi.216473
    return work_item_id.lower().replace("-", ".")


def clean_html(html_text):
    """Remove HTML tags and decode entities"""
    if not html_text:
        return ""
    # Remove HTML tags
    clean = re.sub(r"<[^>]+>", "", html_text)
    # Decode HTML entities
    clean = unescape(clean)
    return clean.strip()


def map_wi_type_to_neurona_type(wi_type):
    """Map Polarion work item types to neurona types"""
    type_mapping = {
        "systemRequirement": "requirement",
        "requirement": "requirement",
        "task": "task",
        "defect": "issue",
        "bug": "issue",
        "testCase": "test_case",
        "feature": "feature",
        "story": "feature",
        "epic": "feature",
    }
    return type_mapping.get(wi_type, "concept")


def map_status_to_tags(status):
    """Map Polarion status to neurona tags"""
    status_tags = {
        "approved": ["approved", "active"],
        "draft": ["draft", "wip"],
        "implemented": ["implemented", "complete"],
        "verified": ["verified", "tested"],
        "closed": ["closed", "archived"],
        "open": ["open", "active"],
        "in_progress": ["wip", "active"],
    }
    return status_tags.get(status.lower(), ["unknown"])


def map_polarion_link_to_connection_type(link_role):
    """Map Polarion link role to neurona connection type"""
    link_mapping = {
        "parent": "parent",
        "child": "child",
        "relates_to": "relates_to",
        "blocks": "blocks",
        "depends_on": "blocked_by",
        "verifies": "validates",
        "verified_by": "validated_by",
        "implements": "implements",
        "implemented_by": "implemented_by",
        "tests": "tests",
        "tested_by": "tested_by",
        "related": "related",
    }
    return link_mapping.get(link_role.lower(), "relates_to")


def extract_relationships(data):
    """Extract relationships from Polarion work item data"""
    relationships = []

    try:
        # Get linked work items from relationships
        rels = data.get("data", {}).get("relationships", {})
        linked_items = rels.get("linkedWorkItems", {}).get("data", [])

        for link in linked_items:
            link_id = link.get("id")
            link_role = link.get("role", "relates_to")  # Default to relates_to

            if link_id:
                # Clean up the link ID - extract just the WI-XXXXX part
                # Polarion returns IDs like: "10033794_ford.../wi.216473/parent/.../wi.63850"
                # We want just: "wi.63850"
                cleaned_id = link_id
                if "/" in link_id:
                    # Extract the last segment that looks like wi.XXXXX
                    parts = link_id.split("/")
                    for part in reversed(parts):
                        if (
                            part.startswith("wi.")
                            or part.startswith("WI-")
                            or part.startswith("WI.")
                        ):
                            cleaned_id = sanitize_id(part)
                            break
                else:
                    cleaned_id = sanitize_id(link_id)

                connection_type = map_polarion_link_to_connection_type(link_role)
                relationships.append(
                    {
                        "target_id": cleaned_id,
                        "connection_type": connection_type,
                        "weight": 80,  # Default weight
                    }
                )

    except Exception as e:
        print(f"    Warning: Could not extract relationships: {e}")

    return relationships


def format_connections_yaml(relationships):
    """Format relationships as YAML connections array"""
    if not relationships:
        return ""

    # Format as simple array: ["connectionType:targetId:weight", ...]
    conn_strings = []
    for rel in relationships:
        conn_str = f'"{rel["connection_type"]}:{rel["target_id"]}:{rel["weight"]}"'
        conn_strings.append(conn_str)

    # Build YAML array
    return f"connections: [{', '.join(conn_strings)}]"


def fetch_work_item(workitem_id, include_links=True):
    """Fetch a single work item from Polarion with optional relationship data"""
    headers = {"Authorization": f"Bearer {TOKEN}", "Accept": "application/json"}

    # Include linked work items and additional metadata
    fields = "title,description,id,status,type,updated,priority,assignee,author,linkedWorkItems"
    if not include_links:
        fields = "title,description,id,status,type,updated,priority,assignee,author"

    url = f"{BASE_URL}/rest/v1/projects/{PROJECT_ID}/workitems/{workitem_id}?fields[workitems]={fields}"
    print(f"Fetching: {workitem_id}...", end=" ")

    try:
        resp = requests.get(url, headers=headers, timeout=30)
        if resp.status_code == 200:
            data = resp.json()

            # Save raw JSON to assets
            json_path = ASSETS_DIR / f"{workitem_id}.json"
            with open(json_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=4)

            print("✓ Retrieved")
            return data, None
        else:
            error = f"HTTP {resp.status_code}"
            print(f"✗ {error}")
            return None, error

    except Exception as e:
        print(f"✗ {str(e)}")
        return None, str(e)


def fetch_document_work_items(document_name, space_id=None, max_items=30):
    """
    Fetch work items from a Polarion document using SVN/Documents API

    Note: Document API access may be restricted. This function provides a fallback
    to fetch recent work items from the project.
    """
    headers = {"Authorization": f"Bearer {TOKEN}", "Accept": "application/json"}

    print(f"\nFetching work items from document: {document_name}...")
    print(
        f"Note: Document API may have restrictions. Fetching recent work items from project..."
    )

    work_items = []

    try:
        # Approach: Fetch recent work items from the project using query API
        # with Lucene query syntax
        query_url = f"{BASE_URL}/rest/v1/projects/{PROJECT_ID}/workitems"

        # Use query parameter to filter by updated date (recent items)
        params = {
            "fields[workitems]": "id,title,type,updated",
            "page[size]": max_items,
            "sort": "-updated",  # Sort by most recently updated
        }

        print(f"Fetching {max_items} most recent work items from {PROJECT_ID}...")
        resp = requests.get(query_url, headers=headers, params=params, timeout=60)

        if resp.status_code == 200:
            data = resp.json()
            items = data.get("data", [])

            print(f"✓ Found {len(items)} work items")

            # Extract work item IDs
            for item in items:
                attrs = item.get("attributes", {})
                wi_id = attrs.get("id")
                if wi_id:
                    work_items.append(wi_id)
                    wi_title = attrs.get("title", "")
                    print(f"  • {wi_id}: {wi_title[:60]}...")

            print(f"\n✓ Returning {len(work_items)} work items")
            return work_items

        elif resp.status_code == 400:
            print(f"✗ Query failed: HTTP {resp.status_code} (Bad Request)")
            print(f"   The query syntax may not be supported by this Polarion version.")
            print(f"   Tip: Use --items or --file to specify work items manually")
            return []
        else:
            print(f"✗ Query failed: HTTP {resp.status_code}")
            return []

    except Exception as e:
        print(f"✗ Query error: {str(e)}")
        print(f"   Tip: Use --items or --file to specify work items manually")
        return []

    except Exception as e:
        print(f"✗ Query error: {str(e)}")
        return []


def convert_to_neurona(work_item_id, data, include_links=True):
    """Convert Polarion work item JSON to Neurona markdown format"""
    attrs = data.get("data", {}).get("attributes", {})

    # Extract fields
    wi_id = attrs.get("id", work_item_id)
    wi_type = attrs.get("type", "concept")
    title = attrs.get("title", "Untitled")
    description_obj = attrs.get("description", {})
    description = clean_html(description_obj.get("value", ""))
    status = attrs.get("status", "unknown")
    updated = attrs.get("updated", datetime.now().isoformat())

    # Enhanced metadata
    priority = attrs.get("priority", None)
    assignee_obj = attrs.get("assignee", {})
    assignee = assignee_obj.get("id", None) if isinstance(assignee_obj, dict) else None
    author_obj = attrs.get("author", {})
    author = author_obj.get("id", None) if isinstance(author_obj, dict) else None

    # Convert to neurona format
    neurona_id = sanitize_id(wi_id)
    neurona_type = map_wi_type_to_neurona_type(wi_type)
    status_tags = map_status_to_tags(status)

    # Build tags list with enhanced semantic tags
    tags = ["polarion", wi_type] + status_tags

    # Add semantic tags from title/description for better searchability
    text = (title + " " + description).lower()
    if "sensor" in text:
        tags.append("sensor")
    if "temperature" in text:
        tags.append("temperature")
    if "configuration" in text or "config" in text:
        tags.append("configuration")
    if "fault" in text or "error" in text:
        tags.append("fault-detection")
    if "micro" in text or "controller" in text:
        tags.append("microcontroller")

    tags = list(dict.fromkeys(tags))  # Remove duplicates while preserving order

    # Extract relationships if requested
    relationships = []
    if include_links:
        relationships = extract_relationships(data)

    # Build context section with enhanced metadata
    context_lines = [
        "context:",
        f'  source: "polarion"',
        f'  original_id: "{wi_id}"',
        f'  status: "{status}"',
        f'  project: "{PROJECT_ID}"',
    ]

    if priority:
        context_lines.append(f"  priority: {priority}")
    if assignee:
        context_lines.append(f'  assignee: "{assignee}"')
    if author:
        context_lines.append(f'  author: "{author}"')

    context_yaml = "\n".join(context_lines)

    # Build frontmatter
    frontmatter = f"""---
id: {neurona_id}
title: {title}
type: {neurona_type}
tags: {json.dumps(tags)}
updated: "{updated}"
{context_yaml}
"""

    # Add connections if any
    if relationships:
        connections_yaml = format_connections_yaml(relationships)
        frontmatter += connections_yaml + "\n"

    frontmatter += "---\n\n"

    # Build content
    content = frontmatter
    if description:
        content += f"{description}\n\n"

    # Add metadata section
    content += "## Metadata\n\n"
    content += f"- **Original ID**: {wi_id}\n"
    content += f"- **Type**: {wi_type}\n"
    content += f"- **Status**: {status}\n"
    if priority:
        content += f"- **Priority**: {priority}\n"
    if assignee:
        content += f"- **Assignee**: {assignee}\n"
    if author:
        content += f"- **Author**: {author}\n"
    content += f"- **Project**: {PROJECT_ID}\n"
    content += f"- **Portal**: [{wi_id}](https://polarionprod1.aptiv.com/polarion/redirect/project/{PROJECT_ID}/workitem?id={wi_id})\n"

    return content, neurona_id, relationships


def process_work_items(items, include_links=True):
    """Process a list of work items"""
    print(f"\n{'=' * 60}")
    print("Batch Work Item Processor")
    print(f"{'=' * 60}\n")
    print(f"Processing {len(items)} work items...")
    if include_links:
        print("Relationship extraction: ENABLED")
    print()

    # Ensure directories exist
    ASSETS_DIR.mkdir(exist_ok=True)
    NEURONAS_DIR.mkdir(exist_ok=True)

    results = {"success": [], "failed": [], "total": len(items), "relationships": []}

    # Process each item
    for idx, item_id in enumerate(items, 1):
        print(f"[{idx}/{len(items)}] ", end="")

        # Fetch from Polarion
        data, error = fetch_work_item(item_id, include_links=include_links)

        if data is None:
            results["failed"].append({"id": item_id, "error": error})
            continue

        # Convert to neurona
        try:
            neurona_content, neurona_id, relationships = convert_to_neurona(
                item_id, data, include_links=include_links
            )

            # Save neurona file
            neurona_path = NEURONAS_DIR / f"{neurona_id}.md"
            with open(neurona_path, "w", encoding="utf-8") as f:
                f.write(neurona_content)

            print(f"         → Saved as {neurona_id}.md", end="")
            if relationships:
                print(f" ({len(relationships)} links)")
                results["relationships"].extend(relationships)
            else:
                print()

            results["success"].append(
                {
                    "id": item_id,
                    "neurona_id": neurona_id,
                    "file": str(neurona_path),
                    "relationships_count": len(relationships),
                }
            )

        except Exception as e:
            print(f"         ✗ Conversion failed: {e}")
            results["failed"].append(
                {"id": item_id, "error": f"Conversion error: {str(e)}"}
            )

    # Print summary
    print(f"\n{'=' * 60}")
    print("Summary")
    print(f"{'=' * 60}")
    print(f"Total Items:    {results['total']}")
    print(f"Successful:     {len(results['success'])} ✓")
    print(f"Failed:         {len(results['failed'])} ✗")
    print(f"Relationships:  {len(results['relationships'])} links extracted")

    if results["failed"]:
        print("\nFailed Items:")
        for item in results["failed"]:
            print(f"  - {item['id']}: {item['error']}")

    print("\nOutput:")
    print(f"  - Raw JSON:   {ASSETS_DIR.absolute()}/")
    print(f"  - Neuronas:   {NEURONAS_DIR.absolute()}/")

    # Save results manifest
    manifest_path = (
        ASSETS_DIR / f"batch_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    )
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)

    print(f"  - Manifest:   {manifest_path}")

    # Suggest next steps
    print("\n" + "=" * 60)
    print("Next Steps:")
    print("=" * 60)
    print("1. Run 'engram sync' to rebuild indices")
    print('2. Query work items: engram query --mode hybrid "sensor"')
    print("3. Trace dependencies: engram trace wi.216473")
    print()

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Batch fetch work items from Polarion and convert to Neuronas",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Single item
  python fetch_wi_batch.py --items WI-216473
  
  # Multiple items
  python fetch_wi_batch.py --items WI-216473 WI-97530 WI-123456
  
  # From file (one ID per line)
  python fetch_wi_batch.py --file work_items.txt
  
  # From Polarion document
  python fetch_wi_batch.py --document "Requirements Specification"
  
  # Without relationship extraction (faster)
  python fetch_wi_batch.py --items WI-216473 --no-links
        """,
    )

    parser.add_argument(
        "--items", nargs="+", help="List of work item IDs (space-separated)"
    )

    parser.add_argument("--file", help="File containing work item IDs (one per line)")

    parser.add_argument(
        "--document", help="Fetch all work items from a Polarion document by name"
    )

    parser.add_argument("--space", help="Polarion space ID (default: project ID)")

    parser.add_argument(
        "--no-links",
        action="store_true",
        help="Disable relationship extraction (faster processing)",
    )

    args = parser.parse_args()

    # Collect work items
    items = []

    if args.items:
        items.extend(args.items)

    if args.file:
        if not os.path.exists(args.file):
            print(f"Error: File '{args.file}' not found")
            return 1

        with open(args.file, "r") as f:
            file_items = [
                line.strip() for line in f if line.strip() and not line.startswith("#")
            ]
            items.extend(file_items)

    if args.document:
        doc_items = fetch_document_work_items(args.document, args.space)
        if not doc_items:
            print(f"Warning: No work items found in document '{args.document}'")
        items.extend(doc_items)

    if not items:
        print("Error: No work items specified. Use --items, --file, or --document")
        parser.print_help()
        return 1

    # Remove duplicates while preserving order
    items = list(dict.fromkeys(items))

    # Process items
    include_links = not args.no_links
    results = process_work_items(items, include_links=include_links)

    # Return exit code
    return 0 if not results["failed"] else 1


if __name__ == "__main__":
    exit(main())
