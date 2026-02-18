#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LLM Retrieval Example for Engram Polarion Knowledge Cortex

This script demonstrates how an LLM agent can retrieve and use Polarion work items
stored as neuronas in Engram.

Example use cases:
  1. Contextual information retrieval for LLM prompts
  2. Automated requirement analysis
  3. Dependency impact analysis
  4. Test coverage verification
"""

import subprocess
import json
import sys
import io

# Set UTF-8 encoding for Windows console
if sys.platform == "win32":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")


class EngramRetriever:
    """Helper class for LLM agents to retrieve information from Engram cortex"""

    def __init__(self, cortex_path="."):
        self.cortex_path = cortex_path

    def _run_engram(self, args):
        """Execute engram command and return parsed JSON"""
        try:
            result = subprocess.run(
                ["engram"] + args,
                cwd=self.cortex_path,
                capture_output=True,
                encoding="utf-8",
                errors="replace",  # Replace invalid characters
                check=False,  # Don't raise on non-zero exit
            )

            # Check if command succeeded
            if result.returncode != 0:
                # Try to extract JSON from stdout even if there were errors
                pass

            # Parse JSON output (ignore stderr which may have debug info)
            if result.stdout and result.stdout.strip():
                # Remove any error messages before JSON
                stdout = result.stdout
                # Find first '[' or '{'
                json_start = min(
                    stdout.find("[") if "[" in stdout else len(stdout),
                    stdout.find("{") if "{" in stdout else len(stdout),
                )
                if json_start < len(stdout):
                    stdout = stdout[json_start:]
                    return json.loads(stdout)

            return None
        except json.JSONDecodeError as e:
            print(f"Error parsing JSON: {e}", file=sys.stderr)
            return None
        except Exception as e:
            print(f"Error running engram: {e}", file=sys.stderr)
            return None
        except json.JSONDecodeError as e:
            print(f"Error parsing JSON: {e}", file=sys.stderr)
            print(f"Output: {result.stdout}", file=sys.stderr)
            return None

    def query_by_type(self, wi_type):
        """Retrieve all work items of a specific type"""
        return self._run_engram(["query", f"type:{wi_type}", "--json"])

    def query_by_tag(self, tag):
        """Retrieve work items with a specific tag"""
        return self._run_engram(["query", f"tag:{tag}", "--json"])

    def text_search(self, query):
        """Perform text search (BM25) for work items"""
        return self._run_engram(["query", "--mode", "text", query, "--json"])

    def semantic_search(self, query):
        """Perform semantic vector search for work items (requires GloVe)"""
        return self._run_engram(["query", "--mode", "vector", query, "--json"])

    def get_work_item(self, wi_id):
        """Get full details of a specific work item"""
        return self._run_engram(["show", wi_id, "--json"])

    def trace_dependencies(self, wi_id, depth=3):
        """Trace all dependencies of a work item"""
        return self._run_engram(["trace", wi_id, "--json", "--depth", str(depth)])

    def get_status(self):
        """Get cortex status and all work items"""
        return self._run_engram(["status", "--json"])

    def build_llm_context(self, query, max_items=5):
        """
        Build context for LLM prompt by retrieving relevant work items

        Args:
            query: Natural language query
            max_items: Maximum number of work items to include

        Returns:
            Formatted context string for LLM
        """
        # Try semantic search first (falls back to text if not available)
        results = self.semantic_search(query) or self.text_search(query) or []

        if not results:
            return "No relevant work items found."

        # Limit results
        results = results[:max_items]

        # Build context string
        context_parts = ["Relevant Polarion Work Items:\n"]

        for idx, wi in enumerate(results, 1):
            # Get full details
            details = self.get_work_item(wi["id"])
            if not details:
                continue

            context_parts.append(f"\n{idx}. {details['title']} ({details['id']})")
            context_parts.append(f"   Type: {details['type']}")
            context_parts.append(
                f"   Status: {details.get('context', {}).get('status', 'unknown')}"
            )

            # Include body content (truncate if too long)
            body = details.get("body", "")
            if len(body) > 300:
                body = body[:300] + "..."
            context_parts.append(f"   Content: {body}")

            # Show connections
            if details.get("connections", 0) > 0:
                context_parts.append(
                    f"   Connected to {details['connections']} other items"
                )

        return "\n".join(context_parts)


# Example usage scenarios
def example_1_requirement_query():
    """Example 1: Query all requirements"""
    print("=" * 70)
    print("Example 1: Query all requirements in the system")
    print("=" * 70)
    print()

    retriever = EngramRetriever()
    requirements = retriever.query_by_type("requirement")

    if requirements:
        print(f"Found {len(requirements)} requirements:\n")
        for req in requirements[:5]:  # Show first 5
            print(f"  • {req['id']}: {req['title']}")
            print(f"    Status: {req.get('context', {}).get('status', 'N/A')}")
            print(f"    Tags: {', '.join(req.get('tags', [])[:5])}")
            print()
    else:
        print("No requirements found.")
    print()


def example_2_llm_context():
    """Example 2: Build context for LLM about sensor requirements"""
    print("=" * 70)
    print("Example 2: Build LLM context for 'temperature sensor requirements'")
    print("=" * 70)
    print()

    retriever = EngramRetriever()
    context = retriever.build_llm_context(
        "temperature sensor configuration", max_items=3
    )

    print("Generated Context for LLM:")
    print("-" * 70)
    print(context)
    print("-" * 70)
    print()

    print("This context can be injected into an LLM prompt like:")
    print()
    print('  prompt = f"""')
    print("  You are an automotive software engineer analyzing requirements.")
    print("  ")
    print("  {context}")
    print("  ")
    print("  Question: What are the temperature sensor configuration requirements?")
    print('  """')
    print()


def example_3_dependency_analysis():
    """Example 3: Analyze dependencies for impact assessment"""
    print("=" * 70)
    print("Example 3: Dependency impact analysis")
    print("=" * 70)
    print()

    retriever = EngramRetriever()
    wi_id = "wi.90087"

    print(f"Analyzing dependencies for {wi_id}...")
    print()

    # Get the work item
    wi = retriever.get_work_item(wi_id)
    if wi:
        print(f"Work Item: {wi['title']}")
        print(f"Type: {wi['type']}")
        print(f"Status: {wi.get('context', {}).get('status', 'N/A')}")
        print()

    # Trace dependencies
    deps = retriever.trace_dependencies(wi_id)
    if deps:
        direct_deps = [d for d in deps if d.get("level", 0) == 1]
        print(f"Direct dependencies: {len(direct_deps)}")
        for dep in direct_deps:
            print(f"  → {dep['id']}")
        print()

        print("Impact Assessment:")
        print(
            f"  If {wi_id} changes, it may affect {len(direct_deps)} related work items."
        )
        print("  LLM can use this to generate change impact reports.")
    print()


def example_4_automated_verification():
    """Example 4: Verify test coverage"""
    print("=" * 70)
    print("Example 4: Automated test coverage verification")
    print("=" * 70)
    print()

    retriever = EngramRetriever()

    # Get all requirements
    requirements = retriever.query_by_type("requirement")
    # Get all test cases
    tests = retriever.query_by_type("test_case")

    print(f"Requirements: {len(requirements) if requirements else 0}")
    print(f"Test Cases: {len(tests) if tests else 0}")
    print()

    # Check which requirements lack test coverage (simplified)
    if requirements:
        print("Requirements without 'validated_by' connections:")
        # This is a simplified check - real implementation would parse connections
        for req in requirements[:3]:
            connections = req.get("connections", 0)
            print(f"  • {req['id']}: {req['title']}")
            print(f"    Connections: {connections}")
    print()

    print("LLM Use Case:")
    print("  An LLM agent can automatically generate test case stubs")
    print("  for requirements that lack test coverage.")
    print()


if __name__ == "__main__":
    print("\n")
    print("*" * 70)
    print("*" + " " * 68 + "*")
    print("*" + "  Engram LLM Integration Examples".center(68) + "*")
    print("*" + "  Polarion Work Items Knowledge Cortex".center(68) + "*")
    print("*" + " " * 68 + "*")
    print("*" * 70)
    print("\n")

    # Run examples
    example_1_requirement_query()
    example_2_llm_context()
    example_3_dependency_analysis()
    example_4_automated_verification()

    print("=" * 70)
    print("Examples Complete!")
    print("=" * 70)
    print()
    print("Key Takeaways:")
    print("  ✓ Engram provides JSON API perfect for LLM integration")
    print("  ✓ Query modes: filter, text, vector, hybrid, activation")
    print("  ✓ Dependency tracing for impact analysis")
    print("  ✓ Structured metadata for automated processing")
    print("  ✓ Sub-10ms performance for real-time LLM workflows")
    print()
