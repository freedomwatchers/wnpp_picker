#!/bin/bash

# WNPP Picker - Query and filter Debian orphaned packages
# Data source: https://www.debian.org/devel/wnpp/orphaned

DATA_FILE="wnpp_data.txt"
CACHE_DIR=".wnpp_cache"

mkdir -p "$CACHE_DIR"

# 1) Get a full list of the current packages.
fetch_orphaned_list() {
    echo "Fetching orphaned packages list..."
    local url="https://www.debian.org/devel/wnpp/orphaned"
    local raw_html="$CACHE_DIR/orphaned.html"
    
    curl -s "$url" > "$raw_html"
    
    # Parse HTML to extract package name and description
    # Format in HTML: <li><a href="...">package: description</a>
    grep "<li><a href=\"https://bugs.debian.org/.*\">.*: .*</a>" "$raw_html" | \
    sed -E 's/.*https:\/\/bugs.debian.org\/([0-9]+)">([^:]+): ([^<]+).*/\1|\2|\3/' > "$DATA_FILE.tmp"
    
    # Move to final data file, adding columns for VCS and tags if they don't exist
    while IFS='|' read -r bug pkg desc; do
        # check if we already have this package to preserve VCS/tags
        local existing=$(grep "^$pkg|" "$DATA_FILE" 2>/dev/null)
        if [ -n "$existing" ]; then
            echo "$existing"
        else
            echo "$pkg|$desc||"
        fi
    done < "$DATA_FILE.tmp" > "$DATA_FILE"
    
    rm "$DATA_FILE.tmp"
    echo "Done. Found $(wc -l < "$DATA_FILE") packages."
}

# 2) Get all the details of each package, including its repo url.
fetch_package_details() {
    local target_pkg="$1"
    local silent="$2"
    
    [ "$silent" != "true" ] && echo "Fetching details for $target_pkg..."
    local tracker_url="https://tracker.debian.org/pkg/$target_pkg"
    local pkg_html="$CACHE_DIR/$target_pkg.html"
    
    # Use cache if it exists and is not too old (e.g., 24h)
    if [ ! -f "$pkg_html" ]; then
        curl -s "$tracker_url" > "$pkg_html"
    fi
    
    # Extract VCS URL
    local vcs_url=$(grep -iP "vcs-(git|svn|hg)" "$pkg_html" | grep -oP 'href="\K[^"]+' | head -n 1)
    
    if [ -n "$vcs_url" ]; then
        # Proper update logic using awk to replace the 3rd field
        awk -v pkg="$target_pkg" -v vcs="$vcs_url" -F'|' 'BEGIN {OFS="|"} $1 == pkg {$3 = vcs} {print}' "$DATA_FILE" > "$DATA_FILE.tmp" && mv "$DATA_FILE.tmp" "$DATA_FILE"
        [ "$silent" != "true" ] && echo "Found VCS: $vcs_url"
    else
        [ "$silent" != "true" ] && echo "No VCS URL found for $target_pkg"
    fi
}

fetch_all_details() {
    local pkgs=$(cut -d'|' -f1 "$DATA_FILE")
    local total=$(echo "$pkgs" | wc -w)
    local current=0
    
    echo "Updating details for $total packages. This will take some time..."
    for pkg in $pkgs; do
        current=$((current + 1))
        printf "\r[%d/%d] Processing %-30s" "$current" "$total" "$pkg"
        
        # Skip if already has VCS
        local has_vcs=$(grep "^$pkg|" "$DATA_FILE" | cut -d'|' -f3)
        if [ -n "$has_vcs" ]; then
            continue
        fi
        
        fetch_package_details "$pkg" "true"
        
        # Polite delay
        sleep 0.2
    done
    echo -e "\nAll details updated."
}

# 3) Tag these packages by category and technology.
tag_packages() {
    echo "Analyzing all packages using cached metadata and descriptions..."
    local total=$(wc -l < "$DATA_FILE")
    local current=0
    
    # We'll use a temp file to store results
    > "$DATA_FILE.analyzed"
    
    while IFS='|' read -r pkg desc vcs tags; do
        current=$((current + 1))
        # Update progress
        printf "\r[%d/%d] Analyzing %-30s" "$current" "$total" "$pkg"
        
        local new_tags=""
        local full_text="$(echo "$pkg $desc" | tr '[:upper:]' '[:lower:]')"
        
        # Technology tags
        [[ "$full_text" =~ (^|[^a-z0-9])perl([^a-z0-9]|$) ]] && new_tags+="perl "
        [[ "$full_text" =~ (^|[^a-z0-9])python([^a-z0-9]|$) ]] && new_tags+="python "
        [[ "$full_text" =~ (^|[^a-z0-9])ruby([^a-z0-9]|$) ]] && new_tags+="ruby "
        [[ "$full_text" =~ (^|[^a-z0-9])java([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])jdk([^a-z0-9]|$) ]] && new_tags+="java "
        [[ "$full_text" =~ (^|[^a-z0-9])node\.js([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])javascript([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])nodejs([^a-z0-9]|$) ]] && new_tags+="javascript "
        [[ "$full_text" =~ (^|[^a-z0-9])c\+\+([^a-z0-9]|$) ]] && new_tags+="cpp "
        [[ "$full_text" =~ (^|[^a-z0-9])rust([^a-z0-9]|$) ]] && new_tags+="rust "
        [[ "$full_text" =~ (^|[^a-z0-9])go([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])golang([^a-z0-9]|$) ]] && new_tags+="go "
        [[ "$full_text" =~ (^|[^a-z0-9])php([^a-z0-9]|$) ]] && new_tags+="php "
        
        # Category tags
        [[ "$full_text" =~ (^|[^a-z0-9])library([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])binding([^a-z0-9]|$) ]] && new_tags+="lib "
        [[ "$full_text" =~ (^|[^a-z0-9])client([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])server([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])network([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])protocol([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])socket([^a-z0-9]|$) ]] && new_tags+="net "
        [[ "$full_text" =~ (^|[^a-z0-9])gui([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])qt([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])gtk([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])wx([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])tk([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])x11([^a-z0-9]|$) ]] && new_tags+="gui "
        [[ "$full_text" =~ (^|[^a-z0-9])cli([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])command([[:space:]]|-)line([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])utility([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])console([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])terminal([^a-z0-9]|$) ]] && new_tags+="cli "
        [[ "$full_text" =~ (^|[^a-z0-9])driver([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])kernel([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])system([^a-z0-9]|$) ]] || [[ "$full_text" =~ (^|[^a-z0-9])embedded([^a-z0-9]|$) ]] && new_tags+="sys "
        
        # HTML-based enhancement
        local pkg_html="$CACHE_DIR/$pkg.html"
        if [ -f "$pkg_html" ]; then
            # Extract component (main/contrib/non-free)
            local comp=$(grep -oP '<span id="component".*?>\K[^<]+' "$pkg_html" | head -n 1)
            [ -n "$comp" ] && new_tags+="$comp "
            
            # Use VCS URL for tech team clues
            [[ "$vcs" =~ (^|[^a-z0-9])perl(-team)?([^a-z0-9]|$) ]] && new_tags+="perl-team "
            [[ "$vcs" =~ (^|[^a-z0-9])python(-team)?([^a-z0-9]|$) ]] && new_tags+="python-team "
            [[ "$vcs" =~ (^|[^a-z0-9])ruby(-team)?([^a-z0-9]|$) ]] && new_tags+="ruby-team "
            [[ "$vcs" =~ (^|[^a-z0-9])go(-team)?([^a-z0-9]|$) ]] && new_tags+="go-team "
        fi
        
        # Clean up tags: remove duplicates, trim
        new_tags=$(echo "$new_tags" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)
        
        echo "$pkg|$desc|$vcs|$new_tags" >> "$DATA_FILE.analyzed"
    done < "$DATA_FILE"
    
    mv "$DATA_FILE.analyzed" "$DATA_FILE"
    echo -e "\nAnalysis complete. Tags updated."
}

# 4) Query packages to filter them based in some criteria.
query_packages() {
    local include_tags=""
    local exclude_tags=""
    local search_term=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --include) include_tags="$2"; shift ;;
            --exclude) exclude_tags="$2"; shift ;;
            *) search_term="$1" ;;
        esac
        shift
    done
    
    printf "%-20s | %-15s | %s\n" "Package" "Tags" "Description"
    echo "--------------------------------------------------------------------------------"
    
    grep -i "$search_term" "$DATA_FILE" | while IFS='|' read -r pkg desc vcs tags; do
        local skip=0
        
        # Filter logic
        if [ -n "$include_tags" ]; then
            for t in $include_tags; do
                if [[ ! "$tags" =~ "$t" ]]; then skip=1; break; fi
            done
        fi
        
        if [ -n "$exclude_tags" ]; then
            for t in $exclude_tags; do
                if [[ "$tags" =~ "$t" ]]; then skip=1; break; fi
            done
        fi
        
        if [ $skip -eq 0 ]; then
            printf "%-20s | %-15s | %s\n" "$pkg" "$tags" "$desc"
            if [ -n "$vcs" ]; then
                echo "                     Repo: $vcs"
            fi
        fi
    done
}

# CLI Interface
case $1 in
    fetch) fetch_orphaned_list ;;
    details) fetch_package_details "$2" ;;
    fetch-all) fetch_all_details ;;
    tag|analyze) tag_packages ;;
    query) shift; query_packages "$@" ;;
    *)
        echo "Usage: $0 {fetch|details [pkg]|fetch-all|tag|analyze|query [options]}"
        echo "Options for query:"
        echo "  --include \"tag1 tag2\""
        echo "  --exclude \"tag1 tag2\""
        echo "  search_term"
        ;;
esac
