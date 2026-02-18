#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Neurona Compliance Verification Script
Validates that generated neuronas comply with Neurona Open Specification v0.1.0
"""

import json
import yaml
import sys
from pathlib import Path

# Set UTF-8 encoding for Windows console
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")


def load_neurona(filepath):
    """Load and parse neurona markdown file"""
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    # Split frontmatter and body
    if not content.startswith("---\n"):
        return None, "Missing frontmatter"

    parts = content.split("---\n", 2)
    if len(parts) < 3:
        return None, "Invalid frontmatter format"

    frontmatter = yaml.safe_load(parts[1])
    body = parts[2].strip()

    return {"frontmatter": frontmatter, "body": body}, None


def validate_tier1(neurona):
    """Validate Tier 1 (Essential) fields"""
    fm = neurona["frontmatter"]
    issues = []

    required = ["id", "title", "tags"]
    for field in required:
        if field not in fm:
            issues.append(f"Missing Tier 1 field: {field}")
        elif not fm[field]:
            issues.append(f"Empty Tier 1 field: {field}")

    # Validate id format (should be dot notation)
    if "id" in fm and "." not in fm["id"]:
        issues.append(f"ID should use dot notation: {fm['id']}")

    # Validate tags is a list
    if "tags" in fm and not isinstance(fm["tags"], list):
        issues.append(f"Tags should be a list: {type(fm['tags'])}")

    return issues


def validate_tier2(neurona):
    """Validate Tier 2 (Standard) fields"""
    fm = neurona["frontmatter"]
    issues = []

    # Type field (optional but recommended)
    valid_types = [
        "concept",
        "reference",
        "artifact",
        "state_machine",
        "lesson",
        "requirement",
        "test_case",
        "issue",
        "feature",
    ]

    if "type" in fm:
        if fm["type"] not in valid_types:
            issues.append(
                f"Invalid type: {fm['type']} (valid: {', '.join(valid_types)})"
            )

    # Updated field (optional)
    if "updated" in fm:
        # Should be ISO 8601 format
        if not isinstance(fm["updated"], str):
            issues.append(f"Updated should be string: {type(fm['updated'])}")

    # Language field (optional)
    if "language" in fm:
        if not isinstance(fm["language"], str) or len(fm["language"]) != 2:
            issues.append(f"Language should be 2-char code: {fm.get('language')}")

    return issues


def validate_tier3(neurona):
    """Validate Tier 3 (Advanced) fields"""
    fm = neurona["frontmatter"]
    issues = []

    # Context field (optional open schema)
    if "context" in fm:
        if not isinstance(fm["context"], dict):
            issues.append(f"Context should be dict: {type(fm['context'])}")

    # LLM metadata (optional)
    if "_llm" in fm:
        llm = fm["_llm"]
        if not isinstance(llm, dict):
            issues.append(f"_llm should be dict: {type(llm)}")
        else:
            # Optional subfields: t, d, k, c, strategy
            if "d" in llm and not (1 <= llm["d"] <= 4):
                issues.append(f"_llm.d should be 1-4: {llm['d']}")
            if "k" in llm and not isinstance(llm["k"], list):
                issues.append(f"_llm.k should be list: {type(llm['k'])}")

    return issues


def validate_neurona(filepath):
    """Full validation of a neurona file"""
    print(f"\n{'=' * 60}")
    print(f"Validating: {filepath.name}")
    print(f"{'=' * 60}")

    # Load neurona
    neurona, error = load_neurona(filepath)
    if error:
        print(f"❌ FAILED: {error}")
        return False

    # Validate tiers
    all_issues = []

    tier1_issues = validate_tier1(neurona)
    tier2_issues = validate_tier2(neurona)
    tier3_issues = validate_tier3(neurona)

    all_issues.extend(tier1_issues)
    all_issues.extend(tier2_issues)
    all_issues.extend(tier3_issues)

    # Report
    fm = neurona["frontmatter"]

    print(f"\nID:       {fm.get('id', 'MISSING')}")
    print(f"Title:    {fm.get('title', 'MISSING')}")
    print(f"Type:     {fm.get('type', 'concept (default)')}")
    print(f"Tags:     {len(fm.get('tags', []))} tags")
    print(f"Updated:  {fm.get('updated', 'not set')}")
    print(f"Context:  {'present' if 'context' in fm else 'absent'}")
    print(f"Body:     {len(neurona['body'])} chars")

    print(f"\n{'─' * 60}")
    print("Tier 1 (Essential):  ", end="")
    if tier1_issues:
        print(f"❌ {len(tier1_issues)} issues")
        for issue in tier1_issues:
            print(f"  • {issue}")
    else:
        print("✅ PASS")

    print("Tier 2 (Standard):   ", end="")
    if tier2_issues:
        print(f"⚠️  {len(tier2_issues)} issues")
        for issue in tier2_issues:
            print(f"  • {issue}")
    else:
        print("✅ PASS")

    print("Tier 3 (Advanced):   ", end="")
    if tier3_issues:
        print(f"⚠️  {len(tier3_issues)} issues")
        for issue in tier3_issues:
            print(f"  • {issue}")
    else:
        print("✅ PASS")

    print(f"{'─' * 60}")

    if not all_issues:
        print("✅ COMPLIANT - No issues found")
        return True
    else:
        # Only Tier 1 issues are failures
        if tier1_issues:
            print(f"❌ NON-COMPLIANT - {len(tier1_issues)} critical issues")
            return False
        else:
            print(f"⚠️  COMPLIANT WITH WARNINGS - {len(all_issues)} suggestions")
            return True


def main():
    neuronas_dir = Path("neuronas")

    if not neuronas_dir.exists():
        print("Error: neuronas/ directory not found")
        print("Run this script from the librarian cortex directory")
        return 1

    # Find all neurona files
    neurona_files = list(neuronas_dir.glob("*.md"))

    if not neurona_files:
        print("No neurona files found in neuronas/")
        return 1

    print(f"\n{'=' * 60}")
    print(f"Neurona Open Specification v0.1.0 - Compliance Checker")
    print(f"{'=' * 60}")
    print(f"Found {len(neurona_files)} neuronas to validate\n")

    # Validate each neurona
    results = {}
    for filepath in sorted(neurona_files):
        results[filepath.name] = validate_neurona(filepath)

    # Summary
    print(f"\n{'=' * 60}")
    print("Summary")
    print(f"{'=' * 60}")
    print(f"Total:      {len(results)}")
    print(f"Compliant:  {sum(1 for v in results.values() if v)} ✅")
    print(f"Failed:     {sum(1 for v in results.values() if not v)} ❌")

    if all(results.values()):
        print("\n✅ ALL NEURONAS ARE COMPLIANT")
        return 0
    else:
        print("\n❌ SOME NEURONAS HAVE ISSUES")
        return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback

        traceback.print_exc()
        sys.exit(1)
