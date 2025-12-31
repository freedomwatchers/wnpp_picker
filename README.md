# WNPP Picker

The `wnpp_picker.sh` script is a bash utility designed to help Debian contributors find orphaned packages that match their skills or interests.

## Features

- **Full List Fetching**: Downloads and parses the current list of orphaned packages from Debian WNPP.
- **Deep Detail Retrieval**: Scrapes the Debian Package Tracker for additional metadata, specifically VCS (repository) URLs.
- **Enhanced Analysis**: Scans local cache and metadata to extract component info and team ownership, with improved regex to ensure high accuracy.
- **Flexible Querying**: Allows filtering by tags and search terms.

## Usage

### 1. Initialize and Fetch Data
First, fetch the list of orphaned packages:
```bash
./wnpp_picker.sh fetch
```

### 2. Get Repository Details
Fetch metadata for all packages in the list (with progress tracking and polite delays):
```bash
./wnpp_picker.sh fetch-all
```

Or fetch for a specific package:
```bash
./wnpp_picker.sh details 2vcard
```

### 3. Analyze and Tag Packages
Run the enhanced analysis logic to categorize all fetched packages using local metadata:
```bash
./wnpp_picker.sh analyze
```
(Alias: `./wnpp_picker.sh tag`)

### 4. Query and Filter
Find non-Perl CLI packages:
```bash
./wnpp_picker.sh query --include cli --exclude perl
```

## Data Source
- [Debian WNPP Orphaned Packages](https://www.debian.org/devel/wnpp/orphaned)
- [Debian Package Tracker](https://tracker.debian.org/pkg/)
