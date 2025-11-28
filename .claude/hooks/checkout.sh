#!/bin/bash
# Checkout source code at specific SHA
#
# This hook provides a simple interface to checkout the CockroachDB source code
# at a specific SHA. It can be used standalone or as part of other workflows.
#
# Usage: checkout.sh <sha> [repo-dir]
# Example: checkout.sh f0bfb1cb00838ff45a508e4f1eba087e9835a674
# Example: checkout.sh f0bfb1cb00838ff45a508e4f1eba087e9835a674 cockroachdb
#
# The script will:
# 1. Navigate to the cockroachdb submodule directory
# 2. Fetch the commit if not already available locally
# 3. Checkout the specific SHA
# 4. Provide feedback on success/failure

set -euo pipefail

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the helper functions
source "$SCRIPT_DIR/triage-helpers.sh"

# Main checkout function
main() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <sha> [repo-dir]"
        echo ""
        echo "Arguments:"
        echo "  sha       - Git commit SHA to checkout (required)"
        echo "  repo-dir  - Repository directory name (default: cockroachdb)"
        echo ""
        echo "Examples:"
        echo "  $0 f0bfb1cb00838ff45a508e4f1eba087e9835a674"
        echo "  $0 f0bfb1cb00838ff45a508e4f1eba087e9835a674 cockroachdb"
        echo ""
        echo "What this does:"
        echo "  - Navigates to the cockroachdb submodule directory"
        echo "  - Fetches the commit if not already available locally"
        echo "  - Checks out the specific SHA"
        echo "  - Makes the source code available for analysis"
        exit 1
    fi

    local sha="$1"
    local repo_dir="${2:-cockroachdb}"

    # Validate SHA format (40-character hex string)
    if ! [[ "$sha" =~ ^[a-f0-9]{40}$ ]]; then
        log_error "Invalid SHA format: $sha"
        log_info "Expected: 40-character hexadecimal string"
        log_info "Example: f0bfb1cb00838ff45a508e4f1eba087e9835a674"
        exit 1
    fi

    log_info "Starting checkout process"
    log_info "SHA: $sha"
    log_info "Repository: $repo_dir"
    echo ""

    # Call the checkout function from triage-helpers.sh
    if checkout_source_code "$sha" "$repo_dir"; then
        echo ""
        log_success "✓ Checkout complete!"
        echo ""
        echo "Source code is now available at:"
        echo "  Repository root: $repo_dir/"
        echo "  Roachtests: $repo_dir/pkg/cmd/roachtest/tests/"
        echo "  Full CRDB source: $repo_dir/pkg/"
        echo ""
        echo "To restore to master branch later, run:"
        echo "  cd $repo_dir && git checkout master"
        echo ""
        exit 0
    else
        echo ""
        log_error "✗ Checkout failed"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Ensure the cockroachdb submodule is initialized:"
        echo "     git submodule update --init"
        echo "  2. Check if the SHA exists in the repository:"
        echo "     cd $repo_dir && git fetch origin && git cat-file -e $sha^{commit}"
        echo "  3. Verify network connectivity to fetch from GitHub"
        echo ""
        exit 1
    fi
}

# Run main function
main "$@"
